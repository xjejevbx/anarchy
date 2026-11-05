# MONSTER_SPAWN.md — Population du monde : monstres, apparitions, écologie (jalon 6)

Document de conception ET d'état (les anciens `JALON_6A/6B/6C.md` y sont fusionnés). Complète `WORLD_GEN.md` (§4.8, §9) et `GAME_DESIGN.md`. Toutes les valeurs chiffrées (PV, densités, probabilités) sont posées « à l'aveugle » : à régler en jeu, comme `Infection.DURATION`.

**Le bestiaire, les groupes et les tables de lieux vivent dans les JSON** (source de vérité, ne plus les recopier ici) : `data/monsters.json`, `monsters_places.json`, `monsters_mutants.json`, `monster_affixes.json`, `data/worldgen/spawn_groups*.json`, `place_spawns.json`, `ecology.json`. Ce document garde les principes, les mécanismes, l'état d'avancement et ce qui reste à créer.

## 0. État d'avancement

| Sous-jalon | Contenu | État |
|---|---|---|
| 6a | `monsters.json` (91 monstres), `MonsterDB`, `SpawnGenerator` (couche ambiante), chunks propriétaires (réserve, restauration), comportements passif / territorial, `ARMOR(n)`, repli visuel teinté | **fait** |
| 6b | Axe vertical (préparation), population par lieu (`place_spawns.json`, 73 plans, mode `affinity`), états `sleep` / `idle` / `guard`, bruit et réveil, `DORMANT` / `GUARD` / `AMBUSH` / `ERRATIC`, 9 affixes, plans médicaux (hôpital, clinique, maison de retraite, garage), mobilier médical | **fait** |
| 6c | `ContaminationMap`, substitutions mutantes, faune contaminée, 20 mutants, capacités `EXPLODE`, auras, `REGEN`, `LEAP`, `CHARGE`, `GRAB`/`CONSTRICT` (drain), `SPLIT`, `SWARM`, `THROW`, `BURST`, 5 affixes de plus (14 au total), statuts `radiation` / `burn` / `frostbite` | **fait** |
| 6d | `SUMMON`, `RAISE`, `STEALTH`, `BLIND_HEARING`, `SWIM`, `AQUATIC`, `FLY`, `SPORE`, pathfinding nautique, faune marine, uniques, rattrapage et migration de la faune | à faire |
| loot | Champ `drops`, tables de loot, `LOOT_CARRIER` | à faire |

Total : **171 monstres** (91 + 60 + 20), 14 affixes, 100+ groupes, 73 plans peuplés.

## 1. Principes

