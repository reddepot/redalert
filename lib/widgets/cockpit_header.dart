import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Restrained instrument graphics, without invented speed or telemetry.
class CockpitHeader extends StatelessWidget {
  const CockpitHeader({super.key});
  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF293440), Color(0xFF11171E)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Stack(children: [
          const Positioned(
              right: -18,
              top: -22,
              bottom: -22,
              width: 160,
              child: ExcludeSemantics(
                  child: CustomPaint(painter: _DialPainter()))),
          Padding(
            padding: const EdgeInsets.all(22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 25, height: 3, color: const Color(0xFFFF7585)),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('CONDUITE & ALERTES',
                        style: TextStyle(
                            color: Color(0xFFC0CBD5),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.6))),
              ]),
              const SizedBox(height: 12),
              const Text('RedAlert',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8)),
              const SizedBox(height: 3),
              const Text('Votre espace de conduite',
                  style: TextStyle(color: Color(0xFFBCC7D0), fontSize: 12)),
            ]),
          ),
        ]),
      );
}

class _DialPainter extends CustomPainter {
  const _DialPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width * .67, size.height * .55);
    final radius = size.shortestSide * .56;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(centre, radius, paint);
    canvas.drawCircle(centre, radius - 15, paint);
    for (var i = 0; i < 22; i++) {
      final angle = (140 + i * 12) * math.pi / 180;
      final unit = Offset(math.cos(angle), math.sin(angle));
      paint.color = i > 17
          ? const Color(0xFFFF7585).withValues(alpha: .6)
          : Colors.white.withValues(alpha: .19);
      paint.strokeWidth = i % 3 == 0 ? 2 : 1;
      canvas.drawLine(centre + unit * (radius - (i % 3 == 0 ? 10 : 5)),
          centre + unit * radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) => false;
}
