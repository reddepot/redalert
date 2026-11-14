import 'package:flutter/material.dart';

/// Unambiguous centre point: the central dot, not the edge of an icon.
class PlacementTarget extends StatelessWidget {
  const PlacementTarget({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Centre exact de la zone. Déplacer la carte sous la croix.',
        child: SizedBox(
            width: 48,
            height: 48,
            child: CustomPaint(
                painter:
                    _TargetPainter(Theme.of(context).colorScheme.primary))),
      );
}

class _TargetPainter extends CustomPainter {
  const _TargetPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = Path()
      ..moveTo(c.dx, 0)
      ..lineTo(c.dx, c.dy - 7)
      ..moveTo(c.dx, c.dy + 7)
      ..lineTo(c.dx, size.height)
      ..moveTo(0, c.dy)
      ..lineTo(c.dx - 7, c.dy)
      ..moveTo(c.dx + 7, c.dy)
      ..lineTo(size.width, c.dy);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
    canvas.drawCircle(c, 5, Paint()..color = Colors.white);
    canvas.drawCircle(c, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TargetPainter oldDelegate) => color != oldDelegate.color;
}
