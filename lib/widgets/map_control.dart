import 'package:flutter/material.dart';

class MapControl extends StatelessWidget {
  const MapControl(
      {super.key,
      required this.tooltip,
      required this.icon,
      this.onPressed,
      this.selected = false});
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              s.surface.withValues(alpha: .62),
              s.surface.withValues(alpha: .42)
            ]),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .10),
              blurRadius: 7,
              offset: const Offset(0, 2))
        ],
      ),
      child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color:
                      selected ? s.primary : s.onSurface.withValues(alpha: .55),
                  width: selected ? 1.8 : .9)),
          child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              constraints: const BoxConstraints.tightFor(width: 58, height: 58),
              iconSize: 27,
              icon: Icon(icon,
                  color: selected ? s.primary : s.onSurface,
                  shadows: [Shadow(color: s.surface, blurRadius: 4)]))),
    );
  }
}
