import 'package:flutter/material.dart';

import '../main.dart';
import '../services/app_version.dart';
import '../services/offline_maps.dart';
import '../services/permission_service.dart';
import '../services/unit_controller.dart';
import 'road_audio_settings_screen.dart';
import 'reliability_screen.dart';
import 'offline_packs_screen.dart';
import 'driving_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _permissionService = PermissionService();
  PermissionStatusSummary? _status;
  String? _version;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    AppVersion.get().then((value) {
      if (mounted) setState(() => _version = value);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _permissionService.currentStatus();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final controller = LocReminderApp.themeOf(context);
    final unitController = LocReminderApp.unitOf(context);
    final status = _status;

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
              leading: const Icon(Icons.directions_car),
              title: const Text('Carte et conduite'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const DrivingSettingsScreen()))),
          const _SectionHeader(label: 'Apparence'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: controller,
                builder: (context, mode, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('Système'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Clair'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Sombre'),
                            ),
                          ],
                          selected: {mode},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) =>
                              controller.setMode(selection.first),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        switch (mode) {
                          ThemeMode.system =>
                            'Comme le thème de ton téléphone.',
                          ThemeMode.light =>
                            'Toujours clair, quel que soit le thème du téléphone.',
                          ThemeMode.dark =>
                            'Toujours sombre, quel que soit le thème du téléphone.',
                        },
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(label: 'Unités de distance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<DistanceUnit>(
                valueListenable: unitController,
                builder: (context, unit, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<DistanceUnit>(
                          segments: const [
                            ButtonSegment(
                              value: DistanceUnit.km,
                              label: Text('km'),
                            ),
                            ButtonSegment(
                              value: DistanceUnit.miles,
                              label: Text('Miles'),
                            ),
                          ],
                          selected: {unit},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) =>
                              unitController.setUnit(selection.first),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        switch (unit) {
                          DistanceUnit.km =>
                            'Distances et rayon d’alerte affichés en mètres et kilomètres (m / km).',
                          DistanceUnit.miles =>
                            'Distances et rayon d’alerte affichés en pieds et miles (ft / mi).',
                        },
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
              child: ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('Alertes et voix'),
            subtitle: const Text('Annonces, rappel de proximité et sonneries'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const RoadAudioSettingsScreen())),
          )),
          const SizedBox(height: 24),
          const _SectionHeader(label: 'Fiabilité des alarmes'),
          if (status == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  _PermissionRow(
                    title: 'Localisation',
                    granted: status.locationServiceEnabled &&
                        status.foregroundLocationGranted,
                    onFix: () async {
                      await _permissionService.requestForegroundLocation();
                      await _refresh();
                    },
                  ),
                  const Divider(height: 1),
                  _PermissionRow(
                    title: 'Localisation en arrière-plan',
                    subtitle: 'Doit être réglé sur « Autoriser tout le temps »',
                    granted: status.backgroundLocationGranted,
                    onFix: () async {
                      await _permissionService.requestBackgroundLocation();
                      await _refresh();
                    },
                  ),
                  const Divider(height: 1),
                  _PermissionRow(
                    title: 'Notifications',
                    granted: status.notificationsGranted,
                    onFix: () async {
                      await _permissionService.requestNotifications();
                      await _refresh();
                    },
                  ),
                  const Divider(height: 1),
                  _PermissionRow(
                    title: 'Alarmes plein écran et sur l’écran verrouillé',
                    subtitle:
                        'Affiche l’alarme et le bouton Arrêter par-dessus l’écran verrouillé',
                    granted: status.fullScreenIntentAllowed,
                    onFix: () async {
                      await _permissionService.requestFullScreenIntent();
                      await _refresh();
                    },
                  ),
                  const Divider(height: 1),
                  _PermissionRow(
                    title: 'Optimisation de la batterie désactivée',
                    subtitle:
                        'Obligatoire : sans ça, Android retarde les alarmes',
                    granted: status.batteryOptimizationDisabled,
                    onFix: () async {
                      await _permissionService
                          .requestDisableBatteryOptimization();
                      await _refresh();
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.health_and_safety_outlined,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              title:
                  const Text('Fiabilité des alarmes et réglages du téléphone'),
              subtitle: const Text(
                'Étapes plein écran et arrière-plan pour chaque marque de téléphone, plus un test de 15 secondes écran verrouillé',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReliabilityScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _permissionService.openSystemAppSettings,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Ouvrir les réglages système de l’appli'),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(label: 'Cartes hors ligne'),
          const _OfflineMapsSection(),
          const SizedBox(height: 24),
          const _SectionHeader(label: 'À propos de cette version'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Version'),
              subtitle: Text(_version ?? '…'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Explains — and gives control over — the one part of this app that does
/// need the internet.
///
/// Worth a section of its own because the question behind it comes up
/// constantly and the answer is not obvious: the alarm has never needed a
/// connection, and the map always will, because a map is pictures held on
/// somebody else's server. What can be done is to keep the pictures, which is
/// what this does.
class _OfflineMapsSection extends StatefulWidget {
  const _OfflineMapsSection();

  @override
  State<_OfflineMapsSection> createState() => _OfflineMapsSectionState();
}

class _OfflineMapsSectionState extends State<_OfflineMapsSection> {
  int? _bytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final bytes = await OfflineMaps.cacheSizeBytes();
    if (mounted) {
      setState(() {
        _bytes = bytes;
      });
    }
  }

  String get _sizeLabel {
    final bytes = _bytes;
    if (bytes == null) return 'Enregistré au fil de l’utilisation de la carte';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} Ko enregistrés';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo enregistrés';
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    await OfflineMaps.clearCache();
    if (!mounted) return;
    setState(() => _clearing = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'L’alarme n’a jamais besoin d’une connexion : elle se contente '
              'du GPS, qui ne fait que recevoir. Seules les images de la carte '
              'et la recherche par nom en ont besoin. Chaque endroit que tu '
              'regardes sur la carte est gardé un mois, pour qu’il s’affiche '
              'encore sans réseau.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Télécharger toute la France'),
              subtitle:
                  const Text('Plans complets, zoom fluide, Wi-Fi uniquement'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const OfflinePacksScreen()))),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Données de carte enregistrées'),
            subtitle: Text(_sizeLabel),
            trailing: _clearing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(onPressed: _clear, child: const Text('Effacer')),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.granted,
    required this.onFix,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool granted;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        granted ? Icons.check_circle : Icons.error_outline,
        color: granted ? Colors.green.shade600 : scheme.error,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: granted
          ? null
          : TextButton(onPressed: onFix, child: const Text('Configurer')),
    );
  }
}
