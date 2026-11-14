import 'package:locreminder/widgets/driving_speed.dart';
import 'package:locreminder/widgets/map_scale.dart';
import 'package:locreminder/widgets/map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locreminder/screens/home_screen.dart';
import 'package:locreminder/theme/app_theme.dart';
import 'package:locreminder/services/driving_route_observer.dart';

void main() {
  const positions = EventChannel('com.zaifears.locreminder/positions');
  const alarms = MethodChannel('com.zaifears.locreminder/alarms');
  MockStreamHandlerEventSink? events;
  final screenPolicy = <bool>[];
  Map<String, Object?> fix(int elapsed, {double lon = 0}) => {
        'latitude': 0.0,
        'longitude': lon,
        'accuracy': 2.0,
        'ageMillis': 0,
        'elapsedMillis': elapsed,
        'speed': 10.0,
        'bearing': 90.0
      };
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    screenPolicy.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarms, (call) async {
      if (call.method == 'setDrivingScreen') {
        screenPolicy.add((call.arguments as Map)['awake'] == true);
        return null;
      }
      if (call.method == 'getLastKnownLocation' ||
          call.method == 'getCurrentLocation') {
        return fix(1000);
      }
      if (call.method == 'getActiveAlarmIds') return <String>[];
      if (call.method == 'getPassageStatus') return {'stale': true};
      if (call.method == 'getWatchStatus') {
        return {'state': 'idle', 'armedCount': 0};
      }
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
        (call) async => 1);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(positions, null);
  });
  testWidgets(
      'map follows with no armed place, pan suspends and centre resumes, menu holds counters',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(positions,
            MockStreamHandler.inline(onListen: (args, sink) {
      events = sink;
    }));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        navigatorObservers: [drivingRouteObserver],
        home: const HomeScreen(tileLayer: SizedBox.shrink())));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Surveillance active · position récente'), findsNothing);
    expect(find.text('0 lieux'), findsNothing);
    expect(find.text('Lieu, adresse ou coordonnées'), findsNothing);
    expect(events, isNotNull);
    events!.success(fix(2000, lon: .001));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    expect(controller.camera.center.longitude, closeTo(.001, .000001));
    expect((controller.camera.rotation % 360 + 360) % 360, closeTo(270, .01));
    await tester.drag(find.byType(FlutterMap), const Offset(80, 0));
    await tester.pumpAndSettle();
    final explored = controller.camera.center;
    events!.success(fix(3000, lon: .002));
    await tester.pumpAndSettle();
    expect(controller.camera.center, explored);
    await tester.tap(find.byTooltip('Reprendre le suivi du véhicule'));
    await tester.pumpAndSettle();
    expect(controller.camera.center.longitude, closeTo(.002, .000001));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Mes lieux'), findsOneWidget);
    expect(find.text('Choisir une destination'), findsOneWidget);
    expect(screenPolicy, contains(true));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(screenPolicy.last, isFalse);
  });

  testWidgets('landscape and large text keep map controls inside the screen',
      (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(positions,
            MockStreamHandler.inline(onListen: (args, sink) {
      events = sink;
    }));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        navigatorObservers: [drivingRouteObserver],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: const HomeScreen(tileLayer: SizedBox.shrink())));
    await tester.pumpAndSettle();
    for (final tooltip in [
      'Zoom avant',
      'Zoom arrière',
      'Garder le nord en haut',
      'Centrer sur ma position',
      'Style de carte'
    ]) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(400));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(800));
    }
    final scale = tester.getRect(find.byType(MapScale));
    final credit = tester.getRect(find.byType(MapAttribution));
    final speed = tester.getRect(find.byType(DrivingSpeed));
    expect(scale.bottom, lessThanOrEqualTo(credit.top));
    expect(credit.bottom, lessThanOrEqualTo(speed.top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
