import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/services/passage_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PassageLog.clear();
  });

  PassageLogEntry entry(String stage, {String label = 'Radar 86'}) =>
      PassageLogEntry(
        at: DateTime(2026, 11, 11, 22, 30, 15),
        label: label,
        stage: stage,
        distanceMetres: 240,
        accuracyMetres: 8,
        stale: false,
      );

  test('keeps one line per change, not per second', () async {
    await PassageLog.record(entry('Entrée dans la zone'));
    await PassageLog.record(entry('Entrée dans la zone'));
    await PassageLog.record(entry('Approche du point'));

    final log = await PassageLog.load();
    expect(log.map((e) => e.stage),
        ['Entrée dans la zone', 'Approche du point']);
  });

  test('a new place breaks the repetition even at the same stage', () async {
    await PassageLog.record(entry('Approche du point', label: 'Radar 86'));
    await PassageLog.record(entry('Approche du point', label: 'Radar 79'));

    final log = await PassageLog.load();
    expect(log.length, 2);
    expect(log.last.label, 'Radar 79');
  });

  test('survives a reload from storage', () async {
    await PassageLog.record(entry('Point dépassé · estimé'));
    final log = await PassageLog.load();
    expect(log.single.stage, 'Point dépassé · estimé');
    expect(log.single.distanceMetres, 240);
  });

  test('is bounded, and keeps the newest end', () async {
    for (var i = 0; i < 320; i++) {
      await PassageLog.record(entry('Étape $i', label: 'Lieu $i'));
    }
    final log = await PassageLog.load();
    expect(log.length, 300);
    expect(log.last.stage, 'Étape 319');
    expect(log.first.stage, 'Étape 20');
  });

  test('exports a pasteable transcript, newest first', () async {
    await PassageLog.record(entry('Entrée dans la zone'));
    await PassageLog.record(entry('Approche du point'));
    final text = PassageLog.export(await PassageLog.load());

    expect(text, contains('Journal de passage LocReminder'));
    expect(text, contains('22:30:15'));
    expect(text, contains('240 m'));
    expect(text, contains('±8 m'));
    // Newest first, so a paste starts with what just happened.
    expect(text.indexOf('Approche du point'),
        lessThan(text.indexOf('Entrée dans la zone')));
  });
}
