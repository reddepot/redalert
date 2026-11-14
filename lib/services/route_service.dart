import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteStep {
  const RouteStep(this.position, this.instruction);
  final LatLng position;
  final String instruction;
}

class DrivingRoute {
  DrivingRoute({
    required this.points,
    required this.distance,
    required this.duration,
    required this.steps,
    required this.destination,
  });
  final List<LatLng> points;
  final double distance, duration;
  final List<RouteStep> steps;
  final String destination;
  double _progressCovered = 0;
  LatLng? _lastProgressPosition;
  RouteProgress progress(LatLng position) {
    var best = double.infinity, covered = 0.0, bestCovered = 0.0;
    final ruler = const Distance(roundResult: false);
    if (points.isEmpty) return const RouteProgress(0, 0, true);
    // UI continuity heuristic, not road matching: nearby return legs must not
    // turn a stationary fix at the start into an arrival at the finish.
    final moved = ruler.as(
      LengthUnit.Meter,
      _lastProgressPosition ?? points.first,
      position,
    );
    final ahead = _progressCovered + math.max(75.0, moved * 3 + 50);
    final behind = math.max(0.0, _progressCovered - 50);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final sx = 111195 * math.cos(position.latitude * math.pi / 180);
      final ax = (a.longitude - position.longitude) * sx,
          ay = (a.latitude - position.latitude) * 111195;
      final bx = (b.longitude - position.longitude) * sx,
          by = (b.latitude - position.latitude) * 111195;
      final dx = bx - ax, dy = by - ay, length2 = dx * dx + dy * dy;
      final t = length2 == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / length2).clamp(0.0, 1.0);
      final lateral = math.sqrt(
        math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2),
      );
      final metres = ruler.as(LengthUnit.Meter, a, b);
      final candidate = covered + t * metres;
      if (candidate >= behind && candidate <= ahead && lateral < best) {
        best = lateral;
        bestCovered = candidate;
      }
      covered += metres;
    }
    final offRoute = best > 75;
    if (!offRoute) {
      _progressCovered = math.max(_progressCovered, bestCovered);
      _lastProgressPosition = position;
    }
    final remaining = math.max(0.0, covered - _progressCovered);
    return RouteProgress(
      remaining,
      covered == 0 ? 0 : duration * remaining / covered,
      offRoute,
    );
  }
}

class RouteProgress {
  const RouteProgress(this.metres, this.seconds, this.offRoute);
  final double metres, seconds;
  final bool offRoute;
}

class RouteService {
  RouteService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _requests = <Completer<void>>{};
  DateTime? _lastRequest;
  Future<DrivingRoute> calculate(
    LatLng start,
    LatLng finish,
    String label,
  ) async {
    final last = _lastRequest;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 1)) {
      throw const FormatException('Attendre une seconde avant de recalculer.');
    }
    _lastRequest = DateTime.now();
    final path =
        '/routed-car/route/v1/driving/${start.longitude},${start.latitude};${finish.longitude},${finish.latitude}';
    final uri = Uri.https('routing.openstreetmap.de', path, {
      'overview': 'full',
      'geometries': 'geojson',
      'steps': 'true',
      'alternatives': 'false',
    });
    final abort = Completer<void>();
    _requests.add(abort);
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['User-Agent'] =
              'RedAlert/2.1.1 (https://github.com/reddepot/redalert)';
    Future<Uint8List> download() async {
      final response = await _client.send(request);
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > 8 * 1024 * 1024) {
        throw const FormatException(
          'Calcul indisponible ou réponse trop volumineuse.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in response.stream) {
        size += chunk.length;
        if (size > 8 * 1024 * 1024) {
          throw const FormatException('Tracé trop volumineux.');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    try {
      final data = await download().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw const FormatException('Le calcul a dépassé le délai prévu.');
        },
      );
      return parse(utf8.decode(data), label);
    } finally {
      if (!abort.isCompleted) abort.complete();
      _requests.remove(abort);
    }
  }

  static DrivingRoute parse(String body, String label) {
    final json = jsonDecode(body);
    if (json is! Map ||
        json['code'] != 'Ok' ||
        json['routes'] is! List ||
        (json['routes'] as List).isEmpty) {
      throw const FormatException('Aucun itinéraire trouvé.');
    }
    final route = json['routes'][0] as Map;
    final coords = (route['geometry'] as Map?)?['coordinates'];
    if (coords is! List || coords.length < 2 || coords.length > 40000) {
      throw const FormatException('Tracé invalide ou trop volumineux.');
    }
    LatLng point(Object? raw) {
      if (raw is! List || raw.length < 2 || raw[0] is! num || raw[1] is! num) {
        throw const FormatException('Coordonnées de tracé invalides.');
      }
      final lon = (raw[0] as num).toDouble(), lat = (raw[1] as num).toDouble();
      if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
        throw const FormatException('Coordonnées hors limites.');
      }
      return LatLng(lat, lon);
    }

    final distance = (route['distance'] as num?)?.toDouble(),
        duration = (route['duration'] as num?)?.toDouble();
    if (distance == null ||
        duration == null ||
        !distance.isFinite ||
        !duration.isFinite ||
        distance < 0 ||
        duration < 0) {
      throw const FormatException('Durée ou distance invalide.');
    }
    final steps = <RouteStep>[];
    for (final leg in route['legs'] as List? ?? []) {
      for (final step in (leg as Map)['steps'] as List? ?? []) {
        final m = (step as Map)['maneuver'] as Map?;
        if (m == null || m['location'] == null) continue;
        final action = switch (m['type']) {
          'depart' => 'Départ',
          'arrive' => 'Arrivée',
          'roundabout' || 'rotary' => 'Au rond-point',
          'merge' => 'Rejoindre la voie',
          'turn' || 'end of road' => 'Tourner',
          'on ramp' => 'Prendre la bretelle',
          'off ramp' => 'Prendre la sortie',
          'new name' => 'Poursuivre',
          'fork' => 'À la bifurcation',
          _ => 'Continuer',
        };
        final direction = switch (m['modifier']) {
          'right' || 'slight right' || 'sharp right' => 'à droite',
          'left' || 'slight left' || 'sharp left' => 'à gauche',
          'uturn' => 'faire demi-tour',
          _ => 'tout droit',
        };
        steps.add(
          RouteStep(
            point(m['location']),
            '$action $direction${step['name'] is String && (step['name'] as String).isNotEmpty ? ' · ${step['name']}' : ''}',
          ),
        );
      }
    }
    return DrivingRoute(
      points: coords.map(point).toList(),
      distance: distance,
      duration: duration,
      steps: steps,
      destination: label,
    );
  }

  void close() {
    for (final abort in _requests) {
      if (!abort.isCompleted) abort.complete();
    }
    _client.close();
  }
}
