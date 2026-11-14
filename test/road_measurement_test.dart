import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locreminder/models/road_measurement.dart';
import 'package:locreminder/services/road_measurement_parser.dart';
import 'package:locreminder/services/road_measurement_repository.dart';

final at = DateTime.utc(2026, 11, 13, 10);
String xml({
  String publisher = 'TIPI',
  String publication = '2026-11-13T10:00:00Z',
  String measured = '2026-11-13T10:00:00Z',
  String values = '<averageVehicleSpeed numberOfInputValuesUsed="4"><speed>62</speed></averageVehicleSpeed><vehicleFlowRate>300</vehicleFlowRate>',
}) =>
    '<d2LogicalModel xmlns="http://datex2.eu/schema/2/2_0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><exchange><supplierIdentification><country>fr</country><nationalIdentifier>$publisher</nationalIdentifier></supplierIdentification></exchange>'
    '<payloadPublication xsi:type="MeasuredDataPublication"><publicationTime>$publication</publicationTime><publicationCreator><country>fr</country><nationalIdentifier>$publisher</nationalIdentifier></publicationCreator>'
    '<headerInformation><confidentiality>noRestriction</confidentiality><informationStatus>real</informationStatus></headerInformation><siteMeasurements><measurementSiteReference id="synthetic"/><measurementTimeDefault>$measured</measurementTimeDefault>$values</siteMeasurements></payloadPublication></d2LogicalModel>';
const header =
    'code_pme;source;source_2;code_insee_commune;axe;pr_debut;abscisse_debut;pr_fin;abscisse_fin;sens_gestionnaire;sens_cardinal;sens_migratoire;sens_giratoire;longueur;nb_voies;x_deb;y_deb;x_fin;y_fin;code_traficolor';
String reference({bool legacy = false}) {
  final cells = [
    'synthetic',
    'DIR',
    '1',
    '',
    'A1',
    '',
    '',
    '',
    '',
    '1',
    'NORD_SUD',
    '',
    '',
    '100',
    '2',
    '',
    '',
    '',
    '',
    '',
  ];
  if (legacy) cells.removeAt(3);
  return '$header\n${cells.join(';')}\n';
}

Future<RoadMeasurementSnapshot> directParser(
  String text,
  String? ref,
  String publisher,
  bool states,
  DateTime now,
) async => parseRoadMeasurements(
  text,
  now,
  reference: ref,
  expectedPublisher: publisher,
  statesOnly: states,
);

