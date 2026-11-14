# Préparation des données dynamiques

Étude et implémentation locale du 13 novembre 2026. Une consultation datée des
événements DIR est disponible dans les sources après catalogue.14. Aucun flux
dynamique ne déclenche d’alerte sonore ni ne crée de lieu armé.

## Sources vérifiées

La [page officielle Bison Futé](https://www.bison-fute.gouv.fr/donnees-sur-la-circulation-du.html)
référence des flux ouverts pour le réseau national non concédé : événements DIR,
mesures QTV et états Traficolor. Cette couverture ne constitue pas l’ensemble
des routes françaises ou des autoroutes concédées.

Le [catalogue du Point d’accès national](https://www.data.gouv.fr/datasets/etat-de-circulation-en-temps-reel-sur-le-reseau-national-routier-non-concede)
décrit les mesures agrégées, leur référentiel et leur cadence annoncée. Une cadence
annoncée ne prouve pas la fraîcheur d’un téléchargement particulier.

Points d’entrée HTTPS effectivement lus :

- `https://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/Evenementiel-DIR/grt/RRN/content.xml`
- Même répertoire : `index.txt` et fichiers numériques de mises à jour.
- `https://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/QTV-DIR/qtvDir.xml`
- Même répertoire : `refDir.csv` pour les références et positions déclarées.
- `https://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/TRAFICOLOR-DIR/`

Aucune position, préférence ou donnée de téléphone n’est jointe à ces lectures.
Aucun abonnement ni compte n’a été créé.

## Réponses observées

L’instantané événementiel reçu fait 2 720 065 octets, publication au
13 novembre 2026 à 04:24:34.471 UTC, SHA-256
`2b63798fa731214197137682bdeff8d0acd0377967a2691d54b77b4bcd73b8a3`.
Son inspection à 04:48 UTC donne 486 fiches :

| État des bornes de validité | Fiches |
|---|---:|
| Fin globale passée | 33 |
| Début global futur | 147 |
| Horaire récurrent ou période particulière à interpréter | 64 |
| Suspension déclarée | 1 |
| Dans les seules bornes globales | 241 |

La dernière ligne **ne signifie pas « 241 alertes actuellement utilisables »**.
Il reste la réalité de la situation, ses horaires, son sens, sa géométrie et les
mises à jour/annulations. Le millésime d’une fiche peut être ancien alors que
la publication qui la transporte est récente.

L’instantané annonce `updateMethod=snapshot` et la séquence 3662038. Le fichier
3662048 lu séparément annonce `allElementUpdate`, publication à 04:43:38.533 UTC.
Le numéro 3662049 indiqué par l’index a renvoyé 404 lors de l’essai : la sémantique
exacte de l’index et l’ordre de publication restent à valider. Aucun succès de
reconstruction complète n’est revendiqué.

Le QTV reçu fait 1 334 853 octets, publication à 04:30 UTC ; son référentiel CSV
fait 110 777 octets. Les champs de position début/fin sont présents. Il faut
interpréter leurs coordonnées et apparier les identifiants avant d’en tirer des
segments cartographiques ou des vitesses locales.

## Décision technique

1. Séparer la consultation dynamique des lieux permanents et de leur armement.
2. Valider l’instantané et toutes ses mises à jour comme un ensemble cohérent.
   Une lacune ou une annulation mal interprétée ne doit pas laisser une ancienne
   situation présentée comme actuelle.
3. Conserver publication, version et validité séparément. Définir et tester la
   péremption par famille de données.
4. Conserver les géométries déclarées ; ne pas fabriquer un point d’alerte depuis
   un segment ou un centre moyen sans décision fonctionnelle explicite.
5. Commencer par une couche consultable et datée, avant une alerte automatique.

L’inspecteur local constitue une première vérification de source. Il refuse les
dates sans fuseau, publications futures incohérentes, DTD, entités et fichiers trop
gros. Il ne déclare jamais une alerte opérationnelle.

```sh
python3 tool/traffic/inspect_snapshot.py /chemin/content.xml \
  --at 2026-11-13T04:48:00Z --output /chemin/inspection.json
python3 -m unittest discover -s tool/traffic -p 'test_*.py'
```

Les quatre tests distinguent publication récente, fiche expirée, événement futur,
horaire récurrent, suspension et intervalle invalide. Les téléchargements restent
hors du dépôt ; aucun instantané ancien n’est embarqué dans l’APK.


## Reconstruction et consultation — catalogue.15 en préparation

Le protocole est maintenant implémenté dans `datex_traffic_parser.dart` et
`traffic_repository.dart`, avec un écran « Trafic et événements » dans Conduite.
La consultation télécharge le flux national seulement après action ; aucun
paramètre de position, itinéraire, identifiant ou préférences n’est accepté.
L’état reste en mémoire ; aucun ancien instantané n’est livré dans l’APK.

### Bornes de séquence vérifiées

Le 13 novembre à 14:06:46 UTC, `index.txt` contient 3663120, avec une modification
à 14:06:42 UTC. Le fichier 3663119 existe, publié à 14:06:42.895 UTC ; 3663120
renvoie 404. Une nouvelle lecture de l’index conserve 3663120. L’observation
antérieure de 404 n’était donc pas la preuve d’une lacune interne : l’index annonce
le prochain numéro. C’est une interprétation de ce flux TIPI vérifiée par ses
réponses horodatées, distincte de la sémantique standard des publications DATEX.

Le numéro `feedType` du snapshot est le premier delta à lire. On inclut ce premier
numéro et on s’arrête à `index - 1`. Dans l’acquisition précédente, le fichier égal
à l’index a été publié pendant le téléchargement : son inclusion réussie ne
prouvait pas qu’il existait à la lecture initiale de l’index. Le test du client
corrigé vérifie explicitement cette borne exclusive.

`allElementUpdate` remplace toutes les fiches **de chaque situation transmise**,
sans effacer les situations absentes de cette mise à jour. Références primaires :
[modèle DATEX II](https://docs.datex2.eu/_static/data/v2.2/umlmodel/html/EARoot/EA1/EA1/EA26.htm),
[cycle de vie](https://docs.datex2.eu/_static/data/v2.2/umlmodel/html/EARoot/EA3/EA609.htm).
Les flags `end` et `cancel` retirent les fiches de la vue déclarée. Versions,
producteur et temps sont contrôlés ; un conflit ou une lacune interne invalide
l’actualisation entière, jamais une partie seulement. Les anciennes versions et
fins restent connues pendant la reconstruction pour empêcher leur résurrection.

### Présentation et fraîcheur

- Filtres Déclarés, Prévus, À vérifier et Terminés ; recherche locale par texte.
- Publication et consultation séparées. Refaire une requête ne rajeunit pas
  la date de la source. Au-delà de 15 minutes depuis la dernière publication,
  la carte est retirée et le relevé précédent est explicitement daté.
- Une actualisation échouée ou annulée retire aussi la validation de fraîcheur
  du cache précédent. Aucun résultat partiel ne le remplace.
- Réalité, confidentialité, occurrence certaine, validités et calendriers restent
  distincts. Les horaires particuliers ne sont pas supposés actifs ; les anciennes
  prévisions ne deviennent pas des faits quand leur heure arrive.
- Points et extrémités de segments conservés. La carte dessine ces positions avec
  des glyphes spécifiques A/B et des groupes de vue ; aucune ligne droite ni
  faux centre ne remplace la géométrie routière absente.
- Aucun lien vers le magasin d’alertes ou le pont d’armement natif.

Les bornes sont : 8 MiB par snapshot, 1 MiB par delta, 24 MiB par opération,
512 deltas et 60 secondes au total. Hôte HTTPS fixe, redirections refusées ;
requêtes successives annulables. XML sans DTD, profondeur et nombre d’éléments
bornés avant allocation du DOM ; calcul effectué hors isolate d’interface.
La montée minimale du SDK Dart à 3.13 correspond au package XML 7.1 utilisé ;
le Flutter local 3.47.1 dispose déjà de cette version.

### Validation

22 tests Flutter ajoutés : bornes inclusives/exclusives, remplacement par situation,
retraits, atomicité et conflits, XML, dates, géométrie, annulation/délai et UI.
La liste est paresseuse ; paysage et texte agrandi sont couverts. La carte disparaît
à péremption même sans nouvelle requête. L’audition et le POCO ne sont pas concernés.

Client réel avec son parseur en isolate : relevé terminé à **14:07:32.788 UTC**,
snapshot à 13:24:34.276, dernière publication à 14:07:20.628 ; deltas **3663030 à
3663121 inclus**, soit **92**. **631 fiches publiques réelles** : 309 déclarées
dans leur période, 170 prévues, 60 à calendrier non interprété, 56 retirées,
26 expirées, 9 incertaines et une suspendue. Cela ne prouve pas l’état physique
des routes ni l’exhaustivité du réseau français. Le premier essai du client,
avec mauvaise borne d’index, a échoué ; il n’est pas compté comme validation.

Inspection hors réseau de fichiers publics préalablement acquis :

```sh
../toolchain/flutter/bin/dart run tool/traffic/reconstruct.dart DIRECTORY HEAD_INCLUS ISO_TIME
```

Sonde réseau volontaire, distincte de la suite automatique :

```sh
REDALERT_PUBLIC_TRAFFIC_PROBE=1 ../toolchain/flutter/bin/flutter test tool/traffic/live_probe_test.dart
```

Elle produit seulement un bilan agrégé dans `build/traffic-validation/` ; aucun
accès Android. QTV, Traficolor, prévisions nationales et conditions hivernales
restent des familles à intégrer séparément. La disponibilité du réseau et la
sémantique d’index doivent rester surveillées ; aucune alerte trafic n’est livrée.


## QTV et Traficolor — catalogue.18

L’étude des mesures est désormais suivie d’une implémentation consultable :
`road_measurement_repository.dart`, `road_measurement_parser.dart` et
`road_measurement_screen.dart`. Accès depuis l’écran trafic, téléchargement
explicite national ou par producteur. Pas de position ou d’itinéraire accepté,
aucune alarme créée et aucune géométrie inventée depuis le référentiel projeté.

QTV joint les mesures aux identifiants CSV. La variante observée à 19 valeurs pour
20 colonnes est signalée ; CSV cité et identifiants `#` traités sans décalage muet.
Traficolor utilise la dernière publication du producteur choisi. Les publications
sans fuseau restent non qualifiées ; chaque mesure exige sa propre heure avec
fuseau. Les capteurs aux dates inexploitables sont comptés, pas supposés actuels.
Une vitesse moyenne reste distincte d’une limitation et le zéro échantillon ne
produit pas de vitesse ou état positivement connu.

8 MiB par XML, 2 MiB par référentiel et 1 MiB par index ; opération totale de
45 s, redirections refusées, annulation immédiate même avant les en-têtes HTTP.
Parseur hors isolate d’interface, XML borné avant DOM, aucune entité externe.
Le cache est dévalidé à l’échec ; péremption contrôlée à la seconde, sans
reconstruire la vue sur un tick stable. Les prévisions et routes en hiver ouvrent
les pages officielles sur action : aucune ingestion locale de ces pages prétendue.

Le client applicatif et son parseur ont réussi la sonde réseau sur QTV (1 397
stations) et les 16 producteurs Traficolor configurés (2 356 mesures exploitables,
31 dates écartées). Les données n’ont pas été embarquées. Bilan daté :
`validation/catalogue18-live-measures.json` ; références et limites dans
`../releases/catalogue18.md`. Émulateur : écran accessible via Artemis et erreur
hors réseau visible ; aucune audition ni validation POCO liée à ce test.

```sh
REDALERT_PUBLIC_MEASURES_PROBE=1 ../toolchain/flutter/bin/flutter test tool/traffic/live_measurement_probe_test.dart
../toolchain/flutter/bin/dart run tool/traffic/inspect_measurements.dart QTV_XML QTV_REFERENCE TRAFICOLOR_DIRECTORY
```
