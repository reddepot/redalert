import 'poi_type.dart';

enum RoadContext {
  automatic('Automatique'),
  urban('Ville'),
  road('Route'),
  motorway('Autoroute');

  const RoadContext(this.label);
  final String label;
  static RoadContext fromName(Object? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => automatic);
}

/// The monitoring envelope uses plausible travel speed, independently of a posted limit.
abstract final class ApproachRadius {
  static int referenceFor(PoiType type) => switch (type) {
        PoiType.redLightCamera => 70,
        PoiType.highSpeedBump => 50,
        PoiType.averageSpeedCamera => 130,
        PoiType.fixedCamera ||
        PoiType.levelCrossing ||
        PoiType.levelCrossingLowClearance =>
          110,
        _ => 80,
      };
  static int expectedSpeed(PoiType type, int? limitKmh, int? referenceKmh,
      {RoadContext context = RoadContext.automatic}) {
    final plausible = referenceKmh ??
        switch (context) {
          RoadContext.urban => 70,
          RoadContext.road => 110,
          RoadContext.motorway => 130,
          RoadContext.automatic => limitKmh == null
              ? referenceFor(type)
              : limitKmh >= 90
                  ? 130
                  : limitKmh >= 70
                      ? 110
                      : 70,
        };
    return (limitKmh != null && limitKmh > plausible ? limitKmh : plausible)
        .clamp(5, 200);
  }

  static double metres(PoiType type, int? limitKmh, int? referenceKmh,
      {RoadContext context = RoadContext.automatic}) {
    final speed = expectedSpeed(type, limitKmh, referenceKmh, context: context);
    final seconds = switch (type) {
      PoiType.averageSpeedCamera => 45,
      PoiType.highSpeedBump => 20,
      _ => 30
    };
    return ((speed / 3.6 * seconds / 50 - 1e-9).ceil() * 50.0).clamp(100, 3000);
  }
}
