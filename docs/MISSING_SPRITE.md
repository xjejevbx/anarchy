# Sprites à vérifier dans assets/tiles.json

Je n'ai pas pu lire `tiles.json`. Cette liste donne les ids de tuiles UltiCa référencés par les données du jeu : à toi de cocher ceux qui
manquent. Un id absent n'empêche pas le jeu de tourner : la case est dessinée avec la couleur de repli (`color` du JSON), ou en
**magenta** quand le terrain n'a pas de `color` (voir plus bas).
Le test (`tests/test_worldgen_determinism.gd`) affiche déjà « AVERTISSEMENT - tuiles absentes du pack » avec la liste exacte : c'est le
moyen le plus fiable pour trancher.

## Terrains (`data/worldgen/terrain.json`, champ `tile`)
Sol naturel (jalons 1, 2 et 9) :
`t_grass`, `t_grass_dead`, `t_grass_long`, `t_moss`, `t_tree`, `t_water_sh`, `t_water_dp`, `t_swater_sh`, `t_mud`, `t_dirt`, `t_sand`

Villes et routes (jalon 3) :
`t_pavement`, `t_pavement_y`, `t_sidewalk`, `t_bridge`, `t_floor`, `t_door_c` (le terrain `t_door` utilise `t_door_c`), `t_window`

Lieux (jalons 4 et 5) :
`t_dirtmound` (champ), `t_chainfence` (clôture), `t_gas_pump`, `t_rock_floor` (béton), `t_grave`, `t_reactor`

Murs (ils passent par `ChunkManager.wall_sprite`, pas par un id de tuile) : `t_wall_edge_ns`, `t_wall_edge_ew`, `t_wall_corner_nw|ne|se|sw`,
`t_wall_t_connection_n|e|s|w`, `t_wall_end_piece_n|e|s|w`, `t_wall_unconnected`.

## Mobilier (`data/worldgen/furniture.json`, champ `tile`)
`f_bed`, `f_table`, `f_chair`, `f_sofa`, `f_bookcase`, `f_fridge`, `f_counter`, `f_oven`, `f_dresser`, `f_sink`, `f_toilet`, `f_bathtub`,
`f_rack`, `f_console`, `f_machinery_light`

## Terrains SANS couleur de repli (apparaissent en magenta si la tuile manque)
`t_grass`, `t_tree`, `t_wall_arena`, `t_water_sh`, `t_water_dp`, `t_swater_sh`, `t_mud`, `t_dirt`, `t_sand`, `t_pavement`, `t_pavement_y`,
`t_sidewalk`, `t_bridge`, `t_wall_house`.
Proposition (à valider avant que je l'ajoute à `terrain.json`) : leur donner un champ `color`, comme les autres terrains.

## Visuels qui n'ont pas de tuile propre (jalon 9)
- Taïga, toundra et jungle utilisent le même `t_tree` que la forêt : il n'y a ni sapin ni palmier. À ajouter plus tard : une tuile d'arbre
  par biome (nouveaux terrains à la FIN de `terrain.json`, et un `tree` par nature dans `WorldMap`).
- Le désert utilise `t_sand` et `t_dirt` ; la savane `t_grass` et `t_grass_dead`.

## Attention : tools/build_ultica_pack.py
Dans la version que j'ai lue, la liste `IDS` ne contient que `t_grass_dead`, `t_grass_long`, `t_moss`. Si tu relances le script tel quel,
il réécrit `tiles.json` avec seulement ces trois tuiles. Remets d'abord tous les ids utilisés (liste ci-dessus) avant de le relancer.
