# RedAlert — catalogues de lieux

Variante de LocReminder 2.1.1, paquet Android
`com.zaifears.locreminder.catalogue`. État local : catalogue.13.

## Importer et activer

Menu → Mes lieux → Catalogues et légende → Importer un catalogue.

- **Radars de référence** : 3 185 observations du catalogue ministériel,
  94 départements continentaux. Leur nombre ne représente pas nécessairement
  des appareils distincts.
- **Passages à niveau SNCF** : 14 891 références routières qualifiées dans
  93 départements. Catalogue embarqué, filtre par classe et difficulté pour
  véhicules surbaissés ; date de traitement du jeu : 18 février 2026.
- **Dangers routiers OSM** : téléchargement explicite par département des points
  `traffic_calming` reconnus : ralentisseurs, vibreurs, creux et rétrécissements.
  Une connexion est nécessaire ; seul le département est envoyé à Overpass.
- **Fichier JSON** : format préparatoire conservé pour les catalogues personnels.

Le chargement affiche les propositions puis ouvre la prévisualisation avant
l’enregistrement. Les nouveaux lieux restent désarmés. Les corrections et
l’armement des lieux déjà connus sont conservés lors d’une réimportation.
Source, identifiant et date sont consultables dans l’éditeur. La date du jeu ne
constitue pas une vérification récente du lieu sur le terrain.

« Points de référence » permet d’armer manuellement un département. Le suivi
automatique de département concerne uniquement les radars ministériels ; il
n’arme pas automatiquement les nouvelles sources SNCF/OSM. Les lieux personnels
restent séparés des actions de département.

## Carte et annonces

Le rayon d’anticipation dépend du contexte et de la vitesse plausible ; le moment
de parole dépend du temps d’approche estimé. Les 15 catégories disposent de
287 clips français embarqués. Le mode passage et les rappels de destination
conservent des comportements distincts. Les réglages audio sont dans
« Alertes et voix » ; chaque bouton d’essai nomme la catégorie choisie.

La carte peut suivre le véhicule ou être explorée, en mode nord ou cap. Les points
sont regroupés aux petites échelles pour limiter la surcharge. Ce regroupement
ne fusionne aucune donnée et ne modifie pas les alertes natives.

## Limites

La reconnaissance de voie reste géométrique ; une route parallèle proche peut
être ambiguë. Un sens renseigné peut filtrer une approche ; aucune direction
inconnue n’est inventée. La précision du GPS et la fraîcheur des données restent
visibles et déterminantes. Les données SNCF excluent notamment les références
secondaires, les passages privés/piétons et les identifiants contradictoires.
OSM reste une couverture communautaire partielle, limitée aux points reconnus.

L’APK catalogue.13 est compilé et vérifié localement ; le POCO reste sur
catalogue.11. Les essais de lecteur sur émulateur ne prouvent pas l’audition,
le Bluetooth ni le déclenchement en circulation. Voir `../AUDIT.md`,
`field-feedback/ROAD_DATA.md` et `testing/ARTEMIS.md`.

## Reconstruction

Flutter 3.47.1, Dart 3.13.1, SDK Android 36, NDK 28.2.13676358 ; Java 25
sur ce Mac, compilation Java/Kotlin cible 17. Configurer les chemins locaux et
exporter `ANDROID_HOME` et `ANDROID_SDK_ROOT` vers le même SDK valide.

```sh
flutter pub get
flutter analyze
flutter test
(cd android && ./gradlew :app:testDebugUnitTest)
python3 tool/gen_locale.py --check
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

L’APK est produit dans `build/app/outputs/flutter-apk/`. Conserver la signature
de développement actuelle pour les mises à jour locales ; aucune clé privée
n’est incluse. GitHub reste en pause. Pour régénérer les PN sans réseau :
`python3 tool/catalogue/build_railway.py`.
