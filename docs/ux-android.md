# Ergonomie Android : critères et état

La base utilise déjà Material 3, des thèmes clair/sombre et un service de premier
plan pour la localisation. La modernisation est évaluée sur les parcours réels,
pas sur la seule version du framework.

Le placement du centre et les paramètres de l’alerte sont désormais deux étapes.
La carte conserve son propre espace visible : les réglages ne recouvrent plus
le centre visé. Une croix avec point central désigne les coordonnées retenues.
Les boutons de zoom et les pas de 1/5/10 m permettent une correction fine ;
l’échelle d’ajustement ne vaut pas précision géographique de la carte ou du GPS.
La rotation est désactivée pendant le placement pour garder les directions
cohérentes. Un relevé GPS est une action explicite. Le zoom seul n’efface pas
son incertitude ; un déplacement manuel l’efface.

Le bouton principal reste séparé des réglages secondaires défilants. Le retour
Android passe des réglages au placement sans perdre les valeurs. L’enregistrement
ne survient qu’à l’action explicite. Une réponse de géocodage devenue obsolète
ne peut plus nommer un autre centre.

Preuves : `test/location_picker_test.dart` avec le thème réel, écrans étroit et
paysage, texte agrandi, clavier, centre du viseur/carte, déplacement géographique
et coordonnées retournées, retour Android et relevé GPS. Les contrôles visés
par le test doivent avoir une surface tactile d’au moins 48 × 48 dp.

Points restant à contrôler sur appareil : import complet, édition, fonctionnement
écran éteint, restrictions HyperOS, comportement avec plusieurs points voisins.
La traduction du reste de l’application et l’audit complet d’accessibilité ne
sont pas terminés ; ce document ne certifie pas toute l’application.

Références primaires :
- https://developer.android.com/guide/topics/ui/accessibility/views/apps-views
- https://m3.material.io/components/bottom-sheets/guidelines
- https://github.com/material-components/material-components-android/blob/master/docs/components/BottomSheet.md
