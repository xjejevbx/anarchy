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

## Jalon 6 : monstres (voir `MONSTER_SPAWN.md`)

Les ids ci-dessous sont des **noms improvisés** (CDDA / UltiCa), choisis sans pouvoir ouvrir `tiles.json`. Par défaut, la tuile d'un monstre est `mon_<id>` (champ `tile` de `data/monsters.json`) ; chaque fiche aura aussi `fallback_tile` (`mon_zombie`) et `tint` (teinte) : **un id absent n'empêche pas de jouer**, le monstre est dessiné avec le sprite de zombie teinté. Pour corriger un id, il suffit de changer `tile` dans `monsters.json`.

Déjà utilisés par le jeu (à ne pas toucher) : `mon_zombie`, `mon_zombie_child`, `mon_zombie_fast`, `mon_zombie_crawler`, `mon_zombie_brute`, `mon_zombie_hulk`, `mon_zombie_spitter`, `mon_zombie_screecher`, `mon_zombie_electric`, `mon_zombie_soldier`, `mon_zombie_dog`, `mon_wolf`, `mon_bear`, `mon_spider_widow_giant`.

**Confiance haute** (ids CDDA très probables) :
`mon_zombie_cop`, `mon_zombie_fireman`, `mon_zombie_scientist`, `mon_zombie_technician`, `mon_zombie_hazmat`, `mon_zombie_swimmer`, `mon_zombie_survivor`, `mon_zombie_miner`, `mon_zombie_prisoner`, `mon_zombie_bio_op`, `mon_zombie_necro`, `mon_zombie_master`, `mon_zombie_acidic`, `mon_zombie_tough`, `mon_zombie_grabber`, `mon_zombie_waif`, `mon_zombie_predator`, `mon_zombie_flamer`, `mon_skeleton`.

**Confiance moyenne** :
`mon_zombie_swat`, `mon_zombie_soldier_armored`, `mon_zombie_commando`, `mon_zombie_heavy_gunner`, `mon_zombie_gasbag`, `mon_zombie_mummified`, `mon_zombie_frozen`, `mon_zombie_charred`, `mon_zombie_overgrown`, `mon_zombie_irradiated`, `mon_zombie_glowing`, `mon_zombie_cryo`, `mon_zombie_drowned`, `mon_deer`, `mon_fox`, `mon_coyote`, `mon_crow`, `mon_boar`, `mon_dog_feral`, `mon_rat_giant`, `mon_snake`, `mon_snake_rattle`, `mon_shark`, `mon_jellyfish`, `mon_crab_giant`, `mon_alligator`, `mon_crocodile`, `mon_lion`, `mon_hyena`, `mon_jaguar`, `mon_python_giant`, `mon_wolf_arctic`, `mon_bear_polar`, `mon_mummy`, `mon_bat_swarm`.

