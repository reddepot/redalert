import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/widgets/map_scale.dart';

void main() {
  test('scale responds to latitude and zoom and remains inside its width', () {
    final base = MapScale.measure(45, 12);
    final closer = MapScale.measure(45, 13);
    expect(closer.metres, lessThan(base.metres));
    final north = MapScale.measure(60, 12);
    expect(north.metres, lessThanOrEqualTo(base.metres));
    for (var z = 3.0; z <= 19; z += .25) {
      final scale = MapScale.measure(48, z);
      expect(scale.pixels, inInclusiveRange(1, 120));
    }
  });
}
