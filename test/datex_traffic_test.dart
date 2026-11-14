import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/traffic_data.dart';
import 'package:locreminder/services/datex_traffic_parser.dart';

final now = DateTime.utc(2026, 11, 13, 14);
String record({
  String id = 'R1',
  int version = 1,
  String extra = '',
  String location = '',
  String probability = 'certain',
  String start = '2026-11-13T13:00:00Z',
  String? end,
  String validity = 'definedByValidityTimeSpec',
}) =>
    '''
<d:situationRecord id="$id" version="$version" xsi:type="d:MaintenanceWorks">
<d:situationRecordVersionTime>2026-11-13T13:00:00Z</d:situationRecordVersionTime>
<d:probabilityOfOccurrence>$probability</d:probabilityOfOccurrence>
<d:validity><d:validityStatus>$validity</d:validityStatus><d:validityTimeSpecification>
<d:overallStartTime>$start</d:overallStartTime>${end == null ? '' : '<d:overallEndTime>$end</d:overallEndTime>'}
</d:validityTimeSpecification></d:validity>$location$extra</d:situationRecord>''';
String situation({
  String id = 'S1',
  int version = 1,
  String? records,
  String status = 'real',
  String confidentiality = 'noRestriction',
}) =>
    '''
<d:situation id="$id" version="$version"><d:situationVersionTime>2026-11-13T13:00:00Z</d:situationVersionTime>
<d:headerInformation><d:informationStatus>$status</d:informationStatus><d:confidentiality>$confidentiality</d:confidentiality></d:headerInformation>
${records ?? record()}</d:situation>''';
String publication({
  String? situations,
  String method = 'snapshot',
  String publisher = 'Tipi',
  String time = '2026-11-13T13:59:00Z',
  int? sequence = 100,
}) =>
    '''
<root xmlns:d="http://datex2.eu/schema/2/2_0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<d:exchange><d:supplierIdentification><d:country>fr</d:country><d:nationalIdentifier>$publisher</d:nationalIdentifier></d:supplierIdentification>
<d:subscription><d:subscriptionState>active</d:subscriptionState><d:updateMethod>$method</d:updateMethod></d:subscription></d:exchange>
<d:payloadPublication xsi:type="d:SituationPublication"><d:publicationTime>$time</d:publicationTime>
<d:publicationCreator><d:country>fr</d:country><d:nationalIdentifier>$publisher</d:nationalIdentifier></d:publicationCreator>
${sequence == null ? '' : '<d:feedType>$sequence</d:feedType>'}${situations ?? situation()}</d:payloadPublication></root>''';
TrafficPublication parsed(String xml) => parseTrafficPublication(xml, now);