**Confiance faible** (probablement absents : repli teinté) :
- Zombies de métier : `mon_zombie_civilian`, `mon_zombie_pajamas`, `mon_zombie_elder`, `mon_zombie_teen`, `mon_zombie_homeowner`, `mon_zombie_bather`, `mon_zombie_hoarder`, `mon_zombie_tenant`, `mon_zombie_scavenger`, `mon_zombie_drunk`, `mon_zombie_biker`, `mon_zombie_driver`, `mon_zombie_trucker`, `mon_zombie_tourist`, `mon_zombie_camper`, `mon_zombie_hiker`, `mon_zombie_mayor`, `mon_zombie_clerk`, `mon_zombie_shopper`, `mon_zombie_stocker`, `mon_zombie_butcher`, `mon_zombie_pharmacist`, `mon_zombie_cook`, `mon_zombie_waiter`, `mon_zombie_bartender`, `mon_zombie_mechanic`, `mon_zombie_receptionist`, `mon_zombie_banker`, `mon_zombie_bank_guard`, `mon_zombie_clerical`, `mon_zombie_security`, `mon_zombie_janitor`, `mon_zombie_toll_clerk`, `mon_zombie_student`, `mon_zombie_teacher`, `mon_zombie_churchgoer`, `mon_zombie_priest`, `mon_zombie_mourner`, `mon_zombie_gravedigger`, `mon_zombie_grave`, `mon_zombie_farmer`, `mon_zombie_farmhand`, `mon_zombie_cowboy`, `mon_zombie_cow`, `mon_zombie_horse`.
- Santé : `mon_zombie_patient`, `mon_zombie_nurse`, `mon_zombie_doctor`, `mon_zombie_surgeon`, `mon_zombie_orderly`, `mon_zombie_paramedic`, `mon_zombie_psych`, `mon_zombie_morgue`, `mon_zombie_quarantine`, `mon_patient_zero`.
- Militaire / science / industrie : `mon_zombie_border_guard`, `mon_zombie_sniper`, `mon_zombie_officer`, `mon_zombie_combat_medic`, `mon_zombie_grenadier`, `mon_zombie_engineer`, `mon_zombie_pilot_mil`, `mon_zombie_sentry`, `mon_zombie_armored_brute`, `mon_zombie_commander`, `mon_zombie_researcher`, `mon_zombie_lab_guard`, `mon_zombie_lab_subject`, `mon_zombie_reactor_tech`, `mon_zombie_lab_director`, `mon_zombie_worker`, `mon_zombie_welder`, `mon_zombie_foreman`, `mon_zombie_electrician`, `mon_zombie_sewer_worker`, `mon_zombie_dam_engineer`, `mon_zombie_bloated` (tile CDDA possible : `mon_zombie_fat`).
- Mer et air : `mon_zombie_sailor`, `mon_zombie_dockworker`, `mon_zombie_stowaway`, `mon_zombie_captain`, `mon_zombie_fisherman`, `mon_zombie_diver`, `mon_zombie_oil_worker`, `mon_zombie_lighthouse_keeper`, `mon_zombie_oceanographer`, `mon_zombie_pirate`, `mon_zombie_smuggler`, `mon_pirate_captain`, `mon_zombie_passenger`, `mon_zombie_flight_attendant`, `mon_zombie_baggage`, `mon_zombie_controller`, `mon_zombie_pilot`, `mon_zombie_skier`.
- Expériences : `mon_experiment_bloated`, `mon_experiment_chimera`, `mon_experiment_flesh_mass`, `mon_experiment_blob`, `mon_experiment_stalker`, `mon_experiment_crawler`, `mon_experiment_homunculus`, `mon_experiment_screamer`, `mon_experiment_parasite`, `mon_experiment_acid_hound`, `mon_experiment_clone`, `mon_experiment_slime`, `mon_experiment_swarm`, `mon_experiment_tyrant`, `mon_experiment_nightmare`.
- Faune mutante et exotique : `mon_wolf_mutant`, `mon_bear_mutant`, `mon_deer_mutant`, `mon_boar_mutant`, `mon_crow_mutant`, `mon_rat_irradiated`, `mon_cockroach_giant`, `mon_ant_giant`, `mon_ant_queen`, `mon_spider_mutant`, `mon_spider_cave`, `mon_bat_giant`, `mon_snake_mutant`, `mon_frog_mutant`, `mon_leech_swarm`, `mon_alligator_mutant`, `mon_seagull_mutant`, `mon_piranha_swarm`, `mon_eel_electric`, `mon_shark_mutant`, `mon_squid_giant`, `mon_kraken`, `mon_mutant_yeti`, `mon_vulture_mutant`, `mon_scorpion_giant`, `mon_sandworm`, `mon_tarantula_giant`, `mon_monkey_mutant`, `mon_mosquito_swarm`, `mon_fire_hound`, `mon_magma_crawler`, `mon_skeleton_brute`, `mon_ruin_guardian`, `mon_troglodyte`, `mon_reactor_horror`.

Plan de repli suggéré : pour chaque id absent, ajouter dans `monsters.json` un `fallback_tile` plus proche (ex. `mon_zombie_cop` pour les policiers) et un `tint`. Les ids sont à ajouter à `IDS` de `tools/build_ultica_pack.py` (voir l'avertissement plus bas).

### Mobilier prévu pour le jalon 6 (à la FIN de `furniture.json`)
Tuiles demandées (confiance faible, repli en carré de la `color`) : `f_hospital_bed` (essayer `f_bed`), `f_gurney`, `f_surgery_table`, `f_morgue_drawer`, `f_cell_bed` (essayer `f_bed`), `f_quarantine_bed` (essayer `f_bed`), `f_lab_table` (essayer `f_table`), `f_cryo_pod`, `f_cage`, `f_vat`, `f_server`, `f_garage_pit`.

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
