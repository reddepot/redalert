/// Published station aggregates, independent of POIs and native alarms.
class RoadMeasurement {
  const RoadMeasurement({
    required this.id,
    required this.measuredAt,
    this.meanSpeedKmh,
    this.vehiclesPerHour,
    this.trafficState,
    this.axis,
    this.direction,
  });
  final String id;
  final DateTime measuredAt;
  final double? meanSpeedKmh, vehiclesPerHour;
  final String? trafficState, axis, direction;
  bool fresh(DateTime now) =>
      now.difference(measuredAt) >= const Duration(minutes: -2) &&
      now.difference(measuredAt) <= const Duration(minutes: 15);
  String get stateLabel => switch (trafficState) {
    'freeFlow' => 'Fluide',
    'heavyTraffic' => 'Dense',
    'congested' => 'Congestionné',
    'impossible' => 'Circulation impossible déclarée',
    _ => 'État inconnu',
  };
}

class RoadMeasurementSnapshot {
  const RoadMeasurementSnapshot({
    required this.publisher,
    required this.checkedAt,
    required this.rows,
    this.publishedAt,
    this.referenceShifted = false,
    this.omittedRows = 0,
  });
  final String publisher;
  final DateTime checkedAt;
  final DateTime? publishedAt;
  final List<RoadMeasurement> rows;
  final bool referenceShifted;
  final int omittedRows;
  bool publicationFresh(DateTime now) =>
      publishedAt == null ||
      (now.difference(publishedAt!) >= const Duration(minutes: -2) &&
          now.difference(publishedAt!) <= const Duration(minutes: 15));
}
