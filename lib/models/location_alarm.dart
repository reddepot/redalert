import 'poi_provenance.dart';
import 'poi_type.dart';
import 'approach_radius.dart';

/// How often an alarm may ring, held as the set of weekdays it is armed on.
///
/// One field covers every choice the picker offers, in `DateTime.weekday`
/// numbering (1 = Monday … 7 = Sunday). Empty means once and then it is gone;
/// a single day is weekly; all seven is daily; anything else is a custom set.
///
/// Deliberately a set rather than an enum plus a payload. "Weekly" and "every
/// Tuesday and Thursday" differ only in how many days are in the set, and an
/// enum would have to carry the set anyway — then the two could disagree, and
/// the one the alarm actually fires on would be whichever the native side
/// happened to read.
abstract final class RepeatSchedule {
  /// Fires once, then deletes itself. The default, and what every alarm
  /// saved before repeats existed becomes on upgrade.
  static const Set<int> once = <int>{};

  static const Set<int> daily = {1, 2, 3, 4, 5, 6, 7};
  static const Set<int> weekdays = {1, 2, 3, 4, 5};
  static const Set<int> weekends = {6, 7};

  static const _names = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static const _longNames = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];

  /// Short name for weekday [day], 1 = Monday.
  static String shortName(int day) => _names[day - 1];

  /// How to say this schedule in a sentence.
  static String describe(Set<int> days) {
    if (days.isEmpty) return 'Une fois';
    if (days.length == 7) return 'Chaque jour';
    if (setEquals(days, weekdays)) return 'En semaine';
    if (setEquals(days, weekends)) return 'Le week-end';
    if (days.length == 1) return 'Chaque ${_longNames[days.first - 1]}';
    final sorted = days.toList()..sort();
    return sorted.map(shortName).join(', ');
  }

  /// Keeps only real weekday numbers, so a corrupt or hand-edited record
  /// cannot put an out-of-range day in front of the native side.
  static Set<int> sanitize(Iterable<int> days) =>
      days.where((d) => d >= 1 && d <= 7).toSet();

  static bool setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);
}

class LocationAlarm {
  const LocationAlarm({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.isActive,
    required this.createdAt,
    this.repeatDays = RepeatSchedule.once,
    this.repeatOnEveryEntry = false,
    this.poiType = PoiType.other,
    this.note = '',
    this.positionStatus = 'to_verify',
    this.positionAccuracyMeters,
    this.originalLatitude,
    this.originalLongitude,
    this.speedLimitKmh,
    this.department,
    this.adaptiveRadius = false,
    this.referenceSpeedKmh,
    this.roadContext = RoadContext.automatic,
    this.travelBearingDegrees,
    this.provenance,
  });

  final String id;

  /// What the user is here to do, in their words — "Buy medicine" — falling
  /// back to the name of the place when they do not type anything.
  final String label;

  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool adaptiveRadius;
  final int? referenceSpeedKmh;
  final RoadContext roadContext;
  final double? travelBearingDegrees;
  final PoiProvenance? provenance;
  final bool isActive;
  final DateTime createdAt;

  /// Weekdays this alarm is armed on; see [RepeatSchedule].
  final Set<int> repeatDays;
  final bool repeatOnEveryEntry;
  final PoiType poiType;
  final String note;
  final String positionStatus;
  final double? positionAccuracyMeters;

  /// Posted speed limit, when the source states one.
  ///
  /// Null means unknown, which is not the same as zero: the native side only
  /// warns about speed at a point whose limit it actually knows.
  final int? speedLimitKmh;

  /// Department code this point was imported for ("86"), or null for a place
  /// the user dropped by hand.
  ///
  /// Kept as the evidence the arming-by-department screen groups on. The label
  /// happens to start with the same code, but a user can rename a place, and
  /// the grouping must not follow the rename.
  final String? department;
  final double? originalLatitude;
  final double? originalLongitude;

  bool get repeats => repeatOnEveryEntry || repeatDays.isNotEmpty;

  /// How this alarm's schedule reads in the list.
  String get scheduleLabel => repeatOnEveryEntry
      ? 'À chaque passage'
      : RepeatSchedule.describe(repeatDays);

  /// Values the editor can change, including a known or cleared speed limit.
  bool hasSameEditableValues(LocationAlarm other) =>
      label == other.label &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      radiusMeters == other.radiusMeters &&
      repeatOnEveryEntry == other.repeatOnEveryEntry &&
      RepeatSchedule.setEquals(repeatDays, other.repeatDays) &&
      poiType == other.poiType &&
      note == other.note &&
      positionStatus == other.positionStatus &&
      positionAccuracyMeters == other.positionAccuracyMeters &&
      speedLimitKmh == other.speedLimitKmh &&
      adaptiveRadius == other.adaptiveRadius &&
      referenceSpeedKmh == other.referenceSpeedKmh &&
      roadContext == other.roadContext &&
      travelBearingDegrees == other.travelBearingDegrees;

