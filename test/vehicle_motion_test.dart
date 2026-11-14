import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:locreminder/models/vehicle_motion.dart';

VehicleFix fix(int time,
        {double lon = 0,
        double accuracy = 2,
        double? speed,
        double? bearing,
        int age = 0}) =>
    VehicleFix(
        position: LatLng(0, lon),
        accuracy: accuracy,
        elapsedMillis: time,
        ageMillis: age,
        speed: speed,
        bearing: bearing);
void main() {
  test('native speed updates even at identical rounded coordinates', () {
    final m = VehicleMotion();
    m.accept(fix(1000, speed: 5));
    m.accept(fix(2000, speed: 10, bearing: 90));
    expect(m.speedMps, 10);
    expect(m.bearing, 90);
  });
  test('coarse network fix does not displace a recent precise fix', () {
    final m = VehicleMotion();
    m.accept(fix(1000, speed: 5));
    expect(m.accept(fix(2000, lon: .02, accuracy: 500)), isFalse);
    expect(m.previous!.position.longitude, 0);
  });
  test('derive only from movement larger than uncertainty and short intervals',
      () {
    final m = VehicleMotion();
    m.accept(fix(1000));
    m.accept(fix(3000, lon: .0005));
    expect(m.speedMps, inInclusiveRange(27, 29));
    expect(m.bearing, closeTo(90, .1));
    m.accept(fix(4000, lon: .00051));
    expect(m.speedMps, isNull);
  });
  test('old fix cannot supply a fresh displayed speed', () {
    final m = VehicleMotion();
    m.accept(fix(1000, speed: 20, age: 4000));
    expect(m.speedMps, isNull);
    expect(
        VehicleFix.parse({
          'latitude': 0,
          'longitude': 0,
          'accuracy': 2,
          'ageMillis': -1,
          'elapsedMillis': 1000
        }),
        isNull);
  });
}
