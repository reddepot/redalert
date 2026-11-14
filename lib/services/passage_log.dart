import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One observed step of one passage, as the phone reported it.
class PassageLogEntry {
  const PassageLogEntry({
    required this.at,
    required this.label,
    required this.stage,
    required this.distanceMetres,
    required this.accuracyMetres,
    required this.stale,
  });

  final DateTime at;
  final String label;
  final String stage;
  final double? distanceMetres;
  final double? accuracyMetres;
  final bool stale;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'label': label,
        'stage': stage,
        'distance': distanceMetres,
        'accuracy': accuracyMetres,
        'stale': stale,
      };

  factory PassageLogEntry.fromJson(Map<String, dynamic> json) =>
      PassageLogEntry(
        at: DateTime.parse(json['at'] as String),
        label: json['label'] as String? ?? '',
        stage: json['stage'] as String? ?? '',
        distanceMetres: (json['distance'] as num?)?.toDouble(),
        accuracyMetres: (json['accuracy'] as num?)?.toDouble(),
        stale: json['stale'] == true,
      );
}

/// A bounded record of what the passage tracker actually saw.
///
/// Written for the one question a field test has to answer and the interface
/// cannot: did the phone observe the entry, the approach and the crossing, or
/// did it skip a stage because the fix jumped? The log stores the stage the
/// native side reported, with its distance and stated accuracy, so a missed
/// alert can be told apart from a GPS gap after the fact.
///
/// Only transitions are stored, never the per-second stream: three hundred
/// entries then cover a long drive instead of twenty minutes of standing still.
class PassageLog {
  static const _prefsKey = 'passage_log_v1';
  static const _maxEntries = 300;

  static List<PassageLogEntry> _cache = const [];
  static String? _lastSignature;

  static Future<List<PassageLogEntry>> load() async {
    if (_cache.isNotEmpty) return _cache;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => PassageLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return _cache = list;
    } catch (_) {
      // A truncated write costs the log, never the app.
      return const [];
    }
  }

  /// Records [entry] unless it repeats the previous one exactly, in which case
  /// the log would fill with the same line once per second.
  static Future<void> record(PassageLogEntry entry) async {
    final signature = '${entry.label}|${entry.stage}|${entry.stale}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    final existing = await load();
    final updated = [...existing, entry];
    _cache = updated.length > _maxEntries
        ? updated.sublist(updated.length - _maxEntries)
        : updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_cache.map((e) => e.toJson()).toList()));
  }

  static Future<void> clear() async {
    _cache = const [];
    _lastSignature = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// What to copy out of the app after a drive, in a shape that survives a
  /// paste into a message.
  static String export(List<PassageLogEntry> entries) {
    final buffer = StringBuffer('Journal de passage LocReminder\n');
    for (final entry in entries.reversed) {
      final time = entry.at.toIso8601String().substring(11, 19);
      final distance = entry.distanceMetres == null
          ? ''
          : ' · ${entry.distanceMetres!.round()} m';
      final accuracy = entry.accuracyMetres == null
          ? ''
          : ' · ±${entry.accuracyMetres!.round()} m';
      final stale = entry.stale ? ' · mesure périmée' : '';
      buffer.writeln(
          '$time · ${entry.stage}$distance$accuracy$stale — ${entry.label}');
    }
    return buffer.toString();
  }
}
