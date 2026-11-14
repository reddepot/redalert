import 'dart:async';

import 'package:flutter/material.dart';

import '../models/road_measurement.dart';
import '../services/road_measurement_repository.dart';
import '../widgets/road_time.dart';

class RoadMeasurementScreen extends StatefulWidget {
  const RoadMeasurementScreen({super.key, this.repository, this.clock});
  final RoadMeasurementRepository? repository;
  final DateTime Function()? clock;
  @override
  State<RoadMeasurementScreen> createState() => _RoadMeasurementScreenState();
}

class _RoadMeasurementScreenState extends State<RoadMeasurementScreen> {
  late final repository = widget.repository ?? RoadMeasurementRepository();
  String? _region, _error;
  String _query = '';
  bool _loading = false, _states = false;
  Timer? _timer;
  DateTime get now => widget.clock?.call() ?? DateTime.now();
  List<bool> _validity = [];
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final snapshot = repository.cached;
      if (snapshot == null) return;
      final validity = [
        snapshot.publicationFresh(now),
        for (final r in snapshot.rows) r.fresh(now),
      ];
      if (validity.length != _validity.length ||
          List.generate(
            validity.length,
            (i) => validity[i] != _validity[i],
          ).any((e) => e)) {
        setState(() => _validity = validity);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    repository.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await repository.refresh(region: _states ? _region : null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Actualisation impossible. Aucun relevé précédent n’est présenté comme actuel.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = repository.cached;
    final wanted = _states ? _region : null;
    final matching =
        snapshot != null &&
        (!_states || _region != null) &&
        repository.cachedRegion == wanted;
    final usable =
        matching && repository.verified && snapshot.publicationFresh(now);
    final rows = !matching
        ? <RoadMeasurement>[]
        : snapshot.rows
              .where(
                (r) => '${r.id} ${r.axis ?? ''} ${r.direction ?? ''}'
                    .toLowerCase()
                    .contains(_query.toLowerCase()),
              )
              .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesures du trafic'),
        actions: [
          IconButton(
            tooltip: 'Actualiser les mesures',
            onPressed: _loading || (_states && _region == null)
                ? null
                : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Réseau national non concédé · mesures de stations. Une vitesse moyenne n’est pas une limitation. Aucune alerte automatique.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Vitesses et débits'),
                          selected: !_states,
                          onSelected: _loading
                              ? null
                              : (_) => setState(() {
                                  _states = false;
                                  _error = null;
                                }),
                        ),
                        ChoiceChip(
                          label: const Text('États Traficolor'),
                          selected: _states,
                          onSelected: _loading
                              ? null
                              : (_) => setState(() {
                                  _states = true;
                                  _error = null;
                                }),
                        ),
                      ],
                    ),
                    if (_states)
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _region,
                        decoration: const InputDecoration(
                          labelText: 'Producteur',
                        ),
                        items: RoadMeasurementRepository.regions.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: _loading
                            ? null
                            : (value) => setState(() {
                                _region = value;
                                _error = null;
                              }),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading || (_states && _region == null)
                          ? null
                          : _refresh,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Consulter la source publique'),
                    ),
                    if (_loading) ...[
                      const LinearProgressIndicator(),
                      TextButton(
                        onPressed: () {
                          repository.cancel();
                        },
                        child: const Text('Annuler'),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (matching) ...[
                      const SizedBox(height: 12),
                      Text('Consulté le ${trafficStamp(snapshot.checkedAt)}'),
                      Text(
                        snapshot.publishedAt == null
                            ? 'Date de publication non confirmée ; vérifier l’heure de chaque mesure.'
                            : 'Publication du ${trafficStamp(snapshot.publishedAt!)}',
                      ),
                      if (!usable)
                        const Text(
                          'Relevé non actuel · valeurs historiques uniquement',
                        ),
                      if (snapshot.omittedRows > 0)
                        Text(
                          '${snapshot.omittedRows} stations sans date de mesure exploitable',
                        ),
                      if (snapshot.referenceShifted)
                        const Text(
                          'Référentiel de station incomplet · localisation non cartographiée',
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Rechercher un axe ou une station',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      Text('${rows.length} stations'),
                    ],
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final fresh = usable && row.fresh(now);
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.axis == null
                              ? row.id
                              : '${row.axis} · ${row.direction ?? row.id}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${row.id} · mesure du ${trafficStamp(row.measuredAt)}',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _states
                              ? row.stateLabel
                              : '${row.meanSpeedKmh?.toStringAsFixed(0) ?? '—'} km/h en moyenne · ${row.vehiclesPerHour?.toStringAsFixed(0) ?? '—'} véhicules/h',
                        ),
                        if (!fresh) const Text('Non actuelle'),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
