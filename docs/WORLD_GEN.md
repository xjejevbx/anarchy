# WORLD_GEN.md — Génération procédurale du monde

Document de **résultat attendu** (conception). Aucun code n'est écrit à ce stade. Il complète `GAME_DESIGN.md`.
Convention d'affichage des touches : voir `GAME_DESIGN.md` (minuscule = touche seule, MAJUSCULE = avec Maj).

## 1. Objectif

Un monde **infini**, généré au fil des déplacements (comme Cataclysm: DDA), mais **identique à chaque partie qui utilise la même seed**,
y compris après sauvegarde / rechargement. À terme : villes, routes, fermes, motels, stations-service, centrales nucléaires, bunkers,
laboratoires, tour radio, etc., avec leur loot et leurs monstres.

## 2. Principes non négociables

1. **Une seule seed** (nombre ou texte, haché en entier 64 bits). Elle est affichée à la création et stockée dans la sauvegarde.
2. **Le terrain est une fonction pure de `(seed, coordonnées)`.** Explorer dans n'importe quel ordre donne le même monde.
3. **Aucun tirage global** (`randi()`, `randf()`, `shuffle()` interdits dans le code de génération). Chaque zone utilise son propre
   `RandomNumberGenerator` dérivé de la seed (voir §3).
4. **On ne sauvegarde jamais le terrain**, seulement les **modifications** du joueur et du monde (« deltas »). Le terrain se régénère.
5. **Tout le contenu est en données** (JSON dans `data/worldgen/`), comme `items.json` : ajouter un motel ou une ferme ne demande pas de code.
6. **Prêt pour les étages** (sous-sols, étages, toits, tour radio) : toutes les clés de chunk et tous les plans portent une coordonnée `z`
   (toujours 0 au début). Voir §10.

## 3. Déterminisme

- Fonction de mélange entière 64 bits (type splitmix64), écrite à la main (pas `hash()` de Godot, qui peut changer d'une version à l'autre) :
  `mix(seed, couche, a, b, c) -> int`.
- Chaque couche de génération a un **identifiant entier constant** (`LAYER_BIOME`, `LAYER_TOWN`, `LAYER_ROAD`, `LAYER_SPECIAL`,
  `LAYER_MAPGEN`, `LAYER_LOOT`, `LAYER_SPAWN`…). Un générateur local = `RandomNumberGenerator` dont la seed est `mix(seed_monde, couche, x, y, z)`.
  Ajouter une couche ne modifie donc pas les autres.
- Bruit continu (biomes, rivières) : `FastNoiseLite` avec une seed dérivée par couche. Les décisions importantes (placement des villes
  et des lieux) n'utilisent **que** des entiers, pour ne dépendre d'aucune subtilité flottante.
- Aucune dépendance à l'ordre : on n'itère jamais sur un `Dictionary` pour décider quoi que ce soit (on trie par id) ; aucune génération ne
  lit l'état d'un chunk voisin déjà généré (seulement des fonctions pures de la macro-carte).
- **Version du générateur** (`generator_version`) écrite dans chaque sauvegarde. Pendant le développement, un changement d'algorithme peut
  casser les anciens mondes ; on l'assume tant que le jeu n'est pas publié, et on l'affiche clairement au chargement.
- **Test de déterminisme automatique** (jalon 1) : générer une même zone dans deux ordres différents doit donner le même hash de contenu.

## 4. Échelles et coordonnées

| Notion | Taille | Détail |
|---|---|---|
| Case | 1 m | unité de jeu actuelle (`TILE_SIZE = 32` px) |
| Cellule macro = **chunk** | 24 × 24 cases | une cellule macro a un type (forêt, route, maison…) ; son chunk est généré à partir de ce type |
| Région | 32 × 32 cellules (768 × 768 cases) | unité de calcul des villes, routes et lieux spéciaux |

- Coordonnée de case : `Vector2i` absolue (infini, signée). Chunk : `floori(case / 24)` ; local : `posmod(case, 24)`.
- Clé de chunk : **`Vector3i(cx, cy, z)`**, `z = 0` = sol, `z < 0` = sous-sols, `z > 0` = étages / toits.
- Les 60 × 40 actuels deviennent une **arène de test** (option debug), utile pour le combat et l'inventaire.

## 5. Pipeline de génération (de l'échelle large à l'échelle fine)

### 5.1 Carte macro : biomes
Des **champs continus** (altitude, humidité, rivière), bruits `FastNoiseLite` seedés par couche, évalués à n'importe quelle coordonnée.
Le terrain d'une case et la cellule macro (24 x 24, échantillonnée en son centre) lisent la même source : bords lisses, aucune couture.
- Lacs : altitude sous un seuil (profond au cœur, peu profond près du bord, berge de sable).
- Rivières : lignes où |bruit| est proche de 0 (courbes et continues), profondes au centre sauf aux **gués** (un 2e bruit les rend peu
  profondes) : le monde n'est jamais coupé par de l'eau profonde ; berges de terre.
