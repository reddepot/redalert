import 'dart:convert';

import 'package:xml/xml.dart';

import '../models/road_measurement.dart';
import 'datex_traffic_parser.dart';

const _ns = 'http://datex2.eu/schema/2/2_0';
const _xsi = 'http://www.w3.org/2001/XMLSchema-instance';
Iterable<XmlElement> _all(XmlNode node, String name) => node.descendantElements
    .where((e) => e.namespaceUri == _ns && e.localName == name);
String? _value(XmlNode node, String name) {
  final values = _all(node, name).toList();
  if (values.length > 1) {
    throw const FormatException('Valeur de mesure ambiguë.');
  }
  return values.firstOrNull?.innerText.trim();
}

String _identity(String? value) {
  if (value == null || !RegExp(r'^[A-Za-z0-9_.#-]{1,120}$').hasMatch(value)) {
    throw const FormatException('Identité de mesure invalide.');
  }
  return value;
}

double? _number(String? value, double maximum) {
  if (value == null) return null;
  final number = double.tryParse(value);
  if (number == null || !number.isFinite || number < 0 || number > maximum) {
    return null;
  }
  return number;
}

List<String> _csvCells(String line) {
  final cells = <String>[];
  final cell = StringBuffer();
  var quoted = false, closed = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(c);
      }
    } else if (c == ';') {
      cells.add(cell.toString());
      cell.clear();
      closed = false;
    } else if (c == '"' && cell.isEmpty && !closed) {
      quoted = true;
    } else {
      if (closed || c == '"') throw const FormatException('Champ CSV ambigu.');
      cell.write(c);
    }
  }
  if (quoted) throw const FormatException('Champ CSV incomplet.');
  cells.add(cell.toString());
  return cells;
}

/// The observed legacy reference omits the commune column in every row.
/// Coordinates are intentionally not interpreted or turned into map segments.
({Map<String, ({String? axis, String? direction})> values, bool shifted})
parseQtvReference(String text) {
  if (text.length > 2 * 1024 * 1024 ||
      utf8.encode(text).length > 2 * 1024 * 1024) {
    throw const FormatException('Référentiel trop volumineux.');
  }
  final lines = const LineSplitter().convert(text.replaceFirst('\ufeff', ''));
  if (lines.isEmpty || lines.length > 20001) {
    throw const FormatException('Référentiel invalide.');
  }
  final header = lines.first.split(';');
  const expected =
      'code_pme;source;source_2;code_insee_commune;axe;pr_debut;abscisse_debut;pr_fin;abscisse_fin;sens_gestionnaire;sens_cardinal;sens_migratoire;sens_giratoire;longueur;nb_voies;x_deb;y_deb;x_fin;y_fin;code_traficolor';
  if (header.join(';') != expected) {
    throw const FormatException('Le format du référentiel QTV a changé.');
  }
  var shifted = false;
  final values = <String, ({String? axis, String? direction})>{};
  for (final line in lines.skip(1).where((e) => e.trim().isNotEmpty)) {
    final cells = _csvCells(line);
    if (cells.length == 19) {
      cells.insert(3, '');
      shifted = true;
    }
    if (cells.length != 20 ||
        cells.any(
          (e) => e.length > 200 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(e),
        )) {
      throw const FormatException('Ligne de référence ambiguë.');
    }
    final id = _identity(cells[0]);
    if (values.containsKey(id)) {
      throw const FormatException('Station de référence dupliquée.');
    }
    final axis = cells[4].trim();
    // A missing field must not silently shift an arbitrary label into the road column.
    if (axis.isNotEmpty &&
        !RegExp(r'^(?:A|N|D|M|R|RN|RD|VC)[0-9][A-Za-z0-9 ./-]{0,40}$')
            .hasMatch(axis)) {
      throw const FormatException('Axe du référentiel non reconnu.');
    }
    final direction = cells[10].trim();
    values[id] = (
      axis: axis.isEmpty ? null : axis,
      direction: direction.isEmpty ? null : direction.replaceAll('_', ' '),
    );
  }
  return (values: values, shifted: shifted);
}

