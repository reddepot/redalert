// Exports real Flutter components over an explicitly illustrative map.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locreminder/screens/home_screen.dart';
import 'package:locreminder/theme/app_theme.dart';
import 'package:locreminder/widgets/app_drawer.dart';

void main() {
  testWidgets('export cockpit menu and driving map, light and dark',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
        const EventChannel('com.zaifears.locreminder/positions'),
        MockStreamHandler.inline(onListen: (_, sink) {}));
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.zaifears.locreminder/alarms'), (call) async {
      if (call.method == 'getLastKnownLocation' ||
          call.method == 'getCurrentLocation') {
        return {
          'latitude': 0.0,
          'longitude': 0.0,
          'accuracy': 8.0,
          'ageMillis': 0,
          'elapsedMillis': 1000,
          'speed': 14.0,
          'bearing': 30.0
        };
      }
      if (call.method == 'getPassageStatus') return {'stale': true};
      if (call.method == 'getWatchStatus') {
        return {'state': 'idle', 'armedCount': 0};
      }
      if (call.method == 'getActiveAlarmIds') return <String>[];
      if ([
        'isLocationEnabled',
        'canUseFullScreenIntent',
        'isIgnoringBatteryOptimizations'
      ].contains(call.method)) {
        return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (_) async => 1);
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf'
    }.entries) {
      await (FontLoader(entry.key)
            ..addFont(Future.value(ByteData.sublistView(File(
                    '$flutterRoot/bin/cache/artifacts/material_fonts/${entry.value}')
                .readAsBytesSync()))))
          .load();
    }
    final key = GlobalKey();
    Widget panel(ThemeData theme, Widget child) => SizedBox(
        width: 360,
        child: Theme(
            data: theme,
            child: MediaQuery(
                data: const MediaQueryData(
                    size: Size(360, 920), devicePixelRatio: 1),
                child: child)));
    await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
      key: key,
      child: Row(children: [
        panel(
            AppTheme.light(),
            const Scaffold(
                body: AppDrawer(
                    placeCount: 24,
                    armedCount: 8,
                    watchLabel: 'Surveillance active · position récente'))),
        panel(AppTheme.light(),
            const HomeScreen(tileLayer: _IllustrativeRoads(dark: false))),
        panel(AppTheme.dark(),
            const HomeScreen(tileLayer: _IllustrativeRoads(dark: true))),
      ]),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('build/previews/cockpit-light-dark.png');
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

class _IllustrativeRoads extends StatelessWidget {
  const _IllustrativeRoads({required this.dark});
  final bool dark;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: _RoadPainter(dark)),
        Positioned(
            top: 22,
            right: 16,
            child: Text(dark ? 'CARTE · NUIT' : 'CARTE · JOUR',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: dark
                        ? const Color(0xFFBDCAD4)
                        : const Color(0xFF596773)))),
        Positioned(
            left: 16,
            bottom: 164,
            right: 16,
            child: Text('PLAN ILLUSTRATIF · DONNÉES SYNTHÉTIQUES',
                style: TextStyle(
                    fontSize: 7,
                    color: dark ? Colors.white54 : Colors.black54))),
      ]);
}

class _RoadPainter extends CustomPainter {
  const _RoadPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(dark ? const Color(0xFF18232B) : const Color(0xFFE4E8E1),
        BlendMode.src);
    final block = Paint()
      ..color = dark ? const Color(0xFF26343C) : const Color(0xFFD3D9D0);
    for (var x = -20.0; x < size.width; x += 82) {
      for (var y = 20.0; y < size.height; y += 106) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, 57, 80), const Radius.circular(8)),
            block);
      }
    }
    final river = Path()
      ..moveTo(size.width * .78, -20)
      ..cubicTo(size.width * .1, size.height * .3, size.width * 1.4,
          size.height * .5, size.width * .45, size.height + 20);
    canvas.drawPath(
        river,
        Paint()
          ..color = dark ? const Color(0xFF294755) : const Color(0xFFB0CDD1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 35);
    final road = Path()
      ..moveTo(-40, size.height * .9)
      ..cubicTo(size.width * .6, size.height * .55, size.width * .25,
          size.height * .55, size.width + 30, size.height * .08);
    canvas.drawPath(
        road,
        Paint()
          ..color = dark ? const Color(0xFF4B5660) : const Color(0xFFB7C0BE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24);
    canvas.drawPath(
        road,
        Paint()
          ..color = dark ? const Color(0xFF7F817A) : const Color(0xFFF5EFDA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18);
    final lane = Path()
      ..moveTo(-20, size.height * .29)
      ..lineTo(size.width + 20, size.height * .68);
    canvas.drawPath(
        lane,
        Paint()
          ..color = dark ? const Color(0xFF59646A) : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9);
  }

  @override
  bool shouldRepaint(covariant _RoadPainter oldDelegate) =>
      dark != oldDelegate.dark;
}
