import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../models/traffic_data.dart';

const _ns = 'http://datex2.eu/schema/2/2_0';
const _xsi = 'http://www.w3.org/2001/XMLSchema-instance';

Iterable<XmlElement> _children(XmlElement node, String name) => node
    .childElements
    .where((e) => e.localName == name && e.namespaceUri == _ns);
Iterable<XmlElement> _all(XmlElement node, String name) => node
    .descendantElements
    .where((e) => e.localName == name && e.namespaceUri == _ns);
XmlElement? _child(XmlElement node, String name) {
  final matches = _children(node, name).toList();
  if (matches.length > 1) throw const FormatException('Champ trafic ambigu.');
  return matches.firstOrNull;
}

String? _text(XmlElement node, String name) =>
    _child(node, name)?.innerText.trim();
String? _deepText(XmlElement node, String name) {
  final found = _all(node, name).toList();
  if (found.length > 1) throw const FormatException('Champ trafic ambigu.');
  return found.firstOrNull?.innerText.trim();
}

String _required(String? text) {
  if (text == null || text.isEmpty || text.length > 200) {
    throw const FormatException('Identité du flux trafic invalide.');
  }
  return text;
}

int _version(String? text) {
  if (text == null || !RegExp(r'^\d{1,12}$').hasMatch(text)) {
    throw const FormatException('Version trafic invalide.');
  }
  return int.parse(text);
}

DateTime trafficTime(String text) {
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(text);
  if (m == null) {
    throw const FormatException('Date trafic sans fuseau ou invalide.');
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  final day = DateTime.utc(parts[0], parts[1], parts[2]);
  if (parts[0] < 2000 ||
      day.year != parts[0] ||
      day.month != parts[1] ||
      day.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59) {
    throw const FormatException('Date trafic invalide.');
  }
  final zone = m.group(7)!;
  if (zone != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 14 ||
          int.parse(zone.substring(4, 6)) > 59 ||
          (zone.substring(1, 3) == '14' && zone.substring(4, 6) != '00'))) {
    throw const FormatException('Fuseau trafic invalide.');
  }
  return DateTime.parse(text).toUtc();
}

DateTime? _time(XmlElement node, String name) {
  final text = _deepText(node, name);
  return text == null ? null : trafficTime(text);
}

bool _flag(XmlElement node, String name) {
  final text = _deepText(node, name);
  if (text == null || text == 'false' || text == '0') return false;
  if (text == 'true' || text == '1') return true;
  throw const FormatException('État de fin trafic invalide.');
}

/// Prefix-independent comparison of versioned payloads. No external resolution.
Object _canonical(XmlElement node) => [
  node.namespaceUri,
  node.localName,
  (node.attributes
      .where((a) => a.name.prefix != 'xmlns' && a.name.qualified != 'xmlns')
      .map(
        (a) => jsonEncode([
          a.namespaceUri,
          a.localName,
          a.namespaceUri == _xsi && a.localName == 'type'
              ? a.value.split(':').last
              : a.value,
        ]),
      )
      .toList()
    ..sort()),
  node.childElements.isEmpty
      ? node.innerText.trim()
      : node.childElements.map(_canonical).toList(),
];

XmlDocument boundedRoadXml(String text) {
  if (text.length > 8 * 1024 * 1024 ||
      utf8.encode(text).length > 8 * 1024 * 1024 ||
      RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
    throw const FormatException(
      'Document trafic trop volumineux ou non accepté.',
    );
  }
  // Bound nesting and element count before allocating a DOM or recursing.
  var depth = 0, elements = 0;
  for (final event in parseEvents(
    text,
    validateNesting: true,
    validateNamespace: true,
    validateDocument: true,
  )) {
    if (event is XmlStartElementEvent) {
      elements++;
      if (elements > 120000 || event.attributes.length > 24 || depth >= 64) {
        throw const FormatException('Structure du flux trafic trop complexe.');
      }
      if (!event.isSelfClosing) depth++;
    } else if (event is XmlEndElementEvent) {
      depth--;
    } else if (event is XmlDoctypeEvent) {
      throw const FormatException('DTD trafic non accepté.');
    }
  }
  return XmlDocument.parse(text);
}