void main() {
  test('excessive XML nesting is refused before DOM allocation', () {
    final nested = '<d:extension>' * 70 + '</d:extension>' * 70;
    final xml = publication(
      situations: situation(records: record(extra: nested)),
    );
    expect(() => parsed(xml), throwsFormatException);
  });

  test('first snapshot sequence is included and updates replace only their situation', () {
    final s = TrafficReconstruction(
      parsed(
        publication(
          situations:
              situation(records: record() + record(id: 'R2')) +
              situation(
                id: 'S2',
                records: record(id: 'R3'),
              ),
        ),
      ),
    );
    s.apply(
      100,
      parsed(
        publication(
          method: 'allElementUpdate',
          sequence: null,
          situations: situation(version: 2, records: record(version: 2)),
        ),
      ),
    );
    final result = s.finish(100, now);
    expect(result.records.map((r) => r.id), ['R1', 'R3']);
    expect(result.situations.length, 2);
  });
  test('end and cancel withdraw records without resurrecting old versions', () {
    for (final flag in ['end', 'cancel']) {
      final s = TrafficReconstruction(parsed(publication()));
      s.apply(
        100,
        parsed(
          publication(
            method: 'allElementUpdate',
            situations: situation(
              version: 2,
              records: record(
                version: 2,
                extra:
                    '<d:management><d:lifeCycleManagement><d:$flag>true</d:$flag></d:lifeCycleManagement></d:management>',
              ),
            ),
          ),
        ),
      );
      expect(
        s.finish(100, now).records.single.window(now),
        TrafficWindow.ended,
      );
      expect(
        () => s.apply(
          101,
          parsed(
            publication(
              method: 'allElementUpdate',
              situations: situation(version: 3, records: record(version: 3)),
            ),
          ),
        ),
        throwsFormatException,
      );
      expect(s.nextSequence, 101);
    }
  });
  test('gap and incomplete head cannot produce a complete view', () {
    final s = TrafficReconstruction(parsed(publication()));
    expect(
      () => s.apply(101, parsed(publication(method: 'allElementUpdate'))),
      throwsFormatException,
    );
    expect(() => s.finish(100, now), throwsFormatException);
    expect(s.nextSequence, 100);
  });
  test('a failed multi-situation update is atomic', () {
    final s = TrafficReconstruction(
      parsed(publication(situations: situation() + situation(id: 'S2'))),
    );
    final update = publication(
      method: 'allElementUpdate',
      situations:
          situation(version: 2, records: record(version: 2)) +
          situation(
            id: 'S2',
            records: record(extra: '<d:generalPublicComment/>'),
          ),
    );
    expect(() => s.apply(100, parsed(update)), throwsFormatException);
    final before = s.finish(99, now);
    expect(before.situations.every((s) => s.version == 1), isTrue);
    expect(s.nextSequence, 100);
  });
  test(
    'identical versions with different namespace prefixes are equivalent',
    () {
      final s = TrafficReconstruction(parsed(publication()));
      final delta = publication(method: 'allElementUpdate')
          .replaceAll('xmlns:d=', 'xmlns:q=')
          .replaceAll('d:', 'q:');
      s.apply(100, parsed(delta));
      expect(s.finish(100, now).records.length, 1);
    },
  );
  test(
    'expired, predicted, suspended and scheduled declarations are distinct',
    () {
      TrafficWindow window(String r) =>
          parsed(publication(situations: situation(records: r)))
              .situations
              .single
              .records
              .single
              .window(now);
      expect(
        window(record(end: '2026-11-13T13:59:00Z')),
        TrafficWindow.expired,
      );
      expect(
        window(record(start: '2026-11-13T15:00:00Z')),
        TrafficWindow.forecast,
      );
      expect(window(record(validity: 'suspended')), TrafficWindow.suspended);
      expect(
        window(record(extra: '<d:validPeriod/>')),
        TrafficWindow.scheduleUnknown,
      );
      expect(window(record(probability: 'probable')), TrafficWindow.uncertain);
      expect(window(record()), TrafficWindow.declared);
      expect(
        window(
          record(start: '2026-11-14T00:00:00Z', end: '2026-11-01T00:00:00Z'),
        ),
        TrafficWindow.uncertain,
      );
    },
  );
  test('test and non-public data cannot enter consultation records', () {
    for (final xml in [
      situation(status: 'test'),
      situation(confidentiality: 'restrictedToAuthorities'),
    ]) {
      final s = TrafficReconstruction(parsed(publication(situations: xml)));
      expect(s.finish(99, now).records, isEmpty);
    }
  });
  test('a fresh fetch never refreshes an old publication timestamp', () {
    final s = TrafficReconstruction(
      parsed(publication(time: '2026-11-13T13:00:00Z')),
    ).finish(99, now);
    expect(s.isStale(now), isTrue);
    expect(s.checkedAt, now);
    expect(s.isStale(now.subtract(const Duration(minutes: 3))), isTrue);
  });
  test('point and line endpoints are retained without inventing a line centre', () {
    String pair(double lat, double lon) =>
        '<d:pointCoordinates><d:latitude>$lat</d:latitude><d:longitude>$lon</d:longitude></d:pointCoordinates>';
    final point = parsed(
      publication(
        situations: situation(
          records: record(
            location:
                '<d:groupOfLocations xsi:type="d:Point"><d:tpegPointLocation><d:point>${pair(45, 2)}</d:point></d:tpegPointLocation></d:groupOfLocations>',
          ),
        ),
      ),
    ).situations.single.records.single;
    expect(point.geometry.point!.latitude, 45);
    final line = parsed(
      publication(
        situations: situation(
          records: record(
            location:
                '<d:groupOfLocations xsi:type="d:Linear"><d:tpegLinearLocation><d:from>${pair(45, 2)}</d:from><d:to>${pair(46, 3)}</d:to></d:tpegLinearLocation></d:groupOfLocations>',
          ),
        ),
      ),
    ).situations.single.records.single;
    expect(line.geometry.point, isNull);
    expect(line.geometry.from!.latitude, 45);
    expect(line.geometry.to!.latitude, 46);
    final invalid = parsed(
      publication(
        situations: situation(
          records: record(
            location:
                '<d:groupOfLocations xsi:type="d:Point"><d:tpegPointLocation>${pair(95, 2)}</d:tpegPointLocation></d:groupOfLocations>',
          ),
        ),
      ),
    ).situations.single.records.single;
    expect(invalid.geometry.hasCoordinates, isFalse);
  });
  test('unsafe, wrong namespace, ambiguous identity or unsupported method fails closed', () {
    for (final xml in [
      '<!DOCTYPE a [<!ENTITY private "value">]>${publication()}',
      publication(publisher: 'Other'),
      publication(method: 'singleElementUpdate'),
      publication().replaceAll(
        'http://datex2.eu/schema/2/2_0',
        'https://wrong.example/ns',
      ),
      publication(situations: situation() + situation()),
      publication(time: '2026-11-14T00:00:00Z'),
      publication().replaceFirst(
        '<d:publicationTime>',
        '<d:publicationTime>2026-11-13T14:00:00Z</d:publicationTime><d:publicationTime>',
      ),
    ]) {
      expect(() => parsed(xml), throwsA(isA<FormatException>()));
    }
  });
  test('timezone and calendar validation reject normalized invalid dates', () {
    for (final s in [
      '2026-11-13T12:00:00',
      '2026-02-30T12:00:00Z',
      '2026-13-01T12:00:00Z',
      '2026-11-13T25:00:00Z',
      '2026-11-13T12:00:00+14:01',
    ]) {
      expect(() => trafficTime(s), throwsFormatException);
    }
    expect(trafficTime('2026-11-13T15:00:00+01:00'), now);
  });
  test(
    'backwards publication time is rejected even with consecutive sequence',
    () {
      final s = TrafficReconstruction(parsed(publication()));
      expect(
        () => s.apply(
          100,
          parsed(
            publication(
              method: 'allElementUpdate',
              time: '2026-11-13T13:58:59Z',
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
