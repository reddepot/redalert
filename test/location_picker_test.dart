import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locreminder/models/poi_type.dart';
import 'package:locreminder/screens/location_picker_screen.dart';
import 'package:locreminder/services/geocoding_service.dart';
import 'package:locreminder/widgets/placement_target.dart';
import 'package:locreminder/theme/app_theme.dart';

class _LocalGeocoder extends GeocodingService {
  @override
  Future<String?> reverse(double latitude, double longitude) async =>
      'Repère synthétique';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> open(WidgetTester tester, Size size, double scale,
      void Function(PickedLocation?) result,
      {bool destinationOnly = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: ElevatedButton(
                  onPressed: () async =>
                      result(await Navigator.of(context).push<PickedLocation>(
                        MaterialPageRoute(
                            builder: (_) => LocationPickerScreen(
                                  initialCenter: const LatLng(0, 0),
                                  destinationOnly: destinationOnly,
                                  geocodingService: _LocalGeocoder(),
                                  tileLayer: const SizedBox.shrink(),
                                )),
                      )),
                  child: const Text('Ouvrir')))),
    ));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'target is centred in visible map and saved point follows a 5m nudge',
      (tester) async {
    PickedLocation? picked;
    await open(tester, const Size(360, 800), 1, (p) => picked = p);
    expect(tester.getCenter(find.byType(PlacementTarget)),
        tester.getCenter(find.byType(FlutterMap)));
    for (final label in ['Déplacer vers l’est', 'Zoom avant', 'Zoom arrière']) {
      final size = tester.getSize(find.byTooltip(label));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byTooltip('Déplacer vers l’est'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser ce centre'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('Régler l’alerte'), findsOneWidget);
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(
        const Distance().as(LengthUnit.Meter, const LatLng(0, 0),
            LatLng(picked!.latitude, picked!.longitude)),
        closeTo(5, 0.2));
    expect(picked!.positionAccuracyMeters, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'keyboard keeps target visible and back returns from settings to placement',
      (tester) async {
    await open(tester, const Size(360, 800), 1, (_) {});
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FlutterMap)).height, greaterThan(140));
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser ce centre'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlacementTarget), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('zoom preserves the accuracy of an explicit GPS capture',
      (tester) async {
    PickedLocation? picked;
    const channel = MethodChannel('com.zaifears.locreminder/alarms');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getCurrentLocation'
            ? {
                'latitude': 0.0,
                'longitude': 0.0,
                'accuracy': 8.0,
                'ageMillis': 100
              }
            : null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await open(tester, const Size(360, 800), 1, (p) => picked = p);
    await tester.tap(find.byTooltip('Placer le centre sur ma position GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom avant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser ce centre'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();
    expect(picked!.positionStatus, 'gps_captured');
    expect(picked!.positionAccuracyMeters, 8);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late GPS response cannot overwrite a newer manual placement',
      (tester) async {
    PickedLocation? picked;
    final fix = Completer<Map<String, Object>>();
    const channel = MethodChannel('com.zaifears.locreminder/alarms');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            call.method == 'getCurrentLocation' ? await fix.future : null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await open(tester, const Size(360, 800), 1, (p) => picked = p);
    await tester.tap(find.byTooltip('Placer le centre sur ma position GPS'));
    await tester.pump();
    await tester.tap(find.byTooltip('Déplacer vers l’est'));
    await tester.pumpAndSettle();
    fix.complete({
      'latitude': 0.0,
      'longitude': -0.001,
      'accuracy': 8.0,
      'ageMillis': 100
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser ce centre'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();
    expect(picked!.longitude, greaterThan(0));
    expect(picked!.positionAccuracyMeters, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'type and note are visible, the coloured sheet changes the type, and '
      'the check in the app bar saves', (tester) async {
    PickedLocation? picked;
    await open(tester, const Size(360, 800), 1, (p) => picked = p);
    await tester.tap(find.text('Utiliser ce centre'));
    await tester.pumpAndSettle();

    // Visible without unfolding anything: the type is what the user came to
    // correct, and it is what colours the pin.
    expect(find.text('Autre lieu'), findsOneWidget);
    expect(find.text('Repères sur place'), findsOneWidget);

    final save = find.byTooltip('Enregistrer');
    expect(save, findsOneWidget);
    expect(tester.getSize(save).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(save).height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('Autre lieu'));
    await tester.pumpAndSettle();
    expect(find.text('Radar de feu rouge'), findsOneWidget);
    await tester.tap(find.text('Radar de feu rouge'));
    await tester.pumpAndSettle();
    expect(find.text('Radar de feu rouge'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Repères sur place'),
        'Feu à gauche, juste après le pont');
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.poiType, PoiType.redLightCamera);
    expect(picked!.note, 'Feu à gauche, juste après le pont');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('two-finger turn keeps north up while allowing zoom',
      (tester) async {
    await open(tester, const Size(360, 800), 1, (_) {});
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final center = tester.getCenter(find.byType(FlutterMap));
    final first =
        await tester.startGesture(center + const Offset(-40, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(40, 0), pointer: 2);
    await tester.pump();
    await first.moveTo(center + const Offset(-65, -55));
    await second.moveTo(center + const Offset(65, 55));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(map.mapController!.camera.rotation, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('destination selection skips alarm settings', (tester) async {
    PickedLocation? result;
    await open(tester, const Size(360, 800), 1, (p) => result = p,
        destinationOnly: true);
    await tester.tap(find.text('Choisir cette destination'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(find.text('Régler l’alerte'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('a newly added road hazard defaults to spoken passage mode',
      (tester) async {
    PickedLocation? result;
    await open(tester, const Size(360, 800), 1, (p) => result = p);
    await tester.tap(find.text('Utiliser ce centre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autre lieu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ralentisseur'));
    await tester.tap(find.text('Ralentisseur'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();
    expect(result!.poiType, PoiType.highSpeedBump);
    expect(result!.repeatOnEveryEntry, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (size, scale) in [
    (const Size(320, 640), 2.0),
    (const Size(640, 360), 1.0)
  ]) {
    testWidgets(
        'map centre and placement action stay usable at $size scale $scale',
        (tester) async {
      await open(tester, size, scale, (_) {});
      expect(tester.takeException(), isNull);
      final target = tester.getRect(find.byType(PlacementTarget));
      final map = tester.getRect(find.byType(FlutterMap));
      expect(map.contains(target.center), isTrue);
      expect(map.height, greaterThan(140));
      await tester.ensureVisible(find.text('Utiliser ce centre'));
      await tester.tap(find.text('Utiliser ce centre'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
