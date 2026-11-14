// Explicit public-source probe, with no Android or personal data access.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/services/road_measurement_repository.dart';

void main() {
  test('public QTV and every configured Traficolor producer use the bounded client', () async {
    if (Platform.environment['REDALERT_PUBLIC_MEASURES_PROBE'] != '1') {
      fail('Explicit REDALERT_PUBLIC_MEASURES_PROBE=1 required');
    }
    final results = <Map<String, Object?>>[];
    for (final region in [null, ...RoadMeasurementRepository.regions.keys]) {
      final repository = RoadMeasurementRepository();
      try {
        final snapshot = await repository.refresh(region: region);
        results.add({
          'family': region == null ? 'QTV' : 'Traficolor',
          'producer': snapshot.publisher,
          'rows': snapshot.rows.length,
          'omitted_rows': snapshot.omittedRows,
          'fresh_rows': snapshot.rows
              .where((r) => r.fresh(DateTime.now()))
              .length,
          'qualified_publication': snapshot.publishedAt != null,
          'reference_shifted': snapshot.referenceShifted,
        });
      } catch (e) {
        results.add({
          'producer': region ?? 'TIPI',
          'error': e.runtimeType.toString(),
        });
      } finally {
        repository.cancel();
      }
    }
    final file = File('build/traffic-validation/live-measures.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'checked_at': DateTime.now().toUtc().toIso8601String(),
        'positions_transmitted': false,
        'operational_alerts_validated': false,
        'results': results,
      }),
    );
    expect(results.where((r) => r.containsKey('error')), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
