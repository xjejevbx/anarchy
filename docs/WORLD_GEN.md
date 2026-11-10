# WORLD_GEN.md — Génération procédurale du monde

Document de conception, mis à jour à chaque jalon (les anciens `JALON_*.md` y sont fusionnés). Complète `GAME_DESIGN.md` (convention des touches : minuscule = seule, MAJUSCULE = avec Maj) et `MONSTER_SPAWN.md` (population).

## 1. Objectif et principes
Monde **infini**, généré au fil des déplacements, **identique pour une même seed** (y compris après sauvegarde). Principes non négociables :
1. Une seule seed (nombre ou texte haché en entier 64 bits), affichée à la création et sauvegardée.
2. Le terrain est une **fonction pure de `(seed, coordonnées)`** : explorer dans n'importe quel ordre donne le même monde.
3. **Aucun tirage global** (`randi()`, `randf()`, `shuffle()`) dans la génération : chaque zone a son `RandomNumberGenerator` dérivé de la seed.
4. On ne sauvegarde jamais le terrain, seulement les **deltas** (modifications) ; il se régénère.
5. Tout le contenu est en **données** (`data/worldgen/`) : ajouter un lieu ne demande pas de code.
6. Prêt pour les **étages** : clés de chunk et plans portent un `z` (0 = surface).

## 2. Déterminisme
- `WorldRng.mix(seed, couche, a, b, c, d)` : mélange 64 bits type splitmix64, écrit à la main (pas `hash()` de Godot). Couches constantes (`LAYER_TERRAIN`, `BIOME`, `TOWN`, `ROAD`, `SPECIAL`, `MAPGEN`, `LOOT`, `SPAWN`), jamais renumérotées : ajouter une couche ne change pas les autres. La 4e coordonnée `d` (0 = ignorée : les résultats existants ne changent pas) sépare des flux quand `c` est déjà pris par l'étage `z`.
- Bruit continu : `FastNoiseLite` seedé par couche (1 à 5 existantes, 6 à 9 planète, 10 archipels : ne jamais renuméroter). Les décisions fines (arbres, placement) n'utilisent que des entiers.
- On n'itère jamais un `Dictionary` pour décider quoi que ce soit ; aucune génération ne lit un chunk voisin déjà généré.
- `generator_version` (`WorldRng.GENERATOR_VERSION`, 1 au jalon 7) dans chaque sauvegarde ; l'incrémenter dès qu'un changement du générateur invalide les deltas. Une sauvegarde d'une autre version est refusée (pas de migration promise en développement).
- Test automatique : même zone générée dans plusieurs ordres = même empreinte (terrain, mobilier, routes, lieux, monstres).

## 3. Échelles
| Notion | Taille |
|---|---|
| Case | 1 m (`TILE_SIZE` = 128 px) |
| Cellule macro = chunk | 24 × 24 cases |
| Région | 32 × 32 cellules (768 × 768 cases) : unité de calcul des villes, routes, lieux |

Case : `Vector2i` absolue ; chunk `floori(case / 24)` ; local `posmod(case, 24)` ; clé `Vector3i(cx, cy, z)`. L'ancienne carte 60 × 40 est une **arène de test** (`USE_TEST_ARENA`).

## 4. Pipeline de génération

### 4.1 Carte du monde (`WorldMap`, `biomes.json`)
Champs continus évalués à toute coordonnée (aucune couture) : altitude, humidité, rivière, gué, détail, continent, température, archipel.
- **Eau** : lacs (altitude sous un seuil, profond au cœur, berge de sable) ; rivières (|bruit| proche de 0, profondes sauf aux **gués**, berge de terre) ; rétrécies en désert.
- **Planète (jalon 9)** : pas de relief, seule l'eau a une profondeur. `continent` = bruit très basse fréquence déformé, relevé autour de l'origine (départ par défaut sur terre) ; sous `sea_level` = océan (profond au-delà de `shelf_margin`) ; plage au-dessus ; `temperature` = bandes de latitude périodiques (`band_height` 12 000) + bruit ; humidité liée à la côte.
- **Règle de climat** (seuils `hot` / `cold` en données) :

| | humide | moyen | sec |
|---|---|---|---|
| chaud | jungle | savane | désert |
| tempéré | forêt (marais si bas et très humide) | plaine | plaine |
| froid | taïga | toundra | toundra |

