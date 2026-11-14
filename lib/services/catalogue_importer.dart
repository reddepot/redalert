import '../models/poi_provenance.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/location_alarm.dart';
import '../models/poi_type.dart';
import '../models/approach_radius.dart';

/// Parses an entire inactive catalogue before any storage is changed.
abstract final class CatalogueImporter {
  static Future<List<LocationAlarm>> parseAsync(String text) async =>
      text.length > 65536 ? compute(parse, text) : parse(text);

  static List<LocationAlarm> parse(String text) {
    if (text.length > 8 * 1024 * 1024 ||
        utf8.encode(text).length > 8 * 1024 * 1024) {
      throw const FormatException('Fichier trop volumineux (8 Mo maximum).');
    }
    return fromDocument(jsonDecode(text));
  }

  /// Validates a trusted in-memory envelope without a JSON round trip.
  static List<LocationAlarm> fromDocument(Object? doc) {
    if (doc is! Map ||
        doc['format'] != 'location-catalogue-preparation' ||
        doc['version'] != 1 ||
        doc['activation'] != 'disabled') {
      throw const FormatException('Format de catalogue non reconnu.');
    }
    final items = doc['items'];
    if (items is! List || items.isEmpty || items.length > 5000) {
      throw const FormatException(
        'Le catalogue doit contenir entre 1 et 5 000 lieux.',
      );
    }
    final ids = <String>{};
    final now = DateTime.now();
    final result = <LocationAlarm>[];
    for (final item in items) {
      if (item is! Map) throw const FormatException('Lieu invalide.');
      final id = item['id'];
      final label = item['label'];
      final lat = item['latitude'];
      final lon = item['longitude'];
      if (id is! String ||
          id.length > 120 ||
          !RegExp(
            r'^(mi:|sncf:pn/|osm:node/|mapatlas:|carte:|archive2018:)[A-Za-z0-9_:/.-]+$',
          ).hasMatch(id) ||
          !ids.add(id) ||
          label is! String ||
          label.trim().isEmpty ||
          label.length > 140 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(label) ||
          lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lon < -180 ||
          lon > 180 ||
          item['armed'] != false) {
        throw const FormatException(
          'Coordonnées, libellé, identifiant ou activation invalides.',
        );
      }
      final department = item['department'];
      if (department != null &&
          (department is! String ||
              !RegExp(r'^(0[1-9]|[1-8][0-9]|9[0-5])$').hasMatch(department) ||
              department == '20')) {
        throw const FormatException('Département continental invalide.');
      }
      final source = item['source'] == null
          ? null
          : PoiProvenance.parse(item['source']);
      final speed = item['speed_limit_from_source_kmh'];
      if (speed != null && (speed is! int || speed < 1 || speed > 130)) {
        throw const FormatException('Limitation de vitesse invalide.');
      }
      result.add(
        LocationAlarm(
          id: id,
          label: label.trim(),
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
          radiusMeters: ApproachRadius.metres(
            PoiType.fromSource(item['category_code']),
            speed as int?,
            null,
          ),
          adaptiveRadius: true,
          isActive: false,
          createdAt: now,
          repeatOnEveryEntry: true,
          poiType: PoiType.fromSource(item['category_code']),
          // Carried through instead of being left in the label: the native side
          // needs the number itself to compare against the measured speed.
          speedLimitKmh: speed,
          department: department as String?,
          provenance: source,
          positionStatus: 'source',
          originalLatitude: lat.toDouble(),
          originalLongitude: lon.toDouble(),
        ),
      );
    }
    return result;
  }

  /// Existing IDs, including edited labels/radii, always take precedence.
  static List<LocationAlarm> merge(
    List<LocationAlarm> existing,
    List<LocationAlarm> incoming,
  ) {
    final ids = existing.map((a) => a.id).toSet();
    final originals = {for (final point in incoming) point.id: point};
    final enriched = existing.map((point) {
      final source = originals[point.id];
      if (point.provenance == null &&
          source?.provenance != null &&
          (point.originalLatitude ?? point.latitude) == source!.latitude &&
          (point.originalLongitude ?? point.longitude) == source.longitude) {
        return point.copyWith(provenance: source.provenance);
      }
      return point;
    });
    return [...enriched, ...incoming.where((a) => ids.add(a.id))];
  }
}
