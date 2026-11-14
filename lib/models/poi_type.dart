enum PoiType {
  fixedCamera('Radar fixe'),
  redLightCamera('Radar de feu rouge'),
  averageSpeedCamera('Radar tronçon'),
  levelCrossing('Passage à niveau'),
  levelCrossingLowClearance('PN difficile'),
  highSpeedBump('Ralentisseur'),
  dangerZone('Zone dangereuse'),
  sharpTurn('Virage serré'),
  rumbleStrip('Bandes rugueuses'),
  roadDip('Creux de chaussée'),
  roadNarrowing('Chaussée rétrécie'),
  steepDescent('Forte descente'),
  roadWorks('Travaux'),
  trafficJam('Ralentissement'),
  other('Autre lieu');

  const PoiType(this.label);
  final String label;

  static PoiType fromName(Object? name) =>
      values.firstWhere((type) => type.name == name, orElse: () => other);

  static PoiType fromSource(Object? code) {
    if (code == 'SNCF_PN_LOW') return levelCrossingLowClearance;
    if (code == 'SNCF_PN') return levelCrossing;
    if (['ETFR', 'signal', 'feux', 'Radar feu rouge', 'OSM_FEU_ROUGE']
        .contains(code)) {
      return redLightCamera;
    }
    if (['ETVM', 'corridor', 'troncons', 'Radar Vitesse Moyenne', 'OSM_TRONCON']
        .contains(code)) {
      return averageSpeedCamera;
    }
    if (['ETPN', 'niveaux', 'Radar Passage à Niveau', 'OSM_PASSAGE_NIVEAU']
        .contains(code)) {
      return levelCrossing;
    }
    if ([
      'ETF',
      'ETD',
      'ETT',
      'ETU',
      'spot',
      'fixes',
      'discriminants',
      'urbain',
      'Radar fixe',
      'Radar discriminant',
      'OSM_VITESSE'
    ].contains(code)) {
      return fixedCamera;
    }
    return switch (code) {
      'bump' || 'hump' || 'table' || 'cushion' || 'mini_bumps' => highSpeedBump,
      'rumble_strip' => rumbleStrip,
      'dip' || 'double_dip' => roadDip,
      'chicane' || 'choker' || 'island' => roadNarrowing,
      _ => other,
    };
  }
}
