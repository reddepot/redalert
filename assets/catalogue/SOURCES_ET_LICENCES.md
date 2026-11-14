# Provenance et attributions à conserver

| Couche | Instantané | Provenance | Licence / statut relevé |
|---|---|---|---|
| Ministère, CSV | 30 décembre 2025 | Ministère de l'Intérieur, data.gouv.fr | Licence Ouverte 2.0 |
| SNCF Réseau — PN routiers | Jeu traité le 18 février 2026 | SNCF Réseau, export officiel archivé | ODbL déclarée dans les métadonnées archivées |
| OpenStreetMap | 10 novembre 2026 | © les contributeurs OpenStreetMap | ODbL 1.0 |
| MapAtlas Camera Index | 21 mai 2024 | MapAtlas / MapMetrics driver reports | CC BY 4.0, attribution et modifications indiquées |
| Carte officielle, API | Date de consultation : 11 novembre 2026 ; date par point non fournie dans la liste | Sécurité routière | Conditions de réutilisation de cet endpoint non déterminées |
| Archive Augusti | 2018 | Antoine Augusti, d'après la Sécurité routière | Licence Ouverte 2.0 déclarée au catalogue data.gouv.fr |

Liens :

- https://www.data.gouv.fr/datasets/liste-des-radars-fixes-en-france
- https://www.openstreetmap.org/copyright
- https://mapatlas.eu/camera-index
- https://creativecommons.org/licenses/by/4.0/
- https://radars.securite-routiere.gouv.fr/radars/all?_format=json
- https://www.data.gouv.fr/datasets/radars-automatiques

Les sources restent séparées. Les licences d'une couche ne sont pas attribuées
à toutes les autres. Une source différente n'est pas automatiquement une collecte
indépendante ; la carte et l'archive dérivent du ministère.

Les trois extraits fournis ont été comparés aux fichiers nationaux téléchargés
directement : identifiants, coordonnées et propriétés d'origine concordent.
Les empreintes des trois fichiers nationaux concordent aussi avec le journal
de vérification fourni. Les ajouts de filtrage et de provenance des extraits
ne sont pas confondus avec les propriétés du producteur.

Traitements effectués : sélection territoriale, normalisation de présentation,
comparaison par distance et identifiant quand celui-ci est commun, création
de liens candidats et mise en forme pour un futur import. Aucune confirmation
terrain, fusion automatique ni activation n'a été effectuée.

Résultats utiles de la comparaison :

- 91 observations MapAtlas sans voisin à moins de 250 m dans les bases ministère/OSM.
- 0 observation de la carte officielle sans voisin à moins de 250 m.
- 37 observations de l'archive de 2018 sans voisin à moins de 250 m : historique,
  pas des installations actuelles confirmées.
- 538 liens historiques proposés pour enrichir la documentation de lieux :
  distance de 25 m ou moins et un seul point ministériel dans un rayon de 50 m.
  Cela ne prouve ni l'identité de l'appareil ni la validité actuelle du sens ou de la route.
- Une divergence de département dans l'archive est signalée dans le rapport.

Les positions de tronçons sont des points de référence de section : elles ne
reconstituent ni les deux extrémités ni l'ensemble des caméras physiques.
Un azimut de caméra n'est pas transformé en direction de circulation.

Les effectifs des couches et les nombres de rapprochements ne doivent pas
être additionnés comme un nombre d'installations uniques.


Complément catalogue.13 : les paquets `railway/` proviennent de la
[liste SNCF](https://ressources.data.sncf.com/explore/dataset/liste-des-passages-a-niveau/).
L’export, ses métadonnées et les empreintes sont dans `data/catalogue/`.
Les classes routières publiques 10–21 sont sélectionnées, les références ambiguës
écartées et les fichiers séparés par code INSEE de commune. Aucun déplacement
ni fusion automatique avec les radars n’est effectué. Les imports OSM de dangers
portent leur propre date d’extrait, distincte de l’ancien instantané ci-dessus.
