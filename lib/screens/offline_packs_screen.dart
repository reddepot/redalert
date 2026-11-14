import 'dart:async';
import 'package:flutter/material.dart';
import '../services/offline_packs.dart';

class OfflinePacksScreen extends StatefulWidget {
  const OfflinePacksScreen({super.key});
  @override
  State<OfflinePacksScreen> createState() => _OfflinePacksScreenState();
}

class _OfflinePacksScreenState extends State<OfflinePacksScreen> {
  final packs = OfflinePacks.instance;
  Timer? timer;
  String size(int n) => n >= 1000000000
      ? '${(n / 1000000000).toStringAsFixed(2)} Go'
      : '${(n / 1000000).toStringAsFixed(0)} Mo';
  @override
  void initState() {
    super.initState();
    packs.refresh();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => packs.refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('France hors ligne')),
        body: ListenableBuilder(
            listenable: packs,
            builder: (context, _) => ListView(children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Plans vectoriels des 21 régions continentales, hors Corse et outre-mer. Les détails inclus restent disponibles sans réseau à chaque zoom. Agrandir davantage ne fait pas apparaître de nouvelles données. Le transfert reprend en arrière-plan, uniquement en Wi-Fi non mesuré.')),
                  SwitchListTile(
                      title:
                          const Text('Télécharger automatiquement la France'),
                      subtitle: Text(
                          '${size(packs.requiredBytes)} au total · ${size(packs.freeBytes)} libres'),
                      value: packs.enabled,
                      onChanged: (v) =>
                          packs.refresh(method: 'setEnabled', value: v)),
                  ListTile(
                      title: Text(packs.label),
                      subtitle: Text('${size(packs.bytes)} reçus'),
                      trailing: IconButton(
                          tooltip: 'Réessayer les échecs',
                          onPressed: () => packs.refresh(method: 'retry'),
                          icon: const Icon(Icons.refresh))),
                  if (packs.freeBytes > 0 &&
                      packs.freeBytes <
                          packs.requiredBytes - packs.bytes + 512 * 1024 * 1024)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Espace insuffisant : les nouveaux transferts attendent. Libérer de la place puis réessayer.')),
                  if (packs.error != null)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(packs.error!)),
                  TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer les plans téléchargés'),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                                    title: const Text('Supprimer les plans ?'),
                                    content: const Text(
                                        'Les lieux et réglages restent conservés. Le téléchargement automatique sera désactivé.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Annuler')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Supprimer'))
                                    ]));
                        if (confirmed == true) {
                          await packs.refresh(method: 'delete');
                        }
                      }),
                  for (final p in packs.packs)
                    ListTile(
                        leading: Icon(p['state'] == 'ready'
                            ? Icons.offline_pin
                            : p['state'] == 'failed'
                                ? Icons.error_outline
                                : Icons.downloading),
                        title: Text((p['id'] as String).replaceAll('-', ' ')),
                        subtitle: Text('${switch (p['state']) {
                          'ready' => 'Prête hors ligne',
                          'running' => 'Téléchargement',
                          'waiting' => 'En attente du Wi-Fi / transfert',
                          'failed' => 'Échec, réessayer',
                          'downloaded' => 'Vérification',
                          _ => 'Pas encore téléchargée'
                        }} · ${size((p['bytes'] as num).toInt())} / ${size((p['total'] as num).toInt())}')),
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          '© OpenStreetMap contributors · Geofabrik · schéma Shortbread. Le téléchargement des cartes ne change pas les lieux armés. Sans région prête, la carte habituelle utilise son cache et le réseau.')),
                ])),
      );
}
