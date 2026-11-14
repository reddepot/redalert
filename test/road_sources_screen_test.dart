import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:locreminder/models/poi_type.dart';
import 'package:locreminder/screens/road_sources_screen.dart';
import 'package:locreminder/services/road_data_repository.dart';
import 'package:locreminder/theme/app_theme.dart';

class FixtureRoadData extends RoadDataRepository {
  bool lowOnly = false;
  @override
  Future<RoadImportBatch> railway(String code,
      {bool lowClearanceOnly = false, int? crossingClass}) async {
    lowOnly = lowClearanceOnly;
    return RoadImportBatch(alarms: [
      LocationAlarm(
          id: 'sncf:pn/synthetic',
          label: 'Synthetic',
          latitude: 0,
          longitude: 0,
          radiusMeters: 900,
          isActive: false,
          createdAt: DateTime.utc(2026),
          repeatOnEveryEntry: true,
          poiType: PoiType.levelCrossingLowClearance)
    ], provider: 'SNCF Réseau', snapshotAt: DateTime.utc(2026, 2, 18));
  }

  @override
  Future<RoadImportBatch> calming(String code) async =>
      throw const FormatException(
          'Réponse OSM incomplète. Aucun lieu importé.');
}

void main() {
  testWidgets(
      'offline source returns inactive preview only after explicit action',
      (tester) async {
    final data = FixtureRoadData();
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPadding);
    List<LocationAlarm>? returned;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      returned = await Navigator.push<List<LocationAlarm>>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => RoadSourcesScreen(
                                  kind: RoadDataKind.railway,
                                  repository: data)));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(returned, isNull);
    final lowFilter = find.widgetWithText(
        SwitchListTile, 'Difficultés pour véhicules surbaissés');
    await tester.scrollUntilVisible(lowFilter, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(lowFilter);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Charger ce département'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charger ce département'));
    await tester.pumpAndSettle();
    expect(data.lowOnly, isTrue);
    expect(returned, isNull);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('road-preview')), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byKey(const ValueKey('road-preview'))).dy,
        lessThanOrEqualTo(600 - 48));
    await tester.tap(find.byKey(const ValueKey('road-preview')));
    await tester.pumpAndSettle();
    expect(returned!.single.isActive, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'large text source layout stays reachable and partial data cannot preview',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: RoadSourcesScreen(
            kind: RoadDataKind.calming, repository: FixtureRoadData())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Interroger OpenStreetMap'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interroger OpenStreetMap'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('road-preview')), findsNothing);
    expect(find.text('Réponse OSM incomplète. Aucun lieu importé.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