- **Natures** (`WorldMap.Kind`, ORDRE identique à `kinds` de `biomes.json` et `RouteMap.KIND_IDS`, vérifié par test ; ajouter à la FIN) : plaine, forêt, marais, lac profond/peu profond, rivière profonde/gué, berge de lac, berge de rivière, océan profond/peu profond, plage, toundra, taïga, désert, savane, jungle.
- **Climat** (`climate_at`, jalon 10) : TEMPERATE / HOT / COLD, mêmes seuils, valable en mer.
- **Îles** (jalon 10) : bruit d'archipel relève de petites terres dans la bande d'océan proche des côtes (`planet.islands`). `island_size(cellule)` : parcours en largeur borné et mis en cache (0 = océan, `max_cells` = continent). `is_small_island`, `island_cells`.
- **Échelles visées** : continent 15 000-40 000 cases, océan 10 000-30 000, île 100-1 000, réglables dans `biomes.json`.
- Terre habitable (`is_habitable_land`) : plaine, forêt, savane, taïga, toundra, jungle (pas eau, plage, marais, désert).

### 4.2 Villes (`SettlementMap`, `towns.json`)
- Par région : 0 à 2 villes (35 / 50 / 15 %) tirées par `mix(seed, LAYER_TOWN, rx, ry)`, entièrement dans la région (marge 1). Site refusé : centre non habitable, petite île, < 70 % de terre constructible, chevauchement.
- Tailles : hameau (rayon 1), village (2), ville (4, rues secondaires tous les 3), grande ville (6). Bord conservé à 60 % (contour irrégulier).
- **Rues** : croix principale + grille ; aucune rue sur lac ni océan. Voisines d'une rue = **parcelles** (maisons ou bâtiments de ville), autres = **jardins** (3 % d'arbres conservés).
- **Cellule de route** : chaussée 8 cases (8-15), trottoirs 2 de chaque côté, lignes jaunes pointillées sur les droites ; forme selon le masque de connexions (`road_mask`). Dessinée PAR-DESSUS la nature : eau sous chaussée/trottoir = **pont**.
- **Zonage urbain (jalon 11)** : `lot_zone(cellule)` = `center` / `mid` / `outskirts` selon la distance de Tchebychev au centre, en pourcents entiers du rayon (`zone_limits`, 50 / 75). Une parcelle qui reçoit un bâtiment (`house_chance` 0,85) reçoit un **bâtiment de ville** avec la probabilité `zones[zone].urban_chance` × `size_urban_scale[taille]` (plafond 0,95), sinon une maison. Le bâtiment est tiré dans `zones[zone].buildings` (`plan`, `weight`, `min_radius`). Tirages : `mix(seed, LAYER_MAPGEN, x, y, 3)` (urbain ou maison) et `4` (quel bâtiment) ; les indices 0 à 2 restent ceux des maisons. Hameaux : maisons seulement. Un bâtiment de ville occupe UNE cellule. 18 bâtiments : supermarché, épicerie, pharmacie, quincaillerie, bar, restaurant, police, école, église, parking, mairie, caserne, banque, appartements, **hôpital, clinique, maison de retraite, garage** (ces quatre : `medical.json`, jalon 6b).
- **Départ** : bout d'une rue principale de la ville la plus proche de l'origine (< 600 cases), sinon pleine nature (`WorldMap.spawn_cell`). Arbres enlevés autour. Scénario île : §4.6.

### 4.3 Routes entre villes (`RouteMap`, section `routes` de `towns.json`)
- Graphe : chaque ville relie ses 2 plus proches voisines (3 pour une grande), < 80 cellules ; arête si b parmi les proches de a OU l'inverse ; départage (distance², x, y).
- Chemin : A* 4 directions sur cellules macro, coûts entiers (plaine 10, berge 12, forêt 30, marais 80, rivière 40 avec pont, lac/océan interdits), heuristique pondérée (glouton). Dans une ville, seules ses rues sont franchissables. Calculé du centre le plus petit vers l'autre, en cache par arête.
- Index par région : union des chemins dont la boîte (+ 16 cellules de marge) recoupe la région ; villes concernées dans ±3 régions.
- `cell_type()` renvoie ROAD ; hors ville, la nature reste autour de la chaussée (`keep_nature`).

