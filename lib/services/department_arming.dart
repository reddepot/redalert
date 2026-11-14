import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/location_alarm.dart';

/// Automatic arming applies only to the ministry reference. Other datasets
/// require an explicit arming action, even when they carry a department.
/// Nearest-reference department detection is approximate near boundaries.
class DepartmentArming {
  static const _prefsKey = 'auto_arm_department';
  static bool _isImported(LocationAlarm alarm) => const [
        'mi:', 'sncf:pn/', 'osm:node/', 'mapatlas:', 'carte:', 'archive2018:'
      ].any(alarm.id.startsWith);

  /// Read once per session: this is consulted on every location fix.
  static bool? _cachedAuto;

  static Future<bool> autoEnabled() async {
    final cached = _cachedAuto;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    return _cachedAuto = prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> setAutoEnabled(bool enabled) async {
    _cachedAuto = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }

  /// Codes of the departments present in [alarms], with how many points each
  /// holds and how many are armed.
  static Map<String, ({int total, int armed})> byDepartment(
      List<LocationAlarm> alarms) {
    final result = <String, ({int total, int armed})>{};
    for (final alarm in alarms) {
      final code = alarm.department;
      if (code == null || !_isImported(alarm)) continue;
      final current = result[code] ?? (total: 0, armed: 0);
      result[code] = (
        total: current.total + 1,
        armed: current.armed + (alarm.isActive ? 1 : 0),
      );
    }
    return result;
  }

  /// The department of the nearest reference point, or null when none is
  /// within [maxDistanceMetres].
  static String? departmentAt(
    List<LocationAlarm> alarms,
    double latitude,
    double longitude, {
    double maxDistanceMetres = 25000,
  }) {
    const earthRadius = 6371000.0;
    double? best;
    String? code;
    final lat1 = latitude * math.pi / 180;
    for (final alarm in alarms) {
      final department = alarm.department;
      if (department == null || !alarm.id.startsWith('mi:')) continue;
      // Equirectangular approximation: at 25 km the error is centimetres,
      // against a haversine that would run 859 times a second.
      final dLat = (alarm.latitude - latitude) * math.pi / 180;
      final dLon = (alarm.longitude - longitude) * math.pi / 180;
      final x = dLon * math.cos((lat1 + alarm.latitude * math.pi / 180) / 2);
      final distance = math.sqrt(x * x + dLat * dLat) * earthRadius;
      if (distance < (best ?? double.infinity)) {
        best = distance;
        code = department;
      }
    }
    return best != null && best <= maxDistanceMetres ? code : null;
  }

  /// Arms every reference point of [department] and pauses the other reference
  /// points, leaving the user's own places exactly as they are.
  ///
  /// Returns the same list instance when nothing would change, so the caller
  /// can skip a write on every location fix.
  static List<LocationAlarm> armOnly(
      List<LocationAlarm> alarms, String department) {
    var changed = false;
    final updated = alarms.map((alarm) {
      if (alarm.department == null || !alarm.id.startsWith('mi:')) return alarm;
      final wanted = alarm.department == department;
      if (alarm.isActive == wanted) return alarm;
      changed = true;
      return alarm.copyWith(isActive: wanted);
    }).toList();
    return changed ? updated : alarms;
  }

  /// Arms or pauses every reference point of one department, leaving the
  /// others untouched.
  static List<LocationAlarm> setDepartment(
      List<LocationAlarm> alarms, String department, bool armed) {
    var changed = false;
    final updated = alarms.map((alarm) {
      if (alarm.department != department || !_isImported(alarm)) return alarm;
      if (alarm.isActive == armed) return alarm;
      changed = true;
      return alarm.copyWith(isActive: armed);
    }).toList();
    return changed ? updated : alarms;
  }

  /// Pauses departmental imports, leaving the user's own places alone.
  static List<LocationAlarm> pauseAll(List<LocationAlarm> alarms) {
    var changed = false;
    final updated = alarms.map((alarm) {
      if (alarm.department == null || !_isImported(alarm) || !alarm.isActive) return alarm;
      changed = true;
      return alarm.copyWith(isActive: false);
    }).toList();
    return changed ? updated : alarms;
  }
}
