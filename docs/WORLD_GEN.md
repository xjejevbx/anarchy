# WORLD_GEN.md — Génération procédurale du monde

Complète `GAME_DESIGN.md` (convention des touches : minuscule = seule, MAJUSCULE = avec Maj).

## 1. Objectif et principes
Monde **infini**, généré au fil des déplacements (comme CDDA), **identique pour une même seed**, même après sauvegarde / rechargement. À terme : villes, routes, fermes, motels, centrales, bunkers, labos, tour radio, avec loot et monstres.

1. **Une seule seed** (nombre ou texte, haché en entier 64 bits), affichée à la création et stockée dans la sauvegarde.
2. **Terrain = fonction pure de `(seed, coordonnées)`** : l'ordre d'exploration n'a aucun effet.
3. **Aucun tirage global** (`randi()`, `randf()`, `shuffle()` interdits en génération) : chaque zone a son `RandomNumberGenerator` dérivé de la seed.
4. **On ne sauvegarde jamais le terrain**, seulement les modifications (deltas).
5. **Tout le contenu est en données** (JSON dans `data/worldgen/`) : ajouter un lieu ne demande pas de code.
6. **Prêt pour les étages** : clés de chunk et plans portent `z` (0 au début, voir §9).

## 2. Déterminisme
- `WorldRng.mix(seed, couche, a, b, c)` : mélange 64 bits écrit à la main (pas `hash()` de Godot). Couches = entiers CONSTANTS (`LAYER_TERRAIN` 1, `BIOME` 2, `TOWN` 3, `ROAD` 4, `SPECIAL` 5, `MAPGEN` 6, `LOOT` 7, `SPAWN` 8) : ne jamais renuméroter, ajouter à la suite.
  Générateur local = `RandomNumberGenerator` seedé par `mix(seed, couche, x, y, z)`.
- Bruit continu (biomes, rivières) : `FastNoiseLite`, seed dérivée par couche. Décisions clés (villes, lieux, arbres) : **entiers uniquement**.
- Jamais d'itération de `Dictionary` pour décider (on trie par id) ; aucune génération ne lit un chunk voisin déjà généré, seulement des fonctions pures de la macro-carte.
- `generator_version` écrit dans chaque sauvegarde ; un changement d'algorithme peut casser les anciens mondes en développement (assumé, signalé au chargement).
- Test automatique : même zone générée dans plusieurs ordres = même hash (`tests/test_worldgen_determinism.gd`).

## 3. Échelles
| Notion | Taille |
|---|---|
| Case | 1 m (`TILE_SIZE` 128 px) |
| Cellule macro = **chunk** | 24 × 24 cases ; a un type (forêt, route, maison...) |
| Région | 32 × 32 cellules (768 × 768 cases) : unité de calcul des villes, routes, lieux |
| Continent / océan | 15 000-40 000 / 10 000-30 000 cases ; bande climatique 12 000 |

Case : `Vector2i` absolue. Chunk : `floori(case / 24)` ; local : `posmod(case, 24)`. Clé de chunk : `Vector3i(cx, cy, z)`. L'ancienne carte 60 × 40 est l'**arène de test** (option debug).

## 4. Pipeline (état construit)

