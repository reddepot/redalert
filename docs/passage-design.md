# Suivi de passage : décision technique

Le suivi reste local, sans journal de trajets ni service de calcul d’itinéraire.
Les coordonnées d’origine sont conservées ; les corrections restent prioritaires
lors d’une réimportation. Les observations de différentes sources ne sont pas
fusionnées automatiquement.

Trois approches ont été examinées : distance au point seule (insuffisante pour
avant/après), trajectoire locale courte (retenue), recalage sur un réseau routier
et un itinéraire (non implémenté, données de sens et de voie souvent manquantes).

Le suivi combine zone, tendance de distance et segment parcouru. Il ne confirme
ni la route empruntée, ni le sens auquel un équipement s’applique. Une route
parallèle très proche reste ambiguë. L’interface utilise des termes estimatifs.
Le seuil de 25 m exige une incertitude suffisamment petite ; une mesure absente
n’est jamais remplacée par une fausse mesure. Un franchissement entre deux
mesures peut être estimé par la géométrie du segment, avec indication explicite.

Les mesures périmées, répétées, désordonnées ou très imprécises n’avancent pas
l’état. Une longue interruption annule l’inférence de franchissement. Deux
mesures hors zone, avec marge et incertitude, réarment un passage. Les points voisins
sont suivis indépendamment. La présentation conserve le point principal pendant
son approche et son franchissement, puis donne la priorité au prochain point en
approche ; les points voisins restent visibles sur la carte. Une proximité
immédiate de 25 m peut prendre la priorité sur une approche plus lointaine.

La demande de mesures rapides ne garantit pas leur livraison. Le service de
premier plan et les permissions Android sont nécessaires. À 130 km/h, une
seconde représente environ 36 m : aucun déclenchement exact à 25 m n’est promis.

Sources primaires :
- https://developer.android.com/reference/android/location/Location
  (accuracy = estimation horizontale à 68 %, horloge monotone pour l’âge).
- https://developer.android.com/about/versions/oreo/background-location-limits
  (limites en arrière-plan et recours au service de premier plan).

Validation attendue : passages répétés, arrêt, demi-tour avant le point, route
parallèle, mesures sautées, GPS perdu, chevauchement de zones, réimportation après
correction et compatibilité des anciens rappels.
