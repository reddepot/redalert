import 'package:flutter/material.dart';

import '../models/poi_type.dart';

/// The colour and icon that stand for a kind of place, everywhere it is drawn.
///
/// Type colours deliberately use different hue families, independent of the
/// Crimson brand palette. A distinct glyph complements the colour on the map,
/// in the list and in the legend.
class PoiStyle {
  const PoiStyle({
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;

  /// Deliberately no `PoiType.other` entry: the fallback below is that entry,
  /// and having it twice would let the two disagree.
  static const Map<PoiType, PoiStyle> _byType = {
    PoiType.fixedCamera: PoiStyle(
      color: Color(0xFF7B1FA2),
      icon: Icons.photo_camera_outlined,
    ),
    PoiType.redLightCamera: PoiStyle(
      color: Color(0xFFD32F2F),
      icon: Icons.traffic_outlined,
    ),
    PoiType.averageSpeedCamera: PoiStyle(
      color: Color(0xFF007F86),
      icon: Icons.linear_scale,
    ),
    PoiType.levelCrossing: PoiStyle(
      color: Color(0xFF37474F),
      icon: Icons.train_outlined,
    ),
    PoiType.levelCrossingLowClearance: PoiStyle(
      color: Color(0xFF9E4C00),
      icon: Icons.priority_high,
    ),
    PoiType.highSpeedBump: PoiStyle(
      color: Color(0xFF2E7D32),
      icon: Icons.waves,
    ),
    PoiType.sharpTurn:
        PoiStyle(color: Color(0xFFBF360C), icon: Icons.turn_sharp_right),
    PoiType.rumbleStrip:
        PoiStyle(color: Color(0xFF00695C), icon: Icons.view_week_outlined),
    PoiType.roadDip:
        PoiStyle(color: Color(0xFF5D4037), icon: Icons.vertical_align_bottom),
    PoiType.roadNarrowing:
        PoiStyle(color: Color(0xFF455A64), icon: Icons.compress),
    PoiType.steepDescent:
        PoiStyle(color: Color(0xFF4527A0), icon: Icons.downhill_skiing),
    PoiType.roadWorks:
        PoiStyle(color: Color(0xFFEF6C00), icon: Icons.construction),
    PoiType.trafficJam: PoiStyle(color: Color(0xFF827717), icon: Icons.traffic),
    PoiType.dangerZone: PoiStyle(
      color: Color(0xFFF9A825),
      icon: Icons.warning_amber_rounded,
    ),
  };

  /// Pink is reserved for places outside the catalogue types.
  static const PoiStyle _fallback = PoiStyle(
    color: Color(0xFFC2187A),
    icon: Icons.place_outlined,
  );

  static PoiStyle of(PoiType type) => _byType[type] ?? _fallback;

  /// The colour to paint a pin when the place is not armed.
  ///
  /// Blended towards the surrounding surface rather than made translucent: a
  /// half-opaque pin lets the map's own colours through and the type stops
  /// being readable, which is exactly the information a paused pin still has
  /// to carry.
  ///
  /// The direction of that blend follows the theme. On a pale map a paused
  /// pin is washed towards the light surface; on the night map the same
  /// operation lands on near-black, so the pin disappears into the tiles
  /// instead of receding. There it is lightened toward white, which keeps the
  /// hue and still reads as "not armed".
  static Color pausedColor(PoiType type, ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? Color.lerp(of(type).color, Colors.white, 0.42)!
          : Color.alphaBlend(
              of(type).color.withValues(alpha: 0.38), scheme.surface);

  /// The outline that separates a pin from the map behind it.
  ///
  /// Follows the same reasoning: a surface-coloured ring vanishes on the dark
  /// map, so night mode uses a light ring.
  static Color pinBorder(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.82)
          : scheme.surface;

  /// Select a monochrome glyph that remains legible on active and paused fills.
  static Color pinInk(Color fill) =>
      fill.computeLuminance() > 0.179 ? Colors.black : Colors.white;

  /// Keep type labels legible even when the map colour is deliberately bright.
  static Color readable(PoiType type, ColorScheme scheme) {
    final base = scheme.brightness == Brightness.dark
        ? Color.lerp(of(type).color, Colors.white, 0.6)!
        : of(type).color;
    final background = scheme.surface.computeLuminance();
    final toward =
        scheme.brightness == Brightness.dark ? Colors.white : Colors.black;
    for (var step = 0; step <= 10; step++) {
      final candidate = Color.lerp(base, toward, step / 10)!;
      final light = candidate.computeLuminance();
      final ratio = light > background
          ? (light + 0.05) / (background + 0.05)
          : (background + 0.05) / (light + 0.05);
      if (ratio >= 4.5) return candidate;
    }
    return toward;
  }
}