### 4.1 Carte macro et planète (`WorldMap`, `biomes.json`) — jalons 2 et 9
Champs continus évalués à toute coordonnée ; la case et la cellule macro (échantillonnée au centre) lisent la même source : aucune couture. **Pas de relief** (ni collines, montagnes, falaises, neige) ; la profondeur n'existe que pour l'eau.
- **Continent** : bruit très basse fréquence (~0,00003) + déformation de domaine ; sous `sea_level` = océan (profond au-delà de `shelf_margin`). `origin_bonus` / `origin_radius` relèvent le continent autour de (0,0) : le départ est toujours sur terre.
- **Température** : `sin(2π y / (4 × band_height)) + bruit` (bandes répétées à l'infini). **Humidité** : bruit + côtes humides / intérieur sec.
- **Lacs** : altitude < `lake.level` (profond sous `level − deep_margin`, berge de sable jusqu'à `level + shore`). **Rivières** : |bruit| < `half_width` (profondes si < `deep_half_width` ET bruit de gué < `ford_level`, sinon **gué** peu profond ; berge de terre) ; rétrécies en désert. Le monde n'est jamais coupé par de l'eau profonde... sauf l'océan (voir nage).
- **17 natures** (ordre = `WorldMap.Kind` = `RouteMap.KIND_IDS` = `kinds` de `biomes.json`, ajouter à la FIN ; vérifié par le test) : plain, forest, swamp, lake_deep, lake_shallow, river_deep, river_shallow, shore_lake, bank_river, ocean_deep, ocean_shallow, beach, tundra, taiga, desert, savanna, jungle.
- **Règle de climat** : chaud (> `hot`) : jungle (humide) / savane / désert (sec) ; froid (< `cold`) : taïga / toundra ; tempéré : marais (humide et bas) / forêt / plaine. Densité d'arbres par nature (hachage entier).
- **Départ** : `WorldMap.spawn_cell()` (spirale, plaine / forêt) en repli ; sinon lisière de ville (4.2). Arbres retirés autour (`ChunkGenerator`).
- **Performance** : `kind_at` sort tôt en mer ; mini-carte jusqu'au zoom 4096.

### 4.2 Villes et rues (`SettlementMap`, `towns.json`) — jalon 3a
- Par région, `mix(seed, LAYER_TOWN, rx, ry)` tire **0 à 2 villes** (35 / 50 / 15 %) tenant entièrement dans la région (marge 1) ; un site est refusé si le centre n'est pas habitable, < 70 % de terre constructible, ou chevauchement.
- Tailles : hameau (rayon 1), village (2), ville (4, rues tous les 3), grande ville (6). Cellules du bord gardées à 60 % (contour irrégulier).
- **Rues** : croix principale + grille secondaire ; aucune rue sur un lac ou l'océan (`_is_water_body`). Voisines d'une rue = **parcelles** (LOT), autres = **jardins** (YARD) ; arbres retirés (3 % gardés).
- **Cellule de route** : chaussée de 8 cases au centre, trottoirs de 2, lignes jaunes pointillées sur les routes droites ; dessin selon le masque de connexions (droit, virage, T, croix, impasse, place). Dessinée PAR-DESSUS le terrain : l'eau sous chaussée / trottoir devient **pont**.
- **Départ** : au bout d'une rue principale de la ville la plus proche de l'origine (< 600 cases), sinon pleine nature.

### 4.3 Routes entre villes (`RouteMap`, section `routes` de `towns.json`) — jalon 3b
- **Graphe** : chaque ville relie ses 2 plus proches voisines (3 pour une grande ville), à < 80 cellules ; arête (a, b) si b parmi les proches de a OU l'inverse ; départage (distance², x, y).
- **Chemin** : A* 4 directions sur cellules macro, coûts entiers (plaine 10, berge 12, forêt 30, marais 80, rivière 40 avec pont, lac / océan interdits), heuristique pondérée (glouton). Dans une ville seules ses rues sont franchissables. Calculé du centre le plus petit vers l'autre, mis en cache par arête.
- **Index par région** : union des chemins dont la boîte (+ marge 16) recoupe la région (villes concernées dans ±3 régions) : une route traversant une région sans ville est prise en compte quel que soit l'ordre d'exploration.
- `cell_type()` renvoie ROAD ; hors ville seule la route est dessinée (la nature reste autour).

### 4.4 Maisons (`MapgenDB`, `FurnitureDB`, `mapgen/houses.json`) — jalon 3c
- Plans ASCII 24 × 24, façade au SUD, compilés une fois en terrain + mobilier (index 1-based, 0 = rien). Palette caractère → terrain et/ou mobilier (vide = terrain naturel). Murs strictement dans le chunk (lignes / colonnes 1-22), porte sur le mur du bas reliée par un chemin au bord. Plan invalide = ignoré, erreurs listées par `errors()`.
- 4 plans : petite maison, familiale, pavillon, cabanon. `SettlementMap.lot_plan()` : 85 % des parcelles habitables ; plan par `mix(..., LAYER_MAPGEN, x, y, 1)`, rotation vers une rue voisine (`..., 2`). Rotations 90 / 180 / 270 (`MapgenDB.plan_index`).
- Terrains ajoutés : `t_floor`, `t_wall_house`, `t_door`, `t_window` (`wall_link` : les murs se raccordent).

### 4.5 Lieux spéciaux et grands lieux (`SpecialMap`, `specials.json`, `mapgen/places.json`, `big_places.json`) — jalons 4 et 5
- **Placement** (pure de seed + région) : lieux triés (priorité décroissante, id) ; pour chacun, `max_per_region` fois, avec probabilité `chance`, jusqu'à 40 tentatives (rotation puis position, `mix(seed, LAYER_SPECIAL, rx, ry, hash(id))`).
  Valide si, sous toute l'empreinte : hors ville / rue / route, biome autorisé, cellule libre ; si la façade touche une route (`near_road`) ; si la distance à la ville la plus proche est dans [min, max]. L'empreinte ne franchit jamais une frontière de région. `common: false` = rare (exempté du test « au moins un par 7 × 7 régions »).
- **Rotation** : façade tournée vers la route, plans tournés avec l'empreinte. **Accès** : pas de piste ; chaque plan contient son chemin (terre ou parking). Rendu : `cell_type()` = SPECIAL, `cell_plan()` donne le plan.
- **Lieux** (14) : station-service (1), motel (2), ferme (2×2), centrale nucléaire (3×3, très rare, ≥ 6 cellules d'une ville : clôture, portail, réacteur, salle de contrôle, turbines, entrepôt, transformateurs, parking), ranch (2×2), usine (2×2), station d'épuration (2×2, bassins), camping (2×1), entrepôt (2×1), cimetière, chapelle, poste électrique, cabane.
- Terrains : `t_field`, `t_fence`, `t_gas_pump`, `t_concrete`, `t_grave`, `t_reactor` ; mobilier `f_rack`, `f_console`, `f_machinery_light`.
- **Repli coloré** : tuile ou meuble sans sprite = carré de la `color` du JSON (magenta si le terrain n'a pas de `color`). `build_ultica_pack.py` n'échoue plus sur un id introuvable (avertit), sauf si plus de la moitié manquent.

### 4.6 Mapgen d'un chunk (`ChunkGenerator`)
1. Terrain de base du biome (herbe, terre, eau, arbres) ; 2. route / parcelle / plan du lieu (+ arbres retirés autour du départ) ; 3. mobilier (`generate_furniture`) ; 4. *(jalon 6)* loot et monstres initiaux, **une seule fois**.

## 5. Données (`data/worldgen/`)
| Fichier | Contenu |
|---|---|
| `terrain.json` | terrains : tuile, `walkable` (à pied), `swim`, `opaque`, `base`, `entity_sprite`, `autotile`, `wall_link`, `color` ; ordre = index (max 255) |
| `furniture.json` | mobilier : tuile, `walkable`, `opaque`, `color` ; ordre = index (ajouter à la suite) |
| `biomes.json` | bruits, seuils, densité d'arbres, couleurs, section `planet` |
| `towns.json` | tailles, zonage, `routes` (coûts par nature) |
| `specials.json` | règles de placement et empreintes |
| `mapgen/*.json` | plans ASCII (maisons, lieux, grands lieux) |
| *(à venir)* `item_groups.json`, `spawn_groups.json` | tables de loot et groupes de monstres pondérés par lieu / zone |

Exemple de lieu : `{"motel": {"priority": 60, "chance": 0.25, "biomes": ["plain","forest"], "near_road": true, "min_town_distance": 2, "max_town_distance": 14, "max_per_region": 1, "cells": [{"offset":[0,0],"mapgen":"motel_office"}, {"offset":[1,0],"mapgen":"motel_wing"}]}}`.

## 6. Exécution
- `ChunkManager` : génère à rayon 3 (immédiat à rayon 2, le reste étalé, `CHUNKS_PER_FRAME` 1), décharge au-delà de 4 (~49 chunks). Cases vues conservées au déchargement. Objectif : < 4 ms par chunk.
- `Chunk` : terrain, mobilier, `seen`, sprites d'arbres ; sol dessiné une fois (cache Godot). Murs : sprite selon les voisins (`wall_sprite`), redessin des chunks voisins au chargement.
- `PathFinder` : A* borné à la demande sur chunks chargés. `World` délègue la carte au `ChunkManager`.
- Mini-carte debug (`m`) : tuiles en cache, rendu progressif, terrain réel à ≤ 1 case / échantillon, villes jusqu'au zoom 256, routes et lieux jusqu'à 16.

## 7. Sauvegarde « seed + deltas » (jalon 7)
```
user://saves/<slot>/meta.json                    { version, generator_version, engine_version, seed, joueur, horloge }
user://saves/<slot>/chunks/<cx>_<cy>_<z>.json    deltas d'un chunk modifié
```
Un chunk n'est écrit que s'il est modifié (objet, porte, monstre tué, cases vues...). Au chargement : régénérer depuis la seed puis remplacer objets au sol et monstres par le delta ; drapeau `populated` (un monstre tué ne revient pas). Monstres rattachés au chunk où ils sont. Création : seed saisie (texte ou nombre), vide = aléatoire affichée et copiable. Nettoyer les deltas redevenus vides.

## 8. Jalons
| # | Jalon | État |
|---|---|---|
| 1 | RNG déterministe + chunks, arène de test | fait |
| 2 | Carte macro : biomes, rivières, lacs, mini-carte | fait |
| 3 | Villes (a), routes et ponts (b), maisons avec mobilier (c) | fait |
| 4 | Lieux spéciaux : station-service, motel, ferme | fait |
| 5 | Grands lieux : centrale nucléaire + 9 autres | fait |
| 6 | Loot (tables pondérées) et monstres (groupes par lieu et densité) | à faire |
| 7 | Sauvegarde / chargement, saisie de la seed | à faire |
| 8 | Finitions : portes et fenêtres dans le FOV, intérieurs / toits, tuiles UltiCa complètes, vraie carte du joueur | à faire |
| 9 | Planète : océans, plages, climats (sans relief) | fait |
| 9b | Nage et noyade (voir `GAME_DESIGN.md`) | fait |
| 10-15 | Moteur de placement et structures (§10) | à faire |

À chaque jalon : mise à jour de `GAME_DESIGN.md`, plan court validé avant de coder, tests lancés seulement sur demande. Réglages initiaux posés « à l'aveugle » (biomes, villes, routes, lieux) : à ajuster à l'œil avec la mini-carte.

**Limites connues** : objets au sol et monstres globaux (non rattachés aux chunks) ; monstre hors chunks chargés immobile ; pas de loot ni monstres dans maisons et lieux ; porte sans état ; pas d'étage ni de toit ;
une ville dont les voisines sont séparées par un grand lac peut rester sans route (recherche bornée) ; routes parfois en escalier ; une maison ne se génère pas sur une cellule dont le centre est berge / marais / eau (peut recouvrir un coin d'eau voisin) ;
une seule variante de plan par bâtiment ; sprites de champ, clôture, pompe, réacteur, console, machine, tombe, béton à vérifier à l'œil ; taïga / toundra / jungle réutilisent `t_tree` (pas de sapin ni palmier).

## 9. Étages (préparation, non implémenté)
Clé `Vector3i(cx, cy, z)` (`z` < 0 sous-sols, > 0 étages / toits) ; plans et lieux avec `z` ; terrains « vide / air » et « toit » ; liaisons verticales (escalier, échelle, ascenseur, trappe) via `connects_z: ±1`, arrivée au même (x, y) ; un lieu multi-étages déclare un plan par niveau. Plus tard : changement de niveau, FOV inter-niveaux, A* par niveau, sauvegarde par `z`.

## 10. Suite : traversée de l'eau et structures (jalons 9b à 15)
- **9b fait** : nage. À venir : **bateaux** (avec les véhicules), ports / marinas / épaves posés dès maintenant, **ponts / tunnels / ferries** sur les détroits étroits.
- **Jalon 10 — moteur de placement** : par **climat** (`climates`) et **relief** (`coast`, `island`, `open_ocean`, `mountain` si relief ajouté) ; `island` = îlot isolé (distance min / max à la côte) ; `open_ocean` = empreinte 100 % eau profonde loin des côtes ; accès : `t_pier`, piste, héliport, ou aucun (lieux de décor, nage / bateau).
- **Impacts planète restant à traiter** : villes côtières et ports, densité de villes selon la fertilité, routes limitées à un continent, `border_checkpoint` entre continents reliés, relief (collines, montagnes avec cols, neige), sprites sable / neige / roche / jungle / désert / falaise.
- **Jalons 11-15 (46 lieux)** : 11 urbain (16, + `port`, `airport`) ; 12 routes (6, + `border_checkpoint`, barrages) ; 13 militaire / secret (9 : `radio_tower`, `bunker`, `missile_silo`, `lab`, en montagne ou désert avec piste) ;
  14 mer et eau (`aircraft_carrier` réel `open_ocean` jusqu'à 14 × 2, `oil_platform`, `lighthouse_island`, `cargo_wreck`, `marina`, `hydro_dam`, `island_village`, `shipwreck_field`, `pirate_base`, `research_station`) ;
  15 rural et climats (`oasis`, `ski_resort`, `volcano_site`, `ancient_ruins`, `cave_entrance`, `desert_outpost`, `arctic_base`).
- **Contenu visé** : ville (maisons, appartements, épicerie, supermarché, pharmacie, quincaillerie, bar, commissariat, école, église, parking...) ; rural (carrière...) ; industrie (centrales) ; militaire / secret.
- **Découverte** : points d'intérêt par biome ; vraie carte du joueur (explorée seulement, repères) ; rumeurs et indices (notes, radios, cartes dans le loot) ; quelques lieux « légendaires » par monde (`max_per_world_window`).
- **Risques** : échelle (un continent de 30 000 cases est énorme à pied : marche auto indispensable, réglage dans `biomes.json` validé à la mini-carte) ; coût de calcul (mesures `perf` du test) ; limite de 255 terrains (confortable).
- **Hors périmètre actuel** : météo, saisons, cycle jour / nuit et éclairage, hordes errantes, véhicules, rivières navigables, multi-joueur, mods.
