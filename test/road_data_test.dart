import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:locreminder/models/poi_type.dart';
import 'package:locreminder/services/catalogue_importer.dart';
import 'package:locreminder/services/road_data_repository.dart';

class FileAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

Map<String, Object?> source() => {
      'name': 'SNCF Réseau',
      'record_id': 'synthetic',
      'url':
          'https://ressources.data.sncf.com/explore/dataset/liste-des-passages-a-niveau/',
      'snapshot_at': '2026-02-18T16:29:18Z',
      'classification': 'Classe 17',
      'low_clearance_difficult': true
    };
Map<String, Object?> item() => {
      'id': 'mi:synthetic',
      'label': 'Synthetic',
      'latitude': 46.0,
      'longitude': 0.0,
      'armed': false,
      'category_code': 'SNCF_PN_LOW',
      'source': source()
    };
String catalogue(List<Object?> items) => jsonEncode({
      'format': 'location-catalogue-preparation',
      'version': 1,
      'activation': 'disabled',
      'items': items
    });
Map<String, Object?> osm(List<Object?> nodes) => {
      'osm3s': {'timestamp_osm_base': '2026-01-01T00:00:00Z'},
      'elements': [
        {
          'type': 'area',
          'id': 1,
          'tags': {'admin_level': '6', 'ref:INSEE': '86'}
        },
        ...nodes
      ]
    };
Map<String, Object?> node(int id, String value) => {
      'type': 'node',
      'id': id,
      'lat': 46.0,
      'lon': 0.0,
      'tags': {'traffic_calming': value}
    };