- Terre ferme : marais (humide et bas), forêt (humide), plaine ; densité d'arbres par biome (hachage entier, pas de flottant).
- Natures : `plaine, forêt, marais, lac profond, lac peu profond, rivière profonde, rivière peu profonde (gué), berge de lac, berge de rivière`.

### 5.2 Villes (jalon 3a, tel que construit)
- Le monde est découpé en **régions de 32 × 32 cellules** (1 cellule = 1 chunk = 24 × 24 cases). Chaque région tire, avec
  `mix(seed, LAYER_TOWN, rx, ry)`, **0 à 2 villes** (poids 35 / 50 / 15 %) qui tiennent **entièrement dans la région** (marge de 1 cellule) :
  aucune dépendance entre régions. Un site est refusé si le centre n'est pas en plaine ou forêt, s'il y a moins de 70 % de terre
  constructible sous la ville, ou s'il chevauche une autre ville de la région.
- Tailles : **hameau** (rayon 1), **village** (rayon 2), **ville** (rayon 4, rues secondaires tous les 3 cellules), **grande ville** (rayon 6).
  La ville couvre (2 × rayon + 1)² cellules ; les cellules du bord sont conservées avec une probabilité de 60 % (contour irrégulier).
- **Rues** : croix principale (cellules alignées sur le centre) + grille de rues secondaires ; pas de rue sur un lac. Les cellules voisines
  d'une rue sont des **parcelles** (futures maisons), les autres des **jardins** ; les arbres y sont enlevés (3 % conservés).
- **Cellule de route** (24 × 24 cases) : chaussée de 8 cases au centre, trottoirs de 2 cases de chaque côté, lignes jaunes en pointillés
  sur les routes droites ; le dessin dépend du masque de connexions (droit, virage, T, croix, impasse, place isolée). La route est
  dessinée PAR-DESSUS le terrain naturel : toute case d'eau sous la chaussée ou le trottoir devient un **pont**.
- Réglages : `data/worldgen/towns.json` (probabilités, tailles, ratios) ; géométrie des routes en constantes de `SettlementMap`.
- **Départ** : au bout d'une rue principale de la ville la plus proche de l'origine (à moins de 600 cases), sinon en pleine nature
  (`WorldMap.spawn_cell()`). Les arbres sont enlevés autour du départ (`ChunkGenerator`).

### 5.3 Routes entre villes (jalon 3b, tel que construit)
- **Graphe** : chaque ville se relie à ses 2 plus proches voisines (3 pour une grande ville), cherchées dans les régions voisines (leurs
  centres se calculent sans générer de chunk), à moins de 80 cellules. Arête (a, b) = b parmi les plus proches de a OU a parmi les plus
  proches de b. Départage déterministe par (distance², x, y) du centre.
