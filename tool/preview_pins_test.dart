// Run with `flutter test tool/preview_pins_test.dart` to refresh the palette preview.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/poi_type.dart';
import 'package:locreminder/theme/poi_style.dart';
import 'package:locreminder/widgets/map_pin.dart';

void main() {
  testWidgets('export the current map pin palette', (tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null) throw StateError('Run through flutter test.');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf'
    }.entries) {
      final font = File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/${entry.value}');
      await (FontLoader(entry.key)
            ..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync()))))
          .load();
    }
    final key = GlobalKey();
    Widget panel(Brightness brightness) {
      final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF8F1734), brightness: brightness);
      return Expanded(
          child: Container(
              color: scheme.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        brightness == Brightness.light
                            ? 'Carte claire'
                            : 'Carte sombre',
                        style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 24,
                            color: scheme.onSurface)),
                    const SizedBox(height: 14),
                    Row(children: [
                      const SizedBox(width: 250),
                      Text('Armé       En pause',
                          style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 16,
                              color: scheme.onSurface))
                    ]),
                    ...PoiType.values.map((type) => SizedBox(
                        height: 78,
                        child: Row(children: [
                          SizedBox(
                              width: 250,
                              child: Text(type.label,
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 18,
                                      color: PoiStyle.readable(type, scheme)))),
                          MapPin(
                              color: PoiStyle.of(type).color,
                              icon: PoiStyle.of(type).icon,
                              borderColor: PoiStyle.pinBorder(scheme)),
                          const SizedBox(width: 38),
                          MapPin(
                              color: PoiStyle.pausedColor(type, scheme),
                              paused: true,
                              icon: PoiStyle.of(type).icon,
                              borderColor: PoiStyle.pinBorder(scheme)),
                        ]))),
                  ])));
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RepaintBoundary(
                key: key,
                child: Row(children: [
                  panel(Brightness.light),
                  panel(Brightness.dark)
                ])))));
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('docs/images/pins-preview.png');
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
