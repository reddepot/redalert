# RedAlert — périmètre produit

Application Android d'alertes de proximité et de préparation de trajet, issue de
LocReminder. Le paquet `com.zaifears.locreminder.catalogue` conserve la continuité
des mises à jour et des données. Ce document décrit RedAlert ; l'historique amont
reste consultable dans Git.

## Usage

Conduite avec carte lisible, position et vitesse récentes, lieux utiles et alertes
vocales brèves. Les rappels de destination restent disponibles avec leur sonnerie.
L'utilisateur peut aussi choisir une destination et obtenir un tracé d'itinéraire.

La fiabilité du moteur natif prime : position incertaine visible, absence de
limitation connue respectée, annonces périmées refusées, fonctionnement indépendant
du moteur Flutter lorsque des lieux sont armés.

## Disponible dans les sources

- Android API 24+, moteur Kotlin sans dépendance à Google Play Services.
- Lieux personnels, édition précise, armement et répétition par passage ; sens
  applicable configurable si connu.
- Catalogue ministériel continental : 3 185 points, 94 départements. Ce catalogue
  ne représente pas tous les types de points d'intérêt de France.
- 15 catégories et 287 phrases françaises embarquées. Catalogue et voix sont des
  ressources séparées : ajouter une catégorie n'en importe pas les points.
- Rayon de surveillance selon contexte/vitesse plausible ; moment de parole
  séparé et fondé sur le temps d'approche. Limitation et vitesse probable distinctes.
- Carte suivie ou explorée, nord/cap, zoom/échelle, position et vitesse actualisées
  même sans lieu armé lorsque la carte est affichée.
- Calcul FOSSGIS/OSRM après action et accord explicites ; tracé/progression en mémoire.
  Pas encore de guidage vocal complet changement par changement.
- Plans régionaux Shortbread/MBTiles à télécharger sur Wi-Fi non mesuré, environ
  5,77 Go pour les 21 archives continentales du manifeste. Rendu jusqu'au zoom natif
  14 puis surzoom ; fraîcheur des archives non garantie.
- Réglage de maintien d'écran sur la carte, alertes audio et diagnostic de surveillance.
- Catalogue SNCF embarqué : 14 891 PN routiers qualifiés, 93 départements, dont
  1 734 signalés difficiles pour véhicules surbaissés ; filtre par classe.
- Import OSM explicite des ralentisseurs, vibreurs, creux et rétrécissements.
  Prévisualisation, lieux désarmés et provenance conservée pour les deux sources.
- Regroupement visuel des points en vue d’ensemble, sans fusion des lieux.
- Consultation Bison Futé/DIR sur demande : événements, retraits, dates et carte
  de points/extrémités déclarés ; périodes particulières et cache périmé signalés.
- QTV (vitesses moyennes/débits) et états Traficolor par producteur : consultation
  datée, péremption par mesure, inconnus explicites. Pas de limitation ni de
  géométrie de route inventées. Aucune alerte trafic automatique.
- Reçus positifs durables des rappels ponctuels et réparation confirmée de la
  copie native, avec préservation des données illisibles et des points valides.
- Interface consolidée : menu conduite/lieux/réglages, apparence automobile sobre,
  repère de position réduit et choix d'aperçu vocal explicitement nommé.

## État des versions et preuves

Catalogue.13 est installé sur POCO sans effacement. L’aperçu ralentisseur est
confirmé audible écran allumé ; l’essai écran éteint a donné une annonce coupée.
La cause n’est pas établie. Le service présent ne prouve pas une lecture audible.

Catalogue.14 a apporté localement : essai différé annulable, lecteur indépendant
de la recréation de l’interface et diagnostic de début/fin sans déverrouillage.
Sur émulateur, la recréation interrompt l’ancienne version et laisse la nouvelle
terminer ; le lecteur du nouvel APK release commence et termine écran éteint.
Ces preuves synthétiques ne valident pas la correction de la coupure sur POCO.
Catalogue.16 consolide ces apports, la consultation du trafic et les corrections de
contraste/stabilité de carte. Son APK est compilé, signé et vérifié localement.
La consolidation est publiée dans la PR #10. Les avis indépendants ont été examinés,
puis les corrections retenues intégrées dans catalogue.17 : continuité/cadence des
passages, vitesse, routage, arrivées, gestion audio, imports et limites de tuiles.
Catalogue.18 termine reçus, récupération, profilage synthétique et consultation
QTV/Traficolor ; le suivi global est dans `docs/WORK_LEDGER.md`.
Le nouvel essai POCO reste postérieur à cette implémentation et aux vérifications.
Le protocole matériel et les limites sont dans `docs/testing/ARTEMIS.md`.

## Données et services

Lieux et décisions d'alerte restent locaux. Aucun modèle IA ne décide du déclenchement.
Le calcul d'itinéraire transmet ses points de départ et d'arrivée après confirmation.
La recherche de lieu et les fonds non présents localement utilisent leurs services
cartographiques ; aucun compte n'est requis pour le parcours actuel.

L'assistant cloud optionnel est autorisé dans le backlog, mais n'est pas livré.
Aucune clé n'est embarquée et aucune position ni trace ne sera jointe implicitement
à un dialogue. Sélection des nouvelles données/IA :
`docs/field-feedback/QWEN_SELECTION.md`.

## Suites séparées

Trafic et événements, services de route, contributions et
assistant vocal sont des lots distincts. Perspective 3D et réveil automatique à
l'approche demandent un support technique et une validation propres. Les jeux de
données historiques ne suffisent pas à attribuer une cause à un accident.
