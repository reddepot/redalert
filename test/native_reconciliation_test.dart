import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:locreminder/models/poi_type.dart';
import 'package:locreminder/services/native_reconciliation.dart';

LocationAlarm alarm({
  required String id,
  bool active = true,
  bool everyEntry = true,
}) => LocationAlarm(
  id: id,
  label: id,
  latitude: 46.5,
  longitude: 0.3,
  radiusMeters: 1000,
  isActive: active,
  createdAt: DateTime(2026, 11, 12),
  poiType: PoiType.fixedCamera,
  repeatOnEveryEntry: everyEntry,
  department: '86',
);

void main() {
  test(
    'a repeating point missing from the watcher is repaired, not disarmed',
    () {
      final alarms = [alarm(id: 'mi:1'), alarm(id: 'mi:2', active: false)];
      final repair = NativeReconciliation.toRepair(alarms, {'mi:2'});
      expect(repair.map((a) => a.id), ['mi:1']);
    },
  );

  test('nothing is repaired while the watcher already knows the point', () {
    final alarms = [alarm(id: 'mi:1')];
    expect(NativeReconciliation.toRepair(alarms, {'mi:1'}), isEmpty);
  });

  test('an empty watcher proves nothing, so nothing is declared rung', () {
    // This is the P0: the store was empty because the arming never reached it,
    // and the old rule turned that into "already rang" and disarmed the list.
    final alarms = [alarm(id: 'perso', everyEntry: false)];
    expect(NativeReconciliation.alreadyRang(alarms, const {}), isEmpty);
  });

  test('missing one-shot with another native row still proves no delivery', () {
    final alarms = [
      alarm(id: 'perso', everyEntry: false),
      alarm(id: 'mi:1', everyEntry: true),
    ];
    final rang = NativeReconciliation.alreadyRang(alarms, {'mi:1'});
    expect(rang, isEmpty);
  });

  test('last consumed one-shot is reconciled from a positive receipt even with an empty watcher', () {
    final places = [alarm(id: 'once', everyEntry: false)];
    expect(
      NativeReconciliation.alreadyRang(
        places,
        {},
        consumedIds: {'once'},
      ).map((p) => p.id),
      ['once'],
    );
    expect(
      NativeReconciliation.toRepair(places, {}, consumedIds: {'once'}),
      isEmpty,
    );
  });
  test('missing unconsumed one-shot is repaired and a rearmed native row wins over stale receipt', () {
    final places = [alarm(id: 'once', everyEntry: false)];
    expect(NativeReconciliation.toRepair(places, {}).map((p) => p.id), [
      'once',
    ]);
    expect(
      NativeReconciliation.alreadyRang(places, {'once'}, consumedIds: {'once'}),
      isEmpty,
    );
  });

  test('only changed armed states are sent to the watcher', () {
    final before = [
      alarm(id: 'a', active: false),
      alarm(id: 'b', active: true),
      alarm(id: 'c', active: true),
    ];
    final after = [
      alarm(id: 'a', active: true), // armed
      alarm(id: 'b', active: false), // paused
      alarm(id: 'c', active: true), // unchanged
      alarm(id: 'new', active: true), // created elsewhere
    ];
    final changes = NativeReconciliation.armingChanges(before, after);
    expect(changes.map((a) => a.id), ['a', 'b']);
    expect(
      changes.firstWhere((a) => a.id == 'b').isActive,
      isFalse,
      reason: 'a paused point must be sent too: that is how it stops ringing',
    );
  });

  test('nothing to send when the arming did not move', () {
    final alarms = [alarm(id: 'a')];
    expect(NativeReconciliation.armingChanges(alarms, alarms), isEmpty);
  });
  test('a weekday reminder missing while another alarm exists is repaired, never declared rung', () {
    final weekday = alarm(
      id: 'weekday',
      everyEntry: false,
    ).copyWith(repeatDays: {1, 2});
    final known = alarm(id: 'known');
    expect(
      NativeReconciliation.toRepair(
        [weekday, known],
        {'known'},
      ).map((a) => a.id),
      ['weekday'],
    );
    expect(
      NativeReconciliation.alreadyRang([weekday, known], {'known'}),
      isEmpty,
    );
  });
}
