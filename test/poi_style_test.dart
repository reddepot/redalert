import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/poi_type.dart';
import 'package:locreminder/theme/poi_style.dart';

void main() {
  test('every kind of place has its own colour and icon', () {
    final colors = <Color>{};
    final icons = <IconData>{};
    for (final type in PoiType.values) {
      final style = PoiStyle.of(type);
      expect(colors.add(style.color), isTrue,
          reason: '${type.name} reuses a colour');
      expect(icons.add(style.icon), isTrue,
          reason: '${type.name} reuses an icon');
    }
    expect(colors.length, PoiType.values.length);
  });

  test('camera types use separate hue families instead of shades of red', () {
    final cameraTypes = [
      PoiType.fixedCamera,
      PoiType.redLightCamera,
      PoiType.averageSpeedCamera
    ];
    for (var a = 0; a < cameraTypes.length; a++) {
      for (var b = a + 1; b < cameraTypes.length; b++) {
        final hueA = HSVColor.fromColor(PoiStyle.of(cameraTypes[a]).color).hue;
        final hueB = HSVColor.fromColor(PoiStyle.of(cameraTypes[b]).color).hue;
        final gap = (hueA - hueB).abs();
        expect(gap > 180 ? 360 - gap : gap, greaterThan(60));
      }
    }
  });

  test('a paused pin keeps its hue but moves away from the armed one', () {
    final light = ColorScheme.fromSeed(
        seedColor: const Color(0xFF8F1734), brightness: Brightness.light);
    final dark = ColorScheme.fromSeed(
        seedColor: const Color(0xFF8F1734), brightness: Brightness.dark);
    for (final type in PoiType.values) {
      final armed = PoiStyle.of(type).color;
      final onLight = PoiStyle.pausedColor(type, light);
      final onDark = PoiStyle.pausedColor(type, dark);
      expect(onLight, isNot(armed));
      // Washed out on a pale map...
      expect(onLight.computeLuminance(), greaterThan(armed.computeLuminance()));
      // ...and lifted on the night map, where washing would have made it
      // vanish into the tiles.
      expect(onDark.computeLuminance(), greaterThan(armed.computeLuminance()));
    }
  });

  test('the readable variant stays legible on both themes', () {
    final dark = ColorScheme.fromSeed(
        seedColor: Colors.blue, brightness: Brightness.dark);
    final light = ColorScheme.fromSeed(
        seedColor: Colors.blue, brightness: Brightness.light);
    for (final type in PoiType.values) {
      final onDark = PoiStyle.readable(type, dark);
      final onLight = PoiStyle.readable(type, light);
      for (final pair in [(onDark, dark.surface), (onLight, light.surface)]) {
        final a = pair.$1.computeLuminance();
        final b = pair.$2.computeLuminance();
        final contrast =
            a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: type.name);
      }
    }
  });
}
