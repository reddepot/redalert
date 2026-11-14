import 'package:flutter/material.dart';
import '../services/native_bridge.dart';
import '../widgets/passage_voice_section.dart';
import '../widgets/alarm_sound_section.dart';

class RoadAudioSettingsScreen extends StatefulWidget {
  const RoadAudioSettingsScreen({super.key});
  @override
  State<RoadAudioSettingsScreen> createState() =>
      _RoadAudioSettingsScreenState();
}

class _RoadAudioSettingsScreenState extends State<RoadAudioSettingsScreen> {
  final _bridge = NativeBridge();
  Map<Object?, Object?>? _status;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await _bridge.getPassageStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible de lire les réglages audio.');
      }
    }
  }

  Future<void> _set(Future<void> Function() save) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await save();
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Réglage non enregistré. Réessayer.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Alertes et voix')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Vos annonces de route',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
            'Les points de passage annoncent une approche. Les rappels de destination utilisent une sonnerie distincte.'),
        const SizedBox(height: 20),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        if (status == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (status != null)
          Card(
              child: Column(children: [
            SwitchListTile(
                title: const Text('Audio des points de passage'),
                subtitle: const Text(
                    'Voix ou sons courts, selon votre choix ci-dessous'),
                value: status['audio'] != false,
                onChanged: _saving
                    ? null
                    : (v) => _set(() => _bridge.setPassageAudio(v))),
            const Divider(indent: 16, endIndent: 16),
            SwitchListTile(
                title: const Text('Rappel de proximité'),
                subtitle:
                    const Text('Une seconde annonce courte avant le point'),
                value: status['level2'] != false,
                onChanged: _saving
                    ? null
                    : (v) => _set(() => _bridge.setPassageLevel2(v))),
            const Divider(indent: 16, endIndent: 16),
            SwitchListTile(
                title: const Text('Alerte de survitesse'),
                subtitle: const Text(
                    'Seulement si la limitation du point est renseignée'),
                value: status['speedAlerts'] != false,
                onChanged: _saving
                    ? null
                    : (v) => _set(() => _bridge.setSpeedAlerts(v))),
          ])),
        const SizedBox(height: 20),
        const PassageVoiceSection(),
        const SizedBox(height: 28),
        Text('Rappels de destination',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
            'Sonnerie et vibration des lieux utilisés comme destinations.'),
        const SizedBox(height: 12),
        const AlarmSoundSection(),
      ])),
    );
  }
}
