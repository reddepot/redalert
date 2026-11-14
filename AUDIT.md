# Guide d'audit indépendant — RedAlert

Ce document s'adresse à un tiers — humain ou modèle de langage — chargé de
vérifier ce que l'application affirme faire. Il dit **où regarder**, **quoi
vérifier**, **comment falsifier** chaque affirmation, et **ce qui n'a pas été
vérifié**. Il ne remplace pas la lecture du code : il l'oriente.

Dernière mise à jour : 2026-11-12, version `2.1.1-catalogue.9+49`.

## 1. Objet et périmètre

RedAlert est une application Android qui prévient un conducteur avant un radar
fixe, un radar de feu rouge, un ralentisseur ou une zone dangereuse, à partir
d'un catalogue de points publics. Trois propriétés comptent plus que les
autres, et un audit doit d'abord les éprouver :

1. **L'alerte arrive** — au bon endroit, au bon moment, écran éteint comprise.
2. **Elle n'invente rien** — pas d'alerte sur un point non armé, pas de
   franchissement annoncé sans mesure, pas de vitesse affichée sans mesure.
3. **La position ne sort pas** — aucune donnée de déplacement transmise.

Hors périmètre de cet audit : la qualité juridique des données de radars, la
conformité au règlement Google Play, et la performance énergétique mesurée sur
une flotte d'appareils.

## 2. Reproduire l'environnement