TrafficPublication parseTrafficPublication(String text, DateTime now) {
  final doc = boundedRoadXml(text);
  var count = 0;
  final payloads = <XmlElement>[], exchanges = <XmlElement>[];
  for (final e in doc.descendantElements) {
    count++;
    if (count > 120000 || e.attributes.length > 24) {
      throw const FormatException('Structure du flux trafic trop complexe.');
    }
    if (e.namespaceUri == _ns && e.localName == 'payloadPublication') {
      payloads.add(e);
    }
    if (e.namespaceUri == _ns && e.localName == 'exchange') exchanges.add(e);
  }
  if (payloads.length != 1 || exchanges.length != 1) {
    throw const FormatException('Une seule publication trafic est attendue.');
  }
  final p = payloads.single, exchange = exchanges.single;
  if (p.getAttribute('type', namespaceUri: _xsi)?.split(':').last !=
      'SituationPublication') {
    throw const FormatException(
      'Ce flux ne contient pas de situations routières.',
    );
  }
  final supplier = _child(exchange, 'supplierIdentification');
  final creator = _child(p, 'publicationCreator');
  String identity(XmlElement? node) => node == null
      ? ''
      : '${_text(node, 'country')}:${_text(node, 'nationalIdentifier')}';
  final publisher = identity(supplier);
  if (publisher != 'fr:Tipi' || publisher != identity(creator)) {
    throw const FormatException('Le producteur du flux trafic a changé.');
  }
  final subscription = _child(exchange, 'subscription');
  if (subscription == null ||
      _text(subscription, 'subscriptionState') != 'active') {
    throw const FormatException('Le flux trafic est suspendu.');
  }
  final method = _required(_text(subscription, 'updateMethod'));
  if (method != 'snapshot' && method != 'allElementUpdate') {
    throw const FormatException(
      'Méthode de mise à jour trafic non prise en charge.',
    );
  }
  final published = trafficTime(_required(_text(p, 'publicationTime')));
  if (published.isAfter(now.add(const Duration(minutes: 2)))) {
    throw const FormatException('Horloge du flux trafic incohérente.');
  }
  final feed = _text(p, 'feedType');
  final sequence = feed == null ? null : _version(feed);
  if (method == 'snapshot' && sequence == null) {
    throw const FormatException('Séquence de l’instantané trafic absente.');
  }
  final situations = <TrafficSituation>[];
  final ids = <String>{};
  var recordCount = 0;
  for (final s in _children(p, 'situation')) {
    final id = _required(s.getAttribute('id'));
    if (!ids.add(id)) {
      throw const FormatException('Situation trafic en doublon.');
    }
    final version = _version(s.getAttribute('version'));
    final updated = trafficTime(_required(_text(s, 'situationVersionTime')));
    if (updated.isAfter(published.add(const Duration(minutes: 2)))) {
      throw const FormatException('Version de situation postérieure au flux.');
    }
    final header = _child(s, 'headerInformation');
    final real = header != null && _text(header, 'informationStatus') == 'real';
    final public =
        header != null && _text(header, 'confidentiality') == 'noRestriction';
    final records = <TrafficRecord>[];
    final recordIds = <String>{};
    for (final r in _children(s, 'situationRecord')) {
      if (++recordCount > 5000) {
        throw const FormatException('Trop de fiches trafic.');
      }
      final rid = _required(r.getAttribute('id'));
      if (!recordIds.add(rid)) {
        throw const FormatException('Fiche trafic en doublon.');
      }
      final rtime = trafficTime(
        _required(_text(r, 'situationRecordVersionTime')),
      );
      if (rtime.isAfter(published.add(const Duration(minutes: 2)))) {
        throw const FormatException('Version de fiche postérieure au flux.');
      }
      final comments = <String>[];
      for (final c in _children(r, 'generalPublicComment')) {
        for (final v in _all(c, 'value')) {
          if (v.getAttribute('lang') == 'fr' ||
              v.getAttribute('lang') == null) {
            final label = v.innerText.trim();
            if (label.isNotEmpty) {
              comments.add(
                label.length > 2000 ? '${label.substring(0, 2000)}…' : label,
              );
            }
          }
        }
      }
      final location = _child(r, 'groupOfLocations');
      LatLng? coordinate(XmlElement? parent) {
        if (parent == null) return null;
        final pair = _all(parent, 'pointCoordinates').toList();
        if (pair.length != 1) return null;
        final lat = double.tryParse(_text(pair.single, 'latitude') ?? '');
        final lon = double.tryParse(_text(pair.single, 'longitude') ?? '');
        if (lat == null ||
            lon == null ||
            !lat.isFinite ||
            !lon.isFinite ||
            lat.abs() > 90 ||
            lon.abs() > 180) {
          return null;
        }
        return LatLng(lat, lon);
      }

      var geometry = const TrafficGeometry();
      if (location != null) {
        final type = location
            .getAttribute('type', namespaceUri: _xsi)
            ?.split(':')
            .last;
        if (type == 'Point') {
          geometry = TrafficGeometry(
            point: coordinate(_child(location, 'tpegPointLocation')),
          );
        } else if (type == 'Linear') {
          final linear = _child(location, 'tpegLinearLocation');
          if (linear != null) {
            geometry = TrafficGeometry(
              from: coordinate(_child(linear, 'from')),
              to: coordinate(_child(linear, 'to')),
            );
          }
        }
      }
      final roads = location == null
          ? <String>[]
          : _all(location, 'roadNumber')
                .map((e) => e.innerText.trim())
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList();
      if (roads.isEmpty && location != null) {
        for (final name in _all(location, 'name')) {
          if (_text(name, 'tpegOtherPointDescriptorType') == 'linkName') {
            for (final v in _all(name, 'value')) {
              final road = v.innerText.trim();
              if (road.isNotEmpty) roads.add(road);
            }
          }
        }
      }
      const detailNames = {
        'accidentType',
        'abnormalTrafficType',
        'maintenanceWorksType',
        'constructionWorkType',
        'roadOrCarriagewayOrLaneManagementType',
        'generalObstructionType',
        'environmentalObstructionType',
        'poorEnvironmentType',
        'weatherRelatedRoadConditionType',
        'nonWeatherRelatedRoadConditionType',
        'vehicleObstructionType',
      };
      records.add(
        TrafficRecord(
          id: rid,
          version: _version(r.getAttribute('version')),
          kind:
              r.getAttribute('type', namespaceUri: _xsi)?.split(':').last ??
              'unknown',
          signature: jsonEncode(_canonical(r)),
          updatedAt: rtime,
          source:
              _deepText(r, 'sourceIdentification') ??
              'DIR — producteur non précisé',
          real: real,
          public: public,
          probability: _text(r, 'probabilityOfOccurrence') ?? 'unknown',
          validity: _deepText(r, 'validityStatus') ?? 'unknown',
          terminal: _flag(r, 'cancel') || _flag(r, 'end'),
          complexSchedule: r.descendantElements.any(
            (e) =>
                e.namespaceUri == _ns &&
                const {
                  'validPeriod',
                  'recurringTimePeriodOfDay',
                  'recurringDayWeekMonthPeriod',
                  'exceptionPeriod',
                  'overrunning',
                }.contains(e.localName),
          ),
          start: _time(r, 'overallStartTime'),
          end: _time(r, 'overallEndTime'),
          comments: List.unmodifiable(comments.toSet()),
          roads: List.unmodifiable(roads.toSet()),
          direction: location == null
              ? null
              : _deepText(location, 'tpegDirection'),
          geometry: geometry,
          details: List.unmodifiable(
            r.childElements
                .where(
                  (e) =>
                      e.namespaceUri == _ns &&
                      detailNames.contains(e.localName),
                )
                .map((e) => e.innerText.trim()),
          ),
        ),
      );
    }
    situations.add(
      TrafficSituation(
        id,
        version,
        updated,
        jsonEncode(_canonical(s)),
        List.unmodifiable(records),
      ),
    );
  }
  return TrafficPublication(
    publisher: publisher,
    publishedAt: published,
    method: method,
    nextSequence: sequence,
    situations: List.unmodifiable(situations),
  );
}

