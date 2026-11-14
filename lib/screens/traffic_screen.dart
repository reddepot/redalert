import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/traffic_data.dart';
import '../services/traffic_repository.dart';
import '../widgets/traffic_map.dart';
import '../widgets/map_tiles.dart';
import 'road_measurement_screen.dart';
import '../widgets/road_time.dart';

String trafficWindowLabel(TrafficWindow window) => switch (window) {
  TrafficWindow.declared => 'Déclaré dans sa période',
  TrafficWindow.forecast => 'Prévu',
  TrafficWindow.scheduleUnknown => 'Horaires à vérifier',
  TrafficWindow.suspended => 'Suspendu',
  TrafficWindow.expired => 'Période terminée',
  TrafficWindow.ended => 'Retiré par le producteur',
  TrafficWindow.uncertain => 'Réalité ou validité à vérifier',
};

class TrafficScreen extends StatefulWidget {
  const TrafficScreen({
    super.key,
    required this.repository,
    this.clock,
    this.tileLayer,
    this.mapStyle = MapStyle.standard,
  });
  final TrafficRepository repository;
  final DateTime Function()? clock;
  final Widget? tileLayer;
  final MapStyle mapStyle;
  @override
  State<TrafficScreen> createState() => _TrafficScreenState();
}

class _TrafficScreenState extends State<TrafficScreen>
    with WidgetsBindingObserver {
  bool _loading = false, _map = false;
  int _done = 0, _total = 0, _filter = 0;
  String? _error;
  String _query = '';
  Timer? _tick;
  List<Object?>? _lastTimeState;
  List<Object?> _timeState(DateTime now) => [
    widget.repository.cached,
    widget.repository.usable(now),
    for (final record in widget.repository.cached?.records ?? <TrafficRecord>[])
      record.window(now),
  ];
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || widget.repository.cached == null) return;
      final state = _timeState(_now);
      if (!listEquals(state, _lastTimeState)) {
        setState(() => _lastTimeState = state);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    widget.repository.cancel();
    super.dispose();
  }

  Future<void> _openPublicPage(String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      /* Keep the consultation screen usable. */
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir cette source.')),
      );
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _done = _total = 0;
      _map = false;
    });
    try {
      await widget.repository.refresh(
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : 'Trafic indisponible. Réessayez plus tard.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matches(TrafficWindow window) => switch (_filter) {
    0 => window == TrafficWindow.declared,
    1 => window == TrafficWindow.forecast,
    2 => const {
      TrafficWindow.scheduleUnknown,
      TrafficWindow.uncertain,
      TrafficWindow.suspended,
    }.contains(window),
    _ => window == TrafficWindow.ended || window == TrafficWindow.expired,
  };
  @override
  Widget build(BuildContext context) {
    final snapshot = widget.repository.cached;
    final now = _now;
    _lastTimeState = _timeState(now);
    final usable = widget.repository.usable(now);
    final records =
        (snapshot?.records ?? <TrafficRecord>[])
            .where(
              (r) =>
                  _matches(r.window(now)) &&
                  '${r.roads.join(' ')} ${r.title} ${r.comments.join(' ')} ${r.source}'
                      .toLowerCase()
                      .contains(_query),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final showMap = _map && usable && _filter == 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trafic et événements'),
        actions: [
          IconButton(
            tooltip: 'Vitesses et états du trafic',
            icon: const Icon(Icons.speed),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RoadMeasurementScreen(),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Préparer un trajet',
            onSelected: _openPublicPage,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'https://www.bison-fute.gouv.fr/previsions,10741.html',
                child: Text('Prévisions Bison Futé'),
              ),
              PopupMenuItem(
                value: 'https://www.bison-fute.gouv.fr/france,10526.html',
                child: Text('Routes en hiver'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Actualiser le trafic',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bison Futé · événements DIR',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Routes nationales et autoroutes non concédées. Consultation datée, sans alerte sonore. Le téléchargement national ne transmet ni position ni itinéraire.',
                          ),
                          if (snapshot == null && !_loading)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: FilledButton.icon(
                                onPressed: _refresh,
                                icon: const Icon(Icons.download),
                                label: const Text('Charger les événements'),
                              ),
                            ),
                          if (_loading)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _total == 0
                                          ? 'Lecture de l’instantané…'
                                          : 'Mises à jour : $_done / $_total',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: widget.repository.cancel,
                                    child: const Text('Annuler'),
                                  ),
                                ],
                              ),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (snapshot != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Publication : ${trafficStamp(snapshot.publishedAt)}\nConsultation : ${trafficStamp(snapshot.checkedAt)}',
                            ),
                            if (!usable)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Dernier relevé seulement : fraîcheur non confirmée. Actualisez pour consulter la carte.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (var i = 0; i < 4; i++)
                                  ChoiceChip(
                                    label: Text(
                                      [
                                        'Déclarés',
                                        'Prévus',
                                        'À vérifier',
                                        'Terminés',
                                      ][i],
                                    ),
                                    selected: _filter == i,
                                    onSelected: (_) => setState(() {
                                      _filter = i;
                                      _map = false;
                                    }),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              decoration: const InputDecoration(
                                labelText:
                                    'Filtrer par route, lieu ou événement',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (text) => setState(
                                () => _query = text.trim().toLowerCase(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_filter == 0)
                              const Text(
                                'Déclarations dont les bornes globales couvrent cet instant. Elles ne constituent pas une vérification terrain.',
                              ),
                            if (_filter == 2)
                              const Text(
                                'Horaires particuliers, suspension ou occurrence incertaine : ces fiches ne sont pas affichées comme événements en cours.',
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${records.length} ${records.length == 1 ? 'fiche' : 'fiches'}',
                                  ),
                                ),
                                if (_filter == 0)
                                  TextButton.icon(
                                    onPressed: usable
                                        ? () => setState(() => _map = !_map)
                                        : null,
                                    icon: Icon(
                                      showMap ? Icons.list : Icons.map_outlined,
                                    ),
                                    label: Text(showMap ? 'Liste' : 'Carte'),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (snapshot != null)
                    if (showMap)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: SizedBox(
                            height: 420,
                            child: TrafficMap(
                              records: records,
                              tileLayer: widget.tileLayer,
                              style: widget.mapStyle,
                              onRecord: (r) =>
                                  showTrafficDetail(context, r, _now),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.builder(
                          itemCount: records.length,
                          itemBuilder: (context, index) {
                            final r = records[index];
                            return Card(
                              child: ListTile(
                                isThreeLine: true,
                                leading: const Icon(Icons.traffic_outlined),
                                title: Text(
                                  '${r.roads.isEmpty ? '' : '${r.roads.join(' / ')} · '}${r.title}',
                                ),
                                subtitle: Text(
                                  '${trafficWindowLabel(r.window(now))}\nFiche du ${trafficStamp(r.updatedAt)}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    showTrafficDetail(context, r, _now),
                              ),
                            );
                          },
                        ),
                      ),
                  if (snapshot != null && records.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucune fiche pour ce filtre. Cela ne garantit pas une route sans événement.',
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextButton.icon(
                        onPressed: () async {
                          final opened = await launchUrl(
                            Uri.parse(TrafficRepository.sourcePage),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Page source indisponible.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Source et couverture Bison Futé'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showTrafficDetail(
  BuildContext context,
  TrafficRecord record,
  DateTime now,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(record.title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(trafficWindowLabel(record.window(now))),
            if (record.roads.isNotEmpty) Text(record.roads.join(' / ')),
            const SizedBox(height: 8),
            for (final text in record.comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(text),
              ),
            Text(
              'Source : ${record.source}\nFiche : ${trafficStamp(record.updatedAt)}',
            ),
            if (record.start != null)
              Text('Début déclaré : ${trafficStamp(record.start!)}'),
            if (record.end != null)
              Text('Fin déclarée : ${trafficStamp(record.end!)}'),
            if (record.direction != null)
              Text(
                'Sens déclaré : ${const {'northBound': 'nord', 'northEastBound': 'nord-est', 'eastBound': 'est', 'southEastBound': 'sud-est', 'southBound': 'sud', 'southWestBound': 'sud-ouest', 'westBound': 'ouest', 'northWestBound': 'nord-ouest', 'bothWays': 'deux sens', 'unknown': 'inconnu'}[record.direction] ?? record.direction}',
              ),
            if (!record.geometry.hasCoordinates)
              const Text('Localisation cartographique non interprétée.'),
            if (record.geometry.point == null && record.geometry.hasCoordinates)
              const Text(
                'Segment : seules ses extrémités déclarées sont connues, pas le tracé de la route.',
              ),
            const SizedBox(height: 12),
            Text(
              'Référence source : ${record.id} · v${record.version}\nType source : ${record.kind}',
            ),
            if (record.details.isNotEmpty)
              Text('Précisions source : ${record.details.join(', ')}'),
          ],
        ),
      ),
    ),
  );
}
