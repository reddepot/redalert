import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/location_alarm.dart';

class MapPoiGroup {
  MapPoiGroup(List<LocationAlarm> points, {LocationAlarm? anchor})
      : _anchor = anchor ?? points.first,
        alarms = List.unmodifiable(points),
        armed = points.where((p) => p.isActive).length;
  final LocationAlarm _anchor;
  final List<LocationAlarm> alarms;
  final int armed;
  LatLng get anchor => LatLng(_anchor.latitude, _anchor.longitude);
}

/// Display-only grouping: it never changes the underlying places or arming.
abstract final class MapPoiGroups {
  static List<MapPoiGroup> select(
      List<LocationAlarm> alarms, MapCamera camera) {
    final bounds = camera.visibleBounds;
    final latPadding = (bounds.north - bounds.south) * .15;
    final halfLongitude = bounds.longitudeWidth * .65;
    final visible = alarms.where((p) {
      final delta =
          ((p.longitude - bounds.longitudeCenter + 540) % 360 - 180).abs();
      return p.latitude >= bounds.south - latPadding &&
          p.latitude <= bounds.north + latPadding &&
          (halfLongitude >= 180 || delta <= halfLongitude);
    }).toList();
    if (camera.zoom >= 13 && visible.length <= 600) {
      return visible.map((p) => MapPoiGroup([p])).toList()
        ..sort((a, b) => a.armed.compareTo(b.armed));
    }
    final buckets = <(int, int), List<LocationAlarm>>{};
    final anchors = <(int, int), LocationAlarm>{};
    for (final alarm in visible) {
      final pixel =
          camera.projectAtZoom(LatLng(alarm.latitude, alarm.longitude));
      final key = ((pixel.dx / 64).floor(), (pixel.dy / 64).floor());
      (buckets[key] ??= []).add(alarm);
      final screen =
          camera.latLngToScreenOffset(LatLng(alarm.latitude, alarm.longitude));
      if (screen.dx >= 0 &&
          screen.dx <= camera.nonRotatedSize.width &&
          screen.dy >= 0 &&
          screen.dy <= camera.nonRotatedSize.height) {
        anchors.putIfAbsent(key, () => alarm);
      }
    }
    return buckets.entries
        .map((e) => MapPoiGroup(e.value, anchor: anchors[e.key]))
        .toList()
      ..sort((a, b) => a.armed.compareTo(b.armed));
  }
}
