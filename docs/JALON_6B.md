# Jalon 6b : audit de l'axe vertical, population par lieu, sommeil, affixes (à reporter dans la doc)

`GAME_DESIGN.md`, `WORLD_GEN.md` et `MONSTER_SPAWN.md` ne sont pas régénérés : coller les passages ci-dessous.

## 1. Audit de l'axe vertical (z)

État AVANT ce jalon, et correction :

| Élément | Avant | Après |
|---|---|---|
| Clés de chunk, `_seen_store`, `_populated`, `_monster_store` | `Vector3i` avec `z` : correct | inchangé |
| RNG : `rng_for(seed, couche, x, y, z)` | `z` occupait la 3e coordonnée, rien pour séparer d'autres flux | `mix` / `rng_for` acceptent une 4e coordonnée `d` (0 = ignorée : **les seeds existantes ne changent pas**) |
| `ChunkGenerator.generate` à `z != 0` | **BUG** : copie du terrain de surface (herbe, arbres) | z < 0 : roche pleine (`t_rock`) ; z > 0 : vide (`t_air`) ; plan d'étage possible (voir 2) |
| `generate_furniture` à `z != 0` | vide | mobilier du plan d'étage s'il existe |
| Terrains | ni roche, ni vide, ni escalier | `terrain_vertical.json` (`t_rock`, `t_air`, `t_stairs_up`, `t_stairs_down`), champ `connects_z`, `TerrainDB.z_link(index)` |
| `ChunkManager` | un seul étage implicite ; **BUG** : les chunks d'un autre z n'étaient jamais déchargés | étage actif `level`, `set_level(z)`, déchargement par z, `chunk_at` sur l'étage actif |
| Monstres | pas de `z` : au déchargement d'un chunk souterrain on aurait pris les monstres de la surface | `Monster.z`, réserve par clé 3D (`m.z == key.z`) |
| Objets au sol | indexés par `Vector2i` seul : un objet posé en sous-sol serait apparu en surface | rangés par étage (`World._ground_by_level`), API inchangée (`get_ground_items(cell)` = étage actif) |
| `World` | pas de notion d'étage | `get_level()`, `change_level(z)` (prépare les escaliers) |
| Spawn | `z != 0` : rien | inchangé (les règles `min_depth` des lieux à étages viendront avec le jalon 8) |

**Modèle retenu : UN seul étage simulé à la fois.** Toutes les requêtes par case (`Vector2i` : `is_walkable`, `FieldOfView`, `PathFinder`, `AutoPath`, mode regard) portent sur l'étage actif ; les autres étages sont déchargés (cases vues et monstres gardés par clé 3D). Le joueur n'a pas de `z` propre : c'est `World.get_level()`.

**Reste à faire pour le jalon 8 (étages)** : utiliser un escalier (`TerrainDB.z_link`) pour appeler `World.change_level` ; plans d'étage ; toits et vue des étages voisins ; `MiniMapUI` et `LookUI` lisent la surface (`ChunkManager.key_of(cell)` avec z = 0) ; la sauvegarde (jalon 7) gardera `z` dans les clés (déjà le cas).

## 2. Plans d'étage (convention)

Un plan nommé `"<id du plan de surface>@<z>"` (ex. `urban_hospital@-1`) est l'étage de ce plan, dans n'importe quel fichier de `data/worldgen/mapgen/`. `ChunkGenerator.level_plan(seed, key)` le retrouve (même rotation que la surface) et le superpose à la roche ou au vide ; les `.` gardent la roche / le vide. Aucun plan d'étage n'existe encore. Escalier : caractère de palette avec `t_stairs_down` sur le plan de surface et `t_stairs_up` au même endroit sur le plan `@-1`.

## 3. Ce qui est fait pour la population (6b)

