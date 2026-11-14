import '../models/location_alarm.dart';

/// Decides what the native watcher should be told, from the two lists that
/// used to drift apart.
///
/// The app keeps the catalogue in `shared_preferences` and the watcher keeps
/// the armed points in its own store. Only the watcher can ring, so a change
/// that stops at the Dart list is a promise the app cannot keep — and worse,
/// the reconciliation that runs at startup used to read "absent from the
/// watcher" as "already rang", which turned a missing write into a false
/// success message and a silently disarmed catalogue.
///
/// These three functions are pure so the rules can be tested without a phone.
abstract final class NativeReconciliation {
  /// Missing armed rows are repaired unless a positive one-shot receipt exists.
  static List<LocationAlarm> toRepair(
    List<LocationAlarm> alarms,
    Set<String> nativeIds, {
    Set<String> consumedIds = const {},
  }) => alarms
      .where(
        (alarm) =>
            alarm.isActive &&
            !nativeIds.contains(alarm.id) &&
            (alarm.repeats || !consumedIds.contains(alarm.id)),
      )
      .toList();

  /// Absence alone never disarms. A currently armed native row wins over a stale receipt.
  static List<LocationAlarm> alreadyRang(
    List<LocationAlarm> alarms,
    Set<String> nativeIds, {
    Set<String> consumedIds = const {},
  }) => alarms
      .where(
        (alarm) =>
            alarm.isActive &&
            !alarm.repeats &&
            !nativeIds.contains(alarm.id) &&
            consumedIds.contains(alarm.id),
      )
      .toList();

  /// The rows whose armed state changed, in the shape the native call wants.
  ///
  /// Deactivations are included on purpose: `replaceSelected` removes the ids
  /// it is given, which is how a paused point stops being watched.
  static List<LocationAlarm> armingChanges(
    List<LocationAlarm> before,
    List<LocationAlarm> after,
  ) {
    final was = {for (final alarm in before) alarm.id: alarm.isActive};
    return after
        .where(
          (alarm) =>
              was.containsKey(alarm.id) && was[alarm.id] != alarm.isActive,
        )
        .toList();
  }
}
