import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/services/mvt_merge.dart';
// Use the renderer's actual decoder to verify merged features and dictionaries.
// ignore: implementation_imports
import 'package:flutter_map_vector_tiles/src/mvt/mvt_decoder.dart';

List<int> field(int number, List<int> value) => [
  (number << 3) | 2,
  ...variable(value.length),
  ...value,
];
List<int> variable(int value) {
  final out = <int>[];
  while (value >= 128) {
    out.add((value & 127) | 128);
    value >>= 7;
  }
  return [...out, value];
}

Uint8List tile(String key, String value, int id) {
  final feature = [
    8,
    id,
    ...field(2, [0, 0]),
    24,
    1,
    ...field(4, [9, 2, 2]),
  ];
  final layer = [
    ...field(1, utf8.encode('places')),
    ...field(2, feature),
    ...field(3, utf8.encode(key)),
    ...field(4, field(1, utf8.encode(value))),
    40,
    128,
    32,
    120,
    2,
  ];
  return Uint8List.fromList(field(3, layer));
}

void main() {
  test(
    'one gzip archive is bounded and decoded before reaching the renderer',
    () {
      final original = tile('name', 'Synthetic', 1);
      final decoded = mergeRegionalTiles([
        Uint8List.fromList(gzip.encode(original)),
      ]);
      expect(decoded, original);
      final bomb = Uint8List.fromList(
        gzip.encode(Uint8List(maxDecodedTileBytes + 1)),
      );
      expect(() => mergeRegionalTiles([bomb]), throwsFormatException);
    },
  );
  test(
    'missing layer name is a typed error and oversized raw input is rejected',
    () {
      final broken = Uint8List.fromList(field(3, field(2, [8, 1])));
      expect(
        () => mergeRegionalTiles([broken, tile('name', 'Synthetic', 1)]),
        throwsFormatException,
      );
      expect(
        () => mergeRegionalTiles([Uint8List(maxCompressedTileBytes + 1)]),
        throwsFormatException,
      );
    },
  );

  test('field budget is shared across every regional layer', () {
    final layer = [
      ...field(1, utf8.encode('places')),
      for (var i = 0; i < 70; i++) ...field(3, utf8.encode('key')),
    ];
    final region = Uint8List.fromList([
      for (var i = 0; i < 1600; i++) ...field(3, layer),
    ]);
    expect(() => mergeRegionalTiles([region, region]), throwsFormatException);
  });

  test('both border fragments retain their own names and property keys', () {
    final merged = mergeRegionalTiles([
      tile('name', 'Rouen', 1),
      Uint8List.fromList(gzip.encode(tile('ref', 'D7', 2))),
    ]);
    final decoded = decodeMvt(merged);
    expect(decoded.layers, hasLength(1));
    final layer = decoded.layers.single;
    expect(layer.features, hasLength(2));
    expect(layer.features[0].decodeProperties(layer), {'name': 'Rouen'});
    expect(layer.features[1].decodeProperties(layer), {'ref': 'D7'});
  });
  test(
    'rejects broken regional payload without reading beyond its boundary',
    () {
      expect(
        () => mergeRegionalTiles([
          tile('name', 'A', 1),
          Uint8List.fromList([26, 128]),
        ]),
        throwsFormatException,
      );
    },
  );
}
