import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:locreminder/services/route_service.dart';

Map<String, Object?> response() => {
  'code': 'Ok',
  'routes': [
    {
      'distance': 1112,
      'duration': 100,
      'geometry': {
        'coordinates': [
          [0, 0],
          [.01, 0],
        ],
      },
      'legs': [],
    },
  ],
};
void main() {
  test(
    'a returning loop near the start cannot jump progress to the finish',
    () {
      final route = DrivingRoute(
        points: const [
          LatLng(0, 0),
          LatLng(0, .01),
          LatLng(.001, .01),
          LatLng(0, .00002),
        ],
        distance: 2300,
        duration: 230,
        steps: const [],
        destination: 'Synthetic',
      );
      final first = route.progress(const LatLng(0, .00003));
      expect(first.offRoute, isFalse);
      expect(first.metres, greaterThan(2000));
      for (var i = 0; i < 5; i++) {
        expect(
          route.progress(const LatLng(0, .00003)).metres,
          closeTo(first.metres, .01),
        );
      }
      route.progress(const LatLng(0, .005));
      route.progress(const LatLng(0, .01));
      route.progress(const LatLng(.001, .01));
      expect(route.progress(const LatLng(0, .00002)).metres, lessThan(10));
    },
  );

  test(
    'chunked route is cancelled at the bound instead of downloading it all',
    () async {
      var consumed = 0;
      final chunk = Uint8List(4 * 1024 * 1024);
      Stream<List<int>> body() async* {
        for (var i = 0; i < 4; i++) {
          consumed++;
          yield chunk;
        }
      }

      final service = RouteService(
        client: MockClient.streaming(
          (request, _) async => http.StreamedResponse(body(), 200),
        ),
      );
      await expectLater(
        service.calculate(
          const LatLng(0, 0),
          const LatLng(0, .01),
          'Synthetic',
        ),
        throwsFormatException,
      );
      expect(consumed, lessThan(4));
      service.close();
    },
  );

  test(
    'route request sends only explicit endpoints and checks returned geometry',
    () async {
      final service = RouteService(
        client: MockClient((r) async {
          expect(r.url.host, 'routing.openstreetmap.de');
          expect(r.url.path, contains('0.0,0.0;0.01,0.0'));
          return http.Response(jsonEncode(response()), 200);
        }),
      );
      final route = await service.calculate(
        const LatLng(0, 0),
        const LatLng(0, .01),
        'Synthetic',
      );
      expect(route.points.length, 2);
      final p = route.progress(const LatLng(0, .005));
      expect(p.metres, inInclusiveRange(550, 565));
      expect(p.seconds, closeTo(50, .2));
      expect(p.offRoute, isFalse);
      expect(route.progress(const LatLng(.01, .005)).offRoute, isTrue);
      service.close();
    },
  );
  test('no route and corrupt coordinates fail explicitly', () {
    expect(
      () => RouteService.parse('{"code":"NoRoute"}', 'Synthetic'),
      throwsFormatException,
    );
    final data = response();
    ((data['routes'] as List)[0]['geometry'] as Map)['coordinates'] = [
      [0, 0],
      [400, 100],
    ];
    expect(
      () => RouteService.parse(jsonEncode(data), 'Synthetic'),
      throwsFormatException,
    );
  });
}
