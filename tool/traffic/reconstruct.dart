// Offline inspection of public files only; never reads Android preferences.
import 'dart:convert';
import 'dart:io';

import 'package:locreminder/services/datex_traffic_parser.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/traffic/reconstruct.dart DIRECTORY HEAD ISO_TIME',
    );
    exitCode = 2;
    return;
  }
  final directory = Directory(args[0]);
  final head = int.parse(args[1]);
  final now = trafficTime(args[2]);
  final watch = Stopwatch()..start();
  String bounded(String name) {
    final file = File('${directory.path}/$name');
    if (file.lengthSync() > 8 * 1024 * 1024) {
      throw const FormatException('Source exceeds 8 MiB');
    }
    return file.readAsStringSync();
  }

  final reconstruction = TrafficReconstruction(
    parseTrafficPublication(bounded('content.xml'), now),
  );
  if (head - reconstruction.firstSequence > 512) {
    throw const FormatException('Too many updates');
  }
  for (var n = reconstruction.firstSequence; n <= head; n++) {
    reconstruction.apply(n, parseTrafficPublication(bounded('$n.xml'), now));
  }
  final result = reconstruction.finish(head, now);
  final windows = <String, int>{};
  for (final r in result.records) {
    windows.update(r.window(now).name, (n) => n + 1, ifAbsent: () => 1);
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'source': 'Bison Futé / DIR',
      'first_sequence': result.firstSequence,
      'last_sequence': result.lastSequence,
      'snapshot_at': result.snapshotAt.toIso8601String(),
      'last_publication_at': result.publishedAt.toIso8601String(),
      'inspected_at': now.toIso8601String(),
      'situations': result.situations.length,
      'public_real_records': result.records.length,
      'windows': windows,
      'stale': result.isStale(now),
      'elapsed_ms': watch.elapsedMilliseconds,
      'operational_alerts_validated': false,
    }),
  );
}
