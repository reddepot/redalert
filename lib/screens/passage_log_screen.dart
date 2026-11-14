import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/passage_log.dart';

/// What the phone actually observed, in order.
///
/// A diagnostic screen, not a feature of the drive: it is here so that a
/// missed or repeated alert can be explained afterwards instead of guessed at.
class PassageLogScreen extends StatefulWidget {
  const PassageLogScreen({super.key});

  @override
  State<PassageLogScreen> createState() => _PassageLogScreenState();
}

class _PassageLogScreenState extends State<PassageLogScreen> {
  List<PassageLogEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await PassageLog.load();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: PassageLog.export(_entries)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Journal copié.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal de passage'),
        actions: [
          IconButton(
            tooltip: 'Copier',
            onPressed: _entries.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Effacer',
            onPressed: _entries.isEmpty
                ? null
                : () async {
                    await PassageLog.clear();
                    await _load();
                  },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Aucun passage enregistré. Roule avec l’application ouverte '
                  'pour voir apparaître ici ce que le téléphone observe : '
                  'entrée dans la zone, approche, franchissement.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _entries[_entries.length - 1 - index];
                final time = entry.at.toIso8601String().substring(11, 19);
                final parts = <String>[
                  if (entry.distanceMetres != null)
                    '${entry.distanceMetres!.round()} m',
                  if (entry.accuracyMetres != null)
                    '±${entry.accuracyMetres!.round()} m',
                  if (entry.stale) 'mesure périmée',
                ];
                return ListTile(
                  dense: true,
                  title: Text(entry.stage),
                  subtitle: Text(
                    '${parts.join(' · ')}${parts.isEmpty ? '' : ' — '}'
                    '${entry.label}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(time),
                );
              },
            ),
    );
  }
}
