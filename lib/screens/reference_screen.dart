import 'package:flutter/material.dart';

import '../models/location_alarm.dart';
import '../models/poi_type.dart';
import '../models/department_names.dart';
import '../services/department_arming.dart';
import '../theme/poi_style.dart';

/// Arms the imported catalogue one department at a time.
///
/// Written for the 859 points of the nineteen-department catalogue: a single
/// list of 859 switches is unusable, while "the Vienne, the Deux-Sèvres and
/// the Gironde" is how a journey is actually described. Personal places never
/// appear here — they are armed one by one on the map, and a bulk action that
/// silently paused them would be a trap.
class ReferenceScreen extends StatefulWidget {
  const ReferenceScreen({
    super.key,
    required this.alarms,
    required this.onChanged,
  });

  final List<LocationAlarm> alarms;

  /// Called with the whole list after any change; the caller persists it and
  /// resynchronises the native watcher.
  final Future<void> Function(List<LocationAlarm> alarms) onChanged;

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends State<ReferenceScreen> {
  /// Codes in the order the catalogue covers them, with the names the driver
  /// knows. Kept here rather than in the data because it is presentation, and
  /// because a code with no name must still render (see [_name]).
  static const _names = departmentNames;

  late List<LocationAlarm> _alarms = widget.alarms;
  bool _auto = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadAuto();
  }

  Future<void> _loadAuto() async {
    final enabled = await DepartmentArming.autoEnabled();
    if (mounted) setState(() => _auto = enabled);
  }

  Future<void> _apply(List<LocationAlarm> updated) async {
    if (identical(updated, _alarms) || _busy) return;
    setState(() {
      _alarms = updated;
      _busy = true;
    });
    try {
      await widget.onChanged(updated);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(String code) => _names[code] ?? 'Département $code';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final byDepartment = DepartmentArming.byDepartment(_alarms);
    final codes = byDepartment.keys.toList()..sort();
    final total = byDepartment.values.fold(0, (sum, d) => sum + d.total);
    final armed = byDepartment.values.fold(0, (sum, d) => sum + d.armed);

    return Scaffold(
      appBar: AppBar(title: const Text('Points de référence')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              title: const Text('Armer les radars selon mon département'),
              subtitle: const Text(
                'Les radars du catalogue ministériel sont armés selon le '
                'département estimé pendant l’affichage de la carte. '
                'Les autres sources et lieux personnels ne sont pas modifiés. '
                'Écran éteint, seuls les points déjà armés sont surveillés. '
                'Avant de partir, arme les départements du trajet.',
              ),
              value: _auto,
              onChanged: (value) async {
                setState(() => _auto = value);
                await DepartmentArming.setAutoEnabled(value);
              },
            ),
          ),
          if (codes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Aucun point importé ne porte encore son département. '
                'Réimporte le catalogue pour que ce classement fonctionne.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$total points · $armed armés',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: armed == 0
                        ? null
                        : () => _apply(DepartmentArming.pauseAll(_alarms)),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Tout mettre en pause'),
                  ),
                ],
              ),
            ),
            for (final code in codes)
              _DepartmentTile(
                code: code,
                name: _name(code),
                total: byDepartment[code]!.total,
                armed: byDepartment[code]!.armed,
                onArmed: (value) => _apply(
                    DepartmentArming.setDepartment(_alarms, code, value)),
              ),
            const SizedBox(height: 16),
            Text(
              'Les sources publiques ne sont pas exhaustives et leurs '
              'positions restent à vérifier sur place. Un point armé ici '
              'n’est pas une confirmation de la présence physique du radar.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _DepartmentTile extends StatelessWidget {
  const _DepartmentTile({
    required this.code,
    required this.name,
    required this.total,
    required this.armed,
    required this.onArmed,
  });

  final String code;
  final String name;
  final int total;
  final int armed;
  final ValueChanged<bool> onArmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = armed == total;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: all
                ? PoiStyle.of(PoiType.fixedCamera).color.withValues(alpha: 0.14)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            code,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: all
                  ? PoiStyle.readable(PoiType.fixedCamera, scheme)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
        title: Text(name),
        subtitle: Text(
          armed > 0 && !all
              ? '$total points · partiellement armé ($armed/$total)'
              : armed == 0
              ? '$total points · en pause'
              : '$total points · $armed armés',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Semantics(
          label: armed > 0 && !all
              ? '$name : armement partiel, $armed sur $total points'
              : 'Armer les points de $name',
          child: Switch(value: armed > 0, onChanged: onArmed),
        ),
      ),
    );
  }
}