### 4.4 Maisons et plans (`MapgenDB`, `houses.json`, `FurnitureDB`)
- Plans ASCII 24 × 24, façade au SUD, compilés une fois en terrain + mobilier ; palette caractère → terrain et/ou meuble (vide = nature). Murs dans les lignes/colonnes 1-22, porte de façade sur le mur du bas avec chemin jusqu'au bord. 4 plans de maison (petite, familiale, pavillon, cabanon).
- `lot_plan(cell)` : 85 % des parcelles habitables ; plan tiré par `mix(seed, LAYER_MAPGEN, x, y, 1)`, rotation vers une rue voisine (`mix(..., 2)`) : `rot` 0 sud, 1 ouest, 2 nord, 3 est.
- Terrains : `t_floor`, `t_wall_house`, `t_door`, `t_window` (`wall_link` : les murs se raccordent). Mobilier : un octet par case (`Chunk.furniture`), index 1-based, 0 = rien ; ajouter à la suite (`furniture.json` puis `furniture_medical.json` : l'index ne change jamais).
- `MapgenDB` charge dans l'ordre : `houses`, `places`, `big_places`, `access_places`, `urban`, `military`, `naval`, `rural`, `medical`. Les plans de maison viennent en premier ; les autres sont retrouvés par `plan_by_id`.
- Un plan nommé `<id>@<z>` est le plan d'ÉTAGE de `<id>` (§8).

### 4.5 Lieux spéciaux (`SpecialMap`, `specials.json`, plans `mapgen/*.json`)
- Fonction pure de (seed, région). Lieux triés par (priorité décroissante, id) ; pour chacun `max_per_region` fois, avec probabilité `chance`, jusqu'à `attempts` (40) tentatives tirées par `mix(seed, LAYER_SPECIAL, rx, ry, hash(id))` : rotation, position, mode d'accès (tirage seulement s'il y a le choix).
- Valide si, sous toute l'**empreinte** (cellules, façade au sud, jamais hors région) : hors ville/rue/route, biome autorisé, cellules libres ; `climates` et `zone` respectés ; accès possible ; distance à la ville dans [`min_town_distance`, `max_town_distance`].
- **zone** : `land` (défaut), `island` (petite île d'au moins `min_island_cells`), `coast` (océan à une cellule), `open_ocean` (aucune terre à `min_land_distance` ; biomes `ocean_deep`).
- **access** : `road` (façade sur une route), `track` (piste de terre ≤ `track_max_length` cellules dans la région, parcours en largeur de la porte à une route, la route gagne un embranchement), `helipad` (plan avec `t_helipad`), `pier` (façade sur l'eau, plan avec `t_pier`), `none`, `on_road`. Piste : `track_mask` (-1 = aucune), `track_terrain` (bande de terre de 4 cases).
- **`on_road` (jalon 12)** : lieu posé SUR une cellule de route entre villes (empreinte d'une cellule, accès seul). Le plan se superpose à la chaussée (ses `.` gardent le terrain de la route) et tourne dans l'axe réel de la route (`rot` 0 ou 2 route est-ouest, 1 ou 3 nord-sud) ; la cellule reste `ROAD` ; `SettlementMap.cell_plan()` renvoie le plan. Placé APRÈS les autres lieux, par candidats : cellules de route de la région triées par (x, y), filtrées (route droite, hors bordure de région, aucune piste voisine, espacement `ROAD_SPACING` = 4, biome, climat, distance à la ville, `road_site`), une est tirée. Ne lit jamais `road_mask()` ni une autre région (évite la récursion de `region_data`). `road_site` : `any`, `bridge` (cellule d'eau : pont), `bridge_end` (terre dont un voisin dans l'axe est de l'eau). Listés par `region_road_places` (PAS `region_places`) ; `special_cell` / `special_plan` les connaissent.
- `common: false` = lieu rare, exempté du test de présence.
- Exemple : `{"motel": {"name": "Motel", "priority": 60, "chance": 0.25, "biomes": ["plain","forest"], "access": ["road"], "min_town_distance": 2, "max_town_distance": 14, "max_per_region": 1, "cells": [{"offset":[0,0],"mapgen":"motel_office"},{"offset":[1,0],"mapgen":"motel_wing"}]}}`

**Catalogue des lieux** (tous rares sauf station-service, motel, ferme ; `chance` et `attempts` réglés « à l'aveugle ») :

| Jalon | Fichier de plans | Lieux (empreinte) |
|---|---|---|
| 4-5 | `places`, `big_places` | station-service, motel (2×1), ferme (2×2), centrale nucléaire (3×3), ranch (2×2), usine (2×2), station d'épuration (2×2), camping (2×1), entrepôt (2×1), cimetière, chapelle, poste électrique, cabane |
| 10 | `access_places` | entrée de bunker (piste ou héliport), avant-poste du désert (piste, chaud), phare (jetée, côte), cabane de l'île, plateforme pétrolière (héliport, pleine mer) |
| 11 | `urban` | port (3×2, côte, route), aéroport (6×2 : piste + hangars, terminal, tour, aires ; côte, route ou piste) |
| 12 | `urban` | `toll_plaza` (péage), `roadblock` (barrage, jusqu'à 2 par région), `border_checkpoint` (poste-frontière, bout de pont), `road_bridge_toll` (péage de pont) sur la route ; `rest_area` (aire de repos) et `truck_stop` (relais routier, 2×1) à côté |
| 13 | `military` | `radio_tower` (piste ou route), `military_outpost` (route), `military_base` (3×2, route, priorité 71), `military_camp` (route), `supply_depot` (2×1, route), `missile_silo` (piste ≤ 14), `research_lab` (2×1, piste ou héliport), `bunker` (piste), `radar_station` (piste ≤ 14) |
| 14 | `naval` | `aircraft_carrier` (14×2, pleine mer, héliport), `research_station` (pleine mer, héliport), `pirate_base` (2×1, côte, jetée), `marina` (jetée), `hydro_dam` (2×1, rivières, piste ou aucun), `cargo_wreck` et `shipwreck_field` (2×1, côte, eau peu profonde, sans porte), `island_village` (2×2, île ≥ 5 cellules, plans de maison existants), `lighthouse_island` (île, jetée) |
| 15 | `rural` | `ski_resort` (2×1, froid), `arctic_base` (2×1, froid, piste ou héliport), `trapper_cabin` (froid, piste), `oasis` (chaud, désert, piste ou aucun), `jungle_temple` (chaud, jungle, piste), `nomad_camp` (chaud, piste ou route), `volcano_site` (2×2, cratère de 48×48, aucun accès), `ancient_ruins` (2×1, sans porte), `cave_entrance` (piste) |

Les plans à piste ont leur porte de façade en colonne 11 et un chemin `=` jusqu'au bord sud. Les plans « sur la route » laissent la chaussée visible (`.`). Plans d'un lieu : voir `_doc` de chaque fichier de `mapgen/`.

- Terrains ajoutés : `t_field`, `t_fence`, `t_gas_pump`, `t_concrete`, `t_grave`, `t_reactor` (aussi la lave du volcan), `t_helipad`, `t_pier`. Mobilier : `f_rack`, `f_console`, `f_machinery_light`, puis `f_desk`, `f_bench`, `f_locker`, `f_glass_fridge`, `f_safe`, `f_altar`, `f_crate`, `f_container`, `f_machinery_heavy` (jalon 11), puis le mobilier médical (jalon 6b). Tuile ou meuble sans sprite : carré de la `color` (repli) ; détournements dans `MISSING_SPRITE.md`.

### 4.6 Départ « perdu sur une île »
`SettlementMap.island_spawn_cell()` : spirale de cellules depuis l'origine, première île d'au moins `spawn_min_cells` avec une case dégagée. `SaveMenuUI` propose le scénario `default` (repli si aucune île) ou `island`.

### 4.7 Mapgen d'un chunk (`ChunkGenerator`)
Terrain naturel → rue/route/parcelle (`road_terrain`, `lot_terrain`) → piste → plan de maison/lieu (y compris lieu sur la route, superposé à la chaussée) → départ dégagé ; mobilier via `generate_furniture`. À z ≠ 0 : roche pleine (z < 0) ou vide (z > 0) plus le plan d'étage s'il existe (§8).

### 4.8 Population (jalon 6, voir `MONSTER_SPAWN.md`)
Les monstres initiaux d'un chunk sont une fonction pure de `(seed, clé, terrain, mobilier, contamination)` (`SpawnGenerator`), créés une seule fois à son premier chargement (`ChunkManager._populated`). `ContaminationMap.sample(seed, chunk)` donne niveau et type (radiation, toxique, expérience, feu, maudit, pétrole) à partir des sources (lieux listés dans `ecology.json`) ; elle lit la région du chunk et, près d'un bord, les régions voisines (au plus 4), mises en cache par instance de `SettlementMap`. À venir : loot (tables, couche `LAYER_LOOT`).

## 5. Données (`data/worldgen/` sauf mention)
| Fichier | Contenu |
|---|---|
| `terrain.json`, `terrain_vertical.json` | terrains : tuile, `base`, `entity_sprite`, `autotile`, `walkable` (à pied), `swim`, `opaque`, `wall_link`, `connects_z`, `color` ; l'ORDRE (fichiers dans l'ordre de chargement) donne l'index (max 255) |
| `furniture.json`, `furniture_medical.json` | mobilier : `tile`, `walkable`, `opaque`, `color` (max 255, ajouter à la suite) |
| `biomes.json` | bruits, seuils, planète, îles, arbres, couleurs |
| `towns.json` | tailles, ratios, routes, zonage urbain, couleurs de mini-carte |
| `specials.json` | règles de placement et empreintes |
| `mapgen/*.json` | plans ASCII (palette + 24 lignes de 24 caractères) |
| `spawn_groups.json`, `spawn_groups_places.json`, `spawn_groups_contamination.json` | groupes de spawn pondérés |
| `place_spawns.json` | population par plan de lieu |
| `ecology.json` | faune ambiante, plafonds, affixes de climat, contamination (sources, substitutions) |
| `../monsters.json`, `../monsters_places.json`, `../monsters_mutants.json`, `../monster_affixes.json` | bestiaire (171 monstres) et modificateurs |
| (à venir) `item_groups.json` | tables de loot |

## 6. Exécution
- `ChunkManager` : génère rayon 3, immédiat rayon 2, décharge > 4 (≈ 49 chunks) ; 1 chunk lointain par frame. Mémoire des cases vues conservée au déchargement. Les murs voisins se redessinent à l'arrivée d'un chunk. Peuple les chunks neufs et restaure les monstres en réserve.
- `Chunk` : terrain et mobilier (octets), cases vues, sprites d'arbres triés par Y ; sol dessiné une fois (cache Godot).
- `PathFinder` : A* borné à la demande (8 directions, diagonale = 2 pas, règle de l'angle), sans grille globale.
- Objets au sol rangés par étage dans `World` ; monstres rattachés aux chunks (réserve par clé 3D).

## 7. Sauvegarde (jalon 7, fait)
`user://saves/<slot>/meta.json` + `chunks/<cx>_<cy>_<z>.json`. Le terrain n'est **jamais** écrit : on sauvegarde la seed, la version du générateur et les **deltas** des chunks modifiés.

- **`meta.json`** (écrit en dernier) : `version` (format, 1), `generator_version` (`WorldRng.GENERATOR_VERSION`, 1), `saved_at` / `saved_unix`, `seed` (chaîne décimale exacte : JSON perdrait les entiers 64 bits), `seed_text`, `scenario`, `use_arena`, `population`, `level`, `clock`, `clock_text`, `safe_centers`, `player`, `chunk_count`.
- **Delta de chunk** : `key`, `populated`, `seen` (24 × 24 octets en base64), `terrain` / `furniture` (paires `[index local, valeur]`, seules les cases modifiées), `items` (`[index local, [objets]]`), `monsters` (état complet via `Monster.to_dict()` : case, PV, état, cible, délais, capacités...). Un monstre absent de `monsters` est mort ; un chunk `populated` sans monstre n'est **jamais** repeuplé, uniques tués compris.
- **Chunks écrits** : tout chunk marqué modifié — exploration (mémoire des cases vues), population figée, terrain/mobilier modifiés, objets au sol ou monstres changés. À l'écrasement, les fichiers de l'ancienne sauvegarde du même emplacement sont effacés.
- **Chargement** : `SaveGame.load_world()` (après `add_child(world)`, AVANT de créer le joueur) remet seed, horloge, étage et deltas ; les chunks régénérés appliquent terrain/mobilier, cases vues, objets et monstres. `SaveGame.apply_player()` restaure ensuite le joueur APRÈS son `_ready()` : case, corps, stamina, posture, zoom, stats, esquive du décor, inventaire (conteneurs imbriqués et objets à poser), effets d'état et infection.
- **Compatibilité** : `version` et `generator_version` doivent correspondre ; sinon la sauvegarde est listée « INCOMPATIBLE » et refusée au chargement.
- **Écran des sauvegardes** (`SaveMenuUI`) : menu principal au lancement (charger, supprimer, nouvelle partie avec seed + scénario, quitter) ; `F5` en jeu (sauvegarder, écraser avec confirmation, charger, supprimer, nouvelle partie, reprendre). Emplacements automatiques `partie-1`, `partie-2`... Seed vide = aléatoire, affichée dans le journal et copiable (`F2` en jeu, `C` dans le menu). L'écran ne s'ouvre pas si le joueur est mort.

## 8. Étages
**Modèle retenu : UN seul étage simulé à la fois.** Toutes les requêtes par case (`Vector2i`) portent sur l'étage actif (`ChunkManager.level`, `World.get_level()`) ; les autres étages sont déchargés (cases vues et monstres gardés par clé 3D). Le joueur n'a pas de `z` propre.

| Élément | État |
|---|---|
| Clés de chunk, `_seen_store`, `_populated`, `_monster_store` | `Vector3i` avec `z` |
| RNG | `mix` / `rng_for` à 4 coordonnées ; seeds existantes inchangées |
| `ChunkGenerator.generate` à `z != 0` | z < 0 : `t_rock` ; z > 0 : `t_air` ; plan d'étage superposé |
| Terrains | `terrain_vertical.json` : `t_rock`, `t_air`, `t_stairs_up`, `t_stairs_down` (`connects_z` ±1, `TerrainDB.z_link`) |
| `ChunkManager` | `set_level(z)` décharge l'ancien étage ; `chunk_at` sur l'étage actif |
| Monstres | `Monster.z` ; réserve par clé 3D |
| Objets au sol | `World._ground_by_level` |
| `World` | `get_level()`, `change_level(z)` |

**Plans d'étage** : un plan `"<id du plan de surface>@<z>"` (ex. `urban_hospital@-1`), dans n'importe quel fichier de `mapgen/`, est l'étage de ce plan (`ChunkGenerator.level_plan`, même rotation que la surface) ; ses `.` gardent la roche / le vide. Escalier : `t_stairs_down` sur le plan de surface et `t_stairs_up` au même endroit sur `@-1`. Aucun plan d'étage n'existe encore.

**Reste (jalon 8)** : utiliser un escalier (`z_link`) pour appeler `change_level` ; plans d'étage (sous-sols du bunker, silo, labo, hôpital) ; toits et vue des étages voisins ; `MiniMapUI` et `LookUI` lisent la surface. Les sauvegardes conservent déjà les deltas par clé 3D (jalon 7, fait).

## 9. Jalons
| # | Jalon | État |
|---|---|---|
| 1 | RNG déterministe, chunks, A* borné, arène | fait |
| 2 | Carte macro : biomes, lacs, rivières, mini-carte de debug | fait |
| 3a / 3b / 3c | Villes et rues ; routes et ponts ; maisons avec mobilier | fait |
| 4 | Lieux spéciaux (station-service, motel, ferme) | fait |
| 5 | Grands lieux (centrale nucléaire, ranch, usine...) | fait |
| 6a | Bestiaire en JSON, population ambiante, chunks propriétaires | fait |
| 6b | Axe vertical (préparation), population par lieu, sommeil, affixes, plans médicaux | fait |
| 6c | Contamination, mutants, expériences ratées, capacités qui agissent | fait |
| 6d | `SUMMON`, `RAISE`, `STEALTH`, `BLIND_HEARING`, `SWIM`, `AQUATIC`, `FLY`, `SPORE`, pathfinding nautique, faune marine, uniques, rattrapage de la faune | à faire |
| 6 (loot) | Tables de loot par lieu | à faire |
| 7 | Sauvegarde / chargement (seed + deltas) | fait |
| 8 | Finitions : étages jouables, portes/fenêtres, toits, carte du joueur, tuiles complètes | à faire |
| 9 / 9b | Monde planétaire sans relief ; nage et noyade | fait |
| 10 | Climats, îles, `zone` / `access`, pistes, scénario île | fait |
| 11 | Zonage urbain (14 bâtiments), port, aéroport | fait |
| 12 | Lieux sur la route, aire de repos, relais routier | fait |
| 13 | Militaire et secret (9 lieux), surface seulement | fait |
| 14 | Mer et eau (9 lieux) | fait |
| 15 | Rural et divers (9 lieux, par climat) | fait |

À chaque jalon : mise à jour de `GAME_DESIGN.md`, plan court validé avant de coder, tests lancés à la demande.

- Pistes d'enrichissement : carte du joueur (n'affiche que l'exploré, repères posés), rumeurs et indices dans le loot, lieux « légendaires » uniques.
- Reporté : neige (saisons), ferries/ponts entre continents, routes limitées à un continent, bateaux, vêtements mouillés, sous-sols des lieux 13 à 15.

## 10. Tests
`test_worldgen_determinism.gd` (ordres de génération, villes, routes + perf, maisons, lieux, biomes, planète, arène, RNG, structure de TOUS les plans : murs dans le chunk, sol atteignable depuis la porte dans les 4 rotations), `test_swimming.gd`, `test_save.gd` (sérialisation objet/inventaire, aller-retour complet monde + joueur, deltas de chunks, monstres, effets/infection, compatibilité, suppression ; à lancer via la scène `tests/test_save.tscn`, car il utilise les autoloads : `godot --headless --path <projet> res://tests/test_save.tscn`), `test_jalon10.gd` (climats, îles, zones, accès, pistes), `test_jalon11.gd` (zonage, bâtiments, port, aéroport), `test_jalon12.gd` (lieux sur la route), `test_jalon13.gd`, `test_jalon14.gd`, `test_jalon15.gd`, `test_vertical.gd` (étages), `test_spawn.gd`, `test_contamination.gd` (voir `MONSTER_SPAWN.md`), `test_pathfinder.gd`.

## 11. Risques et limites
- **Échelle** : un continent de 30 000 cases est énorme à pied (marche automatique indispensable) ; à valider à l'œil avec la mini-carte.
- **Compatibilité des seeds** : le terrain côtier change avec les îles ; les populations ont changé au jalon 6b (acceptable en développement). Les bâtiments tirés sur les parcelles changent quand on modifie les tables de `towns.json`.
- **Coût de calcul** : `island_size`, `open_ocean`, pistes, routes, contamination (lire les sources d'une région voisine force la génération de ses lieux et routes un peu avant l'arrivée du joueur ; au-delà de 16 cellules de rayon, étaler le calcul), porte-avions (28 cellules en `open_ocean`). Mesures `perf routes` et `perf contamination`.
- **Frontières de région** : villes et routes calculées depuis les centres voisins, empreintes et pistes limitées à leur région.
- **Réglages à l'aveugle** : îles, `chance`/`attempts` des lieux.
- Villes séparées par un grand lac : peuvent rester sans route ; routes en escalier (pas de pénalité de virage).
- **Lieux** : le port n'est pas orienté vers la mer ; pas d'unicité (plusieurs mairies possibles) ; le poste-frontière n'est qu'un poste au bout d'un pont de rivière ou de lac ; les barrières sont des `t_fence` et un carré de plancher apparaît sous les véhicules posés sur la route ; le porte-avions n'a pas de rambarde (on y monte à la nage) ; `hydro_dam` n'est pas orienté selon le courant ; `lighthouse_island` peut retirer un spot au scénario île ; le volcan est décoratif (lave infranchissable, sans dégâts) ; l'oasis n'a pas d'eau douce spécifique ; pas de neige (pistes de ski en mousse) ; grotte et temples sans intérieur souterrain avant le jalon 8 ; `bunker_entrance` (jalon 10) coexiste avec `bunker` (jalon 13).
- **Affichage** : pistes absentes de la mini-carte de debug ; piste limitée à la région du lieu et 12 cellules ; île sans route ni ville ; la mini-carte et le mode regard n'affichent pas le type de bâtiment (`SettlementMap.lot_plan_id(cellule)` est prêt).
- **Sauvegarde** : écrasement non atomique (une coupure pendant l'écriture peut laisser un dossier partiel) ; pas de sauvegarde automatique ni d'export/import de fichier ; une sauvegarde d'un autre `generator_version` est refusée sans migration ; les deltas ne couvrent que les chunks marqués modifiés (toute modification faite hors des API de `ChunkManager` doit être marquée).
- Hors périmètre : météo, saisons, éclairage jour/nuit, hordes errantes, véhicules, rivières navigables, multijoueur, mods.