void main() {
  test('source evidence survives import, manual changes, storage and reimport',
      () {
    final imported = CatalogueImporter.parse(catalogue([item()]));
    final edited = imported.single
        .copyWith(latitude: 46.01, label: 'Synthetic edit', isActive: true);
    final saved = LocationAlarm.fromJson(edited.toJson());
    expect(saved.provenance!.provider, 'SNCF Réseau');
    expect(saved.provenance!.lowClearanceDifficult, isTrue);
    expect(saved.poiType, PoiType.levelCrossingLowClearance);
    final merged = CatalogueImporter.merge([saved], imported);
    expect(merged.single.latitude, 46.01);
    expect(merged.single.isActive, isTrue);
    expect(identical(merged.single, saved), isTrue);
    expect(merged.single.provenance!.snapshotAt,
        DateTime.utc(2026, 2, 18, 16, 29, 18));
  });
  test('old reference acquires evidence only when original coordinates match',
      () {
    final incoming = CatalogueImporter.parse(catalogue([item()]));
    final old =
        LocationAlarm.fromJson({...incoming.single.toJson()}..remove('source'))
            .copyWith(latitude: 46.02, isActive: true);
    final enriched = CatalogueImporter.merge([old], incoming).single;
    expect(enriched.provenance, isNotNull);
    expect(enriched.latitude, 46.02);
    expect(enriched.isActive, isTrue);
    final changed = CatalogueImporter.parse(catalogue([
      {...item(), 'latitude': 47.0}
    ]));
    expect(CatalogueImporter.merge([old], changed).single.provenance, isNull);
  });
  test(
      'invalid source date/link rejects import but never destroys a saved alarm',
      () {
    for (final replacement in [
      {'url': 'javascript:alert(1)'},
      {'snapshot_at': '2026-02-31'},
      {'snapshot_at': 'not a date'},
      {'low_clearance_difficult': 'yes'}
    ]) {
      final bad = {...source(), ...replacement};
      expect(
          () => CatalogueImporter.parse(catalogue([
                {...item(), 'source': bad}
              ])),
          throwsFormatException);
      final local = {
        ...CatalogueImporter.parse(catalogue([item()])).single.toJson(),
        'source': bad
      };
      expect(LocationAlarm.fromJson(local).provenance, isNull);
    }
  });
  test('all embedded SNCF departments are inactive, dated and bounded',
      () async {
    final data = RoadDataRepository(bundle: FileAssets());
    final index = await data.railwayIndex();
    var total = 0, low = 0;
    for (final row in index['departments'] as List) {
      final batch = await data.railway(row['code'] as String);
      expect(batch.alarms.length, row['count']);
      expect(batch.alarms.length, inInclusiveRange(1, 5000));
      expect(
          batch.alarms.every((p) =>
              !p.isActive && p.repeatOnEveryEntry && p.provenance != null),
          isTrue);
      expect(batch.alarms.every((p) => p.department == row['code']), isTrue);
      expect(batch.alarms.map((p) => p.id).toSet().length, batch.alarms.length);
      total += batch.alarms.length;
      final subset =
          await data.railway(row['code'] as String, lowClearanceOnly: true);
      expect(subset.alarms.length, row['low_clearance']);
      low += subset.alarms.length;
      expect(
          subset.alarms
              .every((p) => p.poiType == PoiType.levelCrossingLowClearance),
          isTrue);
    }
    expect(total, 14891);
    expect(low, 1734);
    expect(await data.railway('75').then((b) => b.alarms), isEmpty);
    data.close();
  });
  test(
      'SNCF class filter follows the declared class without inventing compatibility',
      () async {
    final data = RoadDataRepository(bundle: FileAssets());
    final all = await data.railway('86');
    final selected = await data.railway('86', crossingClass: 20);
    expect(selected.alarms.length,
        all.alarms.where((p) => p.provenance?.railwayClass == 20).length);
    expect(
        selected.alarms.every(
            (p) => p.provenance?.classification == 'Classe 20' && !p.isActive),
        isTrue);
    await expectLater(
        data.railway('86', crossingClass: 41), throwsFormatException);
    data.close();
  });
  test(
      'OSM supports combined types without guessing speed, direction, height or centres',
      () {
    final batch = RoadDataRepository.parseOsm(
        jsonEncode(osm([
          node(1, 'choker;cushion'),
          node(2, 'dip'),
          node(3, 'rumble_strip'),
          node(4, 'unknown'),
          {...node(5, 'bump'), 'type': 'way'},
          {
            ...node(6, 'bump'),
            'tags': {'traffic_calming': 'bump', 'access': 'private'}
          },
        ])),
        '86');
    expect(batch.alarms.length, 3);
    expect(batch.skipped, 3);
    expect(batch.alarms.first.poiType, PoiType.highSpeedBump);
    expect(batch.alarms.first.label, contains('Chaussée rétrécie'));
    expect(batch.alarms.first.provenance!.rawType, 'choker;cushion');
    expect(
        batch.alarms.every((p) =>
            !p.isActive &&
            p.speedLimitKmh == null &&
            p.travelBearingDegrees == null),
        isTrue);
    expect(batch.alarms[1].poiType, PoiType.roadDip);
  });
  test('OSM partial, wrong-area or duplicate responses never import partially',
      () {
    expect(
        () => RoadDataRepository.parseOsm(
            jsonEncode({
              ...osm([node(1, 'bump')]),
              'remark': 'runtime error'
            }),
            '86'),
        throwsFormatException);
    expect(
        () => RoadDataRepository.parseOsm(
            jsonEncode(osm([node(1, 'bump'), node(1, 'hump')])), '86'),
        throwsFormatException);
    expect(() => RoadDataRepository.parseOsm(jsonEncode(osm([])), '33'),
        throwsFormatException);
    expect(() => RoadDataRepository.osmQuery('2A'), throwsFormatException);
    expect(() => RoadDataRepository.osmQuery('86"] ; node; out;'),
        throwsFormatException);
  });
  test(
      'OSM transport uses explicit department only and parses a full dated response',
      () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'overpass-api.de');
      expect(request.method, 'POST');
      final query = Uri.splitQueryString(request.body)['data']!;
      expect(query, contains('"ref:INSEE"="86"'));
      expect(query, contains('.region out tags;'));
      expect(query, contains('node(area.region)["traffic_calming"]'));
      expect(query, isNot(contains('around:')));
      return http.Response(jsonEncode(osm([node(1, 'bump')])), 200);
    });
    final data = RoadDataRepository(bundle: FileAssets(), client: client);
    expect((await data.calming('86')).alarms.single.id, 'osm:node/1');
    data.close();
  });
}
