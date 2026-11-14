/// Evidence about the imported record, separate from user edits and live position.
class PoiProvenance {
  const PoiProvenance(
      {required this.provider,
      required this.recordId,
      required this.url,
      required this.snapshotAt,
      this.classification,
      this.lowClearanceDifficult,
      this.rawType});
  final String provider, recordId, url;
  final DateTime snapshotAt;
  final String? classification, rawType;
  final bool? lowClearanceDifficult;
  String get dateLabel =>
      '${snapshotAt.day.toString().padLeft(2, '0')}/${snapshotAt.month.toString().padLeft(2, '0')}/${snapshotAt.year}';
  static String? railwayClassDescription(int code) => switch (code) {
        10 => 'Protection manuelle, sans barrières',
        >= 11 && <= 16 => 'Passage gardé avec barrières',
        17 => 'Signalisation lumineuse et barrières (SAL 2)',
        18 => 'Signalisation lumineuse, barrières et îlot séparateur',
        19 => 'Signalisation lumineuse et barrières (SAL 4)',
        20 => 'Sans barrières ni signalisation lumineuse automatique',
        21 => 'Signalisation lumineuse (SAL 0), sans barrières',
        _ => null,
      };
  int? get railwayClass => provider == 'SNCF Réseau'
      ? int.tryParse(classification?.replaceFirst('Classe ', '') ?? '')
      : null;
  Map<String, dynamic> toJson() => {
        'name': provider,
        'record_id': recordId,
        'url': url,
        'snapshot_at': snapshotAt.toUtc().toIso8601String(),
        if (classification != null) 'classification': classification,
        if (lowClearanceDifficult != null)
          'low_clearance_difficult': lowClearanceDifficult,
        if (rawType != null) 'raw_type': rawType,
      };
  static PoiProvenance parse(Object? raw) {
    if (raw is! Map) throw const FormatException('Provenance invalide.');
    String text(String key, int max) {
      final value = raw[key];
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > max ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw FormatException('Champ de source invalide : $key.');
      }
      return value.trim();
    }

    final name = text('name', 100),
        id = text('record_id', 120),
        link = text('url', 1500);
    final uri = Uri.tryParse(link);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Lien de source invalide.');
    }
    final date = text('snapshot_at', 40);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}(T.*(?:Z|[+-]\d{2}:\d{2}))?$')
        .hasMatch(date)) {
      throw const FormatException('Date de source invalide.');
    }
    final year = int.parse(date.substring(0, 4)),
        month = int.parse(date.substring(5, 7)),
        day = int.parse(date.substring(8, 10));
    final calendar = DateTime.utc(year, month, day);
    if (calendar.year != year ||
        calendar.month != month ||
        calendar.day != day) {
      throw const FormatException('Date de source invalide.');
    }
    final snapshot = DateTime.tryParse(date);
    if (snapshot == null || snapshot.year < 2000 || snapshot.year > 2100) {
      throw const FormatException('Date de source invalide.');
    }
    final difficulty = raw['low_clearance_difficult'];
    if (difficulty != null && difficulty is! bool) {
      throw const FormatException('Difficulté de franchissement invalide.');
    }
    return PoiProvenance(
        provider: name,
        recordId: id,
        url: link,
        snapshotAt: snapshot.toUtc(),
        classification:
            raw['classification'] == null ? null : text('classification', 80),
        lowClearanceDifficult: difficulty as bool?,
        rawType: raw['raw_type'] == null ? null : text('raw_type', 120));
  }

  static PoiProvenance? tryParse(Object? raw) {
    if (raw == null) return null;
    try {
      return parse(raw);
    } on FormatException {
      return null;
    }
  }
}
