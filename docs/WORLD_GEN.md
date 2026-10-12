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

### 5.2 Villes
- Chaque région calcule **ses propres centres de villes** (grille jitterée : nombre 0..N, position et taille tirés avec `mix(seed, LAYER_TOWN, rx, ry)`).
  Les centres des régions voisines sont calculables sans les générer, donc pas de couture visible aux bords de région.
- Tailles : hameau (~3 × 3 cellules), village, ville, grande ville (~12 × 12). Un tissu urbain = rues principales + grille secondaire.
- Zonage par distance au centre et bruit : **résidentiel, commercial, industriel, civique**. Chaque cellule de parcelle choisit un bâtiment
  selon des poids du zonage.
- Les cellules de route portent un **masque de connexions** (droit, coin, T, croix) + trottoirs ; le plan est choisi selon ce masque.

### 5.3 Routes entre villes
Chaque ville se relie à ses 2 ou 3 plus proches voisines (y compris dans les régions voisines, connues par leurs centres). Chemin : A* sur la
carte macro avec un coût par biome (forêt chère, rivière interdite sauf **pont**). Le résultat est une fonction pure des deux centres, donc
identique quel que soit l'ordre de génération ; il est mis en cache.

### 5.4 Lieux spéciaux (motel, ferme, centrale…)
Définis en données (§6.2). Algorithme déterministe par région : on parcourt les lieux **triés par priorité puis par id** ; pour chacun,
des tentatives de placement tirées avec `mix(seed, LAYER_SPECIAL, rx, ry, id)` ; un candidat est valide si biome, distance aux villes,
adjacence à une route, empreinte libre (multi-cellules, rotation) et quota (max par région / rareté globale) sont respectés.
Une **empreinte ne franchit jamais une frontière de région** (règle simple qui évite toute dépendance entre régions).
Un lieu isolé reçoit un **chemin d'accès** (A* local vers la route la plus proche).

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
