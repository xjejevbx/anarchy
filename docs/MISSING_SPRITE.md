# Sprites : vérification de `assets/tiles.json` et inventaire de `assets/sprites`

`tiles.json` n'est pas lisible par Claude : cette liste donne les ids de tuiles UltiCa référencés par les données du jeu, à cocher par toi. Un id absent n'empêche pas de jouer : repli en carré de la `color` du JSON
(**magenta** si le terrain n'a pas de `color`). Le test `tests/test_worldgen_determinism.gd` affiche « AVERTISSEMENT - tuiles absentes du pack » avec la liste exacte : c'est le moyen le plus fiable.
Toute nouvelle tuile à ajouter à `tiles.json` doit être listée dans la section « À vérifier » ci-dessous.

## À vérifier dans `tiles.json`
- **Sol naturel** (`terrain.json`) : `t_grass`, `t_grass_dead`, `t_grass_long`, `t_moss`, `t_tree`, `t_water_sh`, `t_water_dp`, `t_swater_sh`, `t_mud`, `t_dirt`, `t_sand`.
- **Villes et routes** : `t_pavement`, `t_pavement_y`, `t_sidewalk`, `t_bridge`, `t_floor`, `t_door_c` (utilisé par `t_door`), `t_window`.
- **Lieux** : `t_dirtmound` (champ), `t_chainfence` (clôture), `t_gas_pump`, `t_rock_floor` (béton), `t_grave`, `t_reactor`.
- **Murs** (via `ChunkManager.wall_sprite`, pas par id de tuile) : `t_wall_edge_ns|ew`, `t_wall_corner_nw|ne|se|sw`, `t_wall_t_connection_n|e|s|w`, `t_wall_end_piece_n|e|s|w`, `t_wall_unconnected`.
- **Mobilier** (`furniture.json`) : `f_bed`, `f_table`, `f_chair`, `f_sofa`, `f_bookcase`, `f_fridge`, `f_counter`, `f_oven`, `f_dresser`, `f_sink`, `f_toilet`, `f_bathtub`, `f_rack`, `f_console`, `f_machinery_light`.
- **Terrains sans `color`** (magenta si la tuile manque) : `t_grass`, `t_tree`, `t_wall_arena`, `t_water_sh`, `t_water_dp`, `t_swater_sh`, `t_mud`, `t_dirt`, `t_sand`, `t_pavement`, `t_pavement_y`, `t_sidewalk`, `t_bridge`, `t_wall_house`.
  Proposition (à valider) : leur ajouter un champ `color` dans `terrain.json`.
- **Visuels sans tuile propre** : taïga, toundra et jungle utilisent `t_tree` (ni sapin ni palmier ; à ajouter : un terrain d'arbre par biome à la FIN de `terrain.json` + un `tree` par nature dans `WorldMap`) ; désert = `t_sand` / `t_dirt` ; savane = `t_grass` / `t_grass_dead`.

## Attention : `tools/build_ultica_pack.py`
Dans la version lue, `IDS` ne contient que `t_grass_dead`, `t_grass_long`, `t_moss` : relancé tel quel, le script réécrit `tiles.json` avec seulement ces 3 tuiles. Remettre d'abord tous les ids utilisés avant de le relancer.

## Inventaire de `assets/sprites/` (noms seulement ; chaque `.png` a son `.png.import`)
Les `.png` de UltiCa sont copiés tels quels (ex. `t_dirt_unconnected`, pas `t_dirt`) ; le nom du fichier n'est donc pas l'id de tuile (voir `tiles.json`).

- **Images propres au projet** (plus grosses, 8-250 Ko) : `arbre`, `sol_herbe`, `survivant_face`, `survivant_dos`, `survivant_profil`, `survivant_profil_2`, `zombie_1` à `zombie_3`, `bonnet`, `bottes`, `echarpe`, `gants`, `gilet_tactique`, `pantalon_jean`, `sac_a_dos`, `tee_shirt`, `veste_grise`, `veste_verte`.
- **Objets (UltiCa)** : `2x4`, `backpack`, `bag_plastic`, `beans_cooked`, `bottle_plastic`, `heavy_stick`, `knife_butter`, `pipe`, `rope_6`, `sheet_metal_small`.
- **Vêtements portés (UltiCa)** : `backpack_m`, `backpack_tactical_large_m`, `hat_ball_m`, `jacket_light_m`, `jeans_m`, `pants_cargo_m`, `sneakers_m`, `undershirt_m`, `skin_brown_m`.
- **Monstres et ombre** : `mon_zombie_1` à `mon_zombie_5`, `shadow_32x48_normal`.
- **Terrain** : `t_grass`, `t_grass_center`, `t_grass_center2` à `4`, `t_grass_giant`, `t_mud`, `t_dirt_unconnected`, `t_sand_unconnected`, `t_water_sh_unconnected`, `t_water_dp_unconnected`, `t_tree_season_spring`.
- **Murs** : `t_wall_edge_ns|ew`, `t_wall_corner_ne|nw|se|sw`, `t_wall_end_piece_n|e|s|w`, `t_wall_t_connection_n|e|s|w`, `t_wall_unconnected`.
