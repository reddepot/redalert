import 'package:flutter/material.dart';
import '../screens/about_screen.dart';
import '../screens/driving_settings_screen.dart';
import '../screens/reliability_screen.dart';
import '../screens/road_audio_settings_screen.dart';
import '../screens/settings_screen.dart';
import 'cockpit_header.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer(
      {super.key,
      this.onImport,
      this.onRepairStore,
      this.onReference,
      this.onPassageLog,
      this.onLegend,
      this.onToggleReference,
      this.referenceActive = false,
      this.onPlaces,
      this.onAddPlace,
      this.onRoute,
      this.onTraffic,
      this.placeCount = 0,
      this.armedCount = 0,
      this.watchLabel});
  final VoidCallback? onPlaces,
      onAddPlace,
      onRoute,
      onTraffic,
      onImport,
      onReference,
      onPassageLog,
      onLegend,
      onToggleReference;
  final Future<void> Function()? onRepairStore;
  final int placeCount, armedCount;
  final bool referenceActive;
  final String? watchLabel;

  void _open(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  VoidCallback? _action(BuildContext context, VoidCallback? callback) =>
      callback == null
          ? null
          : () {
              Navigator.of(context).pop();
              callback();
            };

  void _library(BuildContext context) {
    Navigator.of(context).pop();
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
                child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Catalogues et légende',
                        style: Theme.of(sheet).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _MenuItem(
                        icon: Icons.map_outlined,
                        title: 'Points de référence',
                        subtitle: 'Choisir les départements à surveiller',
                        onTap: _action(sheet, onReference)),
                    _MenuItem(
                        icon: Icons.file_download_outlined,
                        title: 'Importer un catalogue',
                        subtitle: 'Prévisualiser avant d’ajouter',
                        onTap: _action(sheet, onImport)),
                    _MenuItem(
                        icon: referenceActive
                            ? Icons.pause_circle_outline
                            : Icons.notifications_active_outlined,
                        title: referenceActive
                            ? 'Mettre les radars de référence en pause'
                            : 'Activer les radars de référence',
                        onTap: _action(sheet, onToggleReference)),
                    _MenuItem(
                        icon: Icons.palette_outlined,
                        title: 'Légende des lieux',
                        subtitle: 'Types, symboles et couleurs',
                        onTap: _action(sheet, onLegend)),
                  ]),
            )));
  }

  @override
  Widget build(BuildContext context) => Drawer(
        width: 340,
        child: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          const CockpitHeader(),
          const _MenuSection('CONDUITE'),
          _MenuItem(
              icon: Icons.alt_route,
              title: 'Choisir une destination',
              subtitle: 'Calculer un itinéraire',
              featured: true,
              onTap: _action(context, onRoute)),
          _MenuItem(
              icon: Icons.tune,
              title: 'Carte et conduite',
              subtitle: 'Orientation, suivi et écran',
              onTap: () => _open(context, const DrivingSettingsScreen())),
          _MenuItem(
              icon: Icons.traffic_outlined,
              title: 'Trafic et événements',
              subtitle: 'Bison Futé · relevé daté',
              onTap: _action(context, onTraffic)),
          const _MenuSection('MES LIEUX'),
          _MenuItem(
              icon: Icons.bookmark_border_rounded,
              title: 'Mes lieux',
              subtitle:
                  '$placeCount ${placeCount == 1 ? "lieu" : "lieux"} · $armedCount ${armedCount == 1 ? "armé" : "armés"}',
              onTap: _action(context, onPlaces)),
          _MenuItem(
              icon: Icons.add_location_alt_outlined,
              title: 'Ajouter un lieu',
              onTap: _action(context, onAddPlace)),
          _MenuItem(
              icon: Icons.layers_outlined,
              title: 'Catalogues et légende',
              onTap: () => _library(context)),
          const _MenuSection('RÉGLAGES'),
          _MenuItem(
              icon: Icons.graphic_eq,
              title: 'Alertes et voix',
              onTap: () => _open(context, const RoadAudioSettingsScreen())),
          _MenuItem(
              icon: Icons.settings_outlined,
              title: 'Préférences',
              subtitle: 'Apparence, unités et cartes hors ligne',
              onTap: () => _open(context, const SettingsScreen())),
          const SizedBox(height: 14),
          _HealthCard(
              label: watchLabel ?? 'Vérifier la surveillance',
              onTap: () => _open(context, ReliabilityScreen(onRepairStore: onRepairStore))),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.spaceBetween, children: [
            TextButton(
                onPressed: _action(context, onPassageLog),
                child: const Text('Journal')),
            TextButton(
                onPressed: () => _open(context, const AboutScreen()),
                child: const Text('À propos')),
          ]),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('Données cartographiques © OpenStreetMap',
                  style: Theme.of(context).textTheme.bodySmall)),
        ])),
      );
}

class _MenuSection extends StatelessWidget {
  const _MenuSection(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 22, 10, 8),
        child: Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
                letterSpacing: 1.8)),
      );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem(
      {required this.icon,
      required this.title,
      this.subtitle,
      this.onTap,
      this.featured = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: featured
              ? s.primaryContainer.withValues(alpha: .65)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: featured
                      ? s.primary.withValues(alpha: .17)
                      : Colors.transparent)),
          child: ListTile(
            minLeadingWidth: 30,
            horizontalTitleGap: 12,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: Icon(icon,
                size: 24, color: featured ? s.primary : s.onSurfaceVariant),
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            subtitle: subtitle == null
                ? null
                : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            trailing: Icon(Icons.chevron_right, size: 18, color: s.outline),
            onTap: onTap,
          ),
        ));
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Material(
      color: s.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: s.outlineVariant)),
      child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Icon(Icons.sensors, color: s.primary),
          title: const Text('État de la surveillance'),
          subtitle: Text(label, style: Theme.of(context).textTheme.bodySmall),
          onTap: onTap),
    );
  }
}
