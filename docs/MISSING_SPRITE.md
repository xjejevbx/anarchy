# Sprites : vérification de `assets/tiles.json` et inventaire de `assets/sprites`

`tiles.json` n'est pas lisible par Claude : cette liste donne les ids UltiCa référencés par les données, à cocher par toi. Un id absent n'empêche pas de jouer : repli en carré de la `color` du JSON (**magenta** si le terrain n'a pas de `color`) ; monstre sans tuile : sprite de zombie (ou de loup) teinté. Le plus fiable : `tests/test_worldgen_determinism.gd` affiche « AVERTISSEMENT - tuiles absentes du pack ». Toute nouvelle tuile à ajouter à `tiles.json` est listée ci-dessous. Les anciens `MISSING_SPRITE_JALON11` à `15` sont fusionnés ici.

## À vérifier dans `tiles.json`
- **Sol naturel** : `t_grass`, `t_grass_dead`, `t_grass_long`, `t_moss`, `t_tree`, `t_water_sh`, `t_water_dp`, `t_swater_sh`, `t_mud`, `t_dirt`, `t_sand`.
- **Villes et routes** : `t_pavement`, `t_pavement_y`, `t_sidewalk`, `t_bridge` (aussi `t_pier`), `t_floor`, `t_door_c` (pour `t_door`), `t_window`.
- **Lieux** : `t_dirtmound` (champ), `t_chainfence`, `t_gas_pump`, `t_rock_floor` (béton), `t_grave`, `t_reactor`, `t_helipad` (**absent du pack**, repli couleur).
- **Murs** (via `ChunkManager.wall_sprite`) : `t_wall_edge_ns|ew`, `t_wall_corner_nw|ne|se|sw`, `t_wall_t_connection_n|e|s|w`, `t_wall_end_piece_n|e|s|w`, `t_wall_unconnected`.
- **Mobilier (jalons 3-5)** : `f_bed`, `f_table`, `f_chair`, `f_sofa`, `f_bookcase`, `f_fridge`, `f_counter`, `f_oven`, `f_dresser`, `f_sink`, `f_toilet`, `f_bathtub`, `f_rack`, `f_console`, `f_machinery_light`.
- **Objets** (`items.json`) : `antibiotics` et les ids listés dans « Objets (UltiCa) » plus bas.
- **Terrains sans `color`** (magenta si tuile manquante) : `t_grass`, `t_tree`, `t_wall_arena`, `t_water_sh`, `t_water_dp`, `t_swater_sh`, `t_mud`, `t_dirt`, `t_sand`, `t_pavement`, `t_pavement_y`, `t_sidewalk`, `t_bridge`, `t_wall_house`. Proposition : leur ajouter un champ `color` dans `terrain.json`.
- **Visuels sans tuile propre** : taïga, toundra, jungle utilisent `t_tree` (pas de sapin ni palmier ; à ajouter : un terrain d'arbre par biome à la FIN de `terrain.json` + un `tree` par nature dans `WorldMap`) ; désert = `t_sand`/`t_dirt` ; savane = `t_grass`/`t_grass_dead`.

## Jalon 11 : mobilier ajouté (`furniture.json`, à la fin de la liste)
Ids improvisés (nom logique CDDA / UltiCa). Pour corriger : changer le champ `tile` dans `furniture.json`.

| id jeu | tuile demandée | confiance | remarque |
|---|---|---|---|
| `f_desk` | `f_desk` | haute | bureau |
| `f_bench` | `f_bench` | haute | bancs d'église, mairie, aéroport |
| `f_locker` | `f_locker` | haute | casiers, boîtes aux lettres |
| `f_glass_fridge` | `f_glass_fridge` | moyenne | frigo vitrine ; repli possible `f_fridge` |
| `f_safe` | `f_safe_c` | haute | coffre-fort |
| `f_altar` | `f_altar` | moyenne | autel (église, temple, ruines) |
| `f_crate` | `f_crate_c` | haute | caisses |
| `f_container` | `f_container` | **faible** | conteneur maritime ; sinon `f_dumpster` ou un `t_*` de conteneur |
| `f_machinery_heavy` | `f_machinery_heavy` | moyenne | grue, camions, avions, véhicules (provisoire) |

Aucun nouveau terrain au jalon 11 : piste d'atterrissage = `t_pavement` + `t_pavement_y`, quai = `t_concrete`, barreaux du commissariat = `t_fence`.

## Jalons 12 à 15 : aucun nouvel id, détournements provisoires
`tiles.json` n'a pas été modifié. À remplacer le jour où des sprites dédiés existent :

- **Jalon 12 (routes)** : barrières de péage, barrage et poste-frontière = `t_fence` (tuile `t_chainfence` ; option : `t_barricade_road` / `f_barricade_road`) ; véhicules (voitures, camions, file d'attente) = `f_machinery_heavy` ; conteneurs = `f_container` ; pompes = `t_gas_pump` ; tables de pique-nique = `f_table` + `f_chair`. Les meubles posés sur la route reposent sur un carreau `t_floor` : un carré de plancher apparaît sous chaque véhicule.
- **Jalon 13 (militaire)** : mât radio, antenne radar, trappe de silo, véhicules = `f_machinery_heavy` ; générateurs = `f_machinery_light` ; sacs de sable, barrières, clôtures = `t_fence` ; tentes = murs `t_wall_house` ; conteneurs = `f_container` ; héliport du labo = `t_helipad`. *Question en suspens* : sprites dédiés (antenne, trappe de silo, radar, tente) ? Indiquer les fichiers de `assets/sprites/4x/` ou les ids UltiCa voulus, et les entrées seront ajoutées à `furniture.json` et à cette liste.
- **Jalon 14 (mer)** : pont du porte-avions = `t_pavement` / `t_pavement_y`, coque = `t_concrete` ; rambardes des épaves = `t_fence` ; avions, turbines, grues = `f_machinery_heavy` ; conteneurs = `f_container` ; pontons = `t_pier` (tuile `t_bridge`) ; héliports = `t_helipad`. Souhaités : avion, bateau (coque), grue, turbine, ponton.
- **Jalon 15 (rural)** : lave = `t_reactor` (orange) ; cendres = `t_dirt` ; basalte = `t_concrete` ; pistes de ski = `t_moss` (pas de neige avant les saisons) ; remontées mécaniques = `f_machinery_heavy` ; palmiers = `t_tree` ; mare de l'oasis = `t_water_sh` / `t_water_dp` ; autel = `f_altar` ; roche de la grotte = `t_wall_house` ; héliport arctique = `t_helipad`. Souhaités : roche / falaise, lave, neige, palmier, colonne antique, tente, télésiège.
- **Toujours sans sprite** : `t_helipad`.

## Jalon 6 : monstres (voir `MONSTER_SPAWN.md`)

Ids **improvisés** (CDDA / UltiCa). Par défaut, la tuile d'un monstre est `mon_<id>` (champ `tile` de `monsters*.json`) ; chaque fiche a un `fallback_tile` (`mon_zombie`, ou `mon_wolf` pour un animal) et un `tint` : un id absent n'empêche pas de jouer. Pour corriger un id, changer `tile` dans le JSON. Les affixes ne demandent aucun sprite.

Déjà utilisés par le jeu (à ne pas toucher) : `mon_zombie`, `mon_zombie_child`, `mon_zombie_fast`, `mon_zombie_crawler`, `mon_zombie_brute`, `mon_zombie_hulk`, `mon_zombie_spitter`, `mon_zombie_screecher`, `mon_zombie_electric`, `mon_zombie_soldier`, `mon_zombie_dog`, `mon_wolf`, `mon_bear`, `mon_spider_widow_giant`.

**Confiance haute** : `mon_zombie_cop`, `mon_zombie_fireman`, `mon_zombie_scientist`, `mon_zombie_technician`, `mon_zombie_hazmat`, `mon_zombie_swimmer`, `mon_zombie_survivor`, `mon_zombie_miner`, `mon_zombie_prisoner`, `mon_zombie_bio_op`, `mon_zombie_necro`, `mon_zombie_master`, `mon_zombie_acidic`, `mon_zombie_tough`, `mon_zombie_grabber`, `mon_zombie_waif`, `mon_zombie_predator`, `mon_zombie_flamer`, `mon_skeleton`.

**Confiance moyenne** : `mon_zombie_swat`, `mon_zombie_soldier_armored`, `mon_zombie_commando`, `mon_zombie_heavy_gunner`, `mon_zombie_gasbag`, `mon_zombie_mummified`, `mon_zombie_frozen`, `mon_zombie_charred`, `mon_zombie_overgrown`, `mon_zombie_irradiated`, `mon_zombie_glowing`, `mon_zombie_cryo`, `mon_zombie_drowned`, `mon_deer`, `mon_fox`, `mon_coyote`, `mon_crow`, `mon_boar`, `mon_dog_feral`, `mon_rat_giant`, `mon_snake`, `mon_snake_rattle`, `mon_shark`, `mon_jellyfish`, `mon_crab_giant`, `mon_alligator`, `mon_crocodile`, `mon_lion`, `mon_hyena`, `mon_jaguar`, `mon_python_giant`, `mon_wolf_arctic`, `mon_bear_polar`, `mon_mummy`, `mon_bat_swarm`.

**Confiance faible** (probablement absents : repli teinté) :
- Zombies de métier : `mon_zombie_civilian`, `_pajamas`, `_elder`, `_teen`, `_homeowner`, `_bather`, `_hoarder`, `_tenant`, `_scavenger`, `_drunk`, `_biker`, `_driver`, `_trucker`, `_tourist`, `_camper`, `_hiker`, `_mayor`, `_clerk`, `_shopper`, `_stocker`, `_butcher`, `_pharmacist`, `_cook`, `_waiter`, `_bartender`, `_mechanic`, `_receptionist`, `_banker`, `_bank_guard`, `_clerical`, `_security`, `_janitor`, `_toll_clerk`, `_student`, `_teacher`, `_churchgoer`, `_priest`, `_mourner`, `_gravedigger`, `_grave`, `_farmer`, `_farmhand`, `_cowboy`, `_cow`, `_horse` (tous préfixés `mon_zombie`).
- Santé : `mon_zombie_patient`, `_nurse`, `_doctor`, `_surgeon`, `_orderly`, `_paramedic`, `_psych`, `_morgue`, `_quarantine`, `mon_patient_zero`.
- Militaire / science / industrie : `mon_zombie_border_guard`, `_sniper`, `_officer`, `_combat_medic`, `_grenadier`, `_engineer`, `_pilot_mil`, `_sentry`, `_armored_brute`, `_commander`, `_researcher`, `_lab_guard`, `_lab_subject`, `_reactor_tech`, `_lab_director`, `_worker`, `_welder`, `_foreman`, `_electrician`, `_sewer_worker`, `_dam_engineer`, `_bloated` (tile CDDA possible : `mon_zombie_fat`).
- Mer et air : `mon_zombie_sailor`, `_dockworker`, `_stowaway`, `_captain`, `_fisherman`, `_diver`, `_oil_worker`, `_lighthouse_keeper`, `_oceanographer`, `_pirate`, `_smuggler`, `mon_pirate_captain`, `mon_zombie_passenger`, `_flight_attendant`, `_baggage`, `_controller`, `_pilot`, `_skier`.
- Expériences : `mon_experiment_` + `bloated`, `chimera`, `flesh_mass`, `blob`, `stalker`, `crawler`, `homunculus`, `screamer`, `parasite`, `acid_hound`, `clone`, `slime`, `swarm`, `tyrant`, `nightmare`.
- Faune mutante et exotique : `mon_wolf_mutant`, `bear_mutant`, `deer_mutant`, `boar_mutant`, `crow_mutant`, `rat_irradiated`, `cockroach_giant`, `ant_giant`, `ant_queen`, `spider_mutant`, `spider_cave`, `bat_giant`, `snake_mutant`, `frog_mutant`, `leech_swarm`, `alligator_mutant`, `seagull_mutant`, `piranha_swarm`, `eel_electric`, `shark_mutant`, `squid_giant`, `kraken`, `mutant_yeti`, `vulture_mutant`, `scorpion_giant`, `sandworm`, `tarantula_giant`, `monkey_mutant`, `mosquito_swarm`, `fire_hound`, `magma_crawler`, `skeleton_brute`, `ruin_guardian`, `troglodyte`, `reactor_horror`.

Plan de repli suggéré : pour chaque id absent, ajouter dans le JSON un `fallback_tile` plus proche (ex. `mon_zombie_cop` pour les policiers) et un `tint`. Les ids retenus sont à ajouter à `IDS` de `tools/build_ultica_pack.py`.

## Jalon 6b : axe vertical et mobilier médical
- **Terrains verticaux** (`terrain_vertical.json`) : `t_rock` (roche pleine, confiance haute), `t_open_air` (vide, confiance moyenne), `t_stairs_up`, `t_stairs_down` (haute). Repli : carré de la `color` (roche grise, vide presque noir, escaliers beiges). Les étages ne s'affichent qu'après le jalon 8 : ces tuiles ne servent pas encore.
- **Mobilier médical** (`furniture_medical.json`, à la suite de `furniture.json`) : `f_hospital_bed` (essayer `f_bed`), `f_gurney`, `f_surgery_table`, `f_morgue_drawer` (confiance faible, repli couleur).
- **Mobilier prévu, pas encore utilisé** (à la FIN de `furniture*.json`, confiance faible) : `f_cell_bed` et `f_quarantine_bed` (essayer `f_bed`), `f_lab_table` (essayer `f_table`), `f_cryo_pod`, `f_cage`, `f_vat`, `f_server`, `f_garage_pit`.

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
