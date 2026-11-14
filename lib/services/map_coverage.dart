/// Polygon masks from the same regional extraction provider as the archives.
abstract final class MapCoverage {
  static bool contains(List<dynamic> rings, double latitude, double longitude) {
    var outer = false;
    for (final item in rings) {
      final ring = item as Map;
      final points = ring['points'] as List;
      var inside = false;
      for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
        final a = points[i] as List, b = points[j] as List;
        final ay = (a[1] as num).toDouble(), by = (b[1] as num).toDouble();
        if ((ay > latitude) != (by > latitude) &&
            longitude <
                ((b[0] as num) - (a[0] as num)) * (latitude - ay) / (by - ay) +
                    (a[0] as num)) {
          inside = !inside;
        }
      }
      if (inside && ring['hole'] == true) return false;
      if (inside) outer = true;
    }
    return outer;
  }
}
