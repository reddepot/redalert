import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/location_alarm.dart';
import '../models/poi_type.dart';
import '../models/department_names.dart';
import 'catalogue_importer.dart';

enum RoadDataKind { railway, calming }

class RoadImportBatch {
  const RoadImportBatch({
    required this.alarms,
    required this.provider,
    required this.snapshotAt,
    this.skipped = 0,
  });
  final List<LocationAlarm> alarms;
  final String provider;
  final DateTime snapshotAt;
  final int skipped;
}

class RoadDataRepository {
  RoadDataRepository({AssetBundle? bundle, http.Client? client})
    : _bundle = bundle ?? rootBundle,
      _client = client ?? http.Client();
  final AssetBundle _bundle;
  final http.Client _client;
  Future<Map<String, dynamic>>? _index;
  Future<Map<String, dynamic>> railwayIndex() => _index ??= _loadIndex();
  Future<Map<String, dynamic>> _loadIndex() async =>
      jsonDecode(await _bundle.loadString('assets/catalogue/road_sources.json'))
          as Map<String, dynamic>;
  static void checkDepartment(String code) {
    if (!departmentNames.containsKey(code)) {
      throw const FormatException('Département continental invalide.');
    }
  }

  Future<RoadImportBatch> railway(
    String code, {
    bool lowClearanceOnly = false,
    int? crossingClass,
  }) async {
    checkDepartment(code);
    if (crossingClass != null && (crossingClass < 10 || crossingClass > 21)) {
      throw const FormatException('Classe de passage à niveau invalide.');
    }
    final index = await railwayIndex();
    final departments = index['departments'] as List;
    final exists = departments.any((row) => row['code'] == code);
    final points = exists
        ? await CatalogueImporter.parseAsync(
            await _bundle.loadString('assets/catalogue/railway/$code.json'),
          )
        : <LocationAlarm>[];
    return RoadImportBatch(
      alarms: points
          .where(
            (p) =>
                (!lowClearanceOnly ||
                    p.provenance?.lowClearanceDifficult == true) &&
                (crossingClass == null ||
                    p.provenance?.railwayClass == crossingClass),
          )
          .toList(),
      provider: 'SNCF Réseau',
      snapshotAt: DateTime.parse(
        (index['source'] as Map)['snapshot_at'] as String,
      ),
    );
  }

  static String osmQuery(String code) {
    checkDepartment(code);
    return '[out:json][timeout:30][maxsize:33554432];'
        'area["boundary"="administrative"]["admin_level"="6"]["ref:INSEE"="$code"]->.region;'
        '.region out tags;node(area.region)["traffic_calming"];out body;';
  }