```sh
export ANDROID_HOME=/chemin/vers/android-sdk   # obligatoire
# Depuis la racine du dépôt
flutter pub get
flutter analyze          # attendu : « No issues found! »
flutter test             # attendu : 110 tests
cd android && ./gradlew :app:testDebugUnitTest && cd ..   # 275 tests
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Versions de référence : Flutter 3.47.x, Dart 3.13, SDK Android 36, NDK 28.2,
Java 17. Une version différente peut produire d'autres résultats ; le dire
dans le rapport. Les chaînes traduites sont générées par
`python3 tool/gen_locale.py` (PyYAML) — ne pas éditer les fichiers générés.

## 3. Carte du code

| Sujet | Point d'entrée |
|---|---|
| Interface, carte, liste, import | `lib/screens/home_screen.dart` |
| Édition d'un point, placement | `lib/screens/location_picker_screen.dart` |
| Modèle de données | `lib/models/location_alarm.dart`, `poi_type.dart` |
| Stockage Dart + migration | `lib/services/alarm_repository.dart` |
| Import du catalogue | `lib/services/catalogue_importer.dart` |
| Armement par département | `lib/services/department_arming.dart`, `screens/reference_screen.dart` |
| Journal de diagnostic | `lib/services/passage_log.dart` |
| Pont vers le natif | `lib/services/native_bridge.dart` |
| Détection et alertes | `android/.../LocationWatchService.kt` |
| Machine à états du passage | `android/.../PassageTracker.kt`, `PassageCoordinator.kt` |
| Stockage natif | `android/.../AlarmStore.kt`, `ArrivalState.kt` |
| Écran d'alarme natif | `android/.../AlarmActivity.kt`, `res/layout/activity_alarm.xml` |
| Chaînes et traductions | `locale/fr.yaml` → `tool/gen_locale.py` |

Le point à comprendre avant tout : **deux moteurs**. Flutter possède la liste
complète et l'édition ; le service natif possède les points *armés* et décide
seul de sonner, y compris quand le moteur Flutter est suspendu. Toute donnée
ajoutée au modèle Dart doit traverser `native_bridge.dart`, `MainActivity.kt`
et `AlarmStore.persist`, sinon elle n'existe pas pour le service.

## 4. Affirmations vérifiables

Chaque ligne est une promesse du produit, l'endroit où elle se joue, et le
moyen de la mettre en défaut. Un audit utile en casse au moins une.

| # | Affirmation | Où | Comment la falsifier |
|---|---|---|---|
| 1 | Le service de localisation n'ouvre aucune connexion réseau | `LocationWatchService.kt`, `AlarmForegroundService.kt` | chercher `http`, `Socket`, `URL`, `OkHttp` ; tracer une session avec un proxy |
| 2 | L'alerte fonctionne sans le moteur Flutter | `AlarmStore.kt`, `LocationWatchService.kt` | tuer l'app (`am force-stop`), marcher dans un rayon armé |
| 3 | Être déjà dans la zone au démarrage ne sonne pas | `ArrivalState.kt` + test Kotlin | démarrer le service à l'intérieur d'une zone |
| 4 | Un passage répété sonne à chaque entrée, plusieurs fois par jour | `PassageTracker.kt`, tests | simuler entrée/sortie/entrée le même jour |
| 5 | Une mesure GPS périmée ou dupliquée n'avance pas l'état | `PassageTracker.kt`, tests | injecter des fixes identiques ou anciens |
| 6 | L'alerte de survitesse exige une limitation connue, tolère +8 km/h et se répète au plus toutes les 20 s | `LocationWatchService.kt` (`SPEED_MARGIN_KMH`, `SPEED_WARNING_INTERVAL_MS`) | rouler au-dessus de la limite, puis juste en dessous |
| 7 | Un lieu personnel n'est jamais modifié par une action de masse | `department_arming.dart` (`department != null`) | armer un département avec un lieu personnel actif |
| 8 | Une réimportation conserve les corrections locales | `catalogue_importer.dart`, `alarm_repository.dart` | corriger un point, réimporter le même fichier |
| 9 | L'import est borné et validé | `catalogue_importer.dart` (5 000 points, identifiants, libellés, coordonnées) | fournir un JSON hors bornes, un id inconnu, un libellé de 200 caractères |
| 10 | La pointe de l'épingle est sur la coordonnée | `alarm_card`/`home_screen.dart` + `test/map_pin_anchor_test.dart` | changer `Marker.alignment` ; le test doit échouer |
| 11 | L'APK publié est signé avec une clé de développement | `android/app/build.gradle.kts` | `apksigner verify --print-certs` |
| 12 | Aucun secret n'est versionné | tout le dépôt | `git grep -nIE "api[_-]?key\|secret\|password"` ; les seules occurrences sont des noms de *secrets* GitHub Actions |

## 5. Modèle de menace et surfaces sensibles

- **Confidentialité de la position.** Les lieux surveillés sont stockés dans
  `SharedPreferences` (deux copies : Dart et natif). Rien ne les envoie. À
  vérifier : aucune télémétrie ajoutée par une dépendance
  (`pubspec.yaml` → `flutter pub deps`).
- **Fichier de catalogue hostile.** Un JSON importé peut contenir des libellés
  affichés dans des notifications et sur l'écran d'alarme. Le parseur borne la
  taille (8 Mo), le nombre (5 000), la longueur des libellés (140) et rejette
  les caractères de contrôle. À éprouver : injection de texte, Unicode
  bidirectionnel, libellé imitant une alerte système.
- **Composants exportés.** `AlarmActivity` est `exported="false"`. Auditer les
  autres composants du manifeste (`receiver`, `service`) et vérifier qu'aucun
  tiers ne peut armer, arrêter ou déclencher une alarme.
- **Permissions.** Localisation précise et en arrière-plan, notifications,
  plein écran, démarrage automatique, batterie. Chacune doit être justifiée par
  un usage visible ; l'écran de fiabilité explique les réglages constructeur.
- **Signature et mises à jour.** La clé de développement locale n'est pas dans
  le dépôt ; une mise à jour installée par-dessus doit conserver la même
  signature. Un APK reconstruit par un tiers ne peut pas remplacer l'installé.

### Corrections issues des audits adverses (2026-11-12)

Deux relectures indépendantes ont trouvé la même faille, réelle : l'armement
par département n'atteignait pas le moteur natif, et la réconciliation au
démarrage lisait cette absence comme un déclenchement. Corrigé, avec six tests
supplémentaires sur la réconciliation et un cas Kotlin de points chevauchants.
Ont aussi été corrigés : la perte des transitions d'un second point, le stade
de 25 m souvent sauté à vitesse autoroutière, un bip marqué annoncé sans avoir
sonné, la survitesse déclenchée dans tout le disque de 1 km, et une position
périmée présentée comme actuelle.

Deuxième passe (12 novembre) : la géométrie d'approche et de franchissement a
été reprise. L'axe est désormais établi sur cinq secondes de déplacement
accumulé, la vitesse estimée fixe la fenêtre d'approche (`max(30 m, v × 2 s)`
au lieu de 25 m fixes), la tolérance de précision passe à 15 m, et le
franchissement se confirme sur l'écart latéral à l'axe (10 m) plutôt que sur
une distance brute, ce qui rejette les routes parallèles sans dépendre de la
précision. La cadence GPS se calcule sur le bord proche de la zone et non sur
le bord opposé. La matrice d'échantillonnage couvre 5 vitesses × 3 cadences ×
4 précisions ; la suite comptait alors 257 tests Kotlin.

La persistance de passage est ajoutée dans la version catalogue.8 : état courant
borné par point proche, observations géométriques et bips joués, sans historique
de trajet. Une interruption de plus de cinq secondes annule toujours l'inférence
de franchissement ; un changement de démarrage du téléphone invalide la sauvegarde.
Restent ouverts : armement automatique côté natif (le service ne connaît que
les points armés). Catalogue.9 demande un chien de garde à deux minutes
pour les passages armés (quinze minutes pour les autres rappels), sans garantie
de livraison sous Doze.

## 6. Ce qui n'est pas vérifié

À ne pas présenter comme acquis, même après une lecture du code :

- franchissement réel à vitesse autoroutière (le seuil de 25 m est estimé) ;
- sonnerie effective écran éteint pendant un long trajet, sur HyperOS ;
- alerte de survitesse en circulation réelle ;
- écran d'alarme natif déclenché pour de vrai (l'activité n'est pas exportable,
  elle ne peut donc pas être lancée par `adb`) ;
- sens de circulation : une route parallèle très proche reste ambiguë ;
- armement automatique : il ne s'exécute que lorsque l'application tourne, le
  service natif ne connaissant que les points déjà armés.

## 7. Journal des vérifications déjà faites

- Dernière suite locale : `flutter analyze` sans problème ; 110 tests Flutter ; 275 tests Kotlin.
- Sur appareil (POCO M7, Android 16 / HyperOS 3) : import de 859 points en
  pause, couleurs et icônes par type, édition du type, des repères et de la
  position, validation par la barre supérieure, armement d'un département
  (28 points) avec compteurs justes, journal de passage et son état vide,
  thème clair et thème sombre.
- Depuis un clone public du dépôt, sans fichier local autre que
  `ANDROID_HOME` (2026-11-11) : `flutter pub get`, `flutter analyze` (aucun
  problème), `flutter test` (101), `./gradlew :app:testDebugUnitTest` (12),
  `flutter build apk --release` — l'APK est produit. C'est la vérification
  qu'un auditeur peut refaire sans rien connaître de la machine d'origine.
- **Armement vérifié sur appareil (12 novembre)** : depuis l'écran *Points de
  référence*, armer un département (39 points) fait démarrer le service natif —
  ce qui ne peut arriver que si le magasin natif n'est plus vide. Après un
  arrêt forcé et une relance, le service redémarre seul et les points restent
  armés : l'ancienne réconciliation les aurait désarmés avec un faux « déjà
  sonné ». C'était le défaut P0 des audits.
- Historique réécrit le 2026-11-11 (retrait d'un APK de 53 Mo) : clone public
  à 2,8 Mo, 216 commits conservés, `flutter analyze` et les 101 tests
  reverifiés sur l'arbre réécrit.
- Correctifs issus de ces essais : ancrage de l'épingle (décalage de 44 px),
  `MaterialLocalizations` manquantes en français (les champs de texte
  plantaient), lisibilité des épingles en pause sur la carte nuit.

### Reprise après destruction du processus (12 novembre, catalogue.8)

- Base catalogue.8 : 269 tests Kotlin et 107 tests Flutter ; analyse Flutter sans problème.
- Sur POCO : instrumentation dédiée, positions synthétiques et préférences
  isolées. Une première exécution sauve une approche ; après `am force-stop`,
  une seconde restaure depuis le disque et vérifie franchissement, bips déjà
  joués et refus d'inférence après une interruption longue. Les deux exécutions
  renvoient `INSTRUMENTATION_CODE: -1` (`Activity.RESULT_OK`).
- APK release catalogue.8 installé, paquet de test retiré. Après arrêt forcé
  et relance, service de surveillance actif au premier plan, permissions
  conservées. Le magasin contenait 39 points armés avant la mise à jour.
- Cette preuve synthétique ne valide ni la route réelle, ni le son en circulation.

## 8. Format d'un rapport

Pour être exploitable par le propriétaire, un rapport cite :

1. l'affirmation visée (numéro du tableau §4) ou le défaut observé ;
2. le fichier et la ligne, ou la commande exacte et sa sortie ;
3. le scénario qui reproduit le problème (positions simulées, état initial) ;
4. la gravité : *bloquant* (alerte manquée ou fausse), *majeur* (donnée
   corrompue), *mineur* (lisibilité), *documentation* ;
5. la correction proposée, avec le test qui échoue avant et passe après.

Les audits sont indépendants : ne pas supposer qu'une affirmation est vraie
parce qu'un test existe — lire le test, puis essayer de le contourner.

## 9. Revues du 12 novembre

Le premier cycle porte sur les sources GitHub épinglées, sans données appareil.
Avis, manifestes et décisions : `docs/reviews/2026-11-12/cycle-1/`. Les réactions
utilisateur sont des simulations de personas fictifs, pas une validation terrain.
Les questions juridiques et réglementaires sont exclues de ces consultations.
Les sorties incomplètes ne constituent pas des avis finalisés.

Le second et dernier cycle examine `7c51016` :
`docs/reviews/2026-11-12/cycle-2/`. Qwen n'a pas livré de rapport final sur ce
cycle, ce qui n'est pas une approbation. Les deux régressions de persistance
et de réconciliation nouvellement couvertes échouent avant leur correction
puis passent. La version catalogue.9 a ensuite été installée et son service de surveillance observé actif sur appareil ; cela ne vaut pas validation en trajet réel.

## 10. Carte, France et voix — catalogue.10

Le périmètre supplémentaire est décrit dans `docs/roadmap/VALIDATION.md` : nord
en haut, zoom/échelle, catalogue continental de 3 185 points, rayons adaptés,
phrases françaises embarquées et téléchargement des plans régionaux.
Les propositions de données et d'IA sont dans `docs/roadmap/IDEES.md`.

Les preuves locales comprennent le rendu d'une vraie tuile Shortbread sans
fournisseur réseau et la fusion de dictionnaires de régions distinctes. Elles
ne démontrent pas à elles seules une audition effective, un transfert national
achevé ou un comportement routier sur appareil. Les limites du surzoom et la
fraîcheur non garantie des archives sont explicites dans le dossier.


## 11. Conduite, destination et dangers vocaux — catalogue.11

Version `2.1.1-catalogue.11+51`, base `4770b82`. Exigences fonctionnelles,
changements et limites : `docs/field-feedback/VALIDATION.md`.

- **135 tests Flutter**, **286 tests Kotlin** réussis ; analyse Dart sans problème,
  locales générées cohérentes et compilation release pour les trois architectures.
- Deux régressions reproduites avant correction : l'ancien modèle ne migre pas
  le mode d'un ralentisseur ; le détecteur complet empêche une annonce alignée
  au-delà de 250 m malgré sa politique temporelle. Les mêmes cas passent après
  correction. Les segments parallèles et d'éloignement restent exclus des annonces
  anticipées ; les contrôles de franchissement ne sont pas élargis.
- APK ARM64 : **25 486 996 octets**, SHA-256
  `d12e2127a9da5343b9a43aca68af02e9d91cd87f350b3b57d98cfd5bc572882e`.
  Les 268 clips du manifeste sont présents et non compressés dans l'APK, donc
  compatibles avec l'ouverture par AssetFileDescriptor. Cette vérification ne
  prouve pas l'audition.
- Artemis épinglé et installé dans un environnement isolé : contrat factice,
  trois tests de bornage de séance, puis transport réel sur émulateur Android 15
  ARM64. Carte/menu, position synthétique sans lieu armé et création d'un
  ralentisseur en mode passage observés. Aucun compte, aucune position réelle,
  aucun appel de modèle et aucune manipulation du POCO. Protocole et limites :
  `docs/testing/ARTEMIS.md`.
- Le service de routage Dart a aussi obtenu et validé un tracé de 196 points
  auprès de FOSSGIS/OSRM avec deux repères publics synthétiques, sans donnée de
  déplacement personnelle. Cela valide cette requête réseau, pas le guidage terrain.
- L'émulateur est arrêté après ce parcours. L'audition, l'écran éteint, le Bluetooth,
  le guidage en déplacement et les mesures en circulation restent à vérifier ; ils ne sont
  pas déduits des suites unitaires ni des captures.


### Complément sur appareil — catalogue.11

Mise à jour installée sur POCO pendant une fenêtre explicitement renouvelée,
sans effacement. Tuiles visibles et état de position récente observés. L'aperçu
radar fixe est confirmé clairement audible. Pendant la prolongation, le service
de surveillance reste présent et au premier plan écran éteint.

Le test d'annonce de ralentisseur écran éteint est **non validé** : la catégorie
entendue ne correspondait pas à celle demandée. Une première capture d'état audio
précédait l'extinction effective ; la suivante ne montrait plus de lecteur actif.
Ces relevés ne prouvent donc pas une lecture de l'annonce demandée pendant la
veille. Le pilotage doit vérifier la catégorie visible avant chaque lecture.
Aucune position synthétique n'a été injectée dans le téléphone, aucun lieu de
test ajouté, aucune capture privée publiée. Les fenêtres sont terminées.

## 12. Interface automobile — catalogue.12

Version locale `2.1.1-catalogue.12+52`, paquet inchangé. Détails et état matériel :
`docs/field-feedback/COCKPIT.md`.

- Menu conduite/lieux/réglages, écran audio dédié, surfaces graphite et neutres,
  commandes translucides ; point de position de 22 dp.
- Aperçu vocal avec catégorie explicitement nommée dans le bouton et phrase issue
  du manifeste. Le test choisit un ralentisseur et vérifie le type transmis au
  natif. Le moteur d'alerte Kotlin reste celui de catalogue.11.
- **138 tests Flutter réussis**, analyse sans problème, locales cohérentes.
  Contrôle complémentaire du paysage, du texte agrandi et de l'absence de
  chevauchement entre vitesse/attribution/échelle ; rendu synthétique jour/nuit.
  Les 286 tests Kotlin de catalogue.11 restent la référence du moteur inchangé.
- APK ARM64 compilé : **25 487 064 octets**, SHA-256
  `254aa43d7a23a119abfd3440525284057a7caaecfd6417b4c0575ab6e1c0c815`.
  Les 268 clips sont présents, non compressés, et leurs empreintes correspondent
  toutes au manifeste embarqué. Paquet/version contrôlés : catalogue.12, code 522.
- APK et aperçu disponibles localement. Catalogue.12 n'est pas installé sur le
  POCO. Aucune publication GitHub supplémentaire, conformément à la demande.


## 13. Données routières et contrôles vocaux — catalogue.13

Version locale `2.1.1-catalogue.13+53`, base `d4911e6`. Dossier détaillé :
`docs/field-feedback/ROAD_DATA.md` ; protocole Android : `docs/testing/ARTEMIS.md`.

- PN SNCF embarqués : 14 891 références, 93 départements continentaux, dont
  1 734 difficultés surbaissés explicites. Classes 10–21 et filtres ; exclusions
  et millésime traçables. Deux générations hors réseau produisent les mêmes
  empreintes pour les 95 fichiers de catalogue et de bilan.
- Import OSM explicite et borné, provenance persistée. Requête publique testée :
  140 éléments, 136 propositions et trois exclusions ; aucun lien avec une
  position personnelle. Les réponses partielles sont refusées.
- Nouveaux imports désarmés même avec suivi automatique de département.
  Contre-exemple : le test échoue sur `d4911e6` puis passe avec la restriction de
  l’automatisation à la référence ministérielle. Les corrections manuelles restent
  prioritaires. Recouvrements radar/PN examinés sans fusion de sens différents.
- Sélection des points visibles et groupes d’ensemble testés sur 18 000 lieux ;
  aucun effet sur le moteur natif. Performance sur POCO encore à mesurer.
- **156 tests Flutter**, **289 tests Kotlin**, quatre tests du générateur SNCF et
  six tests de bornage/ciblage Artemis réussis. Analyse Dart sans problème ;
  chaînes générées cohérentes. La signature et le package Android sont conservés.
- Parcours Artemis sur AVD AOSP isolé : sélection de catégorie relue, refus d’une
  catégorie absente, fin du clip ralentisseur observée écran éteint. Import
  effectif de 280 lieux SNCF désarmés, avec provenance ; magasin natif inchangé.
  Le dernier bouton respecte désormais la marge de navigation système.
- Parcours GPS synthétique : 43 positions autour du point de fixture, approche,
  deux annonces confirmées démarrées, franchissement puis éloignement dans le
  checkpoint. La tentative préalable sans réception active n’est pas un succès.
  Aucune preuve d’audition ni de comportement routier réel n’est déduite.
- APK ARM64 : **26 550 121 octets**, code **532**, SHA-256
  `23bfd72bc9e2efe32d0129ab631c09c3912fe4dd2dd196f8a2a5838c6875cf19`.
  Les **287 clips** sont présents, non compressés, et conformes à leurs empreintes.
  Les 93 paquets départementaux sont vérifiés dans l’APK contre leur index.
- Émulateur et serveur ADB de test arrêtés. Catalogue.13 reste local ; le POCO
  conserve catalogue.11. Aucune publication GitHub ni consultation LLM payante.


## 14. Préparation du trafic — hors APK

Premier examen des sources DIR/QTV/Traficolor : `docs/data/TRAFFIC.md`.
L’inspecteur local DATEX II distingue les bornes passées/futures, suspensions et
horaires non interprétés. Quatre tests réussis ; aucune alerte opérationnelle
déclarée. L’instantané public lu contient 486 fiches, dont 33 à fin globale passée,
147 futures et 64 à calendrier particulier. Le numéro final de l’index a renvoyé
404 ; la reconstruction avec mises à jour/annulations n’est pas validée. Aucune
couche trafic ajoutée à catalogue.13. Aucune donnée de téléphone ou de trajet
n’a été envoyée pendant cette étude.


## 15. Installation POCO — catalogue.13

Mise à jour installée et lancée sans effacement pendant une nouvelle disponibilité
explicitement accordée. L’annonce spécifique ralentisseur est confirmée audible.
Le premier essai d’extinction ne valide pas la veille : le lecteur avait terminé
avant l’extinction et l’observation utilisateur ne confirme pas un écran noir.
Un second essai synchronise le clic et la commande de veille dans la même shell
locale ; Android passe en sommeil puis y reste pendant 20 secondes. L’observation utilisateur confirme alors un écran noir mais une annonce coupée.
Le callback final n’a pas pu être lu : le verrouillage système masquait
l’application, même après sa remise au premier plan. Le service de surveillance
est ensuite retrouvé au premier plan ; les relevés disponibles ne suffisent pas
à établir la cause de la coupure. Aucun succès de lecture en veille n’est déduit
du seul état Android. Aucune position synthétique ni lieu de test
n’a été ajouté au téléphone. Le fichier de séance privé et la capture de contrôle
sont supprimés après la fenêtre de test.


## 16. Essai vocal en veille — catalogue.14 local

La coupure POCO du §15 reste à expliquer et à retester. Le travail local corrige
une interruption reproductible de l’aperçu lors d’une recréation Activity ; cela
ne prouve pas qu’il s’agissait de la cause sur le téléphone. Le lecteur de test
utilise désormais le contexte Application et un état partagé par le processus.
Un essai de cinq secondes est annulable, avec verrou CPU borné pour le compte
à rebours et récupération du résultat au réveil. Aucun changement du détecteur
ni de ses règles de déclenchement.

- Comparaison Android instrumentée, APK debug non minifiés : lecture confirmée
  commencée avant recréation ; ancienne version interrompue, nouvelle terminée.
- APK release final sur AVD AOSP API 35 : écran en sommeil avant l’échéance,
  démarrage 45 ms après celle-ci, callback de fin après 2 444 ms de lecture ;
  affichage `STATE_OFF` et non interactif au début comme à la fin. Aucun son
  humainement entendu sur l’émulateur n’est revendiqué.
- Diagnostic relu écran verrouillé via `voice-status`, sans capture ni donnée
  de trajet. Schéma et champs limités ; erreurs audio distinctes de la fin.
- Correction d’accessibilité : la carte ne fusionne plus le sélecteur avec ses
  paragraphes. Artemis refuse les gros blocs fusionnés et les cibles déplacées
  entre deux lectures. Test reproduit avant correction puis réussi.
- **162 tests Flutter, 297 Kotlin et 12 tests Artemis Python** réussis ; analyse
  sans problème et contrat factice Artemis réussi, sans appel de modèle.
- APK code **542**, **26 550 233 octets**, SHA-256
  `441336a0da80943071daa374bbaf7d4b410310e29e9896c1e5225606ae6b3cff`.
  287 clips non compressés et 93 paquets départementaux conformes aux empreintes.
- Émulateur et serveur isolé arrêtés après restauration de leurs réglages.
  Aucun accès POCO supplémentaire ni publication GitHub. Limites et protocole :
  `docs/field-feedback/VOICE_SLEEP.md`.


## 17. Consultation des événements DIR — sources catalogue.15

Reconstruction complète du snapshot et des deltas avant publication en mémoire.
Les deux bornes de l’index TIPI sont maintenant vérifiées : premier delta inclus,
index final exclu. Contrôles de versions, fins/annulations et remplacement par
situation, sans perte des autres situations. Consultation dédiée, filtres et
carte de géométries déclarées ; aucun armement ni alerte trafic. Péremption de
15 minutes et retrait de la carte après échec/annulation.

22 tests ajoutés réussis, dont annulation, atomicité, calendrier, géométrie et UI
paysage/texte agrandi. Client réseau réel et parseur en isolate vérifiés : 92 deltas,
631 fiches, dont 56 retirées. Le premier essai à mauvaise borne est exclu des
succès. Le bilan complet et les limites sont dans `docs/data/TRAFFIC.md`.
Aucun accès au téléphone, aucune donnée de trajet transmise. Le code doit encore
être consolidé avec les corrections de contraste et clignotement de carte.


## 18. Carte et consolidation — catalogue.16

Fournisseur vectoriel recréé à chaque build : contre-exemple observé avant
correction puis réussi avec fournisseur stable par révision triée. Le moteur
cartographique effaçait ses tuiles lors de ce remplacement ; c’est une cause
vérifiable de rechargement, sans prétendre expliquer toutes les transitions
visuelles sur le téléphone. Palettes jour/nuit, liserés et contraste raster revus.
Détails : `docs/field-feedback/MAP_CLARITY.md`.

**185 tests Flutter** réussis, analyse sans problème, locales cohérentes. APK release
compilé, code 562, 26 747 898 octets, SHA-256
`da8b82bb75a6ab4e25c030c97e0c2263a46441b2eedadae6500c737405e18b32`.
Signature identique, 287 clips et 93 paquets vérifiés. Pas d’installation POCO.
Le lot natif inchangé garde la référence de 297 tests du §16.

Pause propre demandée par l’utilisateur après ces contrôles, pour recharge du
forfait. Reprise et futur cycle GitHub/revues/POCO consignés dans `HANDOVER.md`.
Aucun avis Kimi/Gemini de ce nouveau cycle ni publication supplémentaire à cette
étape. Émulateur arrêté ; Caffeinate conserve son échéance initiale de 48 h.


## 19. Revues et corrections consolidées — catalogue.17

La PR #10 a fourni la source publique épinglée `00e9035` aux avis indépendants.
Trois rapports Gemini Carbon, trois Grok latest (`x-ai/grok-4.7`) et un complément
usabilité MiniMax latest sont finaux. Kimi n’a pas rendu de rapport exploitable,
y compris sur contexte réduit ; Gemini latest Hydrogen n’a pas passé le test
neutre. Aucun de ces échecs n’est présenté comme validation ni contourné par un
ancien modèle. Chaque axe part d’un contexte neuf, sans ancien avis. Seul le code
public nécessaire est transmis, sans donnée du téléphone ; juridique et
réglementaire explicitement exclus. Pas d’appel GPT payant d’autoévaluation.
Sources, limites, coûts déclarés/estimés et arbitrages :
`docs/reviews/2026-11-13/catalogue16/`.

Corrections : historique et géométrie conservés pendant un cap inapplicable,
cadence vocale par point, avertissement de vitesse indépendant de la cible
présentée et revérifié avant lecture. Routage en flux borné/annulable et progression
ancrée : les contre-exemples de flux surdimensionné et de boucle échouaient avant
correction. Contraste, textes, styles et reconstructions UI revus.

Les arrivées ne prennent plus une attente pour une précision accrue : distance
et incertitude rapportée doivent tenir dans le rayon, sans plancher de 500 m ni
repli à 3 000 m. Quatre tests de politique. Les bips ont une séquence exclusive,
un focus et des callbacks annulables ; sept tests couvrent notamment arrêt,
refus de focus et callback ancien. L’aperçu de sonnerie est asynchrone et borné.
Les imports/sauvegardes lourds quittent l’interface, avec ordre des écritures testé.
Les tuiles sont bornées avant allocation et pendant décompression/fusion, deux
traitements à la fois ; erreurs typées et annulations vérifiées. Les lieux
personnels portant un département restent exclus des actions groupées.

Validation finale : 193 tests Flutter et 319 Kotlin, analyse sans problème et
locales cohérentes. APK ARM64 code 572, 26 878 970 octets, SHA-256
`a63c2572147371e96da98fd542fb2d8c05770258655aae7fb5ca9ca5b1e7b4ed`.
Signature identique à catalogue.16 ; 287 clips et 93 paquets vérifiés.
Le bilan de l’APK signé est conservé localement à côté de l’artefact. Aucune installation ni manipulation POCO pendant ce lot. Les preuves
unitaires ne valident pas audition, Bluetooth, autonomie, position réelle ou
suppression du clignotement sur matériel. L’implémentation retenue précède le
prochain essai, comme demandé.


## 20. Clôture des chantiers engagés — catalogue.18

Le jalon .17 ne clôturait pas toutes les missions. Ont été repris : reçus des
rappels ponctuels, récupération native, diagnostic des enregistrements Flutter
illisibles, capacité globale et consultation QTV/Traficolor. Suivi exhaustif :
`docs/WORK_LEDGER.md`, version : `docs/releases/catalogue18.md`.

Le reçu natif et le retrait d’un rappel unique sont atomiques ; acquittement par
jeton après sauvegarde Flutter, pas de désarmement sur absence seule. Le même ID
réarmé ne perd pas son nouveau reçu sur un ancien acquittement. Données corrompues
préservées et mutation normale bloquée jusqu’à réparation confirmée. Les autres
points natifs valides sont conservés et leur surveillance ne s’arrête pas avec le
dernier rappel de la liste Flutter.

**214 tests Flutter et 331 Kotlin**, analyse sans problème, locales cohérentes ;
12 tests Artemis Python et quatre tests d’inspection trafic. Stockage synthétique
à 20 000 points : 2 888 891 caractères, encodage 73 ms, décodage 86 ms, cent lectures
en cache sous une milliseconde pour ce passage JVM hôte ; aucune extrapolation
au téléphone. La dépendance JSON de test est distincte de l’API Android réelle.
La borne de reçus couvre aussi les identifiants valides échappés à la sérialisation.

Sur l’AVD AOSP Android 15 ARM64 : reçu écrit, arrêt forcé de l’application,
relecture dans un nouveau processus, réarmement, protection contre acquittement
ancien, réparation avec sauvegarde des octets précédents et conservation des
lignes valides. Préférences de fixture isolées, sans accès au magasin personnel.
Artemis ouvre le nouvel écran de mesures et observe son erreur hors réseau ;
aucun modèle autonome. Émulateur et serveur isolé arrêtés, capture temporaire
retirée. Aucun accès ni installation POCO pendant ce lot.

Sonde du véritable client applicatif : QTV 1 397 stations, seize producteurs
Traficolor et 2 356 mesures exploitables ; 31 dates capteur écartées, dates de
publication non qualifiées conservées comme telles. Annulation, tailles, erreurs,
dates et interface sont testées. Aucune alerte trafic automatique ni image de route
reconstituée depuis une droite entre points. Les liens prévisions/hiver restent
une consultation du producteur.

L’ancien lanceur d’avis à modèles figés est désactivé avant lecture d’une clé ou
appel réseau. Pas de nouvel appel GPT payant. Un test neutre Anthropic direct
Opus5 effort max a été refusé pour authentification, sans code transmis. Le
signalement OpenAI a un brouillon minimal privé préparé, sans transmission ni
pièce privée ; aucun outil d’envoi de feedback n’est exposé dans cette session.
