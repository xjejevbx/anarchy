# Jalon 12 : routes (à reporter dans la doc)

`GAME_DESIGN.md` et `WORLD_GEN.md` ne sont pas régénérés : coller les passages ci-dessous.

## WORLD_GEN.md
**§4.5 Lieux spéciaux**, ajouter :
- **Accès `on_road` (jalon 12)** : lieu posé SUR une cellule de route entre villes (empreinte d'une cellule, accès seul). Le plan se superpose à la chaussée (ses `.` gardent le terrain de la route) et tourne dans l'axe réel de la route : `rot` 0 ou 2 pour une route est-ouest, 1 ou 3 pour une route nord-sud. La cellule reste `ROAD` ; `SettlementMap.cell_plan()` renvoie le plan.
- **Placement par candidats**, APRÈS les autres lieux : cellules de route de la région (`RouteMap.region_cells`), triées par (x, y), puis filtrées (route droite, hors bordure de région, aucune piste voisine, espacement `ROAD_SPACING` = 4, biome, climat, distance à la ville, `road_site`) ; une est tirée par `mix(seed, LAYER_SPECIAL, rx, ry, hash(id))`. Ne lit jamais `road_mask()` ni une autre région (évite la récursion de `region_data`).
- **`road_site`** : `any` (défaut), `bridge` (la cellule est de l'eau : la route y est un pont), `bridge_end` (cellule de terre dont un voisin dans l'axe est de l'eau).
- `SpecialMap.region_road_places(région)` liste ces lieux (PAS dans `region_places`) ; `special_cell` / `special_plan` les connaissent (le mode regard les nomme).
- Six lieux : `toll_plaza` (péage), `roadblock` (barrage, jusqu'à 2 par région), `border_checkpoint` (poste-frontière, bout de pont), `road_bridge_toll` (péage de pont) sur la route ; `rest_area` (aire de repos, 1 cellule) et `truck_stop` (relais routier, 2 cellules) à côté de la route (accès `road`). Plans `road_*` dans `mapgen/urban.json`.

**§9 Jalons** : 12 = fait. Reste : ponts entre continents (routes sur l'océan : change l'A*, donc tout le réseau), barrages sur un même continent.

**§10 Tests** : `test_jalon12.gd`.

**Limites** : le poste-frontière n'est qu'un poste au bout d'un pont de rivière ou de lac (pas de frontière entre continents) ; les barrières sont des `t_fence` ; un carré de plancher apparaît sous les véhicules ; une route de ville (rue) n'a jamais de lieu dessus.

## GAME_DESIGN.md
- Statut monde : jalons 1-5, 9, 9b, 10, 11, **12** faits ; restent 6 à 8, 13 à 15.
- Architecture `worldgen/` : `special_map` gère aussi les lieux sur la route ; `chunk_generator` superpose leur plan à la route.
- Tests : ajouter `test_jalon12`.
