# Axes d'amélioration

État des lieux honnête : ce qui est volontairement imparfait, ce qui manque,
et les idées qui rendraient le saver encore meilleur. Classé par impact.

## Dette assumée (issue des revues de code)

- **Espace colorimétrique** — `PixelCanvas.cgColor` construit des couleurs en
  generic-RGB dans un contexte deviceRGB : le même hex rend légèrement différent
  selon le helper qui dessine (mesuré : jusqu'à +26 sur un canal). Toute la
  validation visuelle a eu lieu à travers ce pipeline, donc le « corriger »
  changerait d'un coup toute la palette approuvée. À faire un jour comme un
  changement délibéré : unifier vers deviceRGB puis re-valider les rendus.
- **Dispositions verticales d'écrans** — `ScreenTopology` modélise une bande
  gauche→droite (tri sur `minX`). Un moniteur posé au-dessus du laptop obtient
  un slot arbitraire et le relais gauche/droite ne correspond plus à la
  géométrie physique. Modéliser un graphe d'adjacence 2D si le besoin arrive.
- **Arrivée pendant piste occupée** — si un avion traverse vers l'écran
  principal pendant qu'un autre occupe la piste, il patiente en file (max 2) et
  entre avec du retard : la continuité visuelle du bezel est perdue dans ce cas.
  Piste : le faire entrer quand même en approche et orbiter/remettre les gaz.
- **`make install` livre le build Debug** — 2-3× plus lent par frame que
  Release. Ajouter une target `install-release`.
- **`MACOSX_DEPLOYMENT_TARGET = 26.4`** — rien dans le code ne l'exige ; le
  bundle refuse de charger sur des macOS plus anciens pour rien.
- **Aléatoire non seedable** — le trafic utilise l'aléatoire stdlib. Sans
  graine, impossible de synchroniser deux instances ou de reproduire un bug de
  trafic exactement. Passer à un PRNG seedable si besoin.

## Idées de fonctionnalités (par ordre d'envie probable)

- **Feuille de configuration** (`configureSheet`) : densité du trafic, vitesse
  du taxi, durée de la pause parking, choix des livrées, intensité des étoiles.
- **Cycle jour/nuit lent** — l'ambiance nuit permanente était un choix v1 ; un
  cycle de 10-15 min (aube → jour → crépuscule → nuit) réutiliserait le système
  de bandes de ciel tel quel.
- **Météo** — pluie/neige en pixels, halos de feux élargis par temps de pluie,
  brouillard qui voile la rampe d'approche.
- **Plus de trafic au sol** — follow-me car, camion de carburant, bus qui
  circulent pendant les pauses ; feux de taxiway bleus animés.
- **Diversité aérienne** — hélicoptère (stationnaire puis translation), petit
  monomoteur à hélice, montgolfière lointaine au lever du jour.
- **Étoiles filantes** rares, satellites qui clignotent en traversant lentement.
- **Phase de lune réelle** — dessiner la lune selon le calendrier lunaire du
  jour (petit calcul, grand effet).
- **Sons** — non. C'est un économiseur d'écran.

## Qualité de vie dev

- Un script `make gif` qui rend N frames et assemble un GIF de la scène pour
  le README (les captures statiques ne vendent pas le mouvement).
- Étendre `runway_check` avec des invariants de non-régression sur les durées
  (fenêtres min/max par phase) pour attraper une constante dérèglée.
- Un check de continuité automatisé du handoff (comparer la position du sprite
  des deux côtés de la frontière à ±1 px) pour remplacer l'inspection manuelle.
