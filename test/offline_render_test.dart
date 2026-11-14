import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('real Shortbread roads render without a network provider',
      (tester) async {
    final theme = const vt.ThemeReader().read(
        jsonDecode(File('assets/maps/shortbread.json').readAsStringSync())
            as Map<String, Object?>);
    final provider = vt.MemoryVectorTileProvider(maximumZoom: 13, tiles: {
      const vt.TileKey(13, 4121, 2797):
          File('test/fixtures/shortbread-rouen.pbf').readAsBytesSync()
    });
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RepaintBoundary(
                key: boundaryKey,
                child: FlutterMap(
                    options: const MapOptions(
                        initialCenter: LatLng(49.443, 1.099),
                        initialZoom: 14,
                        interactionOptions:
                            InteractionOptions(flags: InteractiveFlag.none)),
                    children: [
                      vt.VectorTileLayer(
                          theme: theme,
                          tileProviders:
                              vt.TileProviders({'shortbread': provider}),
                          concurrency: 1)
                    ])))));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(tester.takeException(), isNull);
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage());
    final data = await tester.runAsync(() => image!.toByteData());
    final pixels = data!.buffer.asUint32List();
    expect(pixels.toSet().length, greaterThan(12),
        reason:
            'Roads, buildings and labels must paint more than an empty background');
    image!.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
