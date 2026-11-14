import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
// ignore: implementation_imports
import 'package:flutter_map_vector_tiles/src/mvt/mvt_decoder.dart';
import 'package:locreminder/services/mvt_merge.dart';

void main() {
  test(
      'real downloaded Shortbread tile has roads, labels and matching offline style',
      () {
    final bytes = File('test/fixtures/shortbread-rouen.pbf').readAsBytesSync();
    final raw = Uint8List.fromList(gzip.decode(bytes));
    final tile = decodeMvt(raw);
    expect(tile.layer('streets')!.features, isNotEmpty);
    expect(tile.layer('street_labels')!.features, isNotEmpty);
    final source =
        jsonDecode(File('assets/maps/shortbread.json').readAsStringSync())
            as Map<String, Object?>;
    expect(source.containsKey('glyphs'), isFalse);
    expect(jsonEncode(source), isNot(contains('http')));
    final theme = const vt.ThemeReader().read(source);
    expect(theme.layers.length, (source['layers'] as List).length);
    final combined = decodeMvt(mergeRegionalTiles([bytes, bytes]));
    expect(combined.layer('streets')!.features.length,
        tile.layer('streets')!.features.length * 2);
  });
}
