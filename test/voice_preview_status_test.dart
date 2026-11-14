import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/widgets/passage_voice_section.dart';

void main() {
  const channel = MethodChannel('com.zaifears.locreminder/alarms');
  String state = 'playing', asset = 'highSpeedBump_300';
  final calls = <MethodCall>[];
  bool statusTimeout = false;
  bool startedScreenOff = false;
  bool hasRequested = false;
  String? failureCode;
  setUp(() {
    state = 'playing';
    asset = 'highSpeedBump_300';
    calls.clear();
    statusTimeout = false;
    startedScreenOff = false;
    hasRequested = false;
    failureCode = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getPassageStatus') return {'voice': true};
      if (call.method == 'previewPassageVoice') {
        hasRequested = true;
        return true;
      }
      if (call.method == 'stopPassageVoicePreview') {
        state = 'cancelled';
        return null;
      }
      if (call.method == 'getVoicePreviewStatus') {
        if (!hasRequested) return {'state': 'idle'};
        if (statusTimeout) return Completer<Object?>().future;
        return {
          'state': state,
          'asset': asset,
          'startedWhileScreenOff': startedScreenOff,
          'failureCode': failureCode,
          'finishedWhileScreenOff': state == 'completed'
        };
      }
      return null;
    });
  });
  Future<void> selectBump(WidgetTester tester, {bool start = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: PassageVoiceSection()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-category-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ralentisseur').last);
    await tester.pumpAndSettle();
    if (start) {
      await tester.tap(find.byKey(const ValueKey('voice-preview-button')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
      'reader completion screen-off is distinct from merely requesting a preview',
      (tester) async {
    await selectBump(tester);
    expect(find.text('Essai en cours : Ralentisseur'), findsOneWidget);
    expect(find.textContaining('Fin de lecture confirmée'), findsNothing);
    state = 'completed';
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Essai terminé : Ralentisseur'), findsOneWidget);
    expect(find.text('Fin de lecture confirmée par le lecteur, écran éteint.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'unresponsive status reports an unconfirmed preview without crashing',
      (tester) async {
    statusTimeout = true;
    await selectBump(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Statut de lecture indisponible.'), findsOneWidget);
    expect(find.text('Essai terminé : Ralentisseur'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'delayed preview names the chosen type, sends five seconds and can cancel',
      (tester) async {
    state = 'scheduled';
    await selectBump(tester, start: false);
    final delayed = find.byKey(const ValueKey('voice-sleep-preview-button'));
    await tester.ensureVisible(delayed);
    await tester.pumpAndSettle();
    await tester.tap(delayed);
    await tester.pumpAndSettle();
    expect(
        calls
            .where((call) => call.method == 'previewPassageVoice')
            .single
            .arguments,
        {'poiType': 'highSpeedBump', 'delayMillis': 5000});
    expect(
        find.textContaining('Essai programmé : Ralentisseur.'), findsOneWidget);
    final cancel = find.byKey(const ValueKey('voice-cancel-preview-button'));
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('Essai arrêté'), findsOneWidget);
    expect(
        calls.any((call) => call.method == 'stopPassageVoicePreview'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'wake recovers native completion after the UI status request failed',
      (tester) async {
    await selectBump(tester);
    statusTimeout = true;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Statut de lecture indisponible.'), findsOneWidget);
    statusTimeout = false;
    startedScreenOff = true;
    state = 'completed';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Essai terminé : Ralentisseur'), findsOneWidget);
    expect(find.text('Statut de lecture indisponible.'), findsNothing);
    expect(
        find.text(
            'Annonce commencée et terminée écran éteint, selon le lecteur.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'background UI recreation restores the completed native test without replay',
      (tester) async {
    state = 'scheduled';
    await selectBump(tester, start: false);
    final delayed = find.byKey(const ValueKey('voice-sleep-preview-button'));
    await tester.ensureVisible(delayed);
    await tester.pumpAndSettle();
    await tester.tap(delayed);
    await tester.pumpAndSettle();
    final stopsBefore =
        calls.where((c) => c.method == 'stopPassageVoicePreview').length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls.where((c) => c.method == 'stopPassageVoicePreview').length,
        stopsBefore);
    state = 'completed';
    startedScreenOff = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: PassageVoiceSection()))));
    await tester.pumpAndSettle();
    expect(find.text('Essai terminé : Ralentisseur'), findsOneWidget);
    expect(
        find.text(
            'Annonce commencée et terminée écran éteint, selon le lecteur.'),
        findsOneWidget);
    expect(calls.where((c) => c.method == 'previewPassageVoice').length, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'restored audio focus failure stays a failure with an understandable cause',
      (tester) async {
    hasRequested = true;
    state = 'error';
    failureCode = 'audio_focus_lost:-2';
    await selectBump(tester, start: false);
    expect(
        find.text(
            'La sortie audio a été reprise par le système ou une autre application.'),
        findsOneWidget);
    expect(find.text('Essai terminé : Ralentisseur'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'unexpected native category stops the test and never reports success',
      (tester) async {
    asset = 'fixedCamera_300';
    await selectBump(tester);
    expect(find.text('Catégorie de l’essai non confirmée.'), findsOneWidget);
    expect(find.text('Essai terminé : Ralentisseur'), findsNothing);
    expect(
        calls.any((call) => call.method == 'stopPassageVoicePreview'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
