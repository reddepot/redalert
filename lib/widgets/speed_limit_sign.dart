import 'package:flutter/material.dart';

/// The French speed-limit sign, drawn rather than borrowed from an image.
///
/// Same reason the map pin is painted: it has to stay crisp at 24 dp, keep its
/// proportions at any text scale, and be recognisable in one glance while
/// driving. A white disc with a red ring and the number in the middle is the
/// legal sign; reproducing it makes the limit read as a limit and not as
/// another statistic next to the distance.
class SpeedLimitSign extends StatelessWidget {
  const SpeedLimitSign({
    super.key,
    required this.limitKmh,
    this.size = 28,
    this.overLimit = false,
  });

  final int limitKmh;
  final double size;

  /// Rings the sign in the error colour and fills it, for the moment the
  /// measured speed is above the limit.
  final bool overLimit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = overLimit ? scheme.error : const Color(0xFFC62828);
    final fill = overLimit ? scheme.errorContainer : Colors.white;
    final text = overLimit ? scheme.onErrorContainer : Colors.black87;
    // Three characters fit the disc; anything longer would be a limit no
    // French road carries, so it is clamped rather than shrunk into mush.
    final label = limitKmh > 130 ? '130' : '$limitKmh';

    return Semantics(
      label: 'Limite $limitKmh kilomètres par heure',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: size * 0.09),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: text,
            fontSize: size * 0.46,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -0.4,
          ),
        ),
      ),
    );
  }
}