  Future<RoadImportBatch> calming(String code) async {
    final query = osmQuery(code);
    final request =
        http.Request('POST', Uri.https('overpass-api.de', '/api/interpreter'))
          ..headers['User-Agent'] =
              'RedAlert/2.1.1 (https://github.com/reddepot/redalert)'
          ..bodyFields = {'data': query};
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      throw const FormatException(
        'Source OSM indisponible. Réessayer plus tard.',
      );
    }
    var size = 0;
    final bytes = BytesBuilder(copy: false);
    final complete = Completer<Uint8List>();
    final subscription = response.stream.listen(
      (chunk) {
        if (complete.isCompleted) return;
        size += chunk.length;
        if (size > 8 * 1024 * 1024) {
          complete.completeError(
            const FormatException(
              'Extrait OSM trop volumineux (8 Mo maximum).',
            ),
          );
        } else {
          bytes.add(chunk);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!complete.isCompleted) complete.completeError(error, stack);
      },
      onDone: () {
        if (!complete.isCompleted) complete.complete(bytes.takeBytes());
      },
    );
    try {
      final body = await complete.future.timeout(const Duration(seconds: 15));
      return await compute(_parseOsmBytes, (body, code));
    } finally {
      await subscription.cancel();
    }
  }

  static RoadImportBatch parseOsm(String body, String code) {
    checkDepartment(code);
    if (utf8.encode(body).length > 8 * 1024 * 1024) {
      throw const FormatException('Extrait OSM trop volumineux.');
    }
    final Object? doc;
    try {
      doc = jsonDecode(body);
    } on FormatException {
      throw const FormatException(
        'La source OSM n’a pas renvoyé un extrait JSON valide. Réessayer plus tard.',
      );
    }
    if (doc is! Map ||
        doc['remark'] != null ||
        doc['elements'] is! List ||
        (doc['elements'] as List).length > 10001) {
      throw const FormatException(
        'Réponse OSM incomplète ou invalide. Aucun lieu importé.',
      );
    }
    final meta = doc['osm3s'];
    final stamp = meta is Map ? meta['timestamp_osm_base'] : null;
    final date = stamp is String ? DateTime.tryParse(stamp) : null;
    if (date == null || !stamp!.endsWith('Z') || date.year < 2000) {
      throw const FormatException('Date de la base OSM absente ou invalide.');
    }
    final elements = doc['elements'] as List;
    final areas = elements
        .where((row) => row is Map && row['type'] == 'area')
        .toList();
    if (areas.length != 1 ||
        (areas.single as Map)['tags'] is! Map ||
        (areas.single['tags'] as Map)['ref:INSEE'] != code ||
        (areas.single['tags'] as Map)['admin_level'] != '6') {
      throw const FormatException('Le département OSM n’a pas été confirmé.');
    }
    const priority = [
      PoiType.highSpeedBump,
      PoiType.rumbleStrip,
      PoiType.roadDip,
      PoiType.roadNarrowing,
    ];
    final items = <Map<String, Object?>>[];
    var skipped = 0;
    for (final row in elements) {
      if (row is Map && row['type'] == 'area') continue;
      if (row is! Map || row['type'] != 'node' || row['tags'] is! Map) {
        skipped++;
        continue;
      }
      final tags = row['tags'] as Map;
      if (['private', 'no'].contains(tags['access']) ||
          tags['motor_vehicle'] == 'no') {
        skipped++;
        continue;
      }
      final raw = tags['traffic_calming'];
      if (raw is! String || raw.length > 120) {
        skipped++;
        continue;
      }
      final types = raw
          .split(';')
          .map((v) => PoiType.fromSource(v.trim()))
          .where(priority.contains)
          .toSet();
      if (types.isEmpty) {
        skipped++;
        continue;
      }
      final chosen = priority.firstWhere(types.contains);
      final id = row['id'];
      if (id is! int || id <= 0) {
        throw const FormatException('Identifiant OSM invalide.');
      }
      final label = priority
          .where(types.contains)
          .map((p) => p.label)
          .join(' / ');
      items.add({
        'id': 'osm:node/$id',
        'label': '$code · $label · OSM-$id',
        'latitude': row['lat'],
        'longitude': row['lon'],
        'armed': false,
        'department': code,
        'category_code': switch (chosen) {
          PoiType.highSpeedBump => 'bump',
          PoiType.rumbleStrip => 'rumble_strip',
          PoiType.roadDip => 'dip',
          _ => 'chicane',
        },
        'source': {
          'name': 'OpenStreetMap',
          'record_id': 'node/$id',
          'url': 'https://www.openstreetmap.org/node/$id',
          'snapshot_at': date.toUtc().toIso8601String(),
          'raw_type': raw,
        },
      });
    }
    if (items.length > 5000) {
      throw const FormatException('Plus de 5 000 lieux : extrait non importé.');
    }
    final alarms = items.isEmpty
        ? <LocationAlarm>[]
        : CatalogueImporter.fromDocument({
            'format': 'location-catalogue-preparation',
            'version': 1,
            'activation': 'disabled',
            'items': items,
          });
    return RoadImportBatch(
      alarms: alarms,
      provider: 'OpenStreetMap',
      snapshotAt: date,
      skipped: skipped,
    );
  }

  void close() => _client.close();
}

RoadImportBatch _parseOsmBytes((Uint8List, String) data) =>
    RoadDataRepository.parseOsm(utf8.decode(data.$1), data.$2);