- **Chemin** : A* en 4 directions sur les cellules macro, coûts entiers (plaine 10, berge 12, forêt 30, marais 80, rivière 40 avec pont
  automatique, lac interdit). Heuristique pondérée (A* glouton : rapide, chemins un peu moins optimaux ; départage « plus proche du but
  d'abord » pour des tracés plutôt droits). Dans l'emprise d'une ville, seules ses rues sont franchissables : la route entre par un bout
  de rue et rejoint le centre par le réseau existant. Le chemin est une fonction pure des deux centres (calcul toujours du centre le plus
  petit vers l'autre), mis en cache par arête.
- **Index par région** : les cellules de route d'une région sont l'union des chemins des arêtes dont la boîte englobante (+ marge de
  16 cellules) la recoupe ; les villes concernées tiennent dans ±3 régions (valeur déduite de distance maximale + marge). Une route qui
  traverse une région sans ville est donc bien prise en compte, quel que soit l'ordre d'exploration.
- **Rendu** : `SettlementMap.cell_type()` renvoie ROAD pour ces cellules ; masque de connexions, chaussée, trottoirs et ponts sont ceux des
  rues. Hors ville, seule la route est dessinée : arbres et terrain naturel restent autour de la chaussée.
- Réglages : section `routes` de `data/worldgen/towns.json`.

### 5.4 Lieux spéciaux (jalon 4, tel que construit)
- **Données** : `data/worldgen/specials.json` (priorité, chance par région, biomes, `near_road`, distances min / max à la ville la plus proche,
  `max_per_region`, cellules de l'empreinte avec leur plan) ; plans ASCII 24 x 24 dans `data/worldgen/mapgen/places.json` (même format que les maisons).
- **Placement** (`SpecialMap`, fonction pure de la seed et de la région) : lieux triés par (priorité décroissante, id) ; pour chacun, `max_per_region`
  fois, avec la probabilité `chance`, jusqu'à 40 tentatives tirées par `mix(seed, LAYER_SPECIAL, rx, ry, hash(id))` (rotation puis position). Valide si,
  sous toute l'empreinte : hors ville, hors rue ou route, biome autorisé, cellules libres ; si la façade touche une rue ou une route (`near_road`) ;
  et si la distance à la ville la plus proche est dans l'intervalle. Une empreinte ne franchit jamais une frontière de région.
- **Rotation** : la façade (sud des plans) est tournée vers la route ; les plans de chaque cellule tournent avec l'empreinte.
- **Accès** : pas de piste dédiée : tous les lieux longent une route, et chaque plan contient son petit chemin (terre ou parking) de la porte au bord
  de la cellule.
- **Rendu** : `SettlementMap.cell_type()` renvoie SPECIAL ; `ChunkGenerator` pose terrain et mobilier du plan (`cell_plan`).

### 5.5 Mapgen d'un chunk
À la demande : on lit le type de la cellule macro, on choisit un plan (avec rotation) et on remplit les 576 cases :
1. terrain de base du biome (herbe, terre, eau, arbres par bruit) ;
2. plan du bâtiment / de la route / du lieu spécial (§6.3) ;
3. mobilier et objets au sol (tables de loot, §6.4) ;
4. monstres initiaux (groupes de spawn, §6.5), **une seule fois** (voir §8).

## 6. Données (`data/worldgen/`)

| Fichier | Contenu |
|---|---|
| `terrain.json` | terrains et mobilier : id, nom, tuile UltiCa, `walkable`, `opaque`, `blocks_move`… |
| `biomes.json` | seuils de bruit, terrain de base, densité d'arbres, coût de route |
| `towns.json` | tailles, zonage, poids des bâtiments par zone |
| `specials.json` | règles de placement et empreinte des lieux spéciaux |
| `mapgen/*.json` | plans ASCII (façon CDDA) de bâtiments, routes et lieux |
| `item_groups.json` | tables de loot (`items.json` reste la liste des objets) |
| `spawn_groups.json` | groupes de monstres par type de lieu / de zone |

### 6.1 Exemple de lieu spécial (`specials.json`)
```json
{ "id": "motel_roadside", "priority": 50, "rarity": 6,
  "biomes": ["plain", "forest"], "near_road": true, "min_town_distance": 2, "max_town_distance": 12,
  "max_per_region": 1, "rotations": true,
  "cells": [ {"offset": [0, 0], "mapgen": "motel_main"}, {"offset": [1, 0], "mapgen": "motel_wing"} ] }
```

### 6.2 Exemple de plan (`mapgen/motel_main.json`)
```json
{ "id": "motel_main", "size": [24, 24], "z": 0,
  "palette": { ".": {"terrain": "t_grass"}, "#": {"terrain": "t_wall_brick"}, "+": {"terrain": "t_door"},
			   "b": {"terrain": "t_floor", "furniture": "f_bed", "items": "motel_room"},
			   "Z": {"terrain": "t_floor", "monsters": "zombies_few"} },
  "rows": [ "........................", "..######+#######+######.", "…" ] }
```
Les lieux multi-étages auront un plan par `z` (voir §10). Les plans admettent rotation 90 / 180 / 270 et, plus tard, symétrie.

### 6.3 Tables de loot et groupes de monstres
Tables pondérées (`motel_room`, `farm_barn`, `reactor_control`…), avec quantité et probabilité. Les groupes de monstres sont pondérés par
type de lieu et de zone (centre-ville plus dense qu'une ferme isolée).

## 7. Exécution (chunks actifs)

- **ChunkManager** : garde les chunks dans un rayon autour du joueur (génération à rayon 3, déchargement à rayon 4 ≈ 49 chunks ≈ 28 000 cases).
  La vue actuelle (`VIEW_RADIUS = 20`) tient dans 2 chunks.
- La génération est étalée sur plusieurs frames (objectif : moins de 4 ms par chunk, jamais de gel visible).
- **Chunk** : tableaux compacts (terrain, mobilier), objets au sol, monstres, cases vues (`seen`, 576 bits). Le rendu est mis en cache par
  chunk (redessiné seulement quand il change) ; le brouillard et le FOV travaillent sur les chunks chargés.
- **Pathfinding** : A* **borné à la demande** (rayon maximal configurable, sur les chunks chargés) au lieu d'un `AStarGrid2D` global
  reconstruit à chaque changement de fenêtre. À valider au jalon 1.
- `World` garde son rôle (monstres, file d'actions, FOV) mais ne possède plus la carte : il délègue au `ChunkManager`.

## 8. Sauvegarde : « seed + deltas »

```
user://saves/<slot>/meta.json        { version, generator_version, engine_version, seed, joueur, horloge, ... }
user://saves/<slot>/chunks/<cx>_<cy>_<z>.json   deltas d'un chunk modifié
```
- Un chunk n'est écrit que s'il est **modifié** (objet ramassé ou posé, porte ouverte, monstre tué, case vue…).
- Au chargement d'un chunk : on **régénère** terrain, mobilier et loot depuis la seed, puis, s'il existe un delta, on **remplace** la liste
  d'objets au sol et les monstres par ceux sauvegardés. Un drapeau `populated` empêche de repeupler (un monstre tué ne revient pas).
- Les monstres qui se déplacent hors de la zone active sont rattachés au chunk où ils se trouvent.
- Création de partie : saisie d'une seed (texte ou nombre) ; vide = seed aléatoire, affichée et copiable.

## 9. Contenu visé

| Catégorie | Lieux |
|---|---|
| Ville | maisons (plusieurs plans), appartements, épicerie, supermarché, pharmacie, quincaillerie, bar / restaurant, station-service, commissariat, école, église, entrepôt, parking |
| Rural | **ferme** (maison + grange + champs), cabane, **motel** (au bord de route), camping, cimetière, carrière, ranch |
| Industrie / infra | **centrale nucléaire** (clôture, bâtiments, salle de contrôle, réacteur), usine, station d'épuration, centrale électrique |
| Militaire / secret | bunker, poste de contrôle, base militaire, laboratoire, **tour radio** |

Premier lot (jalons 3 à 5) : maison, station-service, motel, ferme, centrale nucléaire. Le reste est ajouté par simples fichiers de données.

## 10. Préparation des étages (sous-sols, étages, toits, tour radio)

Rien de ceci n'est implémenté au départ, mais le plan l'interdit de bloquer plus tard :
- Clé de chunk `Vector3i(cx, cy, z)`, plans et lieux avec un champ `z` ; une seule couche (`z = 0`) générée au début.
- Terrain « vide / air » et « toit » prévus dans `terrain.json`.
- Liaisons verticales (escalier, échelle, ascenseur, trappe) : terrains spéciaux avec `connects_z: +1 / -1` ; la case d'arrivée
  est la même `(x, y)` au niveau voisin.
- Un lieu multi-étages (tour radio, bunker, laboratoire, centrale avec sous-sol) déclare un plan par niveau dans `specials.json`.
- Plus tard : changement de niveau du joueur, FOV entre niveaux, A* par niveau, sauvegarde par `z` (déjà dans le nom des fichiers).

## 11. Jalons et critères de réception

| # | Jalon | Résultat attendu |
|---|---|---|
| 1 | RNG déterministe + chunks | terrain infini simple (herbe, arbres) ; même seed = mêmes chunks (test de déterminisme) ; déplacement, FOV, brouillard et monstres fonctionnent sur chunks ; arène de test conservée |
| 2 | Carte macro | biomes, rivières, lacs ; mini-carte de debug (touche) ; seed visible |
| 3 | Villes, routes, maisons | villes de plusieurs tailles, rues avec trottoirs, routes entre villes, ponts, maisons avec intérieur |
| 4 | Lieux spéciaux | système de placement par données ; motel, ferme, station-service |
| 5 | Grands lieux | centrale nucléaire multi-cellules (avec chemin d'accès) + une dizaine d'autres lieux |
| 6 | Loot et monstres | tables de loot, groupes de monstres par lieu et par densité de zone |
| 7 | Sauvegarde / chargement | seed + deltas, saisie de la seed à la création, un monde rechargé est identique, objets et monstres modifiés conservés |
| 8 | Finitions | portes et fenêtres dans le FOV, intérieurs / toits, tuiles UltiCa complètes |

À chaque jalon : mise à jour de `GAME_DESIGN.md`, plan court validé avant de coder, tests lancés seulement à ta demande.

## 12. Tuiles UltiCa

Chaque terrain / mobilier référence un id de tuile UltiCa. `tools/build_ultica_pack.py` récupère les sprites listés (il en faudra
beaucoup plus : routes, trottoirs, murs, portes, fenêtres, sols, mobilier). Un id absent a un **repli coloré** : le jeu reste jouable avec des sprites provisoires.

## 13. Risques et points à surveiller

- **Déterminisme du bruit** entre plates-formes : limité par le choix d'entiers pour les décisions clés ; on garde un test « empreinte de la carte macro ».
- **Cohérence aux frontières de région** : routes et villes calculées depuis les centres voisins, empreintes de lieux limitées à leur région.
- **Coût de génération** : étalement sur les frames, plans de lieux compilés une fois.
- **Évolution du générateur** : versionnée (`generator_version`) ; pas de compatibilité ascendante promise en développement.
- **Taille des sauvegardes** : seulement les chunks modifiés ; nettoyage des chunks dont le delta est redevenu vide.

## 14. Hors périmètre de cette étape

Météo, saisons, cycle jour/nuit détaillé et éclairage, hordes errantes, véhicules, rivières navigables, multi-joueur, mods.

## 15. Avancement

### Jalon 1 — RNG déterministe + chunks (fait)
- `WorldRng` (mélange 64 bits, couches constantes, seed depuis un texte), `TerrainDB` + `data/worldgen/terrain.json`, `ChunkGenerator`
  (herbe + arbres à 12 % par hachage de case, zone de départ dégagée), `Chunk`, `ChunkManager`, `PathFinder`.
- Le terrain est une fonction pure de `(seed, clé de chunk, mode)`. Les arbres restent des sprites triés par Y ; le sol est dessiné
  par chunk. Les cases vues survivent au déchargement d'un chunk (elles seront sauvegardées au jalon 7).
- Réglages : `ChunkManager` (`GEN_RADIUS` 3, `NEAR_RADIUS` 2, `KEEP_RADIUS` 4, `CHUNKS_PER_FRAME` 2), `PathFinder` (`MAX_EXPANSIONS` 1500,
  `MAX_RADIUS` 40), `FogLayer.DRAW_RADIUS` 40, `ChunkGenerator.TREE_DENSITY` 0,12, `main.gd` (`WORLD_SEED_TEXT`, `USE_TEST_ARENA`).
- Test : `tests/test_worldgen_determinism.gd` (ordres de génération différents, seeds différentes, densité, départ dégagé, arène).
- Limites connues : objets au sol et monstres restent globaux (pas encore rattachés aux chunks : jalons 6-7) ; un monstre hors des
  chunks chargés reste immobile ; le point de départ (5, 5) est provisoire.

### Jalon 2 — carte macro, biomes, rivières, lacs (fait)
- `WorldMap` (`worldgen/world_map.gd`) + `data/worldgen/biomes.json` (fréquences des bruits, seuils des lacs / rivières / gués, humidité
  des marais et forêts, densité d'arbres, couleurs). Tout se règle dans le JSON, la mini-carte sert d'outil de réglage.
- Nouveaux terrains : eau peu profonde (praticable), eau profonde (bloquante, pas de nage), eau de marais, boue, terre, sable.
  Nouveaux sprites UltiCa dans le pack (`tools/build_ultica_pack.py`).
- **Point de départ par seed** : première zone de terre sèche dégagée en spirale depuis l'origine (`WorldMap.spawn_cell()`), plus de (5, 5)
  provisoire ; l'arène garde (5, 5). Objets et zombies de test placés relativement au joueur.
- **Mini-carte de debug** (`ui/minimap_ui.gd`, touche `m`) : biomes en couleurs, joueur, seed, coordonnées, biome sous le curseur, zoom et
  déplacement de la vue. Elle montre l'inexploré (la vraie carte du joueur viendra plus tard).
- Test étendu : carte macro identique sur une instance neuve, départ sur terre sèche, relevé des biomes (eau entre 1 et 60 %, tous les
  biomes et les gués présents).
- Réglages initiaux posés « à l'aveugle » : à ajuster à l'œil avec la mini-carte (`lake.level`, `river.half_width`, `ford_level`,
  `swamp_*`, `forest_humidity`).
- Limites : pas de déplacement ralenti dans l'eau ni de nage ; pas de ponts (jalon 3, avec les routes) ; les arbres sont toujours posés
  sur de l'herbe.

### Jalon 3a — villes et rues (fait)
- `SettlementMap` (`worldgen/settlement_map.gd`) + `data/worldgen/towns.json` ; terrains `t_pavement`, `t_pavement_y`, `t_sidewalk`, `t_bridge`
  (sprites UltiCa ajoutés au pack) ; `ChunkGenerator` superpose villes et rues au terrain naturel ; départ en lisière de ville.
- Mini-carte (`m`) : rues, parcelles et jardins par-dessus les biomes, nom de la ville sous le joueur et sous le curseur.
- Test étendu : villes identiques sur une instance neuve, au moins 5 villes sur 7 × 7 régions, centre de ville = rue, aucune rue sur un lac,
  connexions des rues symétriques, peu de rues isolées, départ praticable, chunks autour du départ identiques dans 2 ordres.
- Réglages initiaux posés « à l'aveugle » : à ajuster avec la mini-carte (`count_weights`, `sizes`, `min_land_ratio`).
- Limites : pas encore de maisons (les parcelles sont de l'herbe), pas de routes entre villes ni de ponts hors des villes (3b), pas de mobilier (3c).

### Jalon 3b — routes entre villes et ponts (fait)
- `RouteMap` (`worldgen/route_map.gd`, une instance par `SettlementMap`) + section `routes` de `data/worldgen/towns.json` ; `SettlementMap`
  expose `routes()`, `cell_type(cell, with_routes)`, `town_cell_type()` (sans routes) et `is_wild_road()` ; `road_terrain` garde la nature
  autour d'une route hors ville (`keep_nature`) ; `ChunkGenerator` le transmet.
- Mini-carte (`m`) : les routes s'affichent jusqu'au zoom `MiniMapUI.ROUTES_MAX_ZOOM` (16).
- Test étendu : toute ville reliée, chemins de centre à centre, aucune route sur un lac, cellules de route = ROAD hors ville, connexions
  symétriques, aucune cellule isolée, déterminisme dans 3 ordres sur des instances neuves, et MESURE du coût (`perf routes` : 1re région,
  puis 6 régions voisines) à relever pour décider d'une anticipation ou d'un thread.
- Réglages initiaux posés « à l'aveugle » : à ajuster avec la mini-carte (`max_link_distance`, `costs`, `near_count`).
- Limites : une ville dont les voisines sont séparées par un grand lac peut rester sans route (la recherche est bornée) ; les routes
  zigzaguent parfois en escalier (pas de pénalité de virage) ; pas de maisons (3c).

### Jalon 3c — maisons avec intérieur et mobilier (fait)
- `MapgenDB` (`worldgen/mapgen_db.gd`) + `data/worldgen/mapgen/houses.json` : palette et plans ASCII 24 x 24 (façade au sud), compilés une fois ;
  4 plans (petite maison, maison familiale, pavillon, cabanon). `FurnitureDB` + `data/worldgen/furniture.json` : mobilier (index 1-based, 0 = rien).
- `SettlementMap.lot_plan(cell)` : 85 % des parcelles en plaine ou forêt reçoivent une maison ; plan tiré par `mix(seed, LAYER_MAPGEN, x, y, 1)`,
  rotation vers une rue voisine (`mix(..., 2)`). `ChunkGenerator` pose le terrain du plan, `generate_furniture()` le mobilier (inclus dans
  l'empreinte de test). `Chunk.furniture` stocke et dessine le mobilier ; `ChunkManager` combine terrain et mobilier pour praticable / opaque.
- Terrains ajoutés (`terrain.json`, à la suite) : `t_floor`, `t_wall_house`, `t_door`, `t_window` (champ `wall_link` : les murs se raccordent
  aux portes et fenêtres). Sprites ajoutés à `tools/build_ultica_pack.py` : à relancer pour régénérer `assets/`.
- Test étendu : plans valides (taille, palette, murs à l'intérieur, mobilier sur du sol), rotation bijective, tout le sol atteignable depuis la
  porte dans les 4 rotations, porte de façade côté rue et case devant praticable sur des maisons générées ; avertissement si des tuiles
  manquent dans le pack.
- Limites : pas de loot ni de monstres dans les maisons (jalon 6) ; porte sans état ouvert / fermé ; pas d'étage ni de toit (jalon 8) ; une
  maison ne se génère pas sur une cellule dont le centre est berge, marais ou eau ; une même maison peut recouvrir un coin d'eau voisin.

### Jalon 4 — lieux spéciaux (fait)
- `SpecialMap` (`worldgen/special_map.gd`) + `data/worldgen/specials.json` ; plans `data/worldgen/mapgen/places.json` ; `MapgenDB` charge maintenant
  plusieurs fichiers (plans de maison d'abord, puis de lieux : `plan_by_id`, `total_count`, `has_door`).
- Lieux : station-service (1 cellule), motel (2 cellules : accueil + aile de chambres), ferme (2 x 2 : deux champs clôturés, maison, grange).
- Terrains ajoutés : `t_field`, `t_fence`, `t_gas_pump` ; mobilier `f_rack` ; sprites ajoutés à `tools/build_ultica_pack.py` (à relancer).
- `SettlementMap` : `CellType.SPECIAL`, `cell_type(cell, with_routes, with_specials)`, `specials()`, `special_plan()`, `cell_plan()` ; mini-carte : couleur,
  légende et nom du lieu sous le curseur.
- Test étendu : plans de lieux valides et accessibles (4 rotations), aucune empreinte hors région, sur terrain libre et biome autorisé, route devant
  chaque façade, bâtiments générés cohérents, au moins un lieu de chaque type sur 7 x 7 régions, déterminisme dans 3 ordres sur instances neuves.
- Réglages initiaux posés « à l'aveugle » : à ajuster avec la mini-carte (`chance`, distances, `attempts`).
- Limites : pas de loot ni de monstres dans les lieux (jalon 6) ; une seule variante de plan par bâtiment ; pas de piste d'accès (les lieux longent
  une route) ; sprites de champ, clôture et pompe à vérifier à l'œil.

### Jalon 5 — grands lieux (fait)
- Dix lieux supplémentaires, uniquement en données : `data/worldgen/specials.json` (entrées ajoutées) et `data/worldgen/mapgen/big_places.json`
  (24 plans, chargé par `MapgenDB` après `places.json`).
- **Centrale nucléaire** (3 x 3 cellules, très rare, à au moins 6 cellules d'une ville) : enceinte clôturée avec portail et guérite tournés vers la
  route, bâtiment du réacteur (cœur infranchissable, consoles, machines), salle de contrôle, salle des turbines, entrepôt, poste de transformateurs, parking.
- **Autres lieux** : ranch (2 x 2), usine (2 x 2), station d'épuration (2 x 2, bassins d'eau profonde), camping (2 x 1), entrepôt (2 x 1), cimetière,
  chapelle, poste électrique, cabane. Champ `common` de `specials.json` : `false` = rare, exempté du contrôle « au moins un lieu par fenêtre » du test.
- Terrains ajoutés : `t_concrete`, `t_grave`, `t_reactor` ; mobilier `f_console`, `f_machinery_light` ; ids ajoutés à `tools/build_ultica_pack.py`
  (`t_chainfence` remplace `t_fence`, absent d'UltiCa : la tuile du terrain `t_fence` pointe désormais dessus).
- **Repli coloré** : une tuile ou un meuble sans sprite dans le pack est dessiné en carré coloré (champ `color` de `terrain.json` et `furniture.json`) ;
  `build_ultica_pack.py` n'échoue plus sur un id introuvable (avertissement), sauf si plus de la moitié manquent.
- Réglages initiaux posés « à l'aveugle » : à ajuster avec la mini-carte (`chance`, distances).
- Limites : pas de loot ni de monstres dans les lieux (jalon 6) ; une seule variante de plan par bâtiment ; ids UltiCa de réacteur, console, machine,
  tombe et béton à vérifier à l'œil (repli coloré sinon).

## 16. Monde « planétaire » et extension des structures (jalons 9 à 15)

### Jalon 9 — Géographie planétaire (océans, continents, climats, relief)

**Principe** : `WorldMap` reste une fonction pure de (seed, coordonnées), mais on ajoute des champs à GRANDE échelle au-dessus des
champs actuels (altitude, humidité, rivière). Le monde reste infini ; il est organisé comme une Terre en miniature.

**Échelles (réglables dans `biomes.json`)** : 1 case = 1 m.
| Notion | Ordre de grandeur | Temps de marche indicatif |
|---|---|---|
| Continent | 15 000 à 40 000 cases de large | plusieurs heures à plusieurs jours de jeu |
| Océan | 10 000 à 30 000 cases entre deux continents | infranchissable à pied |
| Archipel / île | 300 à 3 000 cases | |
| Bande climatique | 12 000 cases de haut | |

**Nouveaux champs de bruit** (couches `LAYER_BIOME` à la suite, jamais renumérotées) :
- `continent` : très basse fréquence (~0,00003), avec déformation de domaine (domain warping) pour des côtes irrégulières. Sous `sea_level` = océan.
- `elevation` : relief à moyenne échelle (collines, chaînes de montagnes en « arêtes » : valeur absolue d'un bruit, comme les rivières).
- `temperature` : fonction de la LATITUDE (y) + un peu de bruit + altitude. Les bandes se répètent à l'infini (pôle, tempéré, tropical,
  tempéré, pôle...) : on garde un monde sans bord mais avec des climats lisibles.
- `humidity` existant, désormais pilotée aussi par la distance à l'océan (côtes humides, intérieur sec).
- `river` / `ford` existants : les rivières naissent en montagne et se dirigent vers les côtes (approximation : le bruit actuel est conservé,
  atténué en zone désertique ; pas de vraie hydrologie).

**Nouvelles natures de case** (ajoutées À LA FIN de `WorldMap.Kind`, de `kinds` dans `biomes.json` ET de `RouteMap.KIND_IDS` : un seul ordre) :
`ocean_deep, ocean_shallow` (plateau continental), `beach, cliff` (falaise, infranchissable sauf rampes), `hills, mountain`
(roche, infranchissable en altitude, avec cols), `snow, tundra, taiga, desert, savanna, jungle`.
Plaine / forêt / marais existants restent pour le climat tempéré.

**Règle de climat** (entiers + seuils en données) : (température, humidité, altitude) -> nature.
| | humide | moyen | sec |
|---|---|---|---|
| chaud | jungle | savane | désert |
| tempéré | forêt | plaine | steppe (plaine clairsemée) |
| froid | taïga | toundra | toundra |
| glacial | neige | neige | neige |

**Impacts sur le code existant (à traiter dans ce jalon)** :
- `SettlementMap` : villes interdites en désert profond / neige / montagne (`_is_buildable`) ; les grandes villes tendent vers les côtes
  (ports) ; densité de villes proportionnelle à la fertilité (peu de villes en désert).
- `RouteMap` : coûts par nature pour les nouveaux biomes (montagne très chère, désert moyen, neige chère, océan interdit) ; routes
  limitées à un même continent ; **ponts et tunnels** sur les détroits étroits (< N cellules) = lien entre deux continents proches.
- `SpawnCell` : départ toujours sur un continent, de préférence en climat tempéré.
- Sprites : sable, neige, roche, jungle, désert, falaise (`tools/build_ultica_pack.py`) ; repli coloré tant qu'ils manquent.
- Mini-carte de debug : zooms supplémentaires jusqu'à 4 096 cases par échantillon pour voir continents et océans ; légende des nouveaux biomes.
- **Performance** : `kind_at` est appelé très souvent (spawn, `_site_ok`, mini-carte). Optimisations prévues : sortie rapide si
  `continent < sea_level` (océan : on ne calcule pas le reste), cache par cellule macro, échantillonnage grossier pour les décisions
  de ville.

**Réglages en données** (`biomes.json`, nouvelle section `planet`) :
`{"continent": {"frequency": 0.00003, "octaves": 4, "warp": 0.4}, "sea_level": -0.05, "shelf_margin": 0.04,
  "climate": {"band_height": 12000, "temp_noise": 0.15, "lapse": 0.6}, "mountain": {"threshold": 0.62, "pass_width": 0.05},
  "coast": {"beach": 0.012, "cliff_slope": 0.08}}`

**Test** : déterminisme dans 3 ordres sur des instances neuves ; relevé grossier (comme aujourd'hui) avec : océan entre 40 et 75 % de
la surface, au moins 3 climats présents, aucun départ hors continent, routes et villes jamais sur l'océan ni en montagne
infranchissable, toute montagne a au moins un col.

**Limites assumées** : pas de vraie érosion ni de vraie hydrologie ; les rivières ne finissent pas forcément à la mer.

### Jalon 9b — Traversée de l'eau (nage, puis bateaux)
Sans cela, un océan est un mur et les îles sont perdues. Proposition par étapes :
1. **Nage** (jalon 9b, petit) : l'eau profonde devient praticable en nageant : stamina qui chute vite, objets lourds = risque de noyade
   (charge > seuil = on coule), vêtements mouillés (plus tard). Distances maximales de nage courtes en pratique.
2. **Bateaux** : arrivent avec les véhicules (hors périmètre actuel). Les ports, marinas et épaves sont posés dès maintenant.
3. **Ponts / tunnels / ferries** pour les détroits proches (jalon 9).

### Jalon 10 — Moteur : modes de placement et briques communes
(identique à l'ancien jalon 9) + ce qui est nouveau :
- placements par **climat** (`climates: ["desert"]`) et par **relief** (`mountain`, `coast`, `island`, `open_ocean`) ;
- `island` : îlot isolé en mer (distance à la côte min / max) ; `open_ocean` : empreinte 100 % en eau profonde, loin de toute côte ;
- jetée / accès : `t_pier` depuis la côte, ou aucun accès (lieux de décor, ou accessibles seulement à la nage / en bateau).

### Jalons 11 à 15 : les structures (46 lieux)
Les listes de l'ancien plan restent valables, avec ces ajustements dus à la planète :
- **Jalon 11 — Urbain** (16) : ajouts côtiers : `port` (grues, conteneurs, entrepôts), `airport` (piste de 6 x 1 cellules, tour, hangars).
- **Jalon 12 — Routes** (6) : + `border_checkpoint` entre deux continents reliés par un pont ; les barrages se placent sur des routes d'un même continent.
- **Jalon 13 — Militaire / secret** (9) : `radio_tower` en montagne ou en plaine ; `bunker`, `missile_silo`, `lab` possibles en montagne ou en désert (`near_road: false` + piste).
- **Jalon 14 — Mer et eau** (6 + 4) : le **porte-avions** passe à l'échelle réelle : `open_ocean`, jusqu'à 14 x 2 cellules (la réduction « 6 x 2 » est abandonnée) ; `oil_platform`, `lighthouse_island`, `cargo_wreck`, `marina`, `hydro_dam`, + **`island_village`, `shipwreck_field` (épaves en eau peu profonde), `pirate_base`, `research_station`** (île ou côte).
- **Jalon 15 — Rural et divers** (9) : + **`oasis`, `ski_resort`, `volcano_site`, `ancient_ruins`, `cave_entrance`, `desert_outpost`, `arctic_base`** : lieux par climat.

### Ce qui donne « plein de choses à découvrir »
- **Points d'intérêt par biome** : désert = oasis, épaves d'avions, avant-postes ; toundra = base arctique, stations de recherche ;
  jungle = ruines, temples ; montagne = mines, bunkers, observatoires ; côtes = phares, ports, épaves.
- **Carte du joueur** (jalon 8 : finitions) : la mini-carte de debug devient une vraie carte qui ne montre que l'exploré, avec
  repères posés par le joueur ; les lieux repérés (vus ou entendus parler) s'y affichent.
- **Rumeurs et indices** (plus tard) : notes, radios et cartes trouvées dans le loot qui révèlent l'emplacement d'un lieu rare.
- **Lieux uniques** : une poignée de lieux « légendaires » par monde (`max_per_world_window`), jamais deux fois proches.

### Risques propres à ce changement
- **Équilibrage de l'échelle** : un continent de 30 000 cases est énorme à pied (marche automatique indispensable) ; l'échelle se règle dans `biomes.json`, on la valide à l'œil avec la mini-carte avant tout le reste.
- **Compatibilité des seeds** : le terrain actuel change entièrement (acceptable en développement, `generator_version` incrémenté).
- **Coût de calcul** : voir ci-dessus ; on mesure comme pour les routes (`perf` dans le test).
- **Nombre de terrains** : ~12 natures de case, mais la limite des 255 terrains reste confortable.
- **Eau profonde et nage** : tant que 9b n'existe pas, un océan est un mur ; le départ est donc toujours sur un continent.