- **Couche lieu** : `data/worldgen/place_spawns.json` (73 plans : maisons, 14 bâtiments de ville, hôpital, clinique, maison de retraite, garage, station-service, motel, ferme, ranch, centrale, camping, cimetière, chapelle, entrepôt, usine, égouts, poste électrique, avant-poste du désert, phare, plateforme, 7 lieux de route, port, aéroport). Modes `floor`, `paved`, `nature`, `any` et `affinity` (meuble ou terrain : le dormeur dans son lit, le fidèle sur son banc, le fossoyeur près des tombes). Règles : `density`, `dormant`, `rare`, `affix`, `chance`. `{"copy": id}` réutilise les règles d'un autre plan.
- **Groupes** : `data/worldgen/spawn_groups_places.json` (80 groupes) ; **monstres** : `data/monsters_places.json` (60 monstres, total 151).
- **États** : `sleep` (immobile, Zzz), `idle`, `guard`. Réveil : le joueur approche (`wake_range` x posture, visible, 15 % par tour de 5 s), bruit (`World.make_noise` : sprint 8 cases, combat 10 ; le signal `action_performed` suffit, `player.gd` n'est pas touché), coup reçu, hurlement, ou voisin qui se réveille. `AMBUSH` : ne se réveille que si le joueur est à 2 cases (alors « surgit ! »), sourd au bruit. `GUARD` : ne dort jamais, revient à son poste (`home_cell`), abandonne la poursuite à 8 cases. `ERRATIC` : 30 % des pas de poursuite au hasard. `DORMANT` : démarre endormi.
- **Affixes** : `data/monster_affixes.json` (9 : gelé, momifié, envahi, putréfié, blindé, enragé, vétéran, grouillant, alpha). `MonsterDB.create(id, affixes)` : nom accordé au genre (« Réceptionniste zombie gelée »), PV, durée du pas, dégâts, armure, menace ; au plus 2 ; filtrés par tags. Tirage : règle `affix`, affixes de climat d'`ecology.json` (gelé en climat froid, momifié en désert, envahi en jungle et marais, putréfié en marais ; cases extérieures, zombies seulement), alpha dans un groupe de 4 et plus (8 %). Les effets spéciaux (aura de froid, spores, explosion à la mort) arrivent en 6c.
- **Plans** : `data/worldgen/mapgen/medical.json` (hôpital, clinique, maison de retraite, garage), mobilier `furniture_medical.json` (lit d'hôpital, brancard, table d'opération, tiroir de morgue). Ils entrent dans les zones de `towns.json` (hôpital : centre et mi-distance, rayon de ville 4 minimum). `MapgenDB`, `TerrainDB` et `FurnitureDB` chargent plusieurs fichiers dans l'ordre (**l'index d'un terrain ou d'un meuble ne change jamais**).
- **Plafonds** : un chunk portant un plan accepte 20 monstres et 60 de menace (`place_max_per_chunk`, `place_threat_budget`), 12 et 30 sinon.
- **Tests** : `tests/test_spawn.gd` (étendu : affixes, population de 12 plans sur leur propre terrain, états, bruit, réveil en chaîne), `tests/test_vertical.gd` (nouveau), `tests/test_jalon11.gd` (accepte les 4 bâtiments médicaux).

## 4. Écarts avec `MONSTER_SPAWN.md`
- Pas de `place_spawns` pour : `sewage_basin` (eau), bunker, silo, labo, lieux marins et ruraux des jalons 13 à 15 (leurs monstres ou leurs étages n'existent pas encore).
- Hôpital : le sous-sol d'expériences (`min_depth`) et le tirage de `patient_zero` attendent les étages et les uniques ; la quarantaine et le service psychiatrique sont des règles rares sur le sol de l'hôpital (pas de meuble dédié).
- Un seul flux aléatoire par chunk (les règles se suivent dans l'ordre du fichier) au lieu d'un flux par règle : déterministe aussi, mais **les populations de 6a changent** (acceptable en développement).
- Les `rare` d'affixes `veteran` des lieux rares ne sont pas encore posés dans `place_spawns.json` (la règle `affix` est prête).

## 5. Limites connues
- Un monstre endormi ne réveille ses voisins qu'à son propre réveil (pas de cri de groupe plus large).
- `zombie_sniper`, `zombie_flamer`, `zombie_grenadier` : le tir à distance existe, mais sans capacité `BURST`, `THROW` ou `EXPLODE` (6c).
- `Player._attack` affiche toujours « -6 PV » (armure : voir JALON_6A.md).
- Le changement de plans de `towns.json` modifie les bâtiments tirés sur les parcelles (nouveaux plans dans les tables).

## 6. À reporter
- **WORLD_GEN.md §8 (étages)** : remplacer « Rien d'implémenté » par la section 1 ci-dessus ; §4.4 et §5 : `medical.json`, `terrain_vertical.json`, `furniture_medical.json` ; §9 : jalon 6b fait ; §10 : `test_vertical.gd`.
- **MONSTER_SPAWN.md** : statut 6b fait (voir section 4) ; §16.1 : les 4 plans médicaux sont créés.
- **GAME_DESIGN.md** : statut monde (jalon 6b), Architecture (`monster_db`, `spawn_generator`, étage actif de `ChunkManager`, `World.get_level`), Tests (`test_spawn`, `test_vertical`), Limites (voir section 5).
