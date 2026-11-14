import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/road_measurement.dart';
import 'road_measurement_parser.dart';

typedef MeasurementParser = Future<RoadMeasurementSnapshot> Function(
  String xml,
  String? reference,
  String publisher,
  bool states,
  DateTime now,
);
Future<RoadMeasurementSnapshot> _parse(
  String xml,
  String? reference,
  String publisher,
  bool states,
  DateTime now,
) => compute(_decode, (xml, reference, publisher, states, now));
RoadMeasurementSnapshot _decode(
  (String, String?, String, bool, DateTime) data,
) => parseRoadMeasurements(
  data.$1,
  data.$5,
  reference: data.$2,
  expectedPublisher: data.$3,
  statesOnly: data.$4,
);

/// Only national or explicitly selected producer files; no position/route parameter.
class RoadMeasurementRepository {
  RoadMeasurementRepository({
    http.Client Function()? clientFactory,
    MeasurementParser? parser,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 45),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _parser = parser ?? _parse,
       _clock = clock ?? DateTime.now;
  static const host = 'tipi.bison-fute.gouv.fr';
  static const prefix = '/bison-fute-ouvert/publicationsDIR/';
  static const regions = <String, String>{
    'ALIENOR': 'ALIENOR',
    'TRAFIC_TraficStBrieuc': 'Saint-Brieuc',
    'TRAFIC_TraficTriskell56': 'Triskell 56',
    'TraficBreizhNantes': 'Nantes',
    'TraficBreizhRennes': 'Rennes',
    'TraficCaen': 'Caen',
    'TraficDirmc': 'DIR Massif central',
    'TraficErato': 'Erato',
    'TraficGentiane': 'Gentiane',
    'TraficHyrondelle': 'Hyrondelle',
    'TraficLille': 'Lille',
    'TraficLimoges': 'Limoges',
    'TraficLyon': 'Lyon',
    'TraficMarius': 'Marius',
    'TraficMyrabel': 'Myrabel',
    'TraficRouen': 'Rouen',
  };
  final http.Client Function() _clientFactory;
  final MeasurementParser _parser;
  final DateTime Function() _clock;
  final Duration timeout;
  http.Client? _client;
  Completer<void>? _abort;
  bool _verified = false;
  RoadMeasurementSnapshot? cached;
  String? cachedRegion;
  bool get verified => _verified;

  Future<String> _get(
    http.Client client,
    Completer<void> abort,
    String path,
    int bound,
  ) async {
    if (abort.isCompleted) throw const FormatException('Consultation annulée.');
    final request =
        http.AbortableRequest(
            'GET',
            Uri.https(host, '$prefix$path'),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent':
                'RedAlert/2.1.1 (https://github.com/reddepot/redalert)',
            'Cache-Control': 'no-cache',
          });
    final response = await client.send(request);
    if (abort.isCompleted) throw const FormatException('Consultation annulée.');
    if (response.statusCode != 200) {
      throw const FormatException('Source de mesures indisponible.');
    }
    if ((response.contentLength ?? 0) > bound) {
      throw const FormatException('Publication de mesures trop volumineuse.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (abort.isCompleted) {
        throw const FormatException('Consultation annulée.');
      }
      if (bytes.length + chunk.length > bound) {
        throw const FormatException('Publication de mesures trop volumineuse.');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  Future<RoadMeasurementSnapshot> refresh({String? region}) async {
    if (region != null && !regions.containsKey(region)) {
      throw const FormatException('Producteur inconnu.');
    }
    if (_client != null) {
      throw const FormatException('Une consultation est déjà en cours.');
    }
    final client = _clientFactory();
    final abort = Completer<void>();
    _client = client;
    _abort = abort;
    _verified = false;
    Future<RoadMeasurementSnapshot> download() async {
      if (region == null) {
        final xml = await _get(
          client,
          abort,
          'QTV-DIR/qtvDir.xml',
          8 * 1024 * 1024,
        );
        final reference = await _get(
          client,
          abort,
          'QTV-DIR/refDir.csv',
          2 * 1024 * 1024,
        );
        return _parser(xml, reference, 'TIPI', false, _clock());
      }
      final directory = 'TRAFICOLOR-DIR/$region/';
      final index = await _get(client, abort, directory, 1024 * 1024);
      final names = RegExp(
        r'href="([A-Za-z0-9_.-]+_DataTRT_\d{8}_\d{6}\.xml)"',
      ).allMatches(index).map((m) => m.group(1)!).toList()..sort();
      if (names.isEmpty || names.length > 10000) {
        throw const FormatException('Aucune publication de ce producteur.');
      }
      final xml = await _get(
        client,
        abort,
        '$directory${names.last}',
        8 * 1024 * 1024,
      );
      return _parser(
        xml,
        null,
        region.replaceFirst('TRAFIC_', ''),
        true,
        _clock(),
      );
    }

    try {
      final result =
          await Future.any<RoadMeasurementSnapshot>([
            download(),
            abort.future.then(
              (_) => throw const FormatException('Consultation annulée.'),
            ),
          ]).timeout(
            timeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              client.close();
              throw const FormatException(
                'La consultation a dépassé son délai.',
              );
            },
          );
      if (abort.isCompleted) {
        throw const FormatException('Consultation annulée.');
      }
      cached = result;
      cachedRegion = region;
      _verified = true;
      return result;
    } finally {
      if (!abort.isCompleted) abort.complete();
      client.close();
      _client = null;
      _abort = null;
    }
  }

  void cancel() {
    _verified = false;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _client?.close();
  }
}