void main() {
  test(
    'QTV joins explicit station IDs and keeps mean speed distinct from a limit',
    () {
      final result = parseRoadMeasurements(xml(), at, reference: reference());
      expect(result.rows.single.axis, 'A1');
      expect(result.rows.single.meanSpeedKmh, 62);
      expect(result.rows.single.vehiclesPerHour, 300);
      expect(result.rows.single.fresh(at), isTrue);
      expect(
        result.rows.single.fresh(at.add(const Duration(minutes: 16))),
        isFalse,
      );
    },
  );
  test(
    'known 19-column reference is flagged and arbitrary shifts are rejected',
    () {
      final result = parseRoadMeasurements(
        xml(),
        at,
        reference: reference(legacy: true),
      );
      expect(result.referenceShifted, isTrue);
      expect(result.rows.single.axis, 'A1');
      expect(
        () => parseQtvReference(reference().replaceFirst('A1', 'wrong-column')),
        throwsFormatException,
      );
    },
  );
  test('wall-clock publication is not turned into UTC; observation requires a zone', () {
    final result = parseRoadMeasurements(
      xml(
        publication: '2026-11-13T11:00:00',
        measured: '2026-11-13T11:00:00+01:00',
      ),
      at,
    );
    expect(result.publishedAt, isNull);
    expect(result.rows.single.fresh(at), isTrue);
    expect(
      () => parseRoadMeasurements(xml(measured: '2026-11-13T11:00:00'), at),
      throwsFormatException,
    );
    expect(
      () => parseRoadMeasurements(xml(measured: '2026-11-13T11:00:00Z'), at),
      throwsFormatException,
    );
  });
  test(
    'zero samples and unknown traffic states never become a positive condition',
    () {
      final speed = parseRoadMeasurements(
        xml(
          values: '<averageVehicleSpeed numberOfInputValuesUsed="0"><speed>130</speed></averageVehicleSpeed>',
        ),
        at,
      );
      expect(speed.rows.single.meanSpeedKmh, isNull);
      final states = parseRoadMeasurements(
        xml(
          values: '<trafficStatus numberOfInputValuesUsed="0"><trafficStatusValue>freeFlow</trafficStatusValue></trafficStatus>',
        ),
        at,
        statesOnly: true,
      );
      expect(states.rows.single.stateLabel, 'État inconnu');
    },
  );
  test(
    'unsafe XML, ambiguous stations and a different producer are rejected',
    () {
      expect(
        () => parseRoadMeasurements('<!DOCTYPE x>${xml()}', at),
        throwsFormatException,
      );
      expect(
        () => parseRoadMeasurements(xml(publisher: 'Other'), at),
        throwsFormatException,
      );
      expect(
        () => parseRoadMeasurements(
          xml().replaceFirst(
            '</siteMeasurements>',
            '</siteMeasurements><siteMeasurements><measurementSiteReference id="synthetic"/><measurementTimeDefault>2026-11-13T10:00:00Z</measurementTimeDefault></siteMeasurements>',
          ),
          at,
        ),
        throwsFormatException,
      );
    },
  );
  test('national client downloads only two fixed HTTPS files and invalidates cache after failure', () async {
    var fail = false;
    final paths = <Uri>[];
    final repo = RoadMeasurementRepository(
      clock: () => at,
      parser: directParser,
      clientFactory: () => MockClient((request) async {
        paths.add(request.url);
        expect(request.followRedirects, isFalse);
        expect(request.url.scheme, 'https');
        expect(request.url.query, isEmpty);
        if (fail) return http.Response('unavailable', 503);
        return http.Response(
          request.url.path.endsWith('.csv') ? reference() : xml(),
          200,
        );
      }),
    );
    await repo.refresh();
    expect(paths, hasLength(2));
    expect(repo.verified, isTrue);
    fail = true;
    await expectLater(repo.refresh(), throwsFormatException);
    expect(repo.cached, isNotNull);
    expect(repo.verified, isFalse);
  });
  test('Traficolor reads latest filename without following paths supplied by listing', () async {
    final paths = <String>[];
    final repo = RoadMeasurementRepository(
      clock: () => at,
      parser: directParser,
      clientFactory: () => MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          request.url.path.endsWith('/')
              ? '<a href="../../evil.xml">no</a><a href="TraficRouen_DataTRT_20261113_090000.xml">old</a><a href="TraficRouen_DataTRT_20261113_100000.xml">latest</a>'
              : xml(
                  publisher: 'TraficRouen',
                  values: '<trafficStatus><trafficStatusValue>heavyTraffic</trafficStatusValue></trafficStatus>',
                ),
          200,
        );
      }),
    );
    final result = await repo.refresh(region: 'TraficRouen');
    expect(paths.last, endsWith('TraficRouen_DataTRT_20261113_100000.xml'));
    expect(result.rows.single.stateLabel, 'Dense');
    expect(result.rows.single.meanSpeedKmh, isNull);
    await expectLater(
      repo.refresh(region: '../arbitrary'),
      throwsFormatException,
    );
  });
  test(
    'cancellation is immediate even if the client has not returned headers',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final repo = RoadMeasurementRepository(
        clientFactory: () => MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final pending = repo.refresh();
      final result = expectLater(pending, throwsFormatException);
      await started.future;
      repo.cancel();
      await result;
      expect(repo.verified, isFalse);
      response.complete(http.Response(xml(), 200));
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('oversized response is refused before parsing', () async {
    var parsed = false;
    final repo = RoadMeasurementRepository(
      parser: (a, b, c, d, e) async {
        parsed = true;
        return directParser(a, b, c, d, e);
      },
      clientFactory: () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(utf8.encode(xml())),
          200,
          contentLength: 9 * 1024 * 1024,
        ),
      ),
    );
    await expectLater(repo.refresh(), throwsFormatException);
    expect(parsed, isFalse);
    expect(repo.cached, isNull);
  });
  test('stream growth is bounded without trusting content length', () async {
    var chunks = 0;
    Stream<List<int>> data() async* {
      for (var i = 0; i < 4; i++) {
        chunks++;
        yield List<int>.filled(4 * 1024 * 1024, 0);
      }
    }

    final repo = RoadMeasurementRepository(
      clientFactory: () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(data(), 200),
      ),
    );
    await expectLater(repo.refresh(), throwsFormatException);
    expect(chunks, 3);
  });
  test('epoch sensor dates are reported as omitted alongside independent valid measurements', () {
    final extra =
        '<siteMeasurements><measurementSiteReference id="old"/><measurementTimeDefault>1970-01-01T01:00:00+01:00</measurementTimeDefault></siteMeasurements>';
    final result = parseRoadMeasurements(
      xml().replaceFirst(
        '</payloadPublication>',
        '$extra</payloadPublication>',
      ),
      at,
    );
    expect(result.rows, hasLength(1));
    expect(result.omittedRows, 1);
    final quoted = reference(legacy: true)
        .replaceAll('synthetic', '"#synthetic"');
    expect(parseQtvReference(quoted).values.keys, ['#synthetic']);
  });
}
