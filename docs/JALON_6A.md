# Jalon 6a : bestiaire en JSON, population ambiante, chunks propriétaires (à reporter dans la doc)

`GAME_DESIGN.md`, `WORLD_GEN.md` et `MONSTER_SPAWN.md` ne sont pas régénérés : coller les passages ci-dessous.

## Ce qui est fait
- **`data/monsters.json`** (91 monstres) : les 14 d'origine (valeurs identiques) + bases civiles, commerces, faune et créatures de climat. `MonsterDB` (`scripts/data/monster_db.gd`) les charge ; `MonsterData.create(id)` et `zombie()`, `wolf()`... restent en façade.
- **Population ambiante** : `SpawnGenerator.generate(seed, clé, terrain, mobilier, population, points sûrs)`, fonction pure. Données : `data/worldgen/spawn_groups.json` (13 groupes) et `data/worldgen/ecology.json` (densités, plafonds).
- **Chunks propriétaires** : `ChunkManager` peuple un chunk à son premier chargement (`_populated`), met ses monstres en réserve au déchargement (`_monster_store`, via `Monster.to_dict()`) et les restaure au rechargement (`World.restore_monster`). Un monstre tué ne réapparaît pas.
- **Comportements** : `passive` (cerf, renard : fuit, se défend acculé) et `territorial` (sanglier, ours : ne repère le joueur qu'à moins de 5 cases, abandonne la poursuite à 10).
- **Capacité `ARMOR(n)`** : chaque coup reçu perd n PV (minimum 1). Les autres capacités sont lues et ignorées jusqu'à leur jalon.
- **Repli visuel** : tuile absente du pack = sprite `mon_zombie` (ou `mon_wolf` pour un animal) teinté (`tint`).
- `main.gd` : réglage `POPULATION`, zone sûre autour du départ (`world.safe_centers`), les 3 zombies de test ne subsistent que dans l'arène.
- Test : `tests/test_spawn.gd`.

## Écarts avec `MONSTER_SPAWN.md`
- L'écologie est dans `ecology.json` (comme prévu §2.1) et ne contient que `limits` et `ambient` ; `contamination` et `substitutions` arrivent en 6c.
- Les groupes de lieux (hôpital, labo, bunker...) arrivent en 6b : en 6a, un lieu spécial ne reçoit **aucun** monstre, et à l'intérieur d'un bâtiment (maison, commerce) non plus. Seules les cases hors bâtiment comptent (rues, routes, jardins, nature).
- La règle « plus de faune hostile loin des villes » (×1.6 au-delà de 40 cellules) n'est pas appliquée (elle demande la distance à la ville la plus proche, donc `SpawnGenerator` lirait les régions voisines).
- L'eau (lacs, rivières, océan) n'a aucun monstre : les aquatiques arrivent en 6d.
- Les poids de groupe peuvent être décimaux (ex. `sandworm: 0.1`).

## Limites connues
- **Journal et armure** : `Player._attack` affiche toujours « -6 PV » (dégâts bruts) même quand l'armure du monstre réduit le coup. À corriger en touchant `player.gd` (utiliser la valeur réellement infligée).
- Densités très faibles hors ville (≈ 1 monstre pour 2 à 4 chunks de nature) : à régler avec `POPULATION` ou `ecology.json`.
- Temps gelé hors des chunks chargés ; un monstre mis en réserve perd sa cible (`has_target`).
- Un chunk lointain peuplé hors d'un `update_fov()` apparaît caché jusqu'au prochain déplacement du joueur (sans conséquence : il est hors de vue).
- Plafond global : 300 monstres (`World.MAX_MONSTERS`) ; un chunk neuf au-delà n'est pas peuplé et retentera à son prochain chargement.

## Sprites
Aucun nouvel id : les `mon_<id>` utilisés sont ceux déjà listés dans `MISSING_SPRITE.md` (section « Jalon 6 »). `mon_zombie` et `mon_wolf` (sprites de repli) existent déjà dans le pack.

## WORLD_GEN.md
- §4.7 : « Population ambiante (jalon 6a) : `SpawnGenerator`, voir `MONSTER_SPAWN.md`. »
- §5 : lignes `spawn_groups.json`, `ecology.json`, et `data/monsters.json`.
- §9 : jalon 6 découpé en 6a (fait), 6b, 6c, 6d.
- §10 : `test_spawn.gd`.

## GAME_DESIGN.md
- « Monstres » : définis dans `data/monsters.json` (91 types), population par chunk, comportements passif / territorial, ARMOR.
- Architecture : `data/` : `monster_db.gd` + `monsters.json` ; `worldgen/` : `spawn_generator.gd` ; `ChunkManager` : réserve de monstres.
- Réglage de partie : `POPULATION` dans `main.gd`.
- Tests : ajouter `test_spawn`.
- Limites : voir ci-dessus.
