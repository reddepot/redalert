import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/location_alarm.dart';

void main() {
  final alarm = LocationAlarm(
      id: 'synthetic',
      label: 'Synthetic',
      latitude: 0,
      longitude: 0,
      radiusMeters: 1000,
      isActive: true,
      createdAt: DateTime(2026),
      speedLimitKmh: 80);
  test('speed-only edits and clearing a limit are persisted as real edits', () {
    expect(alarm.hasSameEditableValues(alarm.copyWith()), isTrue);
    expect(alarm.hasSameEditableValues(alarm.copyWith(speedLimitKmh: 90)),
        isFalse);
    expect(alarm.hasSameEditableValues(alarm.copyWith(clearSpeedLimit: true)),
        isFalse);
    final unknown = alarm.copyWith(clearSpeedLimit: true);
    expect(unknown.hasSameEditableValues(unknown.copyWith(speedLimitKmh: 80)),
        isFalse);
  });
}
