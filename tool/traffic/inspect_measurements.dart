import 'dart:convert';
import 'dart:io';

import 'package:locreminder/services/road_measurement_parser.dart';

String boundedFile(File file, int limit) {
  if (file.lengthSync() > limit) {
    throw const FormatException('File exceeds bound');
  }
  return file.readAsStringSync();
}

void main(List<String> args) {
  if (args.length != 3) {
    throw ArgumentError('QTV_XML QTV_REFERENCE TRAFICOLOR_DIRECTORY');
  }
  final now = DateTime.now().toUtc();
  final result = <Map<String, Object?>>[];
  try {
    final qtv = parseRoadMeasurements(
      boundedFile(File(args[0]), 8 * 1024 * 1024),
      now,
      reference: boundedFile(File(args[1]), 2 * 1024 * 1024),
    );
    result.add({
      'family': 'QTV',
      'rows': qtv.rows.length,
      'fresh': qtv.rows.where((r) => r.fresh(now)).length,
      'named_axes': qtv.rows.where((r) => r.axis != null).length,
      'shifted_reference': qtv.referenceShifted,
    });
  } catch (e) {
    result.add({'family': 'QTV', 'error': e.toString()});
  }
  final sources = File('${args[2]}/traficolor-probe.json');
  final manifest = jsonDecode(boundedFile(sources, 256 * 1024)) as Map;
  for (final source in manifest['sources'] as List) {
    if (source['error'] != null) continue;
    final region = source['region'] as String;
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(region)) {
      throw const FormatException('Invalid source name');
    }
    try {
      final snapshot = parseRoadMeasurements(
        boundedFile(File('${args[2]}/$region.xml'), 8 * 1024 * 1024),
        now,
        expectedPublisher: source['publisher'] as String,
        statesOnly: true,
      );
      result.add({
        'family': 'Traficolor',
        'producer': region,
        'rows': snapshot.rows.length,
        'fresh': snapshot.rows.where((r) => r.fresh(now)).length,
        'qualified_publication': snapshot.publishedAt != null,
      });
    } catch (e) {
      result.add({
        'family': 'Traficolor',
        'producer': region,
        'error': e.toString(),
      });
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ')
        .convert({'checked_at': now.toIso8601String(), 'results': result}),
  );
  if (result.any((r) => r.containsKey('error'))) exitCode = 1;
}
