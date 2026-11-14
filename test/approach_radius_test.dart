import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/approach_radius.dart';
import 'package:locreminder/models/poi_type.dart';
import 'package:locreminder/models/location_alarm.dart';

void main() {
  test(
      'monitoring envelope uses probable travel speed rather than the posted limit',
      () {
    expect(ApproachRadius.metres(PoiType.fixedCamera, 30, null), 600);
    expect(ApproachRadius.metres(PoiType.fixedCamera, 130, null), 1100);
    expect(ApproachRadius.metres(PoiType.fixedCamera, 90, null), 1100);
    expect(
        ApproachRadius.metres(PoiType.fixedCamera, 90, null,
            context: RoadContext.motorway),
        ApproachRadius.metres(PoiType.fixedCamera, 130, null,
            context: RoadContext.motorway));
    expect(ApproachRadius.metres(PoiType.other, null, 5), 100);
    expect(ApproachRadius.metres(PoiType.other, null, 90), 750);
  });
  test(
      'upgrade changes the default catalogue radius but preserves activation and manual choices',
      () {
    final original = LocationAlarm(
        id: 'mi:synthetic',
        label: 'Synthetic',
        latitude: 0,
        longitude: 0,
        radiusMeters: 1000,
        isActive: true,
        createdAt: DateTime(2026),
        repeatOnEveryEntry: true,
        poiType: PoiType.fixedCamera,
        speedLimitKmh: 30);
    final legacy = original.toJson()..remove('adaptiveRadius');
    final upgraded = LocationAlarm.fromJson(legacy);
    expect(upgraded.isActive, isTrue);
    expect(upgraded.radiusMeters, 600);
    expect(upgraded.adaptiveRadius, isTrue);
    expect(
        LocationAlarm.fromJson({...legacy, 'radiusMeters': 450}).adaptiveRadius,
        isFalse);
    expect(LocationAlarm.fromJson({...legacy, 'id': 'personal'}).radiusMeters,
        1000);
    final edited = upgraded.copyWith(speedLimitKmh: 130);
    expect(LocationAlarm.fromJson(edited.toJson()).radiusMeters, 1100);
    expect(
        upgraded
            .copyWith(adaptiveRadius: false, radiusMeters: 450)
            .radiusMeters,
        450);
  });
  test(
      'road context and controlled travel bearing survive storage and explicit clearing',
      () {
    final original = LocationAlarm(
        id: 'synthetic',
        label: 'Synthetic',
        latitude: 0,
        longitude: 0,
        radiusMeters: 500,
        isActive: true,
        createdAt: DateTime(2026),
        adaptiveRadius: true,
        poiType: PoiType.fixedCamera,
        speedLimitKmh: 90);
    final edited = original.copyWith(
        roadContext: RoadContext.motorway, travelBearingDegrees: 90);
    final restored = LocationAlarm.fromJson(edited.toJson());
    expect(restored.radiusMeters, 1100);
    expect(restored.roadContext, RoadContext.motorway);
    expect(restored.travelBearingDegrees, 90);
    expect(restored.hasSameEditableValues(original), isFalse);
    expect(restored.copyWith(clearTravelBearing: true).travelBearingDegrees,
        isNull);
  });
}
