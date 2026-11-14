import 'package:flutter/material.dart';

/// One filter for the assembled raster layer; no per-tile saveLayer allocation.
abstract final class MapPalette {
  static const rasterDay = ColorFilter.matrix([
    1.12,
    0,
    0,
    0,
    -24,
    0,
    1.12,
    0,
    0,
    -24,
    0,
    0,
    1.12,
    0,
    -24,
    0,
    0,
    0,
    1,
    0,
  ]);

  // Invert luminance while retaining chrominance (C' = C + 270 - 2Y).
  // Unlike three identical rows this keeps water and road colours distinct.
  static const rasterNight = ColorFilter.matrix([
    .5748,
    -1.4304,
    -.1444,
    0,
    270,
    -.4252,
    -.4304,
    -.1444,
    0,
    270,
    -.4252,
    -1.4304,
    .8556,
    0,
    270,
    0,
    0,
    0,
    1,
    0,
  ]);
}