RoadMeasurementSnapshot parseRoadMeasurements(
  String text,
  DateTime now, {
  String? reference,
  String expectedPublisher = 'TIPI',
  bool statesOnly = false,
}) {
  final doc = boundedRoadXml(text);
  final payloads = _all(doc, 'payloadPublication').toList();
  if (payloads.length != 1) {
    throw const FormatException(
      'Une seule publication de mesures est attendue.',
    );
  }
  final payload = payloads.single;
  if (payload.getAttribute('type', namespaceUri: _xsi)?.split(':').last !=
      'MeasuredDataPublication') {
    throw const FormatException('Publication de mesures attendue.');
  }
  final creators = _all(payload, 'publicationCreator').toList();
  final suppliers = _all(doc, 'supplierIdentification').toList();
  if (creators.length != 1 ||
      suppliers.length != 1 ||
      _value(creators.single, 'country') != 'fr' ||
      _value(suppliers.single, 'country') != 'fr' ||
      _value(creators.single, 'nationalIdentifier') != expectedPublisher ||
      _value(suppliers.single, 'nationalIdentifier') != expectedPublisher) {
    throw const FormatException('Producteur des mesures non reconnu.');
  }
  if (_value(payload, 'informationStatus') != 'real' ||
      _value(payload, 'confidentiality') != 'noRestriction') {
    throw const FormatException('Mesures non déclarées réelles ou publiques.');
  }
  final stamp = _value(payload, 'publicationTime');
  if (stamp == null) {
    throw const FormatException('Date de publication absente.');
  }
  DateTime? publishedAt;
  if (RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(stamp)) {
    publishedAt = trafficTime(stamp);
    if (publishedAt.difference(now) > const Duration(minutes: 2)) {
      throw const FormatException('Publication datée dans le futur.');
    }
  } else {
    // Preserve uncertainty; do not silently interpret a producer's wall clock as UTC.
    trafficTime('${stamp}Z');
  }
  final refs = reference == null ? null : parseQtvReference(reference);
  final rows = <RoadMeasurement>[];
  final ids = <String>{};
  var processed = 0, omitted = 0;
  for (final site in _all(payload, 'siteMeasurements')) {
    if (++processed > 20000) throw const FormatException('Trop de stations.');
    final references = _all(site, 'measurementSiteReference').toList();
    if (references.length != 1) {
      throw const FormatException('Référence de station ambiguë.');
    }
    final id = _identity(references.single.getAttribute('id'));
    if (!ids.add(id)) {
      throw const FormatException('Mesure de station dupliquée.');
    }
    final DateTime measuredAt;
    try {
      measuredAt = trafficTime(_value(site, 'measurementTimeDefault') ?? '');
    } on FormatException {
      omitted++;
      continue;
    }
    if (measuredAt.difference(now) > const Duration(minutes: 2)) {
      throw const FormatException('Mesure datée dans le futur.');
    }
    final speedFields = _all(site, 'averageVehicleSpeed').toList();
    final statusFields = _all(site, 'trafficStatus').toList();
    if (speedFields.length > 1 || statusFields.length > 1) {
      throw const FormatException('Agrégat de station ambigu.');
    }
    final speedSamples = speedFields.firstOrNull?.getAttribute(
      'numberOfInputValuesUsed',
    );
    final statusSamples = statusFields.firstOrNull?.getAttribute(
      'numberOfInputValuesUsed',
    );
    final state = _value(site, 'trafficStatusValue');
    final ref = refs?.values[id];
    rows.add(
      RoadMeasurement(
        id: id,
        measuredAt: measuredAt,
        meanSpeedKmh: statesOnly || speedSamples == '0'
            ? null
            : _number(_value(site, 'speed'), 300),
        vehiclesPerHour: statesOnly
            ? null
            : _number(_value(site, 'vehicleFlowRate'), 1000000),
        trafficState:
            !statesOnly ||
                statusSamples == '0' ||
                !const [
                  'freeFlow',
                  'heavyTraffic',
                  'congested',
                  'impossible',
                  'unknown',
                ].contains(state)
            ? null
            : state,
        axis: ref?.axis,
        direction: ref?.direction,
      ),
    );
  }
  if (rows.isEmpty) {
    throw const FormatException('Aucune station dans la publication.');
  }
  return RoadMeasurementSnapshot(
    publisher: expectedPublisher,
    checkedAt: now,
    publishedAt: publishedAt,
    rows: List.unmodifiable(rows),
    referenceShifted: refs?.shifted ?? false,
    omittedRows: omitted,
  );
}
