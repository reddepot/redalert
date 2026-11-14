// Explicit opt-in probe of a public national feed. No Android/device data.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:locreminder/services/traffic_repository.dart';

class PublicProbeClient extends http.BaseClient {
  final inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (response.statusCode != 200) {
      // Public endpoint filename/status only; no headers or private device data.
      stdout.writeln('Public source: ${request.url.pathSegments.last} HTTP ${response.statusCode}');
    }
    return response;
  }
  @override
  void close() => inner.close();
}

void main() {
  test('public traffic source, bounded client and background parser', () async {
    if (Platform.environment['REDALERT_PUBLIC_TRAFFIC_PROBE'] != '1') {
      fail('Explicit REDALERT_PUBLIC_TRAFFIC_PROBE=1 required');
    }
    final repository = TrafficRepository(clientFactory: PublicProbeClient.new);
    try {
      final data = await repository.refresh();
      final now = DateTime.now().toUtc();
      final windows = <String, int>{};
      for (final record in data.records) {
        windows.update(record.window(now).name, (n) => n+1, ifAbsent: () => 1);
      }
      final report = {
        'checked_at': data.checkedAt.toUtc().toIso8601String(),
        'snapshot_at': data.snapshotAt.toIso8601String(),
        'published_at': data.publishedAt.toIso8601String(),
        'first_sequence': data.firstSequence, 'last_sequence': data.lastSequence,
        'public_real_records': data.records.length, 'windows': windows,
        'fresh': repository.usable(now), 'positions_transmitted': false,
        'operational_alerts_validated': false,
      };
      final file = File('build/traffic-validation/live-client.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      expect(data.lastSequence, greaterThanOrEqualTo(data.firstSequence-1));
      expect(data.records, isNotEmpty);
    } finally { repository.close(); }
  }, timeout: const Timeout(Duration(seconds: 75)));
}
