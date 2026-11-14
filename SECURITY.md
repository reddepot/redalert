# Signaler un problème de sécurité

RedAlert traite une donnée sensible : la position de la personne qui l'utilise.
Un défaut qui expose cette position, qui permet à un tiers d'armer ou d'arrêter
une alerte, ou qui empêche une alerte de sonner est traité en priorité.

## Comment signaler

Utiliser **l'onglet *Security* → *Report a vulnerability*** de ce dépôt : la
discussion reste privée entre toi et le mainteneur, et le correctif peut être
préparé avant toute publication.

Merci de ne pas ouvrir d'*issue* publique pour un défaut exploitable avant
qu'un correctif existe.

## Périmètre

Sont dans le périmètre :

- la confidentialité de la position (stockage, permissions, journaux, réseau) ;
- l'impossibilité pour une application tierce d'armer, arrêter ou déclencher une
  alerte, ou de lire les lieux enregistrés ;
- le traitement d'un fichier de catalogue hostile (injection dans un libellé,
  Unicode bidirectionnel, caractères de contrôle, volume) ;
- tout comportement qui ferait manquer une alerte sans que l'utilisateur puisse
  le constater.

Hors périmètre : la qualité ou l'exactitude des données publiques de radars,
les limites connues documentées dans [AUDIT.md](AUDIT.md), et les défauts qui
exigent un appareil déjà compromis.

## Ce qu'un rapport doit contenir

1. la version (`pubspec.yaml`) et l'appareil ;
2. le scénario reproductible, avec les positions ou les fichiers utilisés ;
3. la preuve : sortie de commande, journal, ou fichier et ligne ;
4. l'impact concret pour la personne qui conduit.

## Engagement

Accusé de réception sous quelques jours, correctif ou réponse argumentée
ensuite. Ce projet n'a pas de programme de prime, et ne promet pas de délai
contractuel.
