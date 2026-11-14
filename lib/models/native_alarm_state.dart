/// A service receipt confirms presentation, never human audibility.
class NativeAlarmState {
  const NativeAlarmState({
    this.activeIds = const {},
    this.receipts = const {},
    this.corrupt = false,
    this.invalidRecords = 0,
  });
  factory NativeAlarmState.fromMap(Map<Object?, Object?> data) =>
      NativeAlarmState(
        activeIds: (data['activeIds'] as List).cast<String>().toSet(),
        receipts: (data['receipts'] as Map).cast<String, String>(),
        corrupt: data['corrupt'] == true,
        invalidRecords: (data['invalidRecords'] as num?)?.toInt() ?? 0,
      );
  final Set<String> activeIds;
  final Map<String, String> receipts;
  final bool corrupt;
  final int invalidRecords;
}
