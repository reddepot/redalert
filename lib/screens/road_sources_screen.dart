import '../models/poi_provenance.dart';
import 'package:flutter/material.dart';
import '../models/department_names.dart';
import '../models/location_alarm.dart';
import '../services/road_data_repository.dart';

class RoadSourcesScreen extends StatefulWidget {
  const RoadSourcesScreen({super.key, required this.kind, this.repository});
  final RoadDataKind kind;
  final RoadDataRepository? repository;
  @override
  State<RoadSourcesScreen> createState() => _RoadSourcesScreenState();
}

class _RoadSourcesScreenState extends State<RoadSourcesScreen> {
  late final RoadDataRepository _data =
      widget.repository ?? RoadDataRepository();
  late RoadDataKind _kind = widget.kind;
  String _department = '01';
  int _crossingClass = 0;
  bool _lowOnly = false, _loading = false;
  RoadImportBatch? _batch;
  String? _error;
  @override
  void dispose() {
    _data.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _batch = null;
    });
    try {
      final data = _kind == RoadDataKind.railway
          ? await _data.railway(_department,
              lowClearanceOnly: _lowOnly,
              crossingClass: _crossingClass == 0 ? null : _crossingClass)
          : await _data.calming(_department);
      if (mounted) setState(() => _batch = data);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FormatException
            ? error.message.toString()
            : 'Chargement impossible. Aucun lieu n’a été modifié.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reset(VoidCallback update) => setState(() {
        update();
        _batch = null;
        _error = null;
      });
  @override
  Widget build(BuildContext context) {
    final railway = _kind == RoadDataKind.railway, batch = _batch;
    final counts = <String, int>{};
    for (final alarm in batch?.alarms ?? <LocationAlarm>[]) {
      counts.update(alarm.poiType.label, (n) => n + 1, ifAbsent: () => 1);
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Données de route')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Compléter vos lieux',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
              'Choisissez une source et un département. Une prévisualisation précède l’enregistrement ; les nouveaux lieux restent désarmés.'),
          const SizedBox(height: 20),
          DropdownButtonFormField<RoadDataKind>(
            key: const ValueKey('road-source-kind'),
            initialValue: _kind,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'Source'),
            items: const [
              DropdownMenuItem(
                  value: RoadDataKind.railway,
                  child: Text('Passages à niveau SNCF')),
              DropdownMenuItem(
                  value: RoadDataKind.calming,
                  child: Text('Dangers routiers OSM')),
            ],
            onChanged: _loading
                ? null
                : (kind) {
                    if (kind != null) _reset(() => _kind = kind);
                  },
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
              key: const ValueKey('road-department'),
              initialValue: _department,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Département'),
              items: departmentNames.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text('${e.key} · ${e.value}')))
                  .toList(),
              onChanged: _loading
                  ? null
                  : (code) {
                      if (code != null) _reset(() => _department = code);
                    }),
          const SizedBox(height: 16),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            railway
                                ? 'Passages à niveau SNCF Réseau'
                                : 'Aménagements OpenStreetMap',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(railway
                            ? 'Catalogue embarqué, utilisable sans réseau. PN routiers publics ; les références secondaires, PN piétons et identifiants à positions contradictoires sont écartés. Date du jeu affichée après chargement.'
                            : 'Ralentisseurs, vibreurs, creux et rétrécissements cartographiés comme points. Le chargement transmet uniquement le département à Overpass, sans votre position. Connexion requise ; couverture communautaire partielle.'),
                        if (railway) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                              key: const ValueKey('railway-class'),
                              initialValue: _crossingClass,
                              isExpanded: true,
                              itemHeight: null,
                              decoration: const InputDecoration(
                                  labelText: 'Classe du passage'),
                              items: [
                                const DropdownMenuItem(
                                    value: 0,
                                    child:
                                        Text('Toutes les classes routières')),
                                for (var code = 10; code <= 21; code++)
                                  DropdownMenuItem(
                                      value: code, child: Text('Classe $code'))
                              ],
                              onChanged: _loading
                                  ? null
                                  : (code) {
                                      if (code != null) {
                                        _reset(() => _crossingClass = code);
                                      }
                                    }),
                          if (_crossingClass > 0)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                    PoiProvenance.railwayClassDescription(
                                        _crossingClass)!)),
                        ],
                        if (railway)
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                  'Difficultés pour véhicules surbaissés'),
                              subtitle: const Text(
                                  'Limiter aux passages explicitement signalés par la source'),
                              value: _lowOnly,
                              onChanged: _loading
                                  ? null
                                  : (v) => _reset(() => _lowOnly = v)),
                      ]))),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined),
              label: Text(_loading
                  ? 'Chargement…'
                  : railway
                      ? 'Charger ce département'
                      : 'Interroger OpenStreetMap')),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (batch != null) ...[
            const SizedBox(height: 24),
            Text('${batch.alarms.length} lieux proposés',
                style: Theme.of(context).textTheme.titleLarge),
            Text(
                '${batch.provider} · ${railway ? 'jeu traité le' : 'extrait du'} ${batch.snapshotAt.day.toString().padLeft(2, '0')}/${batch.snapshotAt.month.toString().padLeft(2, '0')}/${batch.snapshotAt.year}'),
            const SizedBox(height: 10),
            for (final e in counts.entries) Text('${e.key} : ${e.value}'),
            if (batch.skipped > 0)
              Text(
                  '${batch.skipped} éléments non retenus (type ou accès non pris en charge).'),
            if (batch.alarms.isEmpty)
              const Text(
                  'Aucun lieu proposé dans cet extrait. Cela ne garantit pas l’absence de danger sur le terrain.'),
            const SizedBox(height: 16),
            FilledButton.icon(
                key: const ValueKey('road-preview'),
                onPressed: batch.alarms.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(batch.alarms),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Prévisualiser l’import')),
          ],
        ])));
  }
}
