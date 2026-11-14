import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/location_alarm.dart';

/// Persists the user's saved alarms on the Dart side (for the UI list).
/// The native side keeps its own independent copy (see AlarmStore.kt) so
/// it can ring on arrival without needing the Flutter engine.
class AlarmRepository {
  static const _prefsKey = 'location_alarms';
  static const recoveryKey = 'location_alarms_recovery_v1';
  int rejectedRecords = 0;
  static Future<void>? _pendingSave;

  /// Reads the saved alarms, skipping any record that will not parse.
  ///
  /// One bad entry used to take the whole list with it: `loadAll` threw, the
  /// exception escaped the home screen's bootstrap, and the app sat on its
  /// loading spinner for good with no way back short of clearing its data.
  /// A record written by an older build, or truncated by a kill mid-write, is
  /// kept in a recovery copy, while valid rows remain available.
  Future<List<LocationAlarm>> loadAll() async {
    final pending = _pendingSave;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final decoded = raw.length > 200
        ? await compute(_decodeAlarms, raw)
        : _decodeAlarms(raw);
    rejectedRecords = decoded.rejected;
    if (rejectedRecords > 0 && !await prefs.setStringList(recoveryKey, raw)) {
      throw StateError('Recovery copy could not be preserved');
    }
    return decoded.alarms;
  }

  static ({List<LocationAlarm> alarms, int rejected}) _decodeAlarms(
    List<String> raw,
  ) {
    var rejected = 0;
    final alarms = <LocationAlarm>[];
    for (final entry in raw) {
      try {
        final json = jsonDecode(entry) as Map<String, dynamic>;
        alarms.add(
          _withDerivedFields(
            LocationAlarm.fromJson(json),
            deriveSpeed: !json.containsKey('speedLimitKmh'),
          ),
        );
      } catch (_) {
        rejected++;
        continue;
      }
    }
    return (alarms: alarms, rejected: rejected);
  }

  /// Gives records written before a field existed the value that field would
  /// have held.
  ///
  /// The first catalogue build put the department and the speed limit in the
  /// label only. Re-importing 859 places to add two columns would lose the
  /// corrections made since, so the label it wrote is read back instead — but
  /// only for catalogue ids, where the format is the app's own, never for a
  /// place the user named.
  static final _catalogueId = RegExp(
    r'^(mi:|osm:node/|mapatlas:|carte:|archive2018:)',
  );
  static final _labelDepartment = RegExp(r'^(\d{2,3}) · ');
  static final _labelSpeed = RegExp(r'·\s*(\d{2,3})\s*km/h\s*·');

  static LocationAlarm _withDerivedFields(
    LocationAlarm alarm, {
    required bool deriveSpeed,
  }) {
    if (!_catalogueId.hasMatch(alarm.id)) return alarm;
    final department =
        alarm.department ?? _labelDepartment.firstMatch(alarm.label)?.group(1);
    final speed = deriveSpeed
        ? int.tryParse(_labelSpeed.firstMatch(alarm.label)?.group(1) ?? '')
        : alarm.speedLimitKmh;
    if (department == alarm.department && speed == alarm.speedLimitKmh) {
      return alarm;
    }
    return alarm.copyWith(department: department, speedLimitKmh: speed);
  }

  Future<void> saveAll(List<LocationAlarm> alarms) {
    final snapshot = List<LocationAlarm>.of(alarms);
    // A small edit must never overtake a large encoding operation.
    final previous = _pendingSave;
    final operation = (() async {
      if (previous != null) await previous;
      final encoded = snapshot.length > 200
          ? await compute(_encodeAlarms, snapshot)
          : _encodeAlarms(snapshot);
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(_prefsKey, encoded)) {
        throw StateError('Alarm storage write failed');
      }
    })();
    final tail = operation.catchError((Object _) {});
    _pendingSave = tail;
    tail.then((_) {
      if (identical(_pendingSave, tail)) _pendingSave = null;
    });
    return operation;
  }

  static List<String> _encodeAlarms(List<LocationAlarm> alarms) =>
      alarms.map((a) => jsonEncode(a.toJson())).toList();
}
