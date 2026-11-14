import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:locreminder/services/offline_packs.dart';
import 'package:locreminder/widgets/offline_pack_layer.dart';

void main() {
  testWidgets(
    'position rebuilds and identical pack refreshes retain the vector source',
    (tester) async {
      final manifest = jsonDecode(
        await rootBundle.loadString('assets/maps/packs.json'),
      ) as Map;
      final packs = [
        for (final p in manifest['packs'] as List)
          {
            'id': p['id'],
            'state': 'ready',
            'bytes': p['bytes'],
            'total': p['bytes'],
          },
      ];
      var revision = 0;
      var night = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(OfflinePacks.channel, (call) async {
            if (call.method == 'tile') return <Uint8List>[];
            return {
              'enabled': true,
              'packs': [
                for (var i = 0; i < packs.length; i++)
                  {
                    ...packs[i],
                    if (i == 0) 'total': (packs[i]['total'] as int) + revision,
                  },
              ],
              'freeBytes': 100000,
              'requiredBytes': 0,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(OfflinePacks.channel, null),
      );
      late StateSetter rebuild;
      final controller = MapController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Theme(
                  data: night ? ThemeData.dark() : ThemeData.light(),
                  child: FlutterMap(
                    mapController: controller,
                    options: const MapOptions(
                      initialCenter: LatLng(49.443, 1.099),
                      initialZoom: 13,
                    ),
                    children: [
                      OfflinePackLayer(
                        fallback: const ColoredBox(color: Colors.white),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      final original = tester.widget<vt.VectorTileLayer>(
        find.byType(vt.VectorTileLayer),
      );
      final sources = original.tileProviders;
      rebuild(() {});
      await tester.pump();
      expect(
        identical(
          tester
              .widget<vt.VectorTileLayer>(find.byType(vt.VectorTileLayer))
              .tileProviders,
          sources,
        ),
        isTrue,
        reason: 'An ordinary UI/GPS tick must not rebuild stores and clear rendered tiles.',
      );
      await OfflinePacks.instance.refresh();
      await tester.pump();
      expect(
        identical(
          tester
              .widget<vt.VectorTileLayer>(find.byType(vt.VectorTileLayer))
              .tileProviders,
          sources,
        ),
        isTrue,
      );
      controller.move(const LatLng(49.4432, 1.0992), 13);
      await tester.pump();
      expect(
        identical(
          tester
              .widget<vt.VectorTileLayer>(find.byType(vt.VectorTileLayer))
              .tileProviders,
          sources,
        ),
        isTrue,
      );
      packs.setAll(0, packs.reversed.toList());
      await OfflinePacks.instance.refresh();
      await tester.pump();
      expect(
        identical(
          tester
              .widget<vt.VectorTileLayer>(find.byType(vt.VectorTileLayer))
              .tileProviders,
          sources,
        ),
        isTrue,
      );
      rebuild(() => night = true);
      await tester.pump();
      final dark = tester.widget<vt.VectorTileLayer>(
        find.byType(vt.VectorTileLayer),
      );
      expect(identical(dark.tileProviders, sources), isTrue);
      expect(identical(dark.theme, original.theme), isFalse);
      revision = 1;
      await OfflinePacks.instance.refresh();
      await tester.pump();
      expect(
        identical(
          tester
              .widget<vt.VectorTileLayer>(find.byType(vt.VectorTileLayer))
              .tileProviders,
          sources,
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      controller.dispose();
    },
  );
}
