import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/services/map_coverage.dart';

void main() {
  test('regional polygon excludes neighbouring land within the bounding box',
      () {
    final masks =
        jsonDecode(File('assets/maps/coverage.json').readAsStringSync()) as Map;
    expect(masks.length, 21);
    expect(masks.containsKey('corse'), isFalse);
    expect(
        MapCoverage.contains(masks['haute-normandie'] as List, 49.443, 1.099),
        isTrue);
    expect(MapCoverage.contains(masks['haute-normandie'] as List, 49.0, 1.7),
        isFalse);
    expect(MapCoverage.contains(masks['poitou-charentes'] as List, 46.58, .34),
        isTrue);
  });
  test('holes are not advertised as covered', () {
    final rings = [
      {
        'hole': false,
        'points': [
          [0, 0],
          [3, 0],
          [3, 3],
          [0, 3]
        ]
      },
      {
        'hole': true,
        'points': [
          [1, 1],
          [2, 1],
          [2, 2],
          [1, 2]
        ]
      }
    ];
    expect(MapCoverage.contains(rings, .5, .5), isTrue);
    expect(MapCoverage.contains(rings, 1.5, 1.5), isFalse);
  });
}
