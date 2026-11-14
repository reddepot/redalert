import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:locreminder/screens/home_screen.dart';
import 'package:locreminder/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zaifears.locreminder/alarms');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var corrupt = false;
  var consumed = false;
  var missing = false;
  var unrelated = false;
  final place = LocationAlarm(
    id: 'synthetic-once',
    label: 'Synthetic reminder',
    latitude: 0,
    longitude: 0,
    radiusMeters: 100,
    isActive: true,
    createdAt: DateTime.utc(2026),
    repeatOnEveryEntry: false,
  );

  setUp(() {
    messenger.setMockStreamHandler(
      const EventChannel('com.zaifears.locreminder/positions'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    calls.clear();
    corrupt = false;
    consumed = false;
    missing = false;
    unrelated = false;
    SharedPreferences.setMockInitialValues({
      'location_alarms': [jsonEncode(place.toJson())],
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getAlarmState':
          return {
            'activeIds': [
              if (unrelated) 'unrelated-native',
              if (!consumed && !missing) place.id,
            ],
            'receipts': consumed
                ? {place.id: 'synthetic-token'}
                : <String, String>{},
            'corrupt': corrupt,
            'invalidRecords': corrupt ? 1 : 0,
          };
        case 'getActiveAlarmIds':
          return <String>[if (unrelated) 'unrelated-native'];
        case 'getPassageStatus':
          return {'stale': true};
        case 'getWatchStatus':
          return {
            'state': corrupt ? 'storage_error' : 'stopped',
            'armedCount': 0,
          };
        case 'acknowledgeAlarmReceipts':
          final saved = (await SharedPreferences.getInstance()).getStringList(
            'location_alarms',
          )!;
          expect(
            (jsonDecode(saved.single) as Map)['isActive'],
            isFalse,
            reason: 'a positive native receipt must survive until the inactive UI is durably saved',
          );
          consumed = false;
          return true;
        case 'repairAlarmStore':
          corrupt = false;
          return true;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (_) async => 0,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HomeScreen(tileLayer: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'last one-shot receipt is saved and acknowledged without rearming',
    (tester) async {
      consumed = true;
      await open(tester);
      expect(calls.where((c) => c.method == 'syncSelectedAlarms'), isEmpty);
      expect(
        calls.where((c) => c.method == 'acknowledgeAlarmReceipts'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'unrelated preserved native points keep watching after the last UI reminder is consumed',
    (tester) async {
      consumed = true;
      unrelated = true;
      await open(tester);
      expect(calls.where((c) => c.method == 'startLocationWatch'), isNotEmpty);
      expect(calls.where((c) => c.method == 'stopLocationWatch'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('missing one-shot is restored without a fictitious consumption', (
    tester,
  ) async {
    missing = true;
    await open(tester);
    final writes = calls
        .where((c) => c.method == 'syncSelectedAlarms')
        .toList();
    expect(writes, hasLength(1));
    expect(
      (writes.single.arguments as Map)['alarms'].single['isActive'],
      isTrue,
    );
    expect(calls.where((c) => c.method == 'acknowledgeAlarmReceipts'), isEmpty);
    final saved = (await SharedPreferences.getInstance()).getStringList(
      'location_alarms',
    )!;
    expect((jsonDecode(saved.single) as Map)['isActive'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('corrupt copy is preserved until explicit confirmed repair', (
    tester,
  ) async {
    corrupt = true;
    await open(tester);
    expect(
      calls.where(
        (c) =>
            c.method == 'syncSelectedAlarms' || c.method == 'repairAlarmStore',
      ),
      isEmpty,
    );
    await tester.tap(find.text('Réparer').first);
    await tester.pumpAndSettle();
    expect(find.text('Réparer la surveillance ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Réparer'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'repairAlarmStore'), hasLength(1));
    expect(corrupt, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