/// Transactional in-memory reconstruction. A gap/error never returns a new view.
class TrafficReconstruction {
  TrafficReconstruction(TrafficPublication initial) {
    if (initial.method != 'snapshot' || initial.nextSequence == null) {
      throw const FormatException('Un instantané complet est nécessaire.');
    }
    publisher = initial.publisher;
    snapshotAt = publishedAt = initial.publishedAt;
    firstSequence = nextSequence = initial.nextSequence!;
    for (final s in initial.situations) {
      _situations[s.id] = s;
      _remember(s);
    }
  }
  late final String publisher;
  late final DateTime snapshotAt;
  late DateTime publishedAt;
  late final int firstSequence;
  late int nextSequence;
  final _situations = <String, TrafficSituation>{};
  final _recordVersions = <(String, String), TrafficRecord>{};
  void _remember(TrafficSituation s) {
    for (final r in s.records) {
      _recordVersions[(s.id, r.id)] = r;
    }
  }

  void apply(int sequence, TrafficPublication update) {
    if (sequence != nextSequence ||
        update.method != 'allElementUpdate' ||
        update.publisher != publisher ||
        update.publishedAt.isBefore(publishedAt)) {
      throw const FormatException(
        'Chaîne de mises à jour trafic incomplète ou incohérente.',
      );
    }
    // Validate the entire publication before changing any state.
    for (final s in update.situations) {
      final old = _situations[s.id];
      if (old != null &&
          (s.version < old.version ||
              s.updatedAt.isBefore(old.updatedAt) ||
              (s.version == old.version && s.signature != old.signature))) {
        throw const FormatException('Conflit de versions dans le flux trafic.');
      }
      for (final r in s.records) {
        final prior = _recordVersions[(s.id, r.id)];
        if (prior != null &&
            (r.version < prior.version ||
                r.updatedAt.isBefore(prior.updatedAt) ||
                (r.version == prior.version &&
                    r.signature != prior.signature) ||
                (prior.terminal && !r.terminal))) {
          throw const FormatException('Conflit de versions de fiche trafic.');
        }
      }
    }
    final newSituations = {
      ..._situations.keys,
      ...update.situations.map((s) => s.id),
    };
    final newRecords = {
      ..._recordVersions.keys,
      for (final s in update.situations)
        for (final r in s.records) (s.id, r.id),
    };
    if (newSituations.length > 5000 || newRecords.length > 10000) {
      throw const FormatException('Reconstruction trafic trop volumineuse.');
    }
    for (final s in update.situations) {
      _situations[s.id] = s;
      _remember(s);
    }
    nextSequence++;
    publishedAt = update.publishedAt;
  }

  TrafficSnapshot finish(int head, DateTime checkedAt) {
    if (head != nextSequence - 1) {
      throw const FormatException('Une mise à jour trafic manque.');
    }
    return TrafficSnapshot(
      publishedAt: publishedAt,
      snapshotAt: snapshotAt,
      checkedAt: checkedAt,
      firstSequence: firstSequence,
      lastSequence: head,
      situations: _situations.values,
    );
  }
}
