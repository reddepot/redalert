// Renders a fixed public Shortbread fixture, never a personal map or location.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
// ignore: implementation_imports
import 'package:flutter_map_vector_tiles/src/render/label_painter.dart';

void main() {
  testWidgets('export day and night maps from the same public tile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The renderer exposes this hook because flutter test lacks system fonts.
    final fontPath =
        Platform.environment['REDALERT_PREVIEW_FONT'] ??
        '/System/Library/Fonts/Supplemental/Arial.ttf';
    final fontBytes = File(fontPath).readAsBytesSync();
    final loader = FontLoader('RedAlertPreview')
      ..addFont(Future.value(ByteData.sublistView(fontBytes)));
    await loader.load();
    LabelPainter.debugFontFamilies = ['RedAlertPreview'];
    addTearDown(() => LabelPainter.debugFontFamilies = null);
    for (final mode in ['day', 'night']) {
      final raw = File(
        'assets/maps/shortbread${mode == 'night' ? '-night' : ''}.json',
      ).readAsStringSync();
      final theme = const vt.ThemeReader().read(
        jsonDecode(raw) as Map<String, Object?>,
      );
      final providers = vt.TileProviders({
        'shortbread': vt.MemoryVectorTileProvider(
          maximumZoom: 13,
          tiles: {
            const vt.TileKey(13, 4121, 2797): File(
              'test/fixtures/shortbread-rouen.pbf',
            ).readAsBytesSync(),
          },
        ),
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(49.45384259433074, 1.12060546875),
                  initialZoom: 16,
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  vt.VectorTileLayer(
                    theme: theme,
                    tileProviders: providers,
                    concurrency: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage());
      final rgba = await tester.runAsync(() => image!.toByteData());
      expect(
        rgba!.buffer.asUint32List().toSet().length,
        greaterThan(50),
        reason: 'An empty background cannot validate map appearance.',
      );
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ImageByteFormat.png),
      );
      await tester.runAsync(() async {
        final file = File('build/previews/map-$mode-catalogue16.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      image!.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });
}
