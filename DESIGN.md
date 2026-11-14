# RedAlert — interface de conduite

Référence du 13 novembre 2026, catalogue.16 local. Les préférences produit actuelles
remplacent les anciennes indications graphiques de LocReminder.

## Direction

Univers automobile sobre : graphite, métal mat, surfaces claires neutres et
accent rouge discret. Le cadran du menu est décoratif ; aucune télémétrie ni
vitesse fictive n'y est affichée. Les chiffres de conduite viennent de positions
récentes ; l'absence de mesure est visible.

- Jour : fond `#F5F4F0`, cartes `#FCFCFA`, texte `#202830`.
- Nuit : fond `#14191F`, cartes `#1B222A`, texte `#E9EDF0`.
- Accent : bordeaux `#8F1734` de jour, rose clair contrasté de nuit.
- Surfaces secondaires gris acier. Le rouge ne teinte pas tous les fonds.
- Police système, chiffres tabulaires pour la vitesse ; aucun téléchargement de police.

## Hiérarchie du menu

1. **Conduite** : destination/itinéraire et réglages de carte.
2. **Mes lieux** : lieux enregistrés, ajout et catalogues/légende.
3. **Réglages** : alertes/voix, préférences générales.

La santé de la surveillance est regroupée dans un panneau bas. Journal et
informations de version sont secondaires. Les trois interrupteurs audio sont dans
« Alertes et voix », accessibles sans traverser les réglages d'apparence.
Les actions de catalogues ouvrent une liste distincte ; les confirmations existantes
d'activation sont conservées.

## Carte

- Carte dégagée, position centrale avec pause/reprise du suivi. Nord ou cap au choix.
- Point de position de 22 dp, contour de 2 dp ; flèche de 14 dp en déplacement.
  Le halo d'incertitude reste une distance de précision, indépendant du point.
- Commandes de 58 dp, icônes de 27 dp, fonds translucides, trait fin et ombre courte.
  Les cibles restent grandes malgré le point plus petit.
- Vitesse dans un instrument graphite compact ; valeur inconnue si le GPS est périmé.
- Échelle, attribution et vitesse sont empilées par le layout : aucun décalage fixe
  ne doit provoquer leur superposition lorsque le texte grossit.
- Les vues d’ensemble regroupent les points par cases ; toucher un groupe zoome
  ou ouvre sa liste. Les lieux et leurs coordonnées restent séparés.
- Couleurs et symboles de lieux distincts. Le bleu de la position n'est pas une catégorie.
- Zoom borné 2–19 ; le surzoom ne prétend pas ajouter des données cartographiques.

## Voix et vérification

L'aperçu nomme la catégorie sur son bouton (« Écouter : Ralentisseur ») et affiche
la phrase du manifeste embarqué. Un second bouton programme un essai dans cinq
secondes, annulable, pour laisser le temps d’éteindre l’écran. La sélection, les
explications et les boutons restent des éléments d’accessibilité distincts.
Le lecteur publie début, fin et état d’extinction à ces deux instants. Le résultat
revient après reprise ou recréation de l’écran, sans rejouer le clip. Les catégories
incohérentes et les statuts indisponibles restent non confirmés.
Un clic accepté ne prouve pas l'audition. Sur appareil, relire la catégorie visible
après sélection et avant de lancer le son ; ne pas réutiliser des coordonnées
après un déplacement du contenu.

## Contrôles visuels

`tool/preview_cockpit_test.dart` exporte de vrais composants Flutter en jour/nuit
avec carte illustrative et données synthétiques. Ce rendu ne valide ni une
position réelle ni une navigation. Les essais couvrent aussi le menu à 200 % de
texte et le paysage. Captures privées et réglages du téléphone exclus des aperçus.


## Contraste et stabilité — catalogue.16

Les fonds vectoriels locaux ont deux palettes explicites : papier clair et
routes foncées le jour ; graphite et routes claires la nuit. L’eau et les axes
principaux gardent leurs couleurs propres. Liseré des rues, textes de 12 dp
minimum pour leurs noms et halo renforcé. Les fonds raster reçoivent un seul
filtre de couche ; la nuit conserve leur chrominance au lieu de les rendre gris.

Le fournisseur vectoriel reste identique pendant les mises à jour de position,
les rafraîchissements de statut et le changement jour/nuit. Il est renouvelé
lorsque les archives prêtes changent ; leur ordre dans la réponse ne suffit pas.
Le test reproduit l’ancienne reconstruction inutile avant correction. Le confort
visuel et le clignotement effectif sur POCO restent à vérifier sur matériel.
Détails et aperçus de fixture : `docs/field-feedback/MAP_CLARITY.md`.


## Lisibilité après revue — catalogue.17

Les commandes gardent leur fond translucide, renforcé à 62–42 % ; le bandeau
d’approche est à 86 %. Les textes secondaires du compteur sont agrandis et sa
sémantique précise la limite du point et le dépassement. La limite connue d’un
point n’est pas une reconnaissance de la limitation de la route empruntée.
Le style choisi suit aussi la carte trafic. Les ticks sans changement de
fraîcheur ne reconstruisent plus la carte ; la péremption reste contrôlée.
La liste départementale nomme l’armement partiel.
