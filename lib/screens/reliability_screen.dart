import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/watch_status.dart';

import '../services/native_bridge.dart';
import '../services/oem_service.dart';
import '../services/permission_service.dart';

/// Everything that governs whether an alarm will actually ring and show over
/// the lock screen, in one place: platform permissions, full-screen display
/// setup for every phone brand, vendor background rules, and a 15-second test
/// that proves the alarm breaks through a locked screen.
class ReliabilityScreen extends StatefulWidget {
  const ReliabilityScreen({super.key, this.onRepairStore});
  final Future<void> Function()? onRepairStore;

  @override
  State<ReliabilityScreen> createState() => _ReliabilityScreenState();
}

class _ReliabilityScreenState extends State<ReliabilityScreen>
    with WidgetsBindingObserver {
  final _permissionService = PermissionService();
  final _oemService = OemService();
  final _nativeBridge = NativeBridge();

  PermissionStatusSummary? _permissions;
  DeviceProfile? _device;
  WatchStatus _watchStatus = const WatchStatus("unknown");
  Timer? _watchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _startWatchTimer();
  }

  void _startWatchTimer() {
    _watchTimer?.cancel();
    _watchTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _refreshWatch());
  }

  Future<void> _refreshWatch() async {
    try {
      final watch = WatchStatus.fromMap(await _nativeBridge.getWatchStatus());
      if (mounted) setState(() => _watchStatus = watch);
    } on PlatformException {
      /* Keep the last known state on a channel failure. */
    } on MissingPluginException {
      /* Older native build; state remains unavailable. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _startWatchTimer();
    } else {
      _watchTimer?.cancel();
    }
  }

  Future<void> _refresh() async {
    final permissions = await _permissionService.currentStatus();
    final device = await _oemService.profile();
    await _refreshWatch();
    if (!mounted) return;
    setState(() {
      _permissions = permissions;
      _device = device;
    });
  }

  Future<void> _runTestAlarm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.science_outlined),
        title: const Text('Tester l’alarme'),
        content: const Text(
          'L’alarme va sonner dans 15 secondes.\n\n'
          'Verrouille ton téléphone maintenant et pose-le. Si l’alarme sonne '
          'et que son bouton Arrêter en plein écran apparaît par-dessus '
          'l’écran verrouillé, les alarmes en arrière-plan fonctionnent sur '
          'cet appareil.\n\n'
          'Si tu entends le son sans l’affichage plein écran, suis les étapes '
          'd’affichage plein écran de cette page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Lancer le test'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _nativeBridge.triggerTestAlarm(delaySeconds: 15);
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de lancer le test (${e.message ?? e.code}). Suis les '
            'étapes ci-dessus, puis réessaie.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Verrouille ton téléphone maintenant. L’alarme sonne dans 15 secondes.'),
        duration: Duration(seconds: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissions = _permissions;
    final device = _device;

    return Scaffold(
      appBar: AppBar(title: const Text('Fiabilité des alarmes')),
      body: permissions == null || device == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _StatusHeader(
                  ready: permissions.isFullyReady,
                  watchStatus: _watchStatus,
                ),
                if (_watchStatus.state == 'storage_error' && widget.onRepairStore != null)
                  Card(child: ListTile(
                    title: const Text('Copie de surveillance à réparer'),
                    subtitle: const Text('Les lieux enregistrés restent conservés. La surveillance peut être incomplète.'),
                    trailing: TextButton(onPressed: () async {
                      await widget.onRepairStore!();
                      if (mounted) await _refreshWatch();
                    }, child: const Text('Réparer')),
                  )),
                const SizedBox(height: 24),
                const _Section(label: 'Autorisations Android'),
                Card(
                  child: Column(
                    children: [
                      _CheckRow(
                        title: 'Accès à la localisation et services',
                        granted: permissions.locationServiceEnabled &&
                            permissions.foregroundLocationGranted,
                        onFix: () async {
                          if (!permissions.locationServiceEnabled) {
                            await _nativeBridge.openLocationSettings();
                          } else {
                            await _permissionService
                                .requestForegroundLocation();
                          }
                          await _refresh();
                        },
                      ),
                      const Divider(height: 1),
                      _CheckRow(
                        title: 'Localisation en arrière-plan (tout le temps)',
                        granted: permissions.backgroundLocationGranted,
                        onFix: () async {
                          await _permissionService.requestBackgroundLocation();
                          await _refresh();
                        },
                      ),
                      const Divider(height: 1),
                      _CheckRow(
                        title: 'Notifications',
                        granted: permissions.notificationsGranted,
                        onFix: () async {
                          await _permissionService.requestNotifications();
                          await _refresh();
                        },
                      ),
                      const Divider(height: 1),
                      _CheckRow(
                        title: 'Alarmes plein écran et sur l’écran verrouillé',
                        subtitle: device.isXiaomi
                            ? 'Nécessite « Afficher sur l’écran verrouillé » et « Pop-up en arrière-plan » sur Xiaomi/Redmi'
                            : 'Permet à l’écran d’alarme de s’allumer et de couvrir ton écran verrouillé',
                        granted: permissions.fullScreenIntentAllowed,
                        onFix: () async {
                          await _permissionService.requestFullScreenIntent();
                          await _refresh();
                        },
                      ),
                      const Divider(height: 1),
                      _CheckRow(
                        title: 'Optimisation de la batterie désactivée',
                        granted: permissions.batteryOptimizationDisabled,
                        onFix: () async {
                          await _permissionService
                              .requestDisableBatteryOptimization();
                          await _refresh();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _Section(label: 'Réglage de l’affichage plein écran'),
                _FullScreenSetupCard(
                  device: device,
                  onOpenFullScreenPermission: () async {
                    await _permissionService.requestFullScreenIntent();
                    await _refresh();
                  },
                  onOpenAlarmChannel: () async {
                    await _oemService.openAlarmChannelSettings();
                    await _refresh();
                  },
                  onBrowseAllPhones: () => showAllPhonesFullScreenSheet(context,
                      currentDevice: device),
                ),
                const SizedBox(height: 24),
                const _Section(
                    label: 'Réglage de l’arrière-plan et de la batterie'),
                _DeviceCard(
                  device: device,
                  onOpenAutoStart: () async {
                    final opened = await _oemService.openAutoStartSettings();
                    if (!opened) await _oemService.openAppSettings();
                    await _refresh();
                  },
                ),
                const SizedBox(height: 24),
                const _Section(label: 'Vérifie que ça marche'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tester l’alarme depuis un écran verrouillé',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Fait sonner la vraie alarme au bout de 15 secondes : '
                          'tu peux verrouiller ton téléphone et voir si le '
                          'bouton Arrêter en plein écran apparaît par-dessus '
                          'ton écran verrouillé.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    height: 1.4,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: _runTestAlarm,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text(
                                'Lancer le test d’alarme de 15 secondes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Shows a modal bottom sheet with full-screen & lock-screen setup steps for
/// every phone brand (Xiaomi/Redmi/Poco, Samsung, Pixel, Oppo/Realme, Vivo/iQOO,
/// OnePlus, Motorola, Nothing, Huawei, Honor, Tecno/Infinix, Asus, Sony/Nokia, etc.).
Future<void> showAllPhonesFullScreenSheet(
  BuildContext context, {
  DeviceProfile? currentDevice,
}) {
  final guides = OemService.allPhoneGuides;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Text(
                'Affichage plein écran par marque de téléphone',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choisis ta marque de téléphone ci-dessous pour voir les réglages exacts qui permettent à l’écran d’alarme de s’allumer et de s’afficher par-dessus un écran verrouillé.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              for (final guide in guides)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded: currentDevice != null &&
                        guide.name == currentDevice.vendorName,
                    leading: Icon(Icons.smartphone, color: scheme.primary),
                    title: Text(
                      guide.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    subtitle: Text(
                      guide.modelsHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      for (int i = 0;
                          i < guide.fullScreenSteps.length;
                          i++) ...[
                        _StepTile(
                          index: i + 1,
                          step: guide.fullScreenSteps[i],
                        ),
                        if (i != guide.fullScreenSteps.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.ready, required this.watchStatus});

  final bool ready;
  final WatchStatus watchStatus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = ready;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: good ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            good ? Icons.verified_outlined : Icons.error_outline,
            size: 40,
            color: good ? scheme.onPrimaryContainer : scheme.onErrorContainer,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  good
                      ? 'Autorisations accordées'
                      : 'Les alarmes risquent de ne pas sonner',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: good
                            ? scheme.onPrimaryContainer
                            : scheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  good
                      ? watchStatus.label
                      : 'Il manque des autorisations obligatoires.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: good
                            ? scheme.onPrimaryContainer
                            : scheme.onErrorContainer,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
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
        granted ? Icons.check_circle : Icons.cancel_outlined,
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

class _FullScreenSetupCard extends StatelessWidget {
  const _FullScreenSetupCard({
    required this.device,
    required this.onOpenFullScreenPermission,
    required this.onOpenAlarmChannel,
    required this.onBrowseAllPhones,
  });

  final DeviceProfile device;
  final VoidCallback onOpenFullScreenPermission;
  final VoidCallback onOpenAlarmChannel;
  final VoidCallback onBrowseAllPhones;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fullscreen_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.model.isEmpty
                            ? 'Affichage de l’alarme en plein écran'
                            : device.model,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        device.vendorName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              device.isXiaomi
                  ? 'Sur les téléphones Xiaomi, Redmi et Poco (MIUI et HyperOS), l’autorisation de notification standard d’Android ne suffit pas pour que l’écran d’alarme s’affiche par-dessus l’écran verrouillé. Active ces réglages :'
                  : 'Pour que l’alarme et le bouton Arrêter s’allument et apparaissent par-dessus ton écran verrouillé, vérifie ces réglages sur ton téléphone :',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 14),
            for (int i = 0; i < device.fullScreenSteps.length; i++) ...[
              _StepTile(index: i + 1, step: device.fullScreenSteps[i]),
              if (i != device.fullScreenSteps.length - 1)
                const SizedBox(height: 12),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenFullScreenPermission,
                icon: const Icon(Icons.lock_open_outlined),
                label: Text(
                  device.isXiaomi
                      ? 'Ouvrir les autorisations écran verrouillé et pop-up'
                      : 'Ouvrir le réglage d’alarme plein écran',
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenAlarmChannel,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text(
                    'Ouvrir le canal de notification des alarmes de localisation'),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: onBrowseAllPhones,
                icon: const Icon(Icons.phone_android, size: 18),
                label:
                    const Text('Voir les instructions pour toutes les marques'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onOpenAutoStart});

  final DeviceProfile device;
  final VoidCallback onOpenAutoStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_charging_full_rounded,
                    color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suivi en arrière-plan sur ${device.vendorName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      device.note,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onTertiaryContainer,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            if (device.steps.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (int i = 0; i < device.steps.length; i++) ...[
                _StepTile(index: i + 1, step: device.steps[i]),
                if (i != device.steps.length - 1) const SizedBox(height: 12),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onOpenAutoStart,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(
                    device.needsExtraSetup
                        ? 'Ouvrir les réglages de démarrage auto et d’arrière-plan'
                        : 'Ouvrir les réglages de batterie de l’appli',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.index, required this.step});

  final int index;
  final OemStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                step.path,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
