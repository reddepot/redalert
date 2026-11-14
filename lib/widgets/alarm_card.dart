import 'package:flutter/material.dart';

import '../models/location_alarm.dart';
import '../services/unit_controller.dart';
import '../theme/app_theme.dart';
import '../theme/poi_style.dart';
import 'speed_limit_sign.dart';

/// One saved place, as it appears in the list.
///
/// The card says three things in a fixed order, because they are the three
/// questions asked while driving past: what kind of place is this (colour and
/// icon, so it reads before any text), how close am I to alerting, and what did
/// I note about it last time.
///
/// The actions sit on their own row rather than beside the text. A switch and
/// two icon buttons take roughly half of a phone's width, which left the
/// catalogue labels — "16 · Radar de feu rouge · 70 km/h · MI-12145" — wrapping
/// onto three lines and losing the part that identifies the place.
class AlarmCard extends StatelessWidget {
  const AlarmCard({
    super.key,
    required this.alarm,
    required this.distanceMetres,
    required this.onTap,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.unit = DistanceUnit.km,
  });

  final LocationAlarm alarm;
  final double? distanceMetres;
  final DistanceUnit unit;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = PoiStyle.of(alarm.poiType);
    final accent = PoiStyle.readable(alarm.poiType, scheme);
    final radiusLabel = formatRadiusWithUnit(alarm.radiusMeters, unit);
    final distance = distanceMetres;

    // Distance and radius are two different facts and used to share one
    // sentence: "1,8 km · zone de 300 m" read as one measurement. The charte
    // asks for each to be labelled, so the row says what it is measuring.
    final radiusText = 'Déclenchement à $radiusLabel';
    final distanceText = distance == null
        ? 'Distance inconnue'
        : 'À ${formatDistanceWithUnit(distance, unit)}';
    final status = alarm.isActive
        ? '$distanceText · $radiusText'
        : 'En pause · $radiusText';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: style.color
                        .withValues(alpha: alarm.isActive ? 0.18 : 0.09),
                    child: Icon(
                      style.icon,
                      color: alarm.isActive
                          ? accent
                          : PoiStyle.pausedColor(alarm.poiType, scheme),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alarm.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                alarm.poiType.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: accent),
                              ),
                            ),
                            if (alarm.speedLimitKmh != null) ...[
                              const SizedBox(width: 8),
                              SpeedLimitSign(
                                  limitKmh: alarm.speedLimitKmh!, size: 22),
                            ],
                          ],
                        ),
                        Text(
                          status,
                          style: AppTheme.numeric(theme.textTheme.bodyMedium),
                        ),
                        if (alarm.repeats)
                          Text(
                            alarm.scheduleLabel,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        if (alarm.note.isNotEmpty)
                          Text(
                            alarm.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Semantics(
                    label: 'Armer ${alarm.label}',
                    child: Switch(
                      value: alarm.isActive,
                      onChanged: (_) => onToggle(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Modifier',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
