import 'package:latlong2/latlong.dart';

/// Source declarations for consultation only; never an armed LocationAlarm.
enum TrafficWindow {
  declared,
  forecast,
  scheduleUnknown,
  suspended,
  expired,
  ended,
  uncertain,
}

class TrafficGeometry {
  const TrafficGeometry({this.point, this.from, this.to});
  final LatLng? point, from, to;
  bool get hasCoordinates => point != null || from != null || to != null;
}

class TrafficRecord {
  const TrafficRecord({
    required this.id,
    required this.version,
    required this.kind,
    required this.signature,
    required this.updatedAt,
    required this.source,
    required this.real,
    required this.public,
    required this.probability,
    required this.validity,
    required this.terminal,
    required this.complexSchedule,
    required this.start,
    required this.end,
    required this.comments,
    required this.roads,
    required this.direction,
    required this.geometry,
    required this.details,
  });
  final String id, kind, signature, source, probability, validity;
  final int version;
  final DateTime updatedAt;
  final bool real, public, terminal, complexSchedule;
  final DateTime? start, end;
  final List<String> comments, roads, details;
  final String? direction;
  final TrafficGeometry geometry;

  TrafficWindow window(DateTime now) {
    if (terminal) return TrafficWindow.ended;
    if (!real || !public) return TrafficWindow.uncertain;
    if (validity == 'suspended') return TrafficWindow.suspended;
    if (start != null && end != null && end!.isBefore(start!)) {
      return TrafficWindow.uncertain;
    }
    if (end != null && !end!.isAfter(now)) return TrafficWindow.expired;
    if (start != null && start!.isAfter(now)) return TrafficWindow.forecast;
    if (complexSchedule) return TrafficWindow.scheduleUnknown;
    if (start == null || validity != 'definedByValidityTimeSpec') {
      return TrafficWindow.uncertain;
    }
    // An old prediction is not proof that the event actually started.
    if (probability != 'certain') return TrafficWindow.uncertain;
    return TrafficWindow.declared;
  }

  String get title => switch (kind) {
    'Accident' => 'Accident signalé',
    'AbnormalTraffic' => 'Circulation perturbée',
    'MaintenanceWorks' => 'Travaux d’entretien',
    'ConstructionWorks' => 'Chantier',
    'RoadOrCarriagewayOrLaneManagement' => 'Mesure de circulation',
    'GeneralObstruction' => 'Obstacle signalé',
    'VehicleObstruction' => 'Véhicule gênant',
    'AnimalPresenceObstruction' => 'Animaux signalés',
    'PoorEnvironmentConditions' => 'Conditions difficiles',
    'EnvironmentalObstruction' => 'Obstacle lié à l’environnement',
    'WeatherRelatedRoadConditions' => 'État de la chaussée',
    'NonWeatherRelatedRoadConditions' => 'État de la chaussée',
    'WinterDrivingManagement' => 'Intervention hivernale',
    'SpeedManagement' => 'Mesure de vitesse',
    _ => 'Événement routier',
  };
}

class TrafficSituation {
  const TrafficSituation(
    this.id,
    this.version,
    this.updatedAt,
    this.signature,
    this.records,
  );
  final String id, signature;
  final int version;
  final DateTime updatedAt;
  final List<TrafficRecord> records;
}

class TrafficPublication {
  const TrafficPublication({
    required this.publisher,
    required this.publishedAt,
    required this.method,
    required this.nextSequence,
    required this.situations,
  });
  final String publisher, method;
  final DateTime publishedAt;
  // TIPI content.xml identifies the first numbered update after this snapshot.
  final int? nextSequence;
  final List<TrafficSituation> situations;
}

class TrafficSnapshot {
  TrafficSnapshot({
    required this.publishedAt,
    required this.snapshotAt,
    required this.checkedAt,
    required this.firstSequence,
    required this.lastSequence,
    required Iterable<TrafficSituation> situations,
  }) : situations = List.unmodifiable(situations);
  final DateTime publishedAt, snapshotAt, checkedAt;
  final int firstSequence, lastSequence;
  final List<TrafficSituation> situations;
  Iterable<TrafficRecord> get records =>
      situations.expand((s) => s.records).where((r) => r.public && r.real);
  bool isStale(DateTime now) =>
      now.difference(publishedAt) > const Duration(minutes: 15) ||
      now.isBefore(checkedAt.subtract(const Duration(minutes: 2)));
}
