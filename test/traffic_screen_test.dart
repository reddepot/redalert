import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locreminder/services/datex_traffic_parser.dart';
import 'package:locreminder/services/traffic_repository.dart';
import 'package:locreminder/screens/traffic_screen.dart';
import 'package:locreminder/widgets/traffic_map.dart';
import 'package:locreminder/widgets/map_tiles.dart';

import 'datex_traffic_test.dart' as fixture;

void main() {
  TrafficRepository repository(
    String body, {
    void Function()? request,
    DateTime Function()? clock,
  }) => TrafficRepository(
    clientFactory: () => MockClient((r) async {
      request?.call();
      return http.Response(
        r.url.pathSegments.last == 'index.txt' ? '100' : body,
        200,
      );
    }),
    parser: (text, now) async => parseTrafficPublication(text, now),
    clock: clock ?? () => fixture.now,
  );
  testWidgets(
    'download is explicit, filters distinguish current, planned and terminated source data',
    (tester) async {
      var requests = 0;
      final body = fixture.publication(
        situations:
            fixture.situation() +
            fixture.situation(
              id: 'S2',
              records: fixture.record(
                id: 'FUTURE',
                start: '2026-11-14T00:00:00Z',
              ),
            ) +
            fixture.situation(
              id: 'S3',
              records: fixture.record(id: 'ENDED', end: '2026-11-12T00:00:00Z'),
            ),
      );
      final repo = repository(body, request: () => requests++);
      await tester.pumpWidget(
        MaterialApp(
          home: TrafficScreen(repository: repo, clock: () => fixture.now),
        ),
      );
      await tester.pump();
      expect(requests, 0);
      await tester.runAsync(() async {
        await tester.tap(find.text('Charger les événements'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('1 fiche'), findsOneWidget);
      expect(find.textContaining('Publication :'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
      await tester.tap(find.text('Prévus'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Prévu', findRichText: true),
        findsAtLeastNWidgets(1),
      );
      await tester.ensureVisible(find.byType(ListTile));
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.textContaining('FUTURE'), findsOneWidget);
      expect(find.textContaining('ENDED'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'map is withdrawn when freshness expires even without a new request',
    (tester) async {
      var now = fixture.now;
      final body = fixture.publication(
        situations: fixture.situation(
          records: fixture.record(
            location: '''<d:groupOfLocations xsi:type="d:Point"><d:tpegPointLocation><d:point><d:pointCoordinates><d:latitude>46.6</d:latitude><d:longitude>2.5</d:longitude></d:pointCoordinates></d:point></d:tpegPointLocation></d:groupOfLocations>''',
          ),
        ),
      );
      final repo = repository(body, clock: () => now);
      await tester.runAsync(() => repo.refresh());
      await tester.pumpWidget(
        MaterialApp(
          home: TrafficScreen(
            repository: repo,
            clock: () => now,
            tileLayer: const SizedBox(),
            mapStyle: MapStyle.humanitarian,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Carte'));
      await tester.tap(find.text('Carte'));
      await tester.pumpAndSettle();
      expect(find.byType(TrafficMap), findsOneWidget);
      final stableMap = tester.widget<TrafficMap>(find.byType(TrafficMap));
      expect(stableMap.style, MapStyle.humanitarian);
      await tester.pump(const Duration(seconds: 3));
      expect(
        identical(
          tester.widget<TrafficMap>(find.byType(TrafficMap)),
          stableMap,
        ),
        isTrue,
      );

      now = now.add(const Duration(minutes: 16));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(TrafficMap), findsNothing);
      expect(find.textContaining('fraîcheur non confirmée'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Carte'),
      );
      expect(button.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'segment endpoints use source coordinates with no invented road polyline',
    (tester) async {
      final record = fixture
          .parsed(
            fixture.publication(
              situations: fixture.situation(
                records: fixture.record(
                  location: '''<d:groupOfLocations xsi:type="d:Linear"><d:tpegLinearLocation><d:from><d:pointCoordinates><d:latitude>46.6</d:latitude><d:longitude>2.5</d:longitude></d:pointCoordinates></d:from><d:to><d:pointCoordinates><d:latitude>47.6</d:latitude><d:longitude>3.5</d:longitude></d:pointCoordinates></d:to></d:tpegLinearLocation></d:groupOfLocations>''',
                ),
              ),
            ),
          )
          .situations
          .single
          .records
          .single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 480,
              child: TrafficMap(
                records: [record],
                onRecord: (_) {},
                tileLayer: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PolylineLayer), findsNothing);
      final markers = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers;
      expect(markers, isNotEmpty);
      expect(
        markers.every(
          (m) =>
              m.point == record.geometry.from || m.point == record.geometry.to,
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'traffic screen supports landscape large text and lazy record construction',
    (tester) async {
      tester.view.physicalSize = const Size(720, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final body = fixture.publication(
        situations: fixture.situation(
          records: [for (var i = 0; i < 300; i++) fixture.record(id: 'R$i')]
              .join(),
        ),
      );
      final repo = repository(body);
      await tester.runAsync(() => repo.refresh());
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: TrafficScreen(repository: repo, clock: () => fixture.now),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ListTile).evaluate().length, lessThan(20));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
