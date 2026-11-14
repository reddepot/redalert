import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:locreminder/models/poi_type.dart' show PoiType;
import 'package:locreminder/services/department_arming.dart';

LocationAlarm point({
  String id = 'mi:1',
  String? department = '86',
  double latitude = 46.58,
  double longitude = 0.34,
  bool active = false,
}) =>
    LocationAlarm(
      id: id,
      label: id,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: 1000,
      isActive: active,
      createdAt: DateTime(2026, 11, 11),
      poiType: PoiType.fixedCamera,
      department: department,
    );

void main() {
  final poitiers = point(id: 'mi:1', department: '86');
  final niort =
      point(id: 'mi:2', department: '79', latitude: 46.32, longitude: -0.46);
  final bordeaux =
      point(id: 'mi:3', department: '33', latitude: 44.84, longitude: -0.58);
  final personal = point(id: 'perso', department: null, active: true);
  final alarms = [poitiers, niort, bordeaux, personal];

  test('counts points and armed points per department', () {
    final counts = DepartmentArming.byDepartment(alarms);
    expect(counts['86']!.total, 1);
    expect(counts['86']!.armed, 0);
    expect(counts['33']!.total, 1);
    expect(counts.containsKey(''), isFalse,
        reason: 'a personal place has no department and must not be counted');
  });

  test('finds the department of the nearest point', () {
    expect(DepartmentArming.departmentAt(alarms, 46.579, 0.341), '86');
    expect(DepartmentArming.departmentAt(alarms, 46.32, -0.46), '79');
  });

  test('says nothing when every point is too far away', () {
    // Off the coast of Portugal: 1 000 km from the nearest catalogue point.
    expect(DepartmentArming.departmentAt(alarms, 38.7, -9.1), isNull);
  });

  test('arms one department and pauses the other reference points', () {
    final armed = DepartmentArming.armOnly(alarms, '79');
    expect(armed.firstWhere((a) => a.id == 'mi:2').isActive, isTrue);
    expect(armed.firstWhere((a) => a.id == 'mi:1').isActive, isFalse);
    expect(armed.firstWhere((a) => a.id == 'mi:3').isActive, isFalse);
    // A place the user added by hand is never touched by an automatic rule.
    expect(armed.firstWhere((a) => a.id == 'perso').isActive, isTrue);
  });

  test('leaves the list untouched when the department is already armed', () {
    final once = DepartmentArming.armOnly(alarms, '86');
    final twice = DepartmentArming.armOnly(once, '86');
    expect(identical(once, twice), isTrue,
        reason: 'an unchanged list must not force a write on every fix');
  });

  test('toggles a single department without touching the others', () {
    final opened = DepartmentArming.setDepartment(alarms, '33', true);
    expect(opened.firstWhere((a) => a.id == 'mi:3').isActive, isTrue);
    expect(opened.firstWhere((a) => a.id == 'mi:1').isActive, isFalse);

    final closed = DepartmentArming.setDepartment(opened, '33', false);
    expect(closed.firstWhere((a) => a.id == 'mi:3').isActive, isFalse);
  });

  test('pausing everything keeps the personal places armed', () {
    final mixed = DepartmentArming.setDepartment(alarms, '86', true);
    final paused = DepartmentArming.pauseAll(mixed);
    expect(paused.where((a) => a.department != null).every((a) => !a.isActive),
        isTrue);
    expect(paused.firstWhere((a) => a.id == 'perso').isActive, isTrue);
  });

  test('department actions preserve personal places even with a department', () {
    final own = point(id: 'personal', department: '86', active: true);
    final railway = point(id: 'sncf:pn/1', department: '86', active: true);
    final values = [own, railway];
    expect(DepartmentArming.byDepartment(values)['86']!.total, 1);
    final paused = DepartmentArming.pauseAll(values);
    expect(paused[0].isActive, isTrue);
    expect(paused[1].isActive, isFalse);
    final toggled = DepartmentArming.setDepartment(values, '86', false);
    expect(toggled[0].isActive, isTrue);
    expect(toggled[1].isActive, isFalse);
  });

  test('the distance gate matches the distance helper the app uses', () {
    // 20 km north of Poitiers: still the same department.
    final north = const Distance().offset(const LatLng(46.58, 0.34), 20000, 0);
    expect(
        DepartmentArming.departmentAt(alarms, north.latitude, north.longitude),
        '86');
    // 40 km away: beyond the 25 km ceiling, so no department is claimed.
    final far = const Distance().offset(const LatLng(46.58, 0.34), 40000, 0);
    expect(DepartmentArming.departmentAt(alarms, far.latitude, far.longitude),
        isNull);
  });

  test(
      'automatic arming never enables or pauses separately imported road hazards',
      () {
    final rail = point(id: 'sncf:pn/1', department: '86');
    final community = point(id: 'osm:node/1', department: '79', active: true);
    final values = DepartmentArming.armOnly([poitiers, rail, community], '86');
    expect(values[0].isActive, isTrue);
    expect(values[1].isActive, isFalse);
    expect(values[2].isActive, isTrue);
    final closer = point(
        id: 'sncf:pn/2', department: '79', latitude: 46.579, longitude: .341);
    expect(
        DepartmentArming.departmentAt([poitiers, closer], 46.579, .341), '86');
    expect(
        DepartmentArming.setDepartment(values, '86', true)[1].isActive, isTrue);
  });
}
