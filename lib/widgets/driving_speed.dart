import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DrivingSpeed extends StatelessWidget {
  const DrivingSpeed({super.key, this.kmh, this.pointLimit});
  final int? kmh, pointLimit;
  @override
  Widget build(BuildContext context) {
    final value = kmh;
    final over = value != null && pointLimit != null && value > pointLimit!;
    final ink = value == null
        ? const Color(0xFFABB8C4)
        : !over
            ? Colors.white
            : value <= pointLimit! + 5
                ? const Color(0xFFFFCA80)
                : const Color(0xFFFF8F9D);
    return Semantics(
      label: value == null
          ? 'Vitesse inconnue'
          : 'Vitesse estimée $value kilomètres par heure${pointLimit == null ? '' : ', limite indiquée pour le point $pointLimit kilomètres par heure'}${over ? ', dépassement estimé de ${value - pointLimit!} kilomètres par heure' : ''}',
      child: Container(
        constraints: const BoxConstraints(minWidth: 86, maxWidth: 170),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xE92D3945), Color(0xE9111820)]),
          border: Border.all(color: Colors.white.withValues(alpha: .36)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3))
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 10,
                height: 2,
                color: over ? ink : const Color(0xFFFF7585)),
            const SizedBox(width: 5),
            const Flexible(child: Text('VITESSE',
                style: TextStyle(
                    color: Color(0xFFB8C5D0),
                    fontSize: 11,
                    letterSpacing: 1.7,
                    fontWeight: FontWeight.w600))),
          ]),
          Text(value == null ? '—' : '$value',
              style: AppTheme.numeric(TextStyle(
                  color: ink,
                  fontSize: 35,
                  height: 1.12,
                  letterSpacing: -1.2,
                  fontWeight: FontWeight.w600))),
          const Text('km/h',
              style: TextStyle(color: Color(0xFFBDCAD4), fontSize: 11)),
          if (value == null)
            const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text('GPS à actualiser',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFBDCAD4), fontSize: 12))),
          if (pointLimit != null)
            Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text('Point : $pointLimit km/h',
                    style: const TextStyle(
                        color: Color(0xFFE0E7ED), fontSize: 11))),
        ]),
      ),
    );
  }
}
