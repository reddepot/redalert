import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:locreminder/widgets/map_pin.dart';

/// Guards the one thing a map pin must never get wrong: its tip marks the
/// coordinate, not its middle.
void main() {
  testWidgets('the tip of the pin lands exactly on the coordinate',
      (tester) async {
    const point = LatLng(46.58, 0.34);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FlutterMap(
          options: const MapOptions(
            initialCenter: point,
            initialZoom: 9,
            // No interaction needed; the geometry is what is under test.
            interactionOptions: InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 44,
                  height: 44,
                  // flutter_map's convention is inverted compared with the
                  // usual Flutter alignment: topCenter means the whole widget
                  // sits *above* the point. This line is the regression.
                  alignment: Alignment.topCenter,
                  child: const MapPin(size: 44, color: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The point is the map's centre, so no projection maths is needed.
    final mapCentre = tester.getCenter(find.byType(FlutterMap));
    final pin = tester.getRect(find.byType(MapPin));

    expect((pin.bottomCenter - mapCentre).distance, lessThan(1.5),
        reason: 'the pin tip must sit on the coordinate, at every zoom');
    expect(pin.center.dy, lessThan(mapCentre.dy),
        reason: 'the body of the pin must be above the point');
  });
}
