import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:locreminder/services/map_poi_groups.dart';

MapCamera camera(LatLng center, double zoom) => MapCamera.initialCamera(
        MapOptions(initialCenter: center, initialZoom: zoom))
    .withNonRotatedSize(const Size(390, 844));
LocationAlarm point(int i,
        {double lat = 46.5, double lon = .3, bool active = false}) =>
    LocationAlarm(
        id: 'synthetic:$i',
        label: 'Synthetic',
        latitude: lat,
        longitude: lon,
        radiusMeters: 1000,
        isActive: active,
        createdAt: DateTime.utc(2026));
void main() {
  test(
      'large overview represents every selected point once with bounded marker groups',
      () {
    final points = List.generate(
        18000,
        (i) => point(i,
            lat: 44 + (i % 100) * .05,
            lon: -2 + (i ~/ 100) * .03,
            active: i.isEven));
    final groups = MapPoiGroups.select(points, camera(const LatLng(46, 1), 5));
    final flattened = groups.expand((g) => g.alarms).toList();
    expect(groups.length, lessThan(150));
    expect(flattened.length, points.length);
    expect(flattened.map((p) => p.id).toSet().length, flattened.length);
    expect(groups.fold(0, (sum, g) => sum + g.armed),
        flattened.where((p) => p.isActive).length);
    expect(points.where((p) => p.isActive).length, 9000);
  });
  test(
      'street-level selection retains individual places and excludes distant points',
      () {
    final local = [point(1, active: true), point(2, lon: .3001)];
    final groups = MapPoiGroups.select([...local, point(3, lat: 0, lon: 0)],
        camera(const LatLng(46.5, .3), 16));
    expect(groups.length, 2);
    expect(groups.every((g) => g.alarms.length == 1), isTrue);
    expect(groups.last.alarms.single.isActive, isTrue);
  });
  test('viewport crossing the date line retains visible points in both worlds',
      () {
    final groups = MapPoiGroups.select(
        [point(1, lat: 0, lon: 179), point(2, lat: 0, lon: -179)],
        camera(const LatLng(0, 179.5), 5));
    expect(groups.expand((g) => g.alarms).length, 2);
  });
  test(
      'dense coincident points remain represented without thousands of widgets',
      () {
    final points = List.generate(3000, (i) => point(i));
    final groups =
        MapPoiGroups.select(points, camera(const LatLng(46.5, .3), 19));
    expect(groups.length, 1);
    expect(groups.single.alarms.length, 3000);
  });
}
