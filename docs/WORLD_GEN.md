# WORLD_GEN.md — Génération procédurale du monde

Document de conception, mis à jour à chaque jalon. Complète `GAME_DESIGN.md` (convention des touches : minuscule = seule, MAJUSCULE = avec Maj).

## 1. Objectif et principes
Monde **infini**, généré au fil des déplacements, **identique pour une même seed** (y compris après sauvegarde). Principes non négociables :
1. Une seule seed (nombre ou texte haché en entier 64 bits), affichée à la création et sauvegardée.
2. Le terrain est une **fonction pure de `(seed, coordonnées)`** : explorer dans n'importe quel ordre donne le même monde.
3. **Aucun tirage global** (`randi()`, `randf()`, `shuffle()`) dans la génération : chaque zone a son `RandomNumberGenerator` dérivé de la seed.
4. On ne sauvegarde jamais le terrain, seulement les **deltas** (modifications) ; il se régénère.
5. Tout le contenu est en **données** (`data/worldgen/`) : ajouter un lieu ne demande pas de code.
6. Prêt pour les **étages** : clés de chunk et plans portent un `z` (0 au début).

## 2. Déterminisme
- `WorldRng.mix(seed, couche, a, b, c)` : mélange 64 bits type splitmix64, écrit à la main (pas `hash()` de Godot). Couches constantes (`LAYER_TERRAIN`, `BIOME`, `TOWN`, `ROAD`, `SPECIAL`, `MAPGEN`, `LOOT`, `SPAWN`), jamais renumérotées : ajouter une couche ne change pas les autres.
- Bruit continu : `FastNoiseLite` seedé par couche. Les décisions fines (arbres, placement) n'utilisent que des entiers.
- On n'itère jamais un `Dictionary` pour décider quoi que ce soit ; aucune génération ne lit un chunk voisin déjà généré.
- `generator_version` dans chaque sauvegarde (à incrémenter au jalon 7) ; pas de compatibilité ascendante promise en développement.
- Test automatique : même zone générée dans plusieurs ordres = même empreinte.

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
- **Climat** (`climate_at`, jalon 10) : TEMPERATE / HOT / COLD, même seuils, valable en mer.
- **Îles** (jalon 10) : bruit d'archipel relève de petites terres dans la bande d'océan proche des côtes (`planet.islands`). `island_size(cellule)` : parcours en largeur borné et mis en cache (0 = océan, `max_cells` = continent). `is_small_island`, `island_cells`.
- **Échelles visées** : continent 15 000-40 000 cases, océan 10 000-30 000, île 100-1 000, réglables dans `biomes.json`.
- Terre habitable (`is_habitable_land`) : plaine, forêt, savane, taïga, toundra, jungle (pas eau, plage, marais, désert).

### 4.2 Villes (`SettlementMap`, `towns.json`)
- Par région : 0 à 2 villes (35 / 50 / 15 %) tirées par `mix(seed, LAYER_TOWN, rx, ry)`, entièrement dans la région (marge 1). Site refusé : centre non habitable, petite île, < 70 % de terre constructible, chevauchement.
- Tailles : hameau (rayon 1), village (2), ville (4, rues secondaires tous les 3), grande ville (6). Bord conservé à 60 % (contour irrégulier).
- **Rues** : croix principale + grille ; aucune rue sur lac ni océan. Voisines d'une rue = **parcelles** (maisons), autres = **jardins** (3 % d'arbres conservés).
- **Cellule de route** : chaussée 8 cases (8-15), trottoirs 2 de chaque côté, lignes jaunes pointillées sur les droites ; forme selon le masque de connexions (`road_mask`). Dessinée PAR-DESSUS la nature : eau sous chaussée/trottoir = **pont**.
- **Départ** : bout d'une rue principale de la ville la plus proche de l'origine (< 600 cases), sinon pleine nature (`WorldMap.spawn_cell`). Arbres enlevés autour. Scénario île : §4.6.

### 4.3 Routes entre villes (`RouteMap`, section `routes` de `towns.json`)
- Graphe : chaque ville relie ses 2 plus proches voisines (3 pour une grande), < 80 cellules ; arête si b parmi les proches de a OU l'inverse ; départage (distance², x, y).
- Chemin : A* 4 directions sur cellules macro, coûts entiers (plaine 10, berge 12, forêt 30, marais 80, rivière 40 avec pont, lac/océan interdits), heuristique pondérée (glouton). Dans une ville, seules ses rues sont franchissables. Calculé du centre le plus petit vers l'autre, en cache par arête.
- Index par région : union des chemins dont la boîte (+ 16 cellules de marge) recoupe la région ; villes concernées dans ±3 régions.
- `cell_type()` renvoie ROAD ; hors ville, la nature reste autour de la chaussée (`keep_nature`).

