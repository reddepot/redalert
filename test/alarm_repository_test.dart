import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/services/alarm_repository.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'malformed stored records are reported and preserved before a later save',
    () async {
      final row = LocationAlarm(
        id: 'valid',
        label: 'Synthetic',
        latitude: 0,
        longitude: 0,
        radiusMeters: 100,
        isActive: false,
        createdAt: DateTime.utc(2026),
      );
      final original = [jsonEncode(row.toJson()), '{truncated'];
      SharedPreferences.setMockInitialValues({'location_alarms': original});
      final repo = AlarmRepository();
      final loaded = await repo.loadAll();
      expect(repo.rejectedRecords, 1);
      expect(loaded.map((p) => p.id), ['valid']);
      await repo.saveAll(loaded);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(AlarmRepository.recoveryKey), original);
    },
  );

  test('large off-thread save cannot overtake a later small edit', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = AlarmRepository();
    LocationAlarm item(String id) => LocationAlarm(
      id: id,
      label: 'Synthetic',
      latitude: 0,
      longitude: 0,
      radiusMeters: 100,
      isActive: false,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final first = repo.saveAll([
      for (var i = 0; i < 1000; i++) item('large-$i'),
    ]);
    final latest = repo.saveAll([item('latest')]);
    await Future.wait([first, latest]);
    expect((await AlarmRepository().loadAll()).map((p) => p.id), ['latest']);
  });

  test(
    'a catalogue point written before the fields existed regains them',
    () async {
      SharedPreferences.setMockInitialValues({
        'location_alarms': [
          jsonEncode({
            'id': 'mi:12014',
            'label': '86 · Vitesse discriminante · 80 km/h · MI-12014',
            'latitude': 46.5,
            'longitude': 0.3,
            'radiusMeters': 1000.0,
            'isActive': false,
            'createdAt': '2026-11-11T10:00:00.000',
          }),
        ],
      });

      final alarm = (await AlarmRepository().loadAll()).single;
      expect(alarm.department, '86');
      expect(alarm.speedLimitKmh, 80);
    },
  );

  test(
    'a personal place that merely starts like a code is left alone',
    () async {
      SharedPreferences.setMockInitialValues({
        'location_alarms': [
          jsonEncode({
            'id': '1731234567890',
            'label': '86 · Chez moi',
            'latitude': 46.5,
            'longitude': 0.3,
            'radiusMeters': 500.0,
            'isActive': true,
            'createdAt': '2026-11-11T10:00:00.000',
          }),
        ],
      });

      final alarm = (await AlarmRepository().loadAll()).single;
      expect(alarm.department, isNull);
      expect(alarm.speedLimitKmh, isNull);
      expect(alarm.label, '86 · Chez moi');
    },
  );

  test('a label with no stated limit stays without one', () async {
    SharedPreferences.setMockInitialValues({
      'location_alarms': [
        jsonEncode({
          'id': 'mi:FE316005',
          'label': '16 · Feu rouge · VMA non renseignée · MI-FE316005',
          'latitude': 45.65,
          'longitude': 0.18,
          'radiusMeters': 1000.0,
          'isActive': false,
          'createdAt': '2026-11-11T10:00:00.000',
        }),
      ],
    });

    final alarm = (await AlarmRepository().loadAll()).single;
    expect(alarm.department, '16');
    expect(alarm.speedLimitKmh, isNull);
  });
  test(
    'an explicitly cleared speed limit is not resurrected from an old label',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = AlarmRepository();
      final alarm = LocationAlarm(
        id: 'mi:synthetic',
        label: '16 · Radar · 70 km/h · MI-synthetic',
        latitude: 0,
        longitude: 0,
        radiusMeters: 1000,
        isActive: true,
        createdAt: DateTime(2026),
        speedLimitKmh: 70,
        department: '16',
      );
      await repo.saveAll([alarm.copyWith(clearSpeedLimit: true)]);
      final restored = (await repo.loadAll()).single;
      expect(restored.speedLimitKmh, isNull);
      expect(restored.department, '16');
    },
  );
}
