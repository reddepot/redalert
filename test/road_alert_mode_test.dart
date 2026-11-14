import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/location_alarm.dart';

void main() {
  Map<String, dynamic> legacy() => {
        'id': 'synthetic-bump',
        'label': 'Synthetic',
        'latitude': 0.0,
        'longitude': 0.0,
        'radiusMeters': 500.0,
        'isActive': true,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'repeatDays': <int>[],
        'repeatOnEveryEntry': false,
        'poiType': 'highSpeedBump'
      };
  test('legacy road hazard uses passage speech after upgrade', () {
    expect(LocationAlarm.fromJson(legacy()).repeatOnEveryEntry, isTrue);
  });
  test(
      'explicit destination mode and ordinary places stay destination reminders',
      () {
    expect(
        LocationAlarm.fromJson({...legacy(), 'passageModeExplicit': true})
            .repeatOnEveryEntry,
        isFalse);
    expect(
        LocationAlarm.fromJson({...legacy(), 'poiType': 'other'})
            .repeatOnEveryEntry,
        isFalse);
  });
  test(
      'explicit mode marker survives serialization and a deliberate mode change',
      () {
    final migrated = LocationAlarm.fromJson(legacy());
    final destination = migrated.copyWith(repeatOnEveryEntry: false);
    expect(LocationAlarm.fromJson(destination.toJson()).repeatOnEveryEntry,
        isFalse);
    expect(
        LocationAlarm.fromJson(migrated.toJson()).repeatOnEveryEntry, isTrue);
  });
}