### 4.4 Maisons (`MapgenDB`, `houses.json`, `FurnitureDB`)
- Plans ASCII 24 × 24, façade au SUD, compilés une fois en terrain + mobilier ; palette caractère → terrain et/ou meuble (vide = nature). Murs dans les lignes/colonnes 1-22, porte de façade sur le mur du bas avec chemin jusqu'au bord. 4 plans (petite, familiale, pavillon, cabanon).
- `lot_plan(cell)` : 85 % des parcelles habitables ; plan tiré par `mix(seed, LAYER_MAPGEN, x, y, 1)`, rotation vers une rue voisine (`mix(..., 2)`) : `rot` 0 sud, 1 ouest, 2 nord, 3 est.
- Terrains : `t_floor`, `t_wall_house`, `t_door`, `t_window` (`wall_link` : les murs se raccordent). Mobilier : un octet par case (`Chunk.furniture`), index 1-based, 0 = rien ; ajouter à la suite dans `furniture.json`.

### 4.5 Lieux spéciaux (`SpecialMap`, `specials.json`, plans `mapgen/*.json`)
- Fonction pure de (seed, région). Lieux triés par (priorité décroissante, id) ; pour chacun `max_per_region` fois, avec probabilité `chance`, jusqu'à `attempts` (40) tentatives tirées par `mix(seed, LAYER_SPECIAL, rx, ry, hash(id))` : rotation, position, mode d'accès (tirage seulement s'il y a le choix).
- Valide si, sous toute l'**empreinte** (cellules, façade au sud, jamais hors région) : hors ville/rue/route, biome autorisé, cellules libres ; `climates` et `zone` respectés ; accès possible ; distance à la ville dans [`min_town_distance`, `max_town_distance`].
- **zone** : `land` (défaut), `island` (petite île d'au moins `min_island_cells`), `coast` (océan à une cellule), `open_ocean` (aucune terre à `min_land_distance` ; biomes `ocean_deep`).
- **access** : `road` (façade sur une route), `track` (piste de terre ≤ `track_max_length` cellules dans la région, parcours en largeur de la porte à une route, la route gagne un embranchement), `helipad` (plan avec `t_helipad`), `pier` (façade sur l'eau, plan avec `t_pier`), `none`. `near_road: true` reste compris. Piste : `track_mask` (-1 = aucune), `track_terrain` (bande de terre de 4 cases).
- `common: false` = lieu rare, exempté du test de présence.
- Fichiers de plans : `places.json` (station-service, motel, ferme), `big_places.json` (centrale nucléaire 3×3, ranch, usine, station d'épuration, camping, entrepôt, cimetière, chapelle, poste électrique, cabane), `access_places.json` (entrée de bunker, avant-poste du désert, phare, plateforme pétrolière). Lieux d'essai du jalon 10 (rares, réglés « à l'aveugle ») : `bunker_entrance`, `desert_outpost`, `lighthouse`, `hermit_cabin`, `oil_platform`.
- Terrains ajoutés : `t_field`, `t_fence`, `t_gas_pump`, `t_concrete`, `t_grave`, `t_reactor`, `t_helipad`, `t_pier` ; mobilier `f_rack`, `f_console`, `f_machinery_light`. Tuile ou meuble sans sprite : carré de la `color` (repli).

### 4.6 Départ « perdu sur une île »
`SettlementMap.island_spawn_cell()` : spirale de cellules depuis l'origine, première île d'au moins `spawn_min_cells` avec une case dégagée. `main.gd` : `START_SCENARIO = "island"` (repli default). Le futur menu de création reprendra ce choix.

### 4.7 Mapgen d'un chunk (`ChunkGenerator`)
Terrain naturel → rue/route/parcelle (`road_terrain`, `lot_terrain`) → piste → plan de maison/lieu → départ dégagé ; mobilier via `generate_furniture`. À venir (jalon 6) : loot (tables) et monstres initiaux, une seule fois (flag `populated`).

## 5. Données (`data/worldgen/`)
| Fichier | Contenu |
|---|---|
| `terrain.json` | terrains : tuile, `base`, `entity_sprite`, `autotile`, `walkable` (à pied), `swim`, `opaque`, `wall_link`, `color` ; l'ORDRE donne l'index (max 255) |
| `furniture.json` | mobilier : `tile`, `walkable`, `opaque`, `color` (max 255, ajouter à la suite) |
| `biomes.json` | bruits, seuils, planète, îles, arbres, couleurs |
| `towns.json` | tailles, ratios, routes, couleurs de mini-carte |
| `specials.json` | règles de placement et empreintes |
| `mapgen/*.json` | plans ASCII (palette + 24 lignes de 24 caractères) |
| (à venir) `item_groups.json`, `spawn_groups.json` | loot et groupes de monstres |

Exemple de lieu : `{"motel": {"name": "Motel", "priority": 60, "chance": 0.25, "biomes": ["plain","forest"], "access": ["road"], "min_town_distance": 2, "max_town_distance": 14, "max_per_region": 1, "cells": [{"offset":[0,0],"mapgen":"motel_office"},{"offset":[1,0],"mapgen":"motel_wing"}]}}`

## 6. Exécution
- `ChunkManager` : génère rayon 3, immédiat rayon 2, décharge > 4 (≈ 49 chunks) ; 1 chunk lointain par frame. Mémoire des cases vues conservée au déchargement. Les murs voisins se redessinent à l'arrivée d'un chunk.
- `Chunk` : terrain et mobilier (octets), cases vues, sprites d'arbres triés par Y ; sol dessiné une fois (cache Godot).
- `PathFinder` : A* borné à la demande, sans grille globale.
- Objets au sol et monstres restent globaux dans `World` (rattachement aux chunks : jalons 6-7).

## 7. Sauvegarde (jalon 7)
`user://saves/<slot>/meta.json` (version, `generator_version`, seed, joueur, horloge) + `chunks/<cx>_<cy>_<z>.json` pour les seuls chunks modifiés. Au chargement : régénérer, puis remplacer objets et monstres par le delta ; `populated` empêche de repeupler. Seed vide à la création = aléatoire, affichée et copiable.

## 8. Étages (préparation)
Rien d'implémenté : `z` dans les clés et plans ; terrains « air » et « toit » prévus ; liaisons verticales via `connects_z: ±1` (même `(x, y)` au niveau voisin) ; un lieu multi-étages déclare un plan par `z`.

## 9. Jalons
| # | Jalon | État |
|---|---|---|
| 1 | RNG déterministe, chunks, A* borné, arène | fait |
| 2 | Carte macro : biomes, lacs, rivières, mini-carte de debug | fait |
| 3a / 3b / 3c | Villes et rues ; routes et ponts ; maisons avec mobilier | fait |
| 4 | Lieux spéciaux (station-service, motel, ferme) | fait |
| 5 | Grands lieux (centrale nucléaire, ranch, usine...) | fait |
| 6 | Loot et monstres par lieu et densité de zone | à faire |
| 7 | Sauvegarde / chargement (seed + deltas) | à faire |
| 8 | Finitions : portes/fenêtres, intérieurs/toits, carte du joueur, tuiles complètes | à faire |
| 9 / 9b | Monde planétaire sans relief ; nage et noyade | fait |
| 10 | Climats, îles, `zone` / `access`, pistes, scénario île | fait |
| 11-15 | Structures (46 lieux) : urbain, routes, militaire, mer, rural | à faire |

À chaque jalon : mise à jour de `GAME_DESIGN.md`, plan court validé avant de coder, tests lancés à la demande.

### Jalons 11-15 (idées)
- **11 Urbain** (16) : + `port`, `airport` côtiers. **12 Routes** (6) : + `border_checkpoint` (pont entre continents), barrages sur un même continent.
- **13 Militaire/secret** (9) : `radio_tower`, `bunker`, `missile_silo`, `lab` (accès `track`/`helipad`, sous-sols avec les étages).
- **14 Mer et eau** (10) : porte-avions (`open_ocean`, jusqu'à 14 × 2), `lighthouse_island`, `cargo_wreck`, `marina`, `hydro_dam`, `island_village`, `shipwreck_field`, `pirate_base`, `research_station`.
- **15 Rural/divers** (9) : `oasis`, `ski_resort`, `volcano_site`, `ancient_ruins`, `cave_entrance`, `arctic_base`, lieux par climat.
- Pistes d'enrichissement : carte du joueur (n'affiche que l'exploré, repères posés), rumeurs et indices dans le loot, lieux « légendaires » uniques.
- Reporté : neige (saisons), ferries/ponts entre continents, ports, routes limitées à un continent, bateaux, vêtements mouillés.

## 10. Tests
`test_worldgen_determinism.gd` (ordres de génération, villes, routes + perf, maisons, lieux, biomes, planète, arène, RNG), `test_swimming.gd`, `test_jalon10.gd` (climats, îles, zones, accès, pistes).

## 11. Risques
- **Échelle** : un continent de 30 000 cases est énorme à pied (marche automatique indispensable) ; à valider à l'œil avec la mini-carte.
- **Compatibilité des seeds** : le terrain côtier change avec les îles (acceptable en développement).
- **Coût de calcul** : `island_size`, `open_ocean`, pistes, routes (étalement sur frames, caches, mesures `perf routes`).
- **Frontières de région** : villes et routes calculées depuis les centres voisins, empreintes et pistes limitées à leur région.
- **Réglages à l'aveugle** : îles, `chance`/`attempts` des lieux d'essai.
- Villes séparées par un grand lac : peuvent rester sans route ; routes en escalier (pas de pénalité de virage).
- Hors périmètre : météo, saisons, éclairage jour/nuit, hordes errantes, véhicules, rivières navigables, multijoueur, mods.
