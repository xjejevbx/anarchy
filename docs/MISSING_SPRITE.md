# Sprites : vérification de `assets/tiles.json` et inventaire de `assets/sprites`

`tiles.json` n'est pas lisible par Claude : cette liste donne les ids UltiCa référencés par les données, à cocher par toi. Un id absent n'empêche pas de jouer : repli en carré de la `color` du JSON (**magenta** si le terrain n'a pas de `color`). Le plus fiable : `tests/test_worldgen_determinism.gd` affiche « AVERTISSEMENT - tuiles absentes du pack ». Toute nouvelle tuile à ajouter à `tiles.json` est listée ci-dessous.

## À vérifier dans `tiles.json`
- **Sol naturel** : `t_grass`, `t_grass_dead`, `t_grass_long`, `t_moss`, `t_tree`, `t_water_sh`, `t_water_dp`, `t_swater_sh`, `t_mud`, `t_dirt`, `t_sand`.
- **Villes et routes** : `t_pavement`, `t_pavement_y`, `t_sidewalk`, `t_bridge` (aussi `t_pier`), `t_floor`, `t_door_c` (pour `t_door`), `t_window`.
- **Lieux** : `t_dirtmound` (champ), `t_chainfence`, `t_gas_pump`, `t_rock_floor` (béton), `t_grave`, `t_reactor`, `t_helipad` (**absent du pack**, repli couleur).
- **Murs** (via `ChunkManager.wall_sprite`) : `t_wall_edge_ns|ew`, `t_wall_corner_nw|ne|se|sw`, `t_wall_t_connection_n|e|s|w`, `t_wall_end_piece_n|e|s|w`, `t_wall_unconnected`.
- **Mobilier** : `f_bed`, `f_table`, `f_chair`, `f_sofa`, `f_bookcase`, `f_fridge`, `f_counter`, `f_oven`, `f_dresser`, `f_sink`, `f_toilet`, `f_bathtub`, `f_rack`, `f_console`, `f_machinery_light`.
- **Objets** (`items.json`) : `antibiotics` et les ids déjà listés dans « Objets (UltiCa) » ci-dessous.
- **Terrains sans `color`** (magenta si tuile manquante) : `t_grass`, `t_tree`, `t_wall_arena`, `t_water_sh`, `t_water_dp`, `t_swater_sh`, `t_mud`, `t_dirt`, `t_sand`, `t_pavement`, `t_pavement_y`, `t_sidewalk`, `t_bridge`, `t_wall_house`. Proposition : leur ajouter un champ `color` dans `terrain.json`.
- **Visuels sans tuile propre** : taïga, toundra, jungle utilisent `t_tree` (pas de sapin ni palmier ; à ajouter : un terrain d'arbre par biome à la FIN de `terrain.json` + un `tree` par nature dans `WorldMap`) ; désert = `t_sand`/`t_dirt` ; savane = `t_grass`/`t_grass_dead`.

## Attention : `tools/build_ultica_pack.py`
`IDS` ne contient que `t_grass_dead`, `t_grass_long`, `t_moss` : relancé tel quel, le script réécrit `tiles.json` avec ces 3 tuiles seulement. Remettre d'abord tous les ids utilisés.

## Inventaire de `assets/sprites/` (chaque `.png` a son `.png.import`)
Les PNG UltiCa sont copiés tels quels (ex. `t_dirt_unconnected`, pas `t_dirt`) : le nom de fichier n'est pas l'id de tuile (voir `tiles.json`).
- **Propres au projet** : `arbre`, `sol_herbe`, `survivant_face|dos|profil|profil_2`, `zombie_1` à `3`, `bonnet`, `bottes`, `echarpe`, `gants`, `gilet_tactique`, `pantalon_jean`, `sac_a_dos`, `tee_shirt`, `veste_grise`, `veste_verte`.
- **Objets (UltiCa)** : `2x4`, `backpack`, `bag_plastic`, `beans_cooked`, `bottle_plastic`, `heavy_stick`, `knife_butter`, `pipe`, `rope_6`, `sheet_metal_small`.
- **Vêtements portés** : `backpack_m`, `backpack_tactical_large_m`, `hat_ball_m`, `jacket_light_m`, `jeans_m`, `pants_cargo_m`, `sneakers_m`, `undershirt_m`, `skin_brown_m`.
- **Monstres et ombre** : `mon_zombie_1` à `5`, `shadow_32x48_normal`.
- **Terrain** : `t_grass`, `t_grass_center`, `t_grass_center2` à `4`, `t_grass_giant`, `t_mud`, `t_dirt_unconnected`, `t_sand_unconnected`, `t_water_sh_unconnected`, `t_water_dp_unconnected`, `t_tree_season_spring`.
- **Murs** : `t_wall_edge_ns|ew`, `t_wall_corner_ne|nw|se|sw`, `t_wall_end_piece_n|e|s|w`, `t_wall_t_connection_n|e|s|w`, `t_wall_unconnected`.
