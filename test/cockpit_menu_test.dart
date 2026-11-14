import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/theme/app_theme.dart';
import 'package:locreminder/widgets/app_drawer.dart';
import 'package:locreminder/widgets/passage_voice_section.dart';
import 'package:locreminder/screens/road_audio_settings_screen.dart';

void main() {
  const channel = MethodChannel('com.zaifears.locreminder/alarms');
  final calls = <MethodCall>[];
  var audio = true;
  setUp(() {
    calls.clear();
    audio = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setPassageAudio') {
        audio = (call.arguments as Map)['enabled'] == true;
      }
      if (call.method == 'getPassageStatus') {
        return {
          'audio': audio,
          'voice': true,
          'level2': true,
          'speedAlerts': true
        };
      }
      if (call.method == 'previewPassageVoice') return true;
      return null;
    });
  });
  testWidgets(
      'voice selector has its own accessible target rather than the whole card',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(child: PassageVoiceSection()))));
      await tester.pumpAndSettle();
      final node = tester
          .getSemantics(find.byKey(const ValueKey('voice-category-selector')));
      expect(node.label, contains('Radar fixe'));
      expect(node.label, isNot(contains('Une annonce à l’approche')));
      expect(node.rect.height, lessThan(160));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
      'menu groups navigation and keeps audio switches in their own screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBar(),
          drawer: const AppDrawer(placeCount: 4, armedCount: 2),
          body: const SizedBox.shrink(),
        )));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('CONDUITE'), findsOneWidget);
    expect(find.text('MES LIEUX'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('RÉGLAGES'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('RÉGLAGES'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.ensureVisible(find.text('Alertes et voix'));
    await tester.tap(find.text('Alertes et voix'));
    await tester.pumpAndSettle();
    expect(find.byType(RoadAudioSettingsScreen), findsOneWidget);
    await tester.tap(
        find.widgetWithText(SwitchListTile, 'Audio des points de passage'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'setPassageAudio').single.arguments,
        {'enabled': false});
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(
                SwitchListTile, 'Audio des points de passage'))
            .value,
        isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'selected bump preview sends the bump type and visibly names the played category',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: PassageVoiceSection()),
        )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-category-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ralentisseur').last);
    await tester.pumpAndSettle();
    expect(find.text('Écouter : Ralentisseur'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ralentisseur,'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-preview-button')));
    await tester.pumpAndSettle();
    expect(
        calls.where((c) => c.method == 'previewPassageVoice').single.arguments,
        {'poiType': 'highSpeedBump'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'sleep preview remains reachable with large text and navigation insets',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: const RoadAudioSettingsScreen()));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('voice-sleep-preview-button'));
    await tester.scrollUntilVisible(button, 280,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(640 - 48));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        calls.where((c) => c.method == 'previewPassageVoice').single.arguments,
        {'poiType': 'fixedCamera', 'delayMillis': 5000});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'menu remains scrollable with large text and library actions stay explicit',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var imports = 0, toggles = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            appBar: AppBar(),
            drawer: AppDrawer(
                onImport: () => imports++, onToggleReference: () => toggles++),
            body: const SizedBox.shrink())));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Catalogues et légende'), 240,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Catalogues et légende'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catalogues et légende'));
    await tester.pumpAndSettle();
    expect(imports, 0);
    expect(toggles, 0);
    await tester.ensureVisible(find.text('Importer un catalogue'));
    await tester.tap(find.text('Importer un catalogue'));
    await tester.pumpAndSettle();
    expect(imports, 1);
    expect(toggles, 0);
    expect(tester.takeException(), isNull);
  });
}
