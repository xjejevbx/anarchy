# Jalon 6c : contamination, mutants, expériences ratées, capacités (à reporter dans la doc)

`GAME_DESIGN.md`, `WORLD_GEN.md` et `MONSTER_SPAWN.md` ne sont pas régénérés : coller les passages ci-dessous.

## Ce qui est fait

- **`ContaminationMap`** (`scripts/worldgen/contamination_map.gd`) : fonction pure de (seed, chunk). `sample(seed, chunk)` renvoie `{level (0 à 1), type}` : radiation, toxique, expérience, feu, maudit, pétrole. Niveau d'une source = force x (1 - distance / rayon) ^ falloff, la distance étant mesurée à la cellule la plus proche de l'empreinte du lieu (donc la force partout sous le lieu). Le niveau d'un chunk est le plus fort de ses sources. Seules la région du chunk et, près d'un bord, sa voisine sont lues (au plus 4 régions), mises en cache par instance de `SettlementMap`.
- **Sources** (`ecology.json`, section `contamination.sources`) : centrale nucléaire (1,0 ; 14 cellules), laboratoire (0,9 ; 10), silo (0,7 ; 8), bunker et entrée de bunker (0,4 ; 5), usine (0,5 ; 6), station d'épuration (0,6 ; 6), plateforme pétrolière (0,5 ; 6), volcan (0,8 ; 9), station de recherche en mer (0,6 ; 6), ruines antiques (0,4 ; 5). Tous ces lieux existent déjà dans `specials.json` (jalons 10 à 15).
- **Substitution** : un monstre tiré est remplacé par sa variante mutante avec la probabilité niveau x `substitute_chance` (0,8). Table dans `ecology.json` (`contamination.substitutions`) : loup -> loup mutant / chien d'acide / chien de feu, ours -> ours mutant / chimère, cerf, sanglier, corbeau, rat, zombie civil -> zombie irradié / ballon / sujet de test / calciné, etc. Une valeur `affix:<id>` donne un affixe au lieu de changer de monstre (zombie -> `irradié`, `toxique`, `calciné`). Une règle de lieu avec `contaminate: false` l'ignore (cœur du réacteur).
- **Faune contaminée** : au-dessus de `ambient_switch_level` (0,6), la couche ambiante tire dans `eco_contaminated_<type>` (`spawn_groups_contamination.json`) : plus de faune normale, seulement des mutants.
- **Monstres** : `data/monsters_mutants.json` (20 nouveaux, total 171) : ours / sanglier / corbeau mutants, rat irradié, chien d'acide, chimère, homoncule, essaim de labo, traqueur, rampant mutant, expérience gonflée, masse de chair, blob, sujet de test zombie, chien de feu, zombie calciné, rampant de magma, squelettes, momie.
- **Capacités qui agissent** (`monsters.json` et affixes) :

| Capacité | Effet |
|---|---|
| `EXPLODE(type)` | à la mort, explosion (`World.explode`, types `acid`, `gas`, `fire`, `frag`, `electric`) : blesse le joueur et les monstres du rayon, le gaz empoisonne seulement ; un monstre tué par une explosion peut exploser à son tour |
| `AURA_RAD` / `FIRE_AURA` / `COLD_AURA` | effet d'état sur le joueur à portée (rayon 2 / 1 / 1) : `radiation`, `burn`, `frostbite` (`Monster.AURA_EFFECTS`) |
| `REGEN(x)` | x PV par seconde, après 5 s sans dégât |
| `LEAP` | bond de 2 à 3 cases en ligne (recharge 8 s) |
| `CHARGE` | course de 4 à 8 cases en ligne droite, premier coup x1,5 (recharge 10 s) |
| `GRAB` / `CONSTRICT` | le coup draine 20 de stamina |
| `SPLIT` | chaque coup détache un petit monstre (moitié des PV), jusqu'à la génération 3 |
| `SWARM` | apparaît en essaim (2 à 4 voisins de plus) |
| `THROW(type)` | le tir lance une explosion de rayon 1 sur le joueur (grenadier) |
| `BURST` | le tir fait 3 coups à moitié dégâts (policier d'intervention : ajout d'un tir « Rafale ») |

- **Affixes** : `irradié` (aura radioactive), `toxique` (attaque empoisonnée), `calciné` (aura de feu), `électrifié` (drain de stamina), `gonflé` (explose) ; `gelé` gagne l'aura de froid. 14 affixes au total. Champs `abilities` et `effect` dans `monster_affixes.json`.
- **Statuts** : `StatusEffects` connaît `radiation`, `burn`, `frostbite` ; le drain de stamina peut porter son propre texte.
- **Infobulle / mode regard** : les capacités et modificateurs d'un monstre sont listés.
- **Tests** : `tests/test_contamination.gd` (nouveau : données, niveau = référence recalculée sans la logique de voisinage, substitutions, capacités dans un monde réel, mesure de perf) ; `test_spawn.gd` inchangé (valide aussi les nouveaux monstres et substitutions).

## Écarts avec `MONSTER_SPAWN.md`
- Les sources sont dans `ecology.json` (et non dans un champ `emits` de `specials.json`) : on évite de réécrire un fichier de 8 Ko pour six lignes.
- La contamination est évaluée par chunk (pas par case) ; le niveau et le type du chunk s'appliquent à tout son contenu.
- `GRAB` et `CONSTRICT` ne font que drainer la stamina : l'immobilisation demande de toucher `player.gd` (jalon de combat). `FLY`, `SPORE`, `SUMMON`, `RAISE`, `STEALTH`, `BLIND_HEARING`, `SWIM`, `AQUATIC` restent pour 6d.
- La grenade (`THROW`) ignore la ligne de vue : elle explose sur le joueur dès qu'il est à portée de tir.
- Le groupe `eco_contaminated_oil` n'existe pas : la contamination « pétrole » (plateforme en mer) ne change rien tant que les eaux n'ont pas de monstres (6d).

## Limites connues
- **Coût** : lire les sources d'une région voisine force la génération de ses lieux (donc de ses routes) un peu avant l'arrivée du joueur ; le travail total ne change pas (la région serait calculée en s'y promenant). `test_contamination.gd` affiche le coût à froid (25 chunks) pour régler les rayons. Au-delà de 16 cellules de rayon, il faudrait étaler le calcul.
- Les chunks déjà peuplés avant la contamination ne sont pas repeuplés (monstres rangés par chunk, comme avant).
- `Player._attack` affiche toujours « -6 PV » (voir JALON_6A.md).

## Sprites
Aucun nouvel id : les `mon_<id>` utilisés sont déjà listés dans `MISSING_SPRITE.md` (section « Jalon 6 »).

## WORLD_GEN.md
- §4.7 : « Contamination (jalon 6c) : `ContaminationMap`, voir `MONSTER_SPAWN.md` §5. »
- §5 : lignes `monsters_mutants.json`, `spawn_groups_contamination.json`, section `contamination` d'`ecology.json`.
- §9 : jalon 6c fait. §10 : `test_contamination.gd`.

## GAME_DESIGN.md
- « Monstres » : capacités qui agissent (explosion, auras, régénération, bond, charge, division, essaim, rafale), contamination et faune mutante ; 171 types.
- Architecture : `worldgen/contamination_map.gd`, `World.explode` / `spawn_split`.
- Tests : ajouter `test_contamination`.
- Limites : voir ci-dessus.
