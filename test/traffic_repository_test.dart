import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locreminder/models/traffic_data.dart';
import 'package:locreminder/services/datex_traffic_parser.dart';
import 'package:locreminder/services/traffic_repository.dart';

import 'datex_traffic_test.dart' as fixture;

void main() {
  TrafficRepository repository(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 60),
  }) => TrafficRepository(
    clientFactory: () => MockClient(handler),
    clock: () => fixture.now,
    parser: (text, now) async => parseTrafficPublication(text, now),
    timeout: timeout,
  );
  test('explicit national request reconstructs complete inclusive range with no user data', () async {
    final requests = <http.Request>[];
    final repo = repository((request) async {
      requests.add(request);
      final name = request.url.pathSegments.last;
      return http.Response(switch (name) {
        'content.xml' => fixture.publication(),
        'index.txt' => '102',
        '100.xml' => fixture.publication(
          method: 'allElementUpdate',
          situations: fixture.situation(
            version: 2,
            records: fixture.record(version: 2),
          ),
        ),
        '101.xml' => fixture.publication(
          method: 'allElementUpdate',
          situations: fixture.situation(
            version: 3,
            records: fixture.record(
              version: 3,
              extra: '<d:management><d:lifeCycleManagement><d:end>true</d:end></d:lifeCycleManagement></d:management>',
            ),
          ),
        ),
        _ => throw StateError('Unexpected request'),
      }, 200);
    });
    expect(repo.cached, isNull);
    expect(requests, isEmpty);
    final r = await repo.refresh();
    expect(requests.map((r) => r.url.pathSegments.last), [
      'content.xml',
      'index.txt',
      '100.xml',
      '101.xml',
    ]);
    expect(r.records.single.window(fixture.now), TrafficWindow.ended);
    expect(repo.usable(fixture.now), isTrue);
    for (final request in requests) {
      expect(request.method, 'GET');
      expect(request.body, isEmpty);
      expect(request.url.query, isEmpty);
      expect(request.url.host, 'tipi.bison-fute.gouv.fr');
      expect(request.url.scheme, 'https');
      expect(request.followRedirects, isFalse);
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    }
  });
  test(
    'missing delta invalidates current view and never commits a partial update',
    () async {
      var fail = false;
      final repo = repository(
        (r) async => switch (r.url.pathSegments.last) {
          'content.xml' => http.Response(fixture.publication(), 200),
          'index.txt' => http.Response(fail ? '102' : '100', 200),
          '100.xml' => http.Response(
            fixture.publication(
              method: 'allElementUpdate',
              situations: fixture.situation(version: 2),
            ),
            200,
          ),
          _ => http.Response('missing', 404),
        },
      );
      final before = await repo.refresh();
      expect(repo.usable(fixture.now), isTrue);
      fail = true;
      await expectLater(repo.refresh(), throwsFormatException);
      expect(identical(repo.cached, before), isTrue);
      expect(repo.usable(fixture.now), isFalse);
      expect(repo.cached!.situations.single.version, 1);
      fail = false;
      await repo.refresh();
      expect(repo.usable(fixture.now), isTrue);
    },
  );
  test('index bound, redirects and large bodies refuse to construct a new snapshot', () async {
    for (final mode in ['gap', 'ahead', 'redirect', 'size', 'partial']) {
      final repo = repository((r) async {
        if (r.url.pathSegments.last == 'content.xml') {
          return http.Response(fixture.publication(), 200);
        }
        return switch (mode) {
          'gap' => http.Response('98', 200),
          'ahead' => http.Response('1000', 200),
          'redirect' => http.Response(
            '',
            302,
            headers: {'location': 'https://other.invalid/'},
          ),
          'size' => http.Response('x' * 65, 200),
          _ => http.Response('100 partial', 200),
        };
      });
      await expectLater(repo.refresh(), throwsFormatException);
      expect(repo.cached, isNull);
    }
  });
  test('cancelled or late response cannot replace cache', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final repo = repository((r) {
      started.complete();
      return response.future;
    });
    final task = repo.refresh();
    await started.future;
    repo.cancel();
    response.complete(http.Response(fixture.publication(), 200));
    await expectLater(task, throwsFormatException);
    expect(repo.cached, isNull);
  });
  test('total deadline abandons fetch and rejects a late completion', () async {
    final response = Completer<http.Response>();
    final repo = repository(
      (r) => response.future,
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(repo.refresh(), throwsFormatException);
    response.complete(http.Response(fixture.publication(), 200));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(repo.cached, isNull);
    expect(repo.usable(fixture.now), isFalse);
  });
}
