/// Shared wording for the native watch state on the map and the reliability screen.
class WatchStatus {
  const WatchStatus(this.state, {this.armedCount = 0});
  factory WatchStatus.fromMap(Map<Object?, Object?> value) => WatchStatus(
    value['state'] as String? ?? 'unknown',
    armedCount: (value['armedCount'] as num?)?.toInt() ?? 0,
  );
  final String state;
  final int armedCount;
  String get label => switch (state) {
    'storage_error' => 'Copie de surveillance à réparer',
    'receipt_limit' => 'Ouvrir l’application pour synchroniser les rappels',
    'stopped' => 'Surveillance arrêtée',
    'dormant' => 'En veille · aucune alerte prévue aujourd’hui',
    'unavailable' => 'Localisation indisponible',
    'acquiring' => 'Recherche d’une position GPS',
    'fresh' => 'Surveillance active · position récente',
    'stale' => 'Signal GPS à actualiser',
    'economy' => 'Économie de batterie · position en attente',
    _ => 'État de surveillance indisponible',
  };
}
