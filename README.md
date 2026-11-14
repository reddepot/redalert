# RedAlert

Application Android d’alertes de proximité, de carte de conduite et de préparation
de trajet, issue de [LocReminder](https://github.com/zaifears/locreminder).
Interface française, Flutter pour les lieux et l’affichage, Kotlin pour la
surveillance et les alertes, y compris lorsque l’interface Flutter est suspendue.

## Version consolidée : catalogue.18

Aucun APK n’est distribué depuis ce dépôt : il sert à la relecture du code.
Les validations matérielles encore attendues sont précisées ci-dessous.

- Carte suivie ou explorée, orientation nord ou cap au choix, zoom et échelle,
  position et vitesse accompagnées de leur état de fraîcheur.
- Menu conduite / lieux / réglages, commandes translucides et thèmes jour/nuit.
  Fournisseur vectoriel stabilisé pour éviter les rechargements de tuiles lors
  des simples mises à jour d’interface ; contraste des routes renforcé.
- Destination et calcul FOSSGIS/OSRM après accord explicite ; tracé et progression.
  Le guidage vocal complet changement par changement reste à développer.
- 15 catégories, pictogrammes et couleurs distincts ; 287 annonces françaises
  complètes embarquées, sans synthèse réseau pendant une alerte. Les rappels
  de destination conservent leur sonnerie.
- Surveillance native, approche liée au mouvement, direction configurable,
  contrôle de fraîcheur, reprise du processus et persistance des étapes de passage.
- Essai vocal nommé, immédiat ou différé de cinq secondes, annulable, avec état
  de début/fin récupérable après recréation de l’interface.

Depuis la revue, le cap temporairement incompatible ne détruit plus le suivi,
la répétition vocale est propre à chaque point et la vitesse filtrée est évaluée
sur toutes les cibles applicables. Le téléchargement du tracé est borné en flux
et sa progression est ancrée pour les boucles. Les arrivées exigent une précision
compatible avec le rayon choisi. Bips annulables avec focus audio, aperçu de
sonnerie asynchrone, imports lourds hors interface et décodage des tuiles borné
complètent les corrections. Les sauvegardes conservent leur ordre.

Catalogue.18 termine les reçus durables des rappels ponctuels, leur réconciliation
et la réparation explicite du magasin natif. Les enregistrements illisibles sont
signalés et conservés pour récupération. QTV et les états Traficolor sont consultables
à la demande, avec heures et péremption par station ; aucune de ces mesures ne
crée d’alerte. Prévisions et routes en hiver ouvrent leurs pages officielles.

Les rayons de contexte et le moment de parole sont distincts. La vitesse plausible
de déplacement n’est pas assimilée à une limitation connue. Une donnée absente
reste inconnue ; une proximité géographique ne prouve pas l’appartenance à une voie.

## Données et cartes

| Source | Disponibilité dans les sources |
|---|---|
| Ministère de l’Intérieur | 3 185 points, 94 départements continentaux |
| SNCF Réseau | 14 891 passages à niveau routiers, 93 départements, dont 1 734 difficultés surbaissés explicites |
| OpenStreetMap | Import explicite par département des aménagements routiers reconnus |
| Bison Futé / DIR | Événements reconstruits ; mesures QTV et états Traficolor de 16 producteurs vérifiés, consultation datée |
| Geofabrik Shortbread | 21 archives continentales, environ 5,77 Go ; zoom natif 14 puis surzoom |

Prévisualisation avant import, nouveaux lieux désarmés, corrections existantes
conservées et provenance affichée. L’armement automatique par département concerne
la référence ministérielle ; les lieux personnels sont exclus des actions de masse.
Les groupes sur la carte ne fusionnent pas les objets ni leurs alertes.

Le trafic reste une consultation séparée, sans alerte automatique. Dates de
publication et de consultation, événements prévus, retraits et horaires particuliers
sont distingués. Un relevé périmé ou une mise à jour incomplète ne reste pas affiché
comme une carte actuelle. Seules les positions ou extrémités explicitement fournies
sont représentées ; aucun tracé routier n’est inventé entre deux extrémités.

Le fond hors ligne utilise des archives dédiées au téléchargement. La présence
du manifeste ne prouve ni leur transfert complet sur un téléphone ni leur fraîcheur.
Les catalogues ne constituent pas un recensement exhaustif de tous les POI français.

## Vérifications et limites

Catalogue.18 : **214 tests Flutter et 331 tests Kotlin**, analyse sans problème,
locales cohérentes et APK ARM64 compilé. Les 287 clips et 93 paquets SNCF
embarqués correspondent à leurs empreintes. Signature et paquet Android conservés :
`com.zaifears.locreminder.catalogue`.

Les essais synthétiques Android couvrent notamment reprise, approche, cues,
import désarmé et cycle de vie du lecteur. Le dernier APK installé sur POCO est
catalogue.13 : le ralentisseur est audible écran allumé, mais la lecture complète
en veille reste à revalider. Catalogue.18 attend un nouvel essai sur ce téléphone.
Bluetooth, autonomie, voies parallèles, confort visuel et suppression effective
du clignotement sur matériel restent à mesurer. Les tests et captures synthétiques
ne prouvent pas l’audition ni un trajet réel réussi.

Détails : [AUDIT.md](AUDIT.md) et [trafic](docs/data/TRAFFIC.md).

## Construire et tester

Flutter 3.47.x / Dart 3.13+, SDK Android 36, NDK 28.2 et JDK compatible avec Gradle
(cible Java/Kotlin 17). Exporter les deux variables vers le même SDK valide :

```sh
export ANDROID_HOME=/chemin/android-sdk
export ANDROID_SDK_ROOT="$ANDROID_HOME"
flutter pub get
flutter analyze
flutter test
(cd android && ./gradlew :app:testDebugUnitTest --console plain)
python3 tool/gen_locale.py --check
python3 -m unittest discover -s tool/artemis -p 'test_*.py'
python3 -m unittest discover -s tool/traffic -p 'test_*.py'
python3 -m unittest discover -s tool/catalogue -p 'test_railway.py'
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Les chaînes générées viennent de `locale/`. Ne pas modifier directement les fichiers
sous `lib/l10n` ou `android/app/src/main/res/values*/strings.xml`. Les sources publiques
et leurs empreintes sont conservées dans `data/catalogue/` et `assets/catalogue/`.

## Architecture et confidentialité

Les lieux et décisions d’alerte restent sur l’appareil ; le service natif de suivi
n’ouvre aucune connexion. Aucun compte utilisateur, publicité ou analytique.
Des services externes sont utilisés pour les fonds manquants, recherches d’adresse,
imports OSM, archives cartographiques et consultation nationale du trafic.
Le calcul d’itinéraire transmet départ et arrivée après accord explicite.
Les annonces courantes sont des fichiers locaux ; aucun LLM ne décide des alertes.
L’assistant conversationnel optionnel reste au backlog.

[PRODUCT.md](PRODUCT.md) décrit le périmètre ; [DESIGN.md](DESIGN.md) l’interface.
Ce dépôt public ne contient que le code, les données embarquées et leurs sources ;
les documents de pilotage n’y sont pas publiés.
Les avis externes sont des hypothèses à confronter au code et aux tests, sans vote
majoritaire ni assimilation à des essais humains. Les données personnelles du
téléphone et les traces de trajet sont exclues des dossiers de revue publics.

## Provenance

Fork de LocReminder, MIT, © 2026 Shahoriar Hossain ; licence conservée dans
[LICENSE](LICENSE). Identité RedAlert et développements du fork documentés dans Git.
Sources et attributions : [catalogue](docs/catalogue.md),
[licences](assets/catalogue/SOURCES_ET_LICENCES.md) et [trafic](docs/data/TRAFFIC.md).
Le fond affiche les attributions de ses producteurs. Pour les signalements techniques,
consulter [SECURITY.md](SECURITY.md).