1. **Le lieu raconte une histoire** : les monstres d'un bâtiment sont ceux qui s'y trouvaient (infirmiers à l'hôpital, soldats au bunker).
2. **Le monde raconte la cause** : les mutants apparaissent autour des sources de contamination ; la faune dépend du biome et du climat.
3. **Déterminisme total** : les monstres initiaux d'un chunk sont une fonction pure de `(seed, clé de chunk)`. Aucun `randi()` global à la génération (le temps de jeu, lui, utilise l'aléa d'exécution : réveils, tirs).
4. **Peuplé une seule fois** : un monstre tué reste tué ; un monstre vivant déchargé est mis en réserve et rechargé tel quel.
5. **Tout en données** : ajouter un monstre, un groupe ou la population d'un lieu = éditer du JSON (sauf nouvelle capacité).
6. **Combinatoire par modificateurs** : bases + affixes combinables selon des règles de compatibilité (tags).
7. **Dosage** : plafonds par chunk, monstres dormants (discrets), danger croissant avec la rareté du lieu.

## 2. Architecture

| Fichier | Rôle |
|---|---|
| `scripts/data/monster_db.gd` | `MonsterDB` : charge les trois `monsters*.json` et les affixes, `create(id, affixes)`, validation (`errors()`), `default_state_of`, `threat_of`, `affix_ok` |
| `scripts/data/monster_data.gd` | `MonsterData` : données d'un type (façade `zombie()`, `wolf()`...) ; `has_ability`, `ability_arg`, `ability_value` |
| `scripts/worldgen/spawn_generator.gd` | `SpawnGenerator.generate(seed, key, terrain, furniture, population, safe_centers, ...)` : fonction pure ; `fingerprint` |
| `scripts/worldgen/contamination_map.gd` | `ContaminationMap.sample(seed, chunk)` → `{level, type}` |
| `scripts/entities/monster.gd` | états, orientation, capacités, `to_dict` |
| `scripts/worldgen/chunk_manager.gd` | `_populated`, `_monster_store`, restauration |
| `scripts/world/world.gd` | `spawn_monster_at`, `restore_monster`, `make_noise`, `explode`, `spawn_split`, `MAX_MONSTERS` (300) |
| `tests/test_spawn.gd`, `test_contamination.gd`, `test_monsters.gd`, `test_vertical.gd` | voir §17 |

Flux au chargement d'un chunk :
```
ChunkManager._load(key)
  ├─ terrain + mobilier
  ├─ key ∈ _monster_store            → World.restore_monster pour chacun
  ├─ sinon key ∉ _populated          → SpawnGenerator.generate → World.spawn_monster_at ; _populated[key] = true
  └─ plafond global (300) atteint    → pas de peuplement, on retentera au prochain chargement
ChunkManager._unload(key)
  └─ monstres du chunk (même z) → _monster_store[key] (Monster.to_dict), retirés de World.monsters
```
Un monstre appartient au chunk où il se trouve au moment du déchargement. Hors des chunks chargés, le temps est gelé.

## 3. Formats de données

- **`monsters*.json`** : `name`, `gender` (m/f, accord des affixes), `tile` (défaut `mon_<id>`), `fallback_tile` (défaut `mon_zombie`, ou `mon_wolf` si tag `animal`) + `tint`, `tags`, `hp`, `move_cost`, `detect_range`, `behavior` (`hostile` / `passive` / `territorial`), `default_state`, `wake_range`, `threat` (1 à 10, défaut hp/25), `abilities`, `pack_radius`, `attack {name, cost, damage, zones, effect, infection}`, `special {..., chance}`, `ranged {name, range, cost, damage, cooldown, zones, effect}`, `scream {name, radius, cost, cooldown}`. `zones` = nom de table (`humanoid`, `bite`, `low`, `legs`, `heavy`, `claw`, `spit`, `shock`) ou dictionnaire. `effect` = `{id, chance, duration, dps, stamina, part}`. Tags : `zombie`, `animal`, `mutant`, `experiment`, `skeleton`, `aquatic`, `dressed`, `medical`, `science`, `military`, `police`, `industrial`, `civil`.
- **Groupes** : liste pondérée d'entrées `{monster, weight}` ou `{group, weight}` (inclusion, profondeur ≤ 3, cycles refusés par le test) ; poids décimaux permis.
- **`place_spawns.json`** : clé = id de plan (`MapgenDB.plan_id`) : chaque cellule d'un lieu multi-chunks a sa propre population ; valeur = liste de règles ou `{"copy": autre plan}`. Règle : `group`, `mode` (`floor` = `t_floor` libre, `paved` = asphalte / trottoir / béton, `nature`, `any`, `affinity`), `density` (monstres pour 100 cases candidates), `furniture` / `terrain` + `chance` (affinity : le dormeur sur son lit, le fidèle sur son banc ; le monstre prend la case du meuble s'il est praticable, sinon la première voisine libre), `dormant`, `rare` (probabilité par chunk d'activer la règle), `affix {id, chance}`, `contaminate` (false = ignore la substitution).
- **`ecology.json`** : `limits`, `ambient` (`street`, `yard`, `road`, `kinds` par nature de case), `climate_affixes`, `contamination` (`falloff`, `substitute_chance`, `ambient_switch_level`, `sources`, `substitutions`).

## 4. Algorithme `SpawnGenerator.generate`

Entrées : seed, clé, terrain et mobilier du chunk, `population`, `safe_centers`. Sortie : `[{monster, cell, facing, state, affixes}]`.

1. **Contexte** : id du plan (`SettlementMap.cell_plan`), type de cellule, nature de case et climat de la cellule macro, contamination.
2. **Cases candidates** : praticables à pied, hors eau, sans meuble bloquant, ni sur ni devant une porte, à plus de `safe_radius` (12) des points sûrs (départ du joueur).
3. **Un seul flux aléatoire par chunk** (`rng_for(seed, LAYER_SPAWN, cx, cy, z)`), règles de lieu dans l'ordre du fichier, puis couche ambiante (seulement hors bâtiment : rues, routes, jardins, nature ; lieux spéciaux : aucune ambiance ; eau : aucun monstre).
4. Par règle : `rare`, nombre attendu `density × candidats / 100 × population` (partie entière + tirage sur la fraction), tirage du groupe, **substitution de contamination**, plafond et budget de menace, espacement mini 2 cases, **état** (part `dormant`), **affixes** (règle, climat pour les cases extérieures, `alpha` 8 % dans un groupe de 4 et plus), orientation au hasard.
5. **Essaims** : un monstre `SWARM` arrive avec 2 à 4 voisins.
6. À z ≠ 0 : aucun monstre (les règles `min_depth` viendront avec le jalon 8).

Pureté : pas de lecture d'un chunk voisin, tri stable des candidats, aucune décision en itérant un dictionnaire. L'empreinte de déterminisme intègre la liste de monstres (`SpawnGenerator.fingerprint`).

## 5. Contamination et mutants

`ContaminationMap.sample` : maximum, sur les sources voisines, de `force × (1 − d / rayon)^falloff`, où d = distance à la cellule la plus proche de l'**empreinte** du lieu (donc `force` partout sous le lieu). Seules la région du chunk et ses voisines proches sont lues. Sources (`ecology.json`) :

| Lieu | Force | Rayon (cellules) | Type |
|---|---|---|---|
| `nuclear_plant` | 1,0 | 14 | radiation |
| `research_lab` | 0,9 | 10 | expérience |
| `volcano_site` | 0,8 | 9 | feu |
| `missile_silo` | 0,7 | 8 | radiation |
| `sewage_plant` | 0,6 | 6 | toxique |
| `research_station` | 0,6 | 6 | expérience (mer) |
| `factory`, `oil_platform` | 0,5 | 6 | toxique, pétrole (mer) |
| `bunker`, `bunker_entrance` | 0,4 | 5 | expérience |
| `ancient_ruins` | 0,4 | 5 | maudit |

**Substitution** : un monstre tiré est remplacé par sa variante avec la probabilité `niveau × 0,8` (table `contamination.substitutions` : loup → loup mutant / chien d'acide / chien de feu ; ours → ours mutant / chimère ; cerf, sanglier, corbeau, rat ; zombie civil → irradié / ballon / sujet de test / calciné / squelette ; zombie → affixe `irradié` / `toxique` / `calciné`). Une valeur `affix:<id>` donne un affixe au lieu de changer de monstre. Au-dessus de 0,6 de niveau, la couche ambiante tire dans `eco_contaminated_<type>` (radiation, toxique, expérience, feu, maudit ; **pas de groupe « pétrole »** : sans effet tant que les eaux sont vides). Indice voulu pour le joueur : une zone sans animaux normaux mais avec des mutants est proche d'une source.

## 6. États, sommeil, comportement

| État | Comportement |
|---|---|
| `sleep` | immobile, « Zzz », ne détecte rien ; réveil selon proximité, bruit, coup |
| `idle` | debout sur place (comportement d'avant) |
| `guard` | tient son poste (`home_cell`), ne dort jamais, revient à son poste, abandonne la poursuite à 8 cases |
| `patrol`, `wander` | prévus, non implémentés |

**Réveil** : le joueur à `wake_range × posture` (accroupi ×0,5, sprint ×1,5) ET case du monstre visible : 15 % par tour de 5 s ; bruit (`World.make_noise`) : sprint 8 cases, combat 10, hurlement ; un coup reçu ; un voisin qui se réveille (rayon `pack_radius` ou 4). `AMBUSH` : ne se réveille que si le joueur est à 2 cases (« surgit ! »), sourd au bruit, mais un coup le réveille. `GUARD` : un état `sleep` demandé est refusé. `DORMANT` / `AMBUSH` : démarrent `sleep`. `ERRATIC` : 30 % des pas de poursuite au hasard. Affixe `feral` : ne dort jamais. Un monstre créé par un chunk n'est jamais en chasse : c'est le joueur qui déclenche.

Effet recherché : un hôpital silencieux qu'on traverse accroupi, des gardes qu'on ne franchit pas « par hasard », des passifs (cerf, renard) qui donnent de la vie sans danger, des territoriaux (sanglier, ours) qui punissent l'imprudence.

## 7. Capacités

| Code | Effet | État |
|---|---|---|
| `ARMOR(n)` | chaque coup reçu perd n PV (min 1) | agit |
| `DORMANT`, `GUARD`, `AMBUSH`, `ERRATIC` | voir §6 | agissent |
| `EXPLODE(type)` | explosion à la mort (`acid`, `gas`, `fire`, `frag`, `electric` : `World.EXPLOSIONS`) | agit |
| `AURA_RAD` (rayon 2) / `FIRE_AURA` / `COLD_AURA` (rayon 1) | effet d'état sur le joueur proche (`Monster.AURA_EFFECTS`) | agissent |
| `REGEN(x)` | x PV/s après 5 s sans dégât | agit |
| `LEAP` | bond de 2-3 cases en ligne (recharge 8 s) | agit |
| `CHARGE` | course de 4-8 cases en ligne droite, premier coup ×1,5 (recharge 10 s) | agit |
| `GRAB`, `CONSTRICT` | le coup draine 20 de stamina (l'immobilisation viendra avec le combat) | partiel |
| `SPLIT` | chaque coup détache un petit monstre (moitié des PV), génération 3 max, plafond 280 monstres | agit |
| `SWARM` | apparaît en essaim | agit |
| `THROW(type)` | le tir lance une explosion de rayon 1 sur le joueur (ignore la ligne de vue) | agit |
| `BURST` | tir en rafale de 3 coups à moitié dégâts | agit |
| `SUMMON`, `RAISE`, `STEALTH`, `BLIND_HEARING` | appelle des zombies, relève des cadavres, détection ÷2, détecte au bruit seulement | 6d |
| `SWIM`, `AQUATIC`, `FLY` | traverse l'eau profonde, reste dans l'eau, ignore le terrain | 6d |
| `SPORE` | nuage de spores (poison / infection) | 6d |
| `LOOT_CARRIER` | porte un objet spécial | loot |

Les capacités non encore actives sont lues et ignorées (pas d'erreur).

## 8. Bestiaire

Les 171 fiches sont dans les JSON. Familles couvertes : zombies communs et de métier (foyer, commerces, services, éducation, culte, santé, ordre public, militaire, science, industrie, mer et air), faune normale et mutante, climats (froid, savane, désert, jungle), expériences ratées, contamination.

**À créer** (liste indicative, vérifier avec `MonsterDB.ids()`) :
- **Uniques** (§13) : `zombie_mayor`, `patient_zero`, `zombie_lab_director`, `experiment_nightmare`, `zombie_commander`, `reactor_horror`, `pirate_captain`, `kraken`, `ant_queen`, `alpha_wolf`.
- **Militaire / science (jalon 13, lieux à étages)** : `zombie_combat_medic`, `zombie_commando`, `zombie_heavy_gunner`, `zombie_armored_brute`, `zombie_bio_op`, `zombie_cryo`, `zombie_researcher`, `zombie_lab_guard`, `zombie_dam_engineer`, `experiment_clone`, `experiment_parasite`, `experiment_screamer`, `experiment_tyrant`.
- **Mer et climats** : `zombie_pirate`, `zombie_smuggler`, `zombie_oceanographer`, `zombie_skier`, `piranha_swarm`, `eel_electric`, `jellyfish`, `shark`, `shark_mutant`, `squid_giant`, `alligator_mutant`.
- **Faune** : `cockroach_giant`, `ant_giant`, `spider_mutant`, `spider_cave`, `bat_swarm`, `bat_giant`, `snake_mutant`, `troglodyte`, `ruin_guardian`.
- **Humains hostiles** (`bandit`, `raider`, `cannibal`, `cultist`, `hermit`, `sniper_survivor`) : jalon à part (PNJ : équipement, dialogue, factions).

Sprites : ids `mon_<id>` improvisés, listés dans `MISSING_SPRITE.md` ; un id absent donne le repli teinté.

## 9. Affixes

Un affixe modifie un monstre de base (`MonsterDB.create(id, affixes)`) : `adj_m` / `adj_f`, multiplicateurs `hp` / `speed` (× `move_cost` : > 1 = plus lent) / `dmg`, `armor`, `threat`, `never_sleeps`, `abilities`, `effect`, `allowed_tags` (au moins un) / `forbidden_tags` (aucun). 0 à 2 par monstre, nom accordé au genre.

| Affixe | Effet principal | Condition d'apparition |
|---|---|---|
| gelé (`frozen`) | PV ×1,3, plus lent, `COLD_AURA` | climat froid (25 % des zombies en extérieur) |
| calciné (`charred`) | `FIRE_AURA` | contamination feu |
| irradié (`irradiated`) | PV ×1,3, `AURA_RAD` (refusé par les mutants) | contamination radiation |
| toxique (`toxic`) | attaque empoisonnée | contamination toxique |
| électrifié (`electrified`) | drain de stamina | (poste électrique, orage : à brancher) |
| blindé (`armored`) | armure +2, PV ×1,5 | militaire, police |
| momifié (`mummified`) | PV ×1,1, plus lent | désert (20 %) |
| envahi (`overgrown`) | PV ×1,2, plus lent | jungle, marais (20 %) |
| putréfié (`rotten`) | PV ×0,8, plus lent | marais (15 %) |
| gonflé (`bloated`) | PV ×1,5, `EXPLODE(gas)` | (égouts, marais, port : à brancher) |
| enragé (`feral`) | ne dort jamais, dégâts ×1,2 | à brancher |
| alpha (`alpha`) | PV ×1,8, dégâts ×1,3 | groupe de 4 et plus, 8 % |
| vétéran (`veteran`) | armure +1 | règle `affix` des lieux rares (non posée) |
| grouillant (`infested`) | (mort : rats, à brancher) | entrepôts, égouts |

Exemples : policier zombie gelé, infirmier zombie irradié, garde de labo vétéran irradié (au plus un affixe de contamination).

## 10. Groupes de spawn

Contenu actuel : voir `spawn_groups.json` (ambiants), `spawn_groups_places.json` (foyer, commerce, services, santé, industrie, rural, routes, air, mer partielle), `spawn_groups_contamination.json`. **Groupes à créer** avec les lieux correspondants :
- **Militaire et secret (jalon 13)** : `bunker_g` (soldats, soldats blindés, sentinelles, sniper, officier, médecin, sapeur), `bunker_deep` (bio-opérateurs, commandos, brute blindée, traqueur), `silo_g` (soldats blindés, commandos, lance-flammes, mitrailleurs, officier), `radio_g`, `lab_staff`, `lab_guard`, `lab_subjects`, `lab_failed`, `lab_deep`, `arctic_g`, `carrier_g`.
- **Mer et eau (jalon 14)** : `dam_g`, `marina_g`, `shipwreck_g`, `pirate_g`, `research_g`, `island_village_g`, `sewage_basin_g` (mode `water`).
- **Lieux extrêmes (jalon 15)** : `ski_g`, `volcano_g`, `ruins_g`, `cave_g`, `oasis_g`.

## 11. Population des lieux

Implémentée pour 73 plans (`place_spawns.json`) : maisons, 14 bâtiments de ville, hôpital, clinique, maison de retraite, garage, station-service, motel, ferme, ranch, centrale nucléaire, camping, cimetière, chapelle, entrepôt, usine, égouts, poste électrique, avant-poste du désert, phare, plateforme, 7 lieux de route, port, aéroport.

**Pas encore peuplés** : `sewage_basin` (eau), bunker, silo, labo, lieux marins et ruraux des jalons 13 à 15 (monstres ou étages inexistants). Prévus : `radio_tower` (`radio_g`, gardes), `bunker` (niveau 0 `bunker_g`, niveaux −1 à −2 `bunker_deep`), `missile_silo` (+ `zombie_commander`), labo (z=0 personnel et gardes, z=−1 sujets, z=−2 ratés, z=−3 `lab_deep` ; affinités `f_cage`, `f_cryo_pod`, `f_lab_table` ; uniques `zombie_lab_director`, `experiment_nightmare`), `aircraft_carrier`, `lighthouse_island`, `cargo_wreck` (+ clandestins dans les conteneurs), `marina`, `hydro_dam`, `island_village`, `pirate_base` (+ `pirate_captain`), `research_station`, `oasis`, `ski_resort`, `volcano_site`, `ancient_ruins`, `cave_entrance`, `arctic_base`, lieux par climat (affixe `mummified` chaud, `frozen` froid).

Hôpital : le sous-sol d'expériences (`min_depth`) et le tirage de `patient_zero` attendent les étages et les uniques ; quarantaine et psychiatrie sont des règles rares sur le sol de l'hôpital.

## 12. Écologie ambiante

Implémentée : rue, jardin, route, nature par nature de case (plaine, forêt, marais, taïga, toundra, désert, savane, jungle, plage, berges), densités de 0,025 à 0,25 monstre pour 100 cases, part dormante pour la ville et les routes ; affixes de climat. **Non implémenté** : eaux (lacs, rivières, océan : `eco_water_shallow`, `eco_lake_deep`, `eco_ocean_shallow`, `eco_ocean_deep`, en 6d), et la hausse de faune hostile loin des villes (×1,6 au-delà de 40 cellules : demande la distance à la ville la plus proche, donc la lecture des régions voisines).

## 13. Uniques

Un unique existe au plus une fois par monde (par cellule de région) : tirage `mix(seed, LAYER_SPAWN, rx, ry, hash(id))` avec probabilité de lieu ; non réapparition après la mort (drapeau stocké avec `_populated`). Prévus : `zombie_mayor` (mairie, 0,5), `patient_zero` (hôpital ou labo, 0,15), `zombie_lab_director` (labo, 0,8), `experiment_nightmare` (labo profond, 0,3), `zombie_commander` (silo, bunker profond, 0,5), `reactor_horror` (cœur de réacteur, 0,3), `pirate_captain` (base pirate, 0,7), `kraken` (pleine mer, 0,05 par région océanique), `ant_queen`, `alpha_wolf` (forêt, taïga, 0,08).

## 14. Équilibrage et plafonds

| Réglage | Valeur |
|---|---|
| Monstres par chunk | 12 (20 pour un chunk portant un plan) |
| Budget de menace par chunk (Σ `threat`) | 30 (60 pour un chunk portant un plan) |
| Plafond global de monstres chargés | 300 (`World.MAX_MONSTERS`) ; division des blobs jusqu'à 280 |
| Zone sûre autour du départ | 12 cases |
| Espacement mini entre monstres d'une règle | 2 cases |
| `population` (`main.gd`) | 0 aucun · 0,5 · 1 · 1,5 · 2 (multiplie densités et chances) |

`threat` indicatif : zombie ordinaire 1, spéciaux 2-3, élites 4-6, expériences 5-9, uniques 10. Rareté du lieu = danger : maisons et commerces ≈ 1-3 ; hôpital, police, usine ≈ 3-5 ; bunker, centrale ≈ 5-8 ; silo, labo profond, uniques ≈ 8-10.

## 15. Persistance, performance, évolutions

- **Sauvegarde (jalon 7)** : par chunk, `populated` et la liste de monstres vivants (`to_dict` : id, cellule, PV, état, affixes, étage, génération...) ; un chunk peuplé non modifié ne stocke rien (il se régénère identique, uniques tués exceptés).
- **Coût du tour des monstres** : borné par les chunks chargés ; les dormeurs coûtent un test de distance toutes les 5 s.
- **Contamination** : lire les sources d'une région voisine force la génération de ses lieux (donc de ses routes) un peu avant l'arrivée du joueur ; le travail total ne change pas. `test_contamination.gd` affiche le coût à froid (25 chunks). Au-delà de 16 cellules de rayon, il faudrait étaler le calcul.
- **Temps gelé hors des chunks chargés** : acceptable au départ. Évolution (6d) : rattrapage à la recharge (un chunk absent depuis plus d'une heure de jeu perd 30 % de ses ambiants et en gagne selon l'écologie).
- **Hors périmètre** : errance entre lieux, hordes sur les routes (la structure `wander` / `hunt` est prête), jour / nuit (plus de dormants le jour, `feral` plus fréquent la nuit).

## 16. Plans, mobilier, terrains à créer

- **Fait (6b)** : plans `urban_hospital`, `urban_clinic`, `urban_nursing_home`, `urban_garage` (`medical.json`) ; mobilier `f_hospital_bed`, `f_gurney`, `f_surgery_table`, `f_morgue_drawer` (`furniture_medical.json`) ; terrains `t_rock`, `t_air`, escaliers.
- **Reste** : mobilier `f_cell_bed`, `f_quarantine_bed`, `f_lab_table`, `f_cryo_pod`, `f_cage`, `f_vat`, `f_server`, `f_garage_pit` ; plans d'étage (`<id>@-1`...) pour hôpital, bunker, silo, labo ; marqueur de spawn optionnel dans la palette des plans (`"spawn": "<groupe>"`) pour les scènes que les affinités ne couvrent pas. La limite de 255 meubles n'est pas en danger.
- **Sprites** : `MISSING_SPRITE.md`.

## 17. Tests

- `test_spawn.gd` : bestiaire valide (PV, coûts, zones, effets), groupes sans cycle ni monstre inconnu, déterminisme (5 seeds, 3 ordres), placement (cases praticables, plafonds, zone sûre, portes, pas de doublon, population 0 / 0,5 / 2), persistance (réserve, restauration, monstre tué, monstre blessé), affixes, population de 12 plans sur leur propre terrain (thème, dormeurs), états (bruit, embuscade, garde, réveil en chaîne).
- `test_contamination.gd` : sources valides, niveau = référence recalculée sans la logique de voisinage, substitutions, affixes de contamination, explosions, `EXPLODE` à la mort, `REGEN`, `SPLIT`, mesure de perf.
- `test_monsters.gd` : les 14 monstres d'origine, infection, effets, orientation. `test_vertical.gd` : monstres rangés par étage.

## 18. Écarts, limites et risques

- **Écarts avec la conception initiale** : un seul flux aléatoire par chunk (les règles se suivent dans l'ordre du fichier) au lieu d'un flux par règle ; sources de contamination dans `ecology.json` (pas de champ `emits` dans `specials.json`) ; contamination évaluée par chunk (pas par case) ; `GRAB` ne fait que drainer la stamina ; la grenade ignore la ligne de vue.
- **Journal et armure** : `Player._attack` affiche toujours « −6 PV » (dégâts bruts) même quand l'armure réduit le coup ; il faut utiliser la valeur réellement infligée (touche `player.gd`). Les poings font 6 : `ARMOR` ≥ 4 rend certains monstres presque invulnérables tant que le joueur n'a pas d'arme.
- Densités très faibles hors ville (≈ 1 monstre pour 2 à 4 chunks de nature) : à régler avec `POPULATION` ou `ecology.json`. Un mode debug (monstres par chunk sur la mini-carte) serait utile.
- Un monstre en réserve perd sa cible ; un chunk lointain peuplé hors d'un `update_fov()` apparaît caché jusqu'au prochain déplacement.
- Un monstre endormi ne réveille ses voisins qu'à son propre réveil.
- `zombie_sniper`, `zombie_flamer`, `zombie_grenadier` : tir à distance seulement partiellement fidèle (pas de capacité propre au-delà de `THROW` / `BURST`).
- Les chunks déjà peuplés avant l'ajout d'une contamination ne sont pas repeuplés.
- Les affixes `veteran` ne sont pas posés dans `place_spawns.json` ; `electrified`, `bloated`, `feral`, `infested` n'ont pas de règle d'apparition.
- Aquatiques : rien ne naît dans l'eau tant que le pathfinding nautique n'existe pas.
- **Lisibilité** : trop de variantes visuelles identiques perdent le joueur ; le repli par teinte aide, mais les uniques et élites gagneront de vrais sprites.
