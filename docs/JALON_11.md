# Jalon 11 : lieux urbains et côtiers (à reporter dans la doc)

Les fichiers `GAME_DESIGN.md` et `WORLD_GEN.md` n'ont pas pu être régénérés (trop volumineux, non accessibles) : coller les passages ci-dessous.

## WORLD_GEN.md
**§4.2 Villes**, ajouter :
- **Zonage urbain (jalon 11)** : `lot_zone(cellule)` = `center` / `mid` / `outskirts` selon la distance de Tchebychev au centre, en pourcents entiers du rayon (`zone_limits`, 50 / 75). Une parcelle qui reçoit un bâtiment (`house_chance`) reçoit un **bâtiment de ville** avec la probabilité `zones[zone].urban_chance` × `size_urban_scale[taille]` (plafond 0,95), sinon une maison. Le bâtiment est tiré dans `zones[zone].buildings` (`plan`, `weight`, `min_radius`). Tirages : `mix(seed, LAYER_MAPGEN, x, y, 3)` (urbain ou maison) et `4` (quel bâtiment) ; les indices 0 à 2 restent ceux des maisons. Hameaux : maisons seulement. Un bâtiment de ville occupe UNE cellule.

**§4.5 Lieux spéciaux**, ajouter : `port` (3×2, coast, accès route) et `airport` (6×2 : piste 6×1 + hangars, terminal, tour, aires ; coast, accès route ou piste). Plans dans `mapgen/urban.json` (14 `urban_*`, `port_*`, `airport_*`).

**§5 Données**, ajouter la ligne : `mapgen/urban.json` | bâtiments de ville, port, aéroport.

**§9 Jalons** : jalon 11 « Urbain » = fait (14 bâtiments de ville + port + aéroport = 16). Reste : étages et toits (jalon 8), loot (jalon 6).

**Tests (§10)** : `test_jalon11.gd`.

**Limites** : port non orienté vers la mer (le quai peut tourner le dos à l'océan ; la rotation suit la route) ; pas d'unicité (plusieurs mairies possibles dans une grande ville) ; pas d'étages ; ni la mini-carte ni le mode regard n'affichent encore le type de bâtiment (`SettlementMap.lot_plan_id(cellule)` est prêt pour ça).

## GAME_DESIGN.md
- « Monde procédural » / Statut : jalons 1-5, 9, 9b, 10, **11** faits ; restent 6 à 8, 12 à 15.
- Architecture `worldgen/` : `settlement_map` gère aussi le zonage urbain ; `mapgen_db` charge aussi `urban.json`.
- Tests : ajouter `test_jalon11`.
