import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/poi_type.dart';
import '../theme/poi_style.dart';

class PassageVoiceSection extends StatefulWidget {
  const PassageVoiceSection({super.key});
  @override
  State<PassageVoiceSection> createState() => _PassageVoiceSectionState();
}

class _PassageVoiceSectionState extends State<PassageVoiceSection>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('com.zaifears.locreminder/alarms');
  bool voice = true, requesting = false;
  PoiType previewType = PoiType.fixedCamera;
  String? error;
  Map<String, dynamic> samples = {};
  Timer? _previewPoll;
  DateTime? _previewDeadline;
  String? _expectedAsset, _previewPhase;
  PoiType? _lastPreviewType;
  bool _polling = false;
  bool? _finishedScreenOff;
  bool? _startedScreenOff;
  bool get _active =>
      requesting ||
      const ['scheduled', 'preparing', 'playing'].contains(_previewPhase);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadSamples();
    _restorePreview();
  }

  Future<void> _restorePreview() async {
    requesting = true;
    try {
      final state = await channel
          .invokeMapMethod<Object?, Object?>('getVoicePreviewStatus')
          .timeout(const Duration(seconds: 2));
      if (!mounted || state == null || state['state'] == 'idle') return;
      final asset = state['asset'];
      final types = PoiType.values.where((p) => '${p.name}_300' == asset);
      if (asset is! String || types.isEmpty) return;
      setState(() {
        _expectedAsset = asset;
        _lastPreviewType = types.first;
        previewType = types.first;
      });
      if (await _refreshPreview(asset)) _watchPreview(asset, 5000);
    } catch (_) {
      // No prior result is safer than reconstructing one from UI state.
    } finally {
      if (mounted) setState(() => requesting = false);
    }
  }

  String _failureText(String? code) {
    if (code?.startsWith('audio_focus_lost:') == true) {
      return 'La sortie audio a été reprise par le système ou une autre application.';
    }
    return switch (code) {
      'activity_finished' ||
      'view_disposed' =>
        'L’écran d’essai a été fermé avant la fin de l’annonce.',
      'focus_refused' => 'La sortie audio a refusé cet essai.',
      'preparation_expired' ||
      'countdown_expired' ||
      'timeout' =>
        'L’annonce n’a pas pu être lue dans le délai prévu.',
      'asset_unavailable' => 'Le fichier de cette annonce est indisponible.',
      _ => 'Essai vocal interrompu ou indisponible.',
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final asset = _expectedAsset;
    if (state == AppLifecycleState.resumed && asset != null && !_polling) {
      unawaited(_resumePreview(asset));
    }
  }

  Future<void> _resumePreview(String asset) async {
    _polling = true;
    try {
      if (!await _refreshPreview(asset)) _previewPoll?.cancel();
    } catch (_) {
      // Keep the last result; a resumed screen must not invent completion.
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadSamples() async {
    final bytes = await rootBundle.load('assets/voice/fr/manifest.json');
    final manifest = jsonDecode(utf8.decode(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)))
        as Map;
    if (mounted) {
      setState(() =>
          samples = Map<String, dynamic>.from(manifest['utterances'] as Map));
    }
  }

  Future<void> _load() async {
    try {
      final data =
          await channel.invokeMapMethod<Object?, Object?>('getPassageStatus');
      if (mounted) {
        setState(() {
          voice = data?['voice'] != false;
          error = data?['voiceError'] as String?;
        });
      }
    } on PlatformException {
      if (mounted) {
        setState(() => error = 'Réglage vocal indisponible. Réessayer.');
      }
    }
  }

  Future<bool> _refreshPreview(String asset) async {
    final state = await channel
        .invokeMapMethod<Object?, Object?>('getVoicePreviewStatus')
        .timeout(const Duration(seconds: 2));
    if (!mounted || asset != _expectedAsset || state == null) return false;
    if (state['asset'] != asset) {
      setState(() {
        _previewPhase = 'error';
        error = 'Catégorie de l’essai non confirmée.';
      });
      await channel.invokeMethod<void>('stopPassageVoicePreview');
      return false;
    }
    final phase = state['state'] as String?;
    final off = state['finishedWhileScreenOff'] as bool?;
    final startedOff = state['startedWhileScreenOff'] as bool?;
    if (_previewPhase != phase ||
        _finishedScreenOff != off ||
        _startedScreenOff != startedOff) {
      setState(() {
        _previewPhase = phase;
        _finishedScreenOff = off;
        _startedScreenOff = startedOff;
        error = phase == 'error' ||
                (phase == 'cancelled' &&
                    state['failureCode'] == 'activity_finished')
            ? _failureText(state['failureCode'] as String?)
            : null;
      });
    }
    return const ['scheduled', 'preparing', 'playing'].contains(_previewPhase);
  }

  void _watchPreview(String asset, int delayMillis) {
    _previewPoll?.cancel();
    _previewDeadline =
        DateTime.now().add(Duration(milliseconds: 8000 + delayMillis));
    _previewPoll =
        Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (_polling) return;
      if (!mounted || asset != _expectedAsset) {
        timer.cancel();
        return;
      }
      _polling = true;
      try {
        // On wake, read the native completion before evaluating elapsed time.
        if (!await _refreshPreview(asset)) {
          timer.cancel();
        } else if (DateTime.now().isAfter(_previewDeadline!)) {
          timer.cancel();
          setState(() {
            _previewPhase = 'error';
            error = 'Fin de lecture non confirmée.';
          });
          await channel.invokeMethod<void>('stopPassageVoicePreview');
        }
      } catch (_) {
        timer.cancel();
        if (mounted && asset == _expectedAsset) {
          setState(() {
            _previewPhase = 'error';
            error = 'Statut de lecture indisponible.';
          });
        }
      } finally {
        _polling = false;
      }
    });
  }

  Future<void> _preview({int delayMillis = 0}) async {
    if (_active) return;
    final selected = previewType;
    _previewPoll?.cancel();
    _expectedAsset = '${selected.name}_300';
    setState(() {
      requesting = true;
      _lastPreviewType = selected;
      _previewPhase = null;
      _finishedScreenOff = null;
      _startedScreenOff = null;
      error = null;
    });
    try {
      final accepted = await channel.invokeMethod<bool>('previewPassageVoice', {
        'poiType': selected.name,
        if (delayMillis > 0) 'delayMillis': delayMillis,
      }).timeout(const Duration(seconds: 2));
      if (!mounted) return;
      if (accepted != true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sortie audio occupée. Réessayer dans un instant.')));
      } else if (await _refreshPreview(_expectedAsset!)) {
        _watchPreview(_expectedAsset!, delayMillis);
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _previewPhase = 'error';
          error = 'Statut de lecture indisponible.';
        });
      }
    } on PlatformException catch (failure) {
      if (mounted) {
        setState(() => error = failure.code == 'watch_inactive'
            ? 'Activez la surveillance de vos lieux avant cet essai en veille.'
            : 'Aperçu vocal indisponible. Réessayer.');
      }
    } finally {
      if (mounted) setState(() => requesting = false);
    }
  }

  Future<void> _cancelPreview() async {
    _previewPoll?.cancel();
    try {
      await channel.invokeMethod<void>('stopPassageVoicePreview',
          {'reason': 'user_cancelled'}).timeout(const Duration(seconds: 2));
      if (mounted) await _refreshPreview(_expectedAsset!);
    } catch (_) {
      if (mounted) setState(() => error = 'Arrêt de l’essai non confirmé.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewPoll?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive) {
      channel.invokeMethod<void>(
          'stopPassageVoicePreview', {'reason': 'view_disposed'});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sample =
        (samples['${previewType.name}_300'] as Map?)?['text'] as String?;
    return Card(
        semanticContainer: false,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Annonces vocales'),
                    subtitle: const Text('Français · utilisable sans réseau'),
                    value: voice,
                    onChanged: (v) async {
                      try {
                        await channel.invokeMethod<void>(
                            'setPassageVoice', {'enabled': v});
                        await _load();
                      } on PlatformException {
                        if (mounted) {
                          setState(() => error = 'Réglage non enregistré.');
                        }
                      }
                    }),
                const SizedBox(height: 4),
                const Text(
                    'Une annonce à l’approche, puis un rappel si activé. Les rappels de destination gardent leur sonnerie.'),
                const SizedBox(height: 20),
                DropdownButtonFormField<PoiType>(
                  key: const ValueKey('voice-category-selector'),
                  initialValue: previewType,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Choisir une annonce'),
                  items: PoiType.values
                      .map((type) => DropdownMenuItem(
                          value: type, child: Text(type.label)))
                      .toList(),
                  onChanged: _active
                      ? null
                      : (type) {
                          if (type != null) setState(() => previewType = type);
                        },
                ),
                const SizedBox(height: 12),
                if (sample != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text('« $sample »',
                          style: Theme.of(context).textTheme.bodyMedium)),
                FilledButton.tonalIcon(
                  key: const ValueKey('voice-preview-button'),
                  onPressed: _active ? null : () => _preview(),
                  icon: Icon(PoiStyle.of(previewType).icon),
                  label: Text('Écouter : ${previewType.label}'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('voice-sleep-preview-button'),
                  onPressed: _active ? null : () => _preview(delayMillis: 5000),
                  icon: const Icon(Icons.bedtime_outlined),
                  label: const Text('Tester écran éteint · délai de 5 s'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      'Lancez l’essai puis éteignez l’écran. L’annonce choisie démarre après cinq secondes.'),
                ),
                if (_active)
                  TextButton.icon(
                    key: const ValueKey('voice-cancel-preview-button'),
                    onPressed: _cancelPreview,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Annuler l’essai'),
                  ),
                if (_previewPhase != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(switch (_previewPhase) {
                      'scheduled' =>
                        'Essai programmé : ${_lastPreviewType!.label}. Éteignez l’écran maintenant.',
                      'completed' =>
                        'Essai terminé : ${_lastPreviewType!.label}',
                      'playing' ||
                      'preparing' =>
                        'Essai en cours : ${_lastPreviewType!.label}',
                      'cancelled' => 'Essai arrêté',
                      _ => 'Essai non confirmé',
                    }),
                  ),
                if (_previewPhase == 'completed' && _finishedScreenOff == true)
                  Text(_startedScreenOff == true
                      ? 'Annonce commencée et terminée écran éteint, selon le lecteur.'
                      : 'Fin de lecture confirmée par le lecteur, écran éteint.'),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ],
            )));
  }
}
