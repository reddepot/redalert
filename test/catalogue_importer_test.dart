import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/services/catalogue_importer.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:locreminder/models/poi_type.dart';

Map<String, dynamic> record() => {
      'id': 'mi:test',
      'label': 'Lieu de test',
      'latitude': 46.5,
      'longitude': 0.3,
      'armed': false,
    };
String catalogue(List<Object?> items) => jsonEncode({
      'format': 'location-catalogue-preparation',
      'version': 1,
      'activation': 'disabled',
      'items': items,
    });

void main() {
  test(
      'embedded reference catalogue loads entirely inactive with repeat on entry',
      () {
    final alarms = CatalogueImporter.parse(
        File('assets/catalogue/catalogue_reference.json').readAsStringSync());
    expect(alarms, hasLength(3185));
    expect(alarms.map((a) => a.id).toSet(), hasLength(3185));
    expect(
        alarms.every((a) =>
            !a.isActive &&
            a.repeatOnEveryEntry &&
            a.adaptiveRadius &&
            a.radiusMeters >= 100 &&
            a.radiusMeters <= 3000),
        isTrue);
  });
  test('rejects the entire catalogue on duplicate ID or bad coordinates', () {
    expect(() => CatalogueImporter.parse(catalogue([record(), record()])),
        throwsFormatException);
    expect(
        () => CatalogueImporter.parse(catalogue([
              record(),
              {...record(), 'id': 'mi:other', 'latitude': 100}
            ])),
        throwsFormatException);
    expect(
        () => CatalogueImporter.parse(catalogue([
              {...record(), 'latitude': true}
            ])),
        throwsFormatException);
  });
  test(
      'rejects activation, unexpected schema, control characters and excessive count',
      () {
    expect(
        () => CatalogueImporter.parse(catalogue([
              {...record(), 'armed': true}
            ])),
        throwsFormatException);
    expect(() => CatalogueImporter.parse('{}'), throwsFormatException);
    expect(
        () => CatalogueImporter.parse(catalogue([
              {...record(), 'label': 'Bad\nlabel'}
            ])),
        throwsFormatException);
    expect(
        () => CatalogueImporter.parse(catalogue(
            List.generate(5001, (i) => {...record(), 'id': 'mi:$i'}))),
        throwsFormatException);
  });
  test('source categories distinguish fixed, light and average-speed points',
      () {
    final alarms = CatalogueImporter.parse(
        File('assets/catalogue/catalogue_reference.json').readAsStringSync());
    expect(alarms.where((a) => a.poiType == PoiType.redLightCamera),
        hasLength(496));
    expect(alarms.where((a) => a.poiType == PoiType.averageSpeedCamera),
        hasLength(66));
    expect(alarms.where((a) => a.poiType == PoiType.other), isEmpty);
  });
  test(
      'correction preserves original coordinates and survives reimport and storage',
      () {
    final incoming = CatalogueImporter.parse(catalogue([record()]));
    final corrected = incoming.first.copyWith(
        latitude: 46.501,
        longitude: 0.301,
        poiType: PoiType.highSpeedBump,
        note: 'Repère synthétique',
        positionStatus: 'gps_captured',
        positionAccuracyMeters: 8);
    final restored = LocationAlarm.fromJson(corrected.toJson());
    expect(restored.originalLatitude, 46.5);
    expect(restored.originalLongitude, 0.3);
    expect(restored.latitude, 46.501);
    expect(restored.poiType, PoiType.highSpeedBump);
    expect(restored.note, 'Repère synthétique');
    expect(restored.positionAccuracyMeters, 8);
    final movedAgain =
        restored.copyWith(latitude: 46.502, clearPositionAccuracy: true);
    expect(movedAgain.originalLatitude, 46.5);
    expect(movedAgain.positionAccuracyMeters, isNull);
    expect(
        CatalogueImporter.merge([movedAgain], incoming).first.latitude, 46.502);
  });
  test('reimport is idempotent and preserves manual points and edited settings',
      () {
    final incoming = CatalogueImporter.parse(catalogue([record()]));
    final edited = incoming.first
        .copyWith(label: 'Mon libellé', radiusMeters: 300, isActive: true);
    final manual = LocationAlarm(
        id: 'manual',
        label: 'Manuel',
        latitude: 46.0,
        longitude: 0.0,
        radiusMeters: 500,
        isActive: true,
        createdAt: DateTime(2026));
    final merged = CatalogueImporter.merge([edited, manual], incoming);
    expect(merged, hasLength(2));
    expect(identical(merged.first, edited), isTrue);
    expect(identical(merged.last, manual), isTrue);
    expect(CatalogueImporter.merge(merged, incoming), hasLength(2));
    final restored = LocationAlarm.fromJson(edited.toJson());
    expect(restored.repeatOnEveryEntry, isTrue);
    expect(restored.repeats, isTrue);
    expect(restored.scheduleLabel, 'À chaque passage');
    expect(restored.copyWith(label: 'Encore').repeatOnEveryEntry, isTrue);
  });
}
