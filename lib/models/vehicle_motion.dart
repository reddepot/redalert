import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class VehicleFix {
  VehicleFix(
      {required this.position,
      required this.accuracy,
      required this.elapsedMillis,
      required this.ageMillis,
      this.speed,
      this.bearing,
      this.speedAccuracy});
  final LatLng position;
  final double accuracy;
  final int elapsedMillis, ageMillis;
  final double? speed, bearing, speedAccuracy;
  static VehicleFix? parse(Map<Object?, Object?> row) {
    final lat = (row['latitude'] as num?)?.toDouble(),
        lon = (row['longitude'] as num?)?.toDouble();
    final accuracy = (row['accuracy'] as num?)?.toDouble();
    final age = (row['ageMillis'] as num?)?.toInt(),
        elapsed = (row['elapsedMillis'] as num?)?.toInt();
    if (lat == null ||
        lon == null ||
        accuracy == null ||
        age == null ||
        elapsed == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        age < 0) {
      return null;
    }
    return VehicleFix(
        position: LatLng(lat, lon),
        accuracy: accuracy,
        elapsedMillis: elapsed,
        ageMillis: age,
        speed: (row['speed'] as num?)?.toDouble(),
        bearing: (row['bearing'] as num?)?.toDouble(),
        speedAccuracy: (row['speedAccuracy'] as num?)?.toDouble());
  }
}

class VehicleMotion {
  VehicleFix? previous;
  double? speedMps, bearing;
  bool accept(VehicleFix fix) {
    final old = previous;
    if (old != null && fix.elapsedMillis < old.elapsedMillis) return false;
    if (old != null &&
        fix.elapsedMillis - old.elapsedMillis < 5000 &&
        old.accuracy <= 30 &&
        fix.accuracy > math.max(50, old.accuracy * 3)) {
      return false;
    }
    double? speed = fix.speed;
    if (fix.ageMillis > 3000 ||
        fix.accuracy > 50 ||
        speed == null ||
        !speed.isFinite ||
        speed < 0 ||
        speed > 70 ||
        (fix.speedAccuracy != null && fix.speedAccuracy! > 3)) {
      speed = null;
    }
    double? derivedBearing;
    if (old != null &&
        fix.elapsedMillis > old.elapsedMillis &&
        fix.ageMillis <= 3000 &&
        fix.accuracy <= 25 &&
        old.accuracy <= 25) {
      final dt = (fix.elapsedMillis - old.elapsedMillis) / 1000;
      final distance =
          const Distance().as(LengthUnit.Meter, old.position, fix.position);
      if (dt >= .5 &&
          dt <= 5 &&
          distance > math.max(5, old.accuracy + fix.accuracy)) {
        final derived = distance / dt;
        if (derived <= 70) {
          speed ??= derived;
          derivedBearing = const Distance().bearing(old.position, fix.position);
        }
      }
    }
    speedMps = speed;
    final course = fix.bearing;
    if (speed != null && speed >= 2 && fix.ageMillis <= 3000) {
      final next = course != null && course.isFinite ? course : derivedBearing;
      if (next != null) bearing = (next % 360 + 360) % 360;
    }
    previous = fix;
    return true;
  }
}
