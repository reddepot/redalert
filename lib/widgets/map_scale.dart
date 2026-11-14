import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Metric ground distance represented by a short bar in Web Mercator.
class MapScale extends StatelessWidget {
  const MapScale({super.key});

  static ({double metres, double pixels}) measure(double latitude, double zoom,
      {double maxWidth = 120}) {
    final metresPerPixel = 40075016.68557849 *
        math.cos(latitude * math.pi / 180) /
        (256 * math.pow(2, zoom));
    final available = maxWidth * metresPerPixel;
    final power =
        math.pow(10, (math.log(available) / math.ln10).floor()).toDouble();
    final metres =
        [5.0, 2.0, 1.0].map((n) => n * power).firstWhere((n) => n <= available);
    return (metres: metres, pixels: metres / metresPerPixel);
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final scale = measure(camera.center.latitude, camera.zoom);
    final label = scale.metres >= 1000
        ? '${(scale.metres / 1000).toStringAsFixed(0)} km'
        : '${scale.metres.round()} m';
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
        label: 'Échelle : $label',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 12,
                    shadows: [Shadow(color: scheme.surface, blurRadius: 3)])),
            Container(
                width: scale.pixels,
                height: 7,
                decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(color: scheme.onSurface, width: 2),
                        right: BorderSide(color: scheme.onSurface, width: 2),
                        bottom:
                            BorderSide(color: scheme.onSurface, width: 2)))),
          ]),
        ));
  }
}
