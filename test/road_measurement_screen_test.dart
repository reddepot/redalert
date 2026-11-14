import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/road_measurement.dart';
import 'package:locreminder/screens/road_measurement_screen.dart';
import 'package:locreminder/services/road_measurement_repository.dart';
import 'package:locreminder/theme/app_theme.dart';

class MemoryMeasures extends RoadMeasurementRepository {
  int requests = 0;
  bool valid = false;
  DateTime date = DateTime.utc(2026, 11, 13, 10);
  @override
  bool get verified => valid;
  @override
  Future<RoadMeasurementSnapshot> refresh({String? region}) async {
    requests++;
    valid = true;
    cachedRegion = region;
    return cached = RoadMeasurementSnapshot(
      publisher: 'Synthetic',
      checkedAt: date,
      publishedAt: date,
      rows: [
        RoadMeasurement(
          id: 'synthetic',
          measuredAt: date,
          axis: 'A1',
          meanSpeedKmh: 62,
          vehiclesPerHour: 300,
          trafficState: region == null ? null : 'heavyTraffic',
        ),
      ],
    );
  }

  @override
  void cancel() {
    valid = false;
  }
}

void main() {
  testWidgets(
    'download is explicit and row freshness expires without another request',
    (tester) async {
      final repo = MemoryMeasures();
      var now = repo.date;
      await tester.pumpWidget(
        MaterialApp(
          home: RoadMeasurementScreen(repository: repo, clock: () => now),
        ),
      );
      expect(repo.requests, 0);
      await tester.tap(find.text('Consulter la source publique'));
      await tester.pumpAndSettle();
      expect(repo.requests, 1);
      expect(find.text('62 km/h en moyenne · 300 véhicules/h'), findsOneWidget);
      expect(find.text('Non actuelle'), findsNothing);
      now = now.add(const Duration(minutes: 16));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Non actuelle'), findsOneWidget);
      expect(repo.requests, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'switching to states never labels a cached QTV row as a traffic state',
    (tester) async {
      final repo = MemoryMeasures();
      await tester.pumpWidget(
        MaterialApp(
          home: RoadMeasurementScreen(repository: repo, clock: () => repo.date),
        ),
      );
      await tester.tap(find.text('Consulter la source publique'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('États Traficolor'));
      await tester.pumpAndSettle();
      expect(find.text('62 km/h en moyenne · 300 véhicules/h'), findsNothing);
      expect(find.text('État inconnu'), findsNothing);
      expect(repo.requests, 1);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Rouen'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rouen').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Consulter la source publique'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consulter la source publique'));
      await tester.pumpAndSettle();
      expect(find.text('Dense'), findsOneWidget);
      expect(repo.requests, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('large text landscape keeps metrics reachable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryMeasures();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: RoadMeasurementScreen(repository: repo, clock: () => repo.date),
      ),
    );
    await tester.ensureVisible(find.text('Consulter la source publique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consulter la source publique'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('62 km/h en moyenne · 300 véhicules/h'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
