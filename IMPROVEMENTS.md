# Axes d'amélioration

État des lieux honnête : ce qui est volontairement imparfait, ce qui manque,
et les idées qui rendraient le saver encore meilleur. Classé par impact.

## Dette assumée (issue des revues de code)

- **`MACOSX_DEPLOYMENT_TARGET = 26.4`** — rien dans le code ne l'exige ; le
  bundle refuse de charger sur des macOS plus anciens pour rien.

Réglées le 2026-08-03 : topologie 2D des écrans (adjacence par bords réels,
relais vertical des montées), remise des gaz quand la piste est occupée (plus
de file invisible), `make install` en Release, PRNG seedable (SplitMix64,
rendus déterministes par seed).

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