  LocationAlarm copyWith({
    String? label,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    bool? isActive,
    Set<int>? repeatDays,
    bool? repeatOnEveryEntry,
    PoiType? poiType,
    String? note,
    String? positionStatus,
    double? positionAccuracyMeters,
    bool clearPositionAccuracy = false,
    int? speedLimitKmh,
    bool clearSpeedLimit = false,
    String? department,
    bool? adaptiveRadius,
    int? referenceSpeedKmh,
    RoadContext? roadContext,
    double? travelBearingDegrees,
    bool clearTravelBearing = false,
    PoiProvenance? provenance,
  }) {
    final auto = adaptiveRadius ?? this.adaptiveRadius;
    final limit = clearSpeedLimit ? null : speedLimitKmh ?? this.speedLimitKmh;
    final reference = referenceSpeedKmh ?? this.referenceSpeedKmh;
    return LocationAlarm(
      id: id,
      label: label ?? this.label,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: auto
          ? ApproachRadius.metres(poiType ?? this.poiType, limit, reference,
              context: roadContext ?? this.roadContext)
          : radiusMeters ?? this.radiusMeters,
      adaptiveRadius: auto,
      referenceSpeedKmh: reference,
      roadContext: roadContext ?? this.roadContext,
      travelBearingDegrees: clearTravelBearing
          ? null
          : travelBearingDegrees ?? this.travelBearingDegrees,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      repeatDays: repeatDays ?? this.repeatDays,
      repeatOnEveryEntry: repeatOnEveryEntry ?? this.repeatOnEveryEntry,
      poiType: poiType ?? this.poiType,
      note: note ?? this.note,
      positionStatus: positionStatus ?? this.positionStatus,
      positionAccuracyMeters: clearPositionAccuracy
          ? null
          : positionAccuracyMeters ?? this.positionAccuracyMeters,
      originalLatitude: originalLatitude ?? this.latitude,
      originalLongitude: originalLongitude ?? this.longitude,
      speedLimitKmh:
          clearSpeedLimit ? null : speedLimitKmh ?? this.speedLimitKmh,
      department: department ?? this.department,
      provenance: provenance ?? this.provenance,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        // Sorted so an unchanged alarm serialises identically every time,
        // which keeps a rewrite of the list from looking like an edit.
        'repeatDays': (repeatDays.toList()..sort()),
        'repeatOnEveryEntry': repeatOnEveryEntry,
        'passageModeExplicit': true,
        'poiType': poiType.name,
        'note': note,
        'positionStatus': positionStatus,
        'positionAccuracyMeters': positionAccuracyMeters,
        'originalLatitude': originalLatitude ?? latitude,
        'originalLongitude': originalLongitude ?? longitude,
        'speedLimitKmh': speedLimitKmh,
        'department': department,
        'adaptiveRadius': adaptiveRadius,
        'referenceSpeedKmh': referenceSpeedKmh,
        'roadContext': roadContext.name,
        'travelBearingDegrees': travelBearingDegrees,
        if (provenance != null) 'source': provenance!.toJson(),
      };

  factory LocationAlarm.fromJson(Map<String, dynamic> json) {
    final type = PoiType.fromName(json['poiType']);
    final auto = json['adaptiveRadius'] as bool? ??
        ((json['id'] as String).startsWith('mi:') &&
            json['repeatOnEveryEntry'] == true &&
            (json['radiusMeters'] as num) == 1000);
    final limit = (json['speedLimitKmh'] as num?)?.toInt();
    final context = RoadContext.fromName(json['roadContext']);
    final reference = (json['referenceSpeedKmh'] as num?)?.toInt();
    return LocationAlarm(
      id: json['id'] as String,
      label: json['label'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: auto
          ? ApproachRadius.metres(type, limit, reference, context: context)
          : (json['radiusMeters'] as num).toDouble(),
      adaptiveRadius: auto,
      referenceSpeedKmh: reference,
      roadContext: context,
      travelBearingDegrees: (json['travelBearingDegrees'] as num?)?.toDouble(),
      isActive: json['isActive'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      // Absent on every alarm saved before repeats existed, which is
      // exactly what those alarms were: one-shot.
      repeatDays: RepeatSchedule.sanitize(
        (json['repeatDays'] as List<dynamic>? ?? const [])
            .map((d) => (d as num).toInt()),
      ),
      repeatOnEveryEntry: json['repeatOnEveryEntry'] == true ||
          (json['passageModeExplicit'] != true &&
              type != PoiType.other &&
              (json['repeatDays'] as List? ?? const []).isEmpty),
      poiType: PoiType.fromName(json['poiType']),
      note: json['note'] as String? ?? '',
      positionStatus: json['positionStatus'] as String? ?? 'to_verify',
      positionAccuracyMeters:
          (json['positionAccuracyMeters'] as num?)?.toDouble(),
      originalLatitude:
          ((json['originalLatitude'] ?? json['latitude']) as num).toDouble(),
      originalLongitude:
          ((json['originalLongitude'] ?? json['longitude']) as num).toDouble(),
      speedLimitKmh: (json['speedLimitKmh'] as num?)?.toInt(),
      department: json['department'] as String?,
      provenance: PoiProvenance.tryParse(json['source']),
    );
  }
}
