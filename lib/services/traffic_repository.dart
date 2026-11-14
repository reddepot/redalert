import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/traffic_data.dart';
import 'datex_traffic_parser.dart';

typedef TrafficParser = Future<TrafficPublication> Function(String, DateTime);
Future<TrafficPublication> _parse(String text, DateTime now) =>
    compute(_decode, (text, now));
TrafficPublication _decode((String, DateTime) input) =>
    parseTrafficPublication(input.$1, input.$2);

class _TrafficRequest {
  _TrafficRequest(this.client);
  final http.Client client;
  bool cancelled = false;
  int bytes = 0;
}

/// Explicit national downloads only: this API accepts no user position or route.
class TrafficRepository {
  TrafficRepository({
    http.Client Function()? clientFactory,
    TrafficParser? parser,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 60),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _parser = parser ?? _parse,
       _clock = clock ?? DateTime.now;
  static const sourcePage =
      'https://www.bison-fute.gouv.fr/donnees-sur-la-circulation-du.html';
  static final base = Uri.parse(
    'https://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/Evenementiel-DIR/grt/RRN/',
  );
  final http.Client Function() _clientFactory;
  final TrafficParser _parser;
  final DateTime Function() _clock;
  final Duration timeout;
  _TrafficRequest? _request;
  bool _verified = false;
  TrafficSnapshot? cached;
  bool usable(DateTime now) =>
      _verified && cached != null && !cached!.isStale(now);

  Future<String> _get(_TrafficRequest job, String name, int bound) async {
    if (job.cancelled) throw const FormatException('Actualisation annulée.');
    final request = http.Request('GET', base.resolve(name))
      ..followRedirects = false
      ..headers.addAll({
        'User-Agent': 'RedAlert/2.1.1 (https://github.com/reddepot/redalert)',
        'Cache-Control': 'no-cache',
      });
    final response = await job.client
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const FormatException(
        'Une publication trafic est indisponible. Réessayez dans un instant.',
      );
    }
    if (response.contentLength != null && response.contentLength! > bound) {
      throw const FormatException('Publication trafic trop volumineuse.');
    }
    final bytes = BytesBuilder(copy: false);
    final complete = Completer<Uint8List>();
    var size = 0;
    final subscription = response.stream.listen(
      (chunk) {
        if (complete.isCompleted) return;
        size += chunk.length;
        job.bytes += chunk.length;
        if (size > bound || job.bytes > 24 * 1024 * 1024) {
          complete.completeError(
            const FormatException('Chargement trafic trop volumineux.'),
          );
        } else if (job.cancelled) {
          complete.completeError(
            const FormatException('Actualisation annulée.'),
          );
        } else {
          bytes.add(chunk);
        }
      },
      onError: (Object e, StackTrace stack) {
        if (!complete.isCompleted) complete.completeError(e, stack);
      },
      onDone: () {
        if (!complete.isCompleted) complete.complete(bytes.takeBytes());
      },
    );
    try {
      final body = await complete.future.timeout(const Duration(seconds: 15));
      if (job.cancelled) throw const FormatException('Actualisation annulée.');
      return utf8.decode(body);
    } finally {
      await subscription.cancel();
    }
  }

  Future<TrafficSnapshot> refresh({void Function(int, int)? onProgress}) async {
    if (_request != null) {
      throw const FormatException('Une actualisation est déjà en cours.');
    }
    final job = _TrafficRequest(_clientFactory());
    _request = job;
    _verified = false;
    Future<TrafficSnapshot> download() async {
      final initial = await _parser(
        await _get(job, 'content.xml', 8 * 1024 * 1024),
        _clock(),
      );
      final chain = TrafficReconstruction(initial);
      final rawHead = (await _get(job, 'index.txt', 64)).trim();
      if (!RegExp(r'^\d{1,12}$').hasMatch(rawHead)) {
        throw const FormatException('Index du flux trafic invalide.');
      }
      // TIPI index.txt is the next sequence, not an already published file.
      final head = int.parse(rawHead) - 1;
      final count = head - chain.firstSequence + 1;
      if (count < 0 || count > 512) {
        throw const FormatException(
          'L’index et l’instantané ne sont pas synchronisés. Réessayez après leur mise à jour.',
        );
      }
      onProgress?.call(0, count);
      for (var sequence = chain.firstSequence; sequence <= head; sequence++) {
        final publication = await _parser(
          await _get(job, '$sequence.xml', 1024 * 1024),
          _clock(),
        );
        if (job.cancelled) {
          throw const FormatException('Actualisation annulée.');
        }
        chain.apply(sequence, publication);
        onProgress?.call(sequence - chain.firstSequence + 1, count);
      }
      if (job.cancelled) throw const FormatException('Actualisation annulée.');
      return chain.finish(head, _clock());
    }

    try {
      final result = await download().timeout(
        timeout,
        onTimeout: () {
          job.cancelled = true;
          job.client.close();
          throw const FormatException(
            'Le téléchargement du trafic a dépassé le délai prévu.',
          );
        },
      );
      if (job.cancelled) throw const FormatException('Actualisation annulée.');
      cached = result;
      _verified = true;
      return result;
    } finally {
      job.cancelled = true;
      job.client.close();
      if (identical(_request, job)) _request = null;
    }
  }

  void cancel() {
    final job = _request;
    if (job == null) return;
    job.cancelled = true;
    _verified = false;
    job.client.close();
  }

  void close() => cancel();
}
