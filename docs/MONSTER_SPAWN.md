# MONSTER_SPAWN.md — Population du monde : monstres, apparitions, écologie (jalon 6)

Document de conception, **rien n'est codé**. Il complète `WORLD_GEN.md` (§4.7 « À venir : monstres initiaux », §9 jalon 6, §11 risques) et `GAME_DESIGN.md` (« Monstres définis en code (à passer en JSON) »). Convention des touches inchangée. Toutes les valeurs chiffrées (PV, densités, probabilités) sont posées « à l'aveugle » : à régler en jeu, comme `Infection.DURATION`.

Tuiles de monstres : ids improvisés, listés dans `MISSING_SPRITE.md` (section « Jalon 6 »). Un monstre sans sprite se dessine avec `mon_zombie` teinté (champ `tint`, voir §3.1) : le jeu reste jouable sans aucun sprite neuf.

---

## 1. Principes

1. **Le lieu raconte une histoire** : les monstres d'un bâtiment sont ceux qui s'y trouvaient (infirmiers à l'hôpital, scientifiques au labo, soldats au bunker). Un zombie n'est pas « un zombie », c'est *quelqu'un*.
2. **Le monde raconte la cause** : les mutants apparaissent autour des sources de contamination, la faune dépend du biome et du climat. Rencontrer un loup mutant doit signifier « il y a une centrale ou un labo pas loin ».
3. **Déterminisme total** : les monstres initiaux d'un chunk sont une fonction pure de `(seed, clé de chunk)`, comme le terrain (`WORLD_GEN.md` §2). Même seed = mêmes monstres aux mêmes endroits, quel que soit l'ordre d'exploration. Aucun `randi()` global à la génération.
4. **Peuplé une seule fois** : un chunk génère ses monstres à sa première apparition, jamais plus. Un monstre tué reste tué ; un monstre vivant déchargé est mis en réserve et rechargé tel quel.
5. **Tout en données** : ajouter un monstre, un groupe ou la population d'un lieu = éditer du JSON, pas du code (sauf nouvelle *capacité*, §7).
6. **Combinatoire par modificateurs** : plutôt que d'écrire à la main chaque variante (« policier gelé », « soldat irradié »…), on définit des **bases** (§8) et des **affixes** (§9) combinables selon des règles de compatibilité. Cela donne plusieurs centaines de variantes sans multiplier les fiches.
7. **Dosage** : la menace doit rester lisible. Plafonds par chunk (§14), monstres dormants (donc discrets), progression : le danger monte avec la rareté du lieu.

---

## 2. Architecture

### 2.1 Fichiers à créer

| Fichier | Rôle |
|---|---|
| `data/monsters.json` | tous les monstres (remplace les fonctions de `MonsterData`) |
| `data/monster_affixes.json` | modificateurs (gelé, irradié, blindé…) et règles de compatibilité |
| `data/worldgen/spawn_groups.json` | groupes pondérés (modèle *monstergroups* de CDDA) |
| `data/worldgen/place_spawns.json` | plan / lieu → groupes, densités, mode de placement, sommeil |
| `data/worldgen/ecology.json` | faune ambiante par nature de case, climat, eau, route ; sources de contamination ; substitutions |
| `scripts/data/monster_db.gd` | `MonsterDB` : charge `monsters.json`, `create(id)`, tags, validation |
| `scripts/worldgen/spawn_generator.gd` | `SpawnGenerator.generate(seed, key, terrain, furniture)` : fonction pure |
| `scripts/worldgen/contamination_map.gd` | `ContaminationMap.level(cell)` : fonction pure (0 à 1) |
| `tests/test_spawn.gd` | validation des données, déterminisme, plafonds, cohérence lieu ↔ monstres |

### 2.2 Fichiers à modifier

| Fichier | Changement |
|---|---|
| `monster_data.gd` | `create(id)` délègue à `MonsterDB` ; les fonctions `zombie()`… restent en façade (compatibilité `test_monsters.gd`, `main.gd`, `Infection._turn`) puis disparaissent |
| `monster.gd` | état (`state`), affixes, armure, capacités, `home_chunk`, sérialisation (`to_dict` / `from_dict`) |
| `chunk_manager.gd` | `_populated` (clés peuplées), `_monster_store` (monstres déchargés, comme `_seen_store`), appel de `SpawnGenerator` au premier chargement |
| `world.gd` | `spawn_monster(data, near, extra)` accepte état et affixes ; plafond global ; réveil par le bruit |
| `mapgen_db.gd` | (6b, optionnel) marqueur `spawn` dans la palette des plans |
| `chunk_generator.gd` | rien : le spawn lit les octets déjà produits (terrain et mobilier) |

### 2.3 Flux au chargement d'un chunk

```
ChunkManager._load(key)
  ├─ terrain + mobilier (existant)
  ├─ si key ∈ _monster_store            → restaurer les monstres sauvegardés (position, PV, état, affixes)
  ├─ sinon si key ∉ _populated          → SpawnGenerator.generate(seed, key, terrain, furniture)
  │                                        → World.spawn_monster(...) pour chaque entrée ; _populated.add(key)
  └─ chunks lointains : la population est faite dans la file (process_queue), jamais d'un bloc
ChunkManager._unload(key)
  └─ monstres dont grid_pos est dans le chunk → _monster_store[key] (dictionnaires), retirés de World.monsters
```

Un monstre appartient au chunk où il se trouve **au moment du déchargement** (il peut avoir quitté son chunk d'origine en poursuivant le joueur). Hors des chunks chargés, le temps est gelé (migration et repeuplement : §15).

---

## 3. Données

### 3.1 `monsters.json` (une entrée par monstre)

Reprend les champs de `MonsterData` (mêmes noms) et ajoute :

```json
{"monsters": {
 "zombie_nurse": {
  "name": "Infirmier zombie", "gender": "m",
  "tile": "mon_zombie_nurse", "fallback_tile": "mon_zombie", "tint": "#9fd8d0",
  "tags": ["zombie", "medical", "dressed"],
  "hp": 24, "move_cost": 1.1, "detect_range": 14,
  "attack": {"name": "Griffure", "cost": 1.4, "damage": 4, "zones": "humanoid"},
  "special": {"name": "Morsure", "cost": 3.2, "damage": 8, "chance": 0.3, "zones": "bite", "infection": 0.5},
  "abilities": [], "behavior": "hostile", "default_state": "idle",
  "wake_range": 6, "threat": 2,
  "drops": "loot_medical"
 }}}
```

- `zones` : nom d'une table (`humanoid`, `bite`, `low`, `legs`, `heavy`, `claw`, `spit`, `shock` reprennent les `ZONES_*` actuels) ou dictionnaire direct.
- `tags` : `zombie`, `animal`, `mutant`, `experiment`, `human`, `skeleton`, `aquatic`, `dressed` (porte un costume : sensible aux affixes de vêtement), `medical`, `science`, `military`, `police`, `industrial`, `civil`, `unique`.
- `behavior` : `hostile` (défaut), `passive` (fuit le joueur : cerf, renard), `territorial` (n'attaque que dans un rayon autour de son point d'apparition : sanglier, ours), `pack` (meute : `pack_radius`).
- `default_state` : `sleep`, `idle`, `guard`, `patrol`, `wander` (voir §6).
- `threat` : 1 à 10, sert aux plafonds de chunk et au budget de menace (§14).
- `fallback_tile` + `tint` : repli visuel si la tuile manque (même principe que la `color` des terrains).
- `drops` : id d'une table de loot (jalon 6, hors de ce document ; le champ est réservé).
- Valeurs de type `Dictionary` (effets) : même format que `MonsterData.effect()`.

### 3.2 `spawn_groups.json`

```json
{"groups": {"hosp_staff": {"entries": [
  {"monster": "zombie_nurse", "weight": 6},
  {"monster": "zombie_doctor", "weight": 4},
  {"monster": "zombie_orderly", "weight": 2}]}}}
```

Un groupe peut en inclure un autre (`{"group": "amb_street", "weight": 2}`) : profondeur limitée à 3, cycles refusés par le test. Contenu complet : §10.

### 3.3 `place_spawns.json`

Clé = **id de plan** (`MapgenDB.plan_id`) : chaque cellule d'un lieu multi-chunks (aéroport 6×2, centrale 3×3) a donc sa propre population, et la fonction reste pure (un chunk ne lit jamais ses voisins).

```json
{"urban_police": [
  {"group": "police_staff", "mode": "floor", "density": 1.2, "dormant": 0.4},
  {"group": "police_cells", "mode": "affinity", "furniture": "f_bed", "chance": 0.7, "dormant": 0.2},
  {"group": "police_swat",  "mode": "floor", "density": 0.3, "dormant": 0.1, "rare": 0.15}]}
```

Champs d'une règle :

| Champ | Sens |
|---|---|
| `group` | groupe tiré |
| `mode` | `floor` (`t_floor` praticable, sans meuble bloquant), `paved` (asphalte, béton, trottoir), `nature` (terrain naturel praticable du plan), `any` (toute case praticable), `affinity` (case praticable adjacente à un meuble donné), `water` (eau, nécessite `AQUATIC`, §7) |
| `density` | monstres attendus pour **100 cases candidates** (avant réglage de population) |
| `furniture` / `chance` | mode `affinity` : meuble ciblé et probabilité par meuble |
| `dormant` | part de monstres créés en sommeil (sinon `default_state` du monstre) |
| `rare` | probabilité (par chunk) que la règle s'active du tout (lieux « parfois infestés ») |
| `min_depth` | étage minimal (`z` négatif plus tard : sous-sols de labos et de bunkers) |
| `contaminate` | `false` pour ignorer la substitution par contamination (défaut : `true`) |
| `affixes` | liste de contraintes pour forcer/interdire un affixe (ex. `{"force": "frozen"}`) |

Le mode `affinity` est la clé de la « vie » : le zombie en pyjama dort **dans un lit**, le patient dans un lit d'hôpital, le serveur derrière le comptoir, le fossoyeur près d'une tombe, le clandestin dans un conteneur.

### 3.4 `ecology.json`

Trois sections : `ambient` (groupes par nature de case, climat, route, eau), `contamination` (sources, rayon, atténuation), `substitutions` (monstre → variante mutante). Contenu : §5 et §12.

---

## 4. Algorithme `SpawnGenerator.generate`

Entrées : `world_seed`, `key`, `terrain` et `furniture` du chunk (déjà produits par `ChunkGenerator`). Sortie : `Array[Dictionary]` `{monster, cell, state, affixes, facing}`, triée de façon stable.

1. **Contexte du chunk** : id du plan (`SettlementMap.cell_plan`) ; type de cellule (`cell_type` : rue, parcelle, jardin, route sauvage, lieu, nature) ; nature de case et climat de la cellule macro ; niveau de contamination au centre du chunk (§5).
2. **Zone sûre** : aucune apparition à moins de 12 cases du départ du joueur (`SettlementMap.spawn_cell()`), ni sur une case de porte, ni sur la case juste devant une porte de façade.
3. **Listes de candidats** par mode, construites en parcourant les cases dans l'ordre d'indice (jamais en itérant un `Dictionary`).
4. **Pour chaque règle**, dans l'ordre du fichier :
   - `rng = WorldRng.rng_for(seed, LAYER_SPAWN, cx, cy, hash(plan_id + index_de_règle))` ;
   - si `rare` : un tirage décide si la règle s'active ;
   - nombre attendu `n = density × candidats / 100 × réglage_population` ; partie entière + tirage sur la partie fractionnaire ;
   - pour chaque monstre : tirer le groupe pondéré, choisir une case candidate non prise (espacement mini 2 cases entre monstres d'une même règle, sauf essaims), retirer la case, appliquer **substitution de contamination** (§5), **affixes** (§9), **état** (sommeil), orientation.
5. **Couche ambiante** (après les règles du lieu) : seulement sur les cases `nature` et `paved` hors bâtiment : groupes d'`ecology.json` selon biome / climat / route, avec la densité de la zone.
6. **Budget de menace** : somme des `threat` plafonnée par chunk (§14). Les règles de lieu passent avant l'ambiance : en cas de dépassement, on supprime d'abord des monstres ambiants.
7. **Uniques** (§13) : tirage séparé, une seule fois par monde (clé de région).

Contraintes de pureté : pas de lecture d'un chunk voisin, pas de `randi()`, tri stable des candidats, aucune décision prise en itérant un dictionnaire. Le test d'empreinte (`test_worldgen_determinism.gd`) intègre la liste de monstres de chaque chunk.

Le coût de calcul est comparable à `generate_furniture` (un passage sur 576 cases) ; la contamination est la partie à mesurer (§5, §18).

---

## 5. Contamination et mutants

### 5.1 Principe

`ContaminationMap.level(cell) → float [0, 1]` : fonction pure de (seed, case). Maximum, sur les **sources** voisines, de `force × (1 − distance/rayon)^atténuation`. Sources = lieux spéciaux portant un champ `emits` (à ajouter à `specials.json`) :

| Source | Force | Rayon (cellules) | Type de contamination |
|---|---|---|---|
| `nuclear_plant` | 1.0 | 14 | radiation |
| `lab` (jalon 13) | 0.9 | 10 | expérience |
| `missile_silo` (jalon 13) | 0.7 | 8 | radiation + militaire |
| `bunker` / `bunker_entrance` | 0.4 | 5 | expérience |
| `factory` | 0.5 | 6 | toxique |
| `sewage_plant` | 0.6 | 6 | toxique |
| `oil_platform` | 0.5 | 6 | pétrole (mer) |
| `volcano_site` (jalon 15) | 0.8 | 9 | feu |
| `research_station` (jalon 14) | 0.6 | 6 | expérience (mer) |
| `ancient_ruins` (jalon 15) | 0.4 | 5 | maudit (squelettes, momies) |

### 5.2 Substitution

Quand un monstre est tiré, avec la probabilité `niveau × substitution.chance`, il est remplacé par sa variante mutante selon le type de contamination :

| Base | radiation | toxique | expérience | feu | maudit |
|---|---|---|---|---|---|
| `wolf` | `wolf_mutant` | `wolf_mutant` | `experiment_acid_hound` | `fire_hound` | `skeleton_brute` |
| `bear` | `bear_mutant` | `bear_mutant` | `experiment_chimera` | `fire_hound` | — |
| `deer` | `deer_mutant` | `deer_mutant` | — | — | — |
| `boar` | `boar_mutant` | `boar_mutant` | — | — | — |
| `crow` | `crow_mutant` | `crow_mutant` | `experiment_swarm` | — | — |
| `rat_giant` | `rat_irradiated` | `experiment_slime` | `experiment_homunculus` | — | — |
| `zombie_civilian` | `zombie_irradiated` | `zombie_gasbag` | `zombie_lab_subject` | `zombie_charred` | `skeleton` |
| `zombie_worker` | `zombie_irradiated` | affixe `toxic` | `zombie_lab_subject` | `zombie_charred` | — |
| `zombie` | affixe `irradiated` | affixe `toxic` | — | affixe `charred` | — |

Au-dessus de 0.6 de contamination, la couche ambiante bascule de la faune normale vers un groupe `eco_contaminated_*` (mutants seulement). Indice voulu pour le joueur : une zone sans animaux normaux mais avec des mutants est proche d'une source.

---

## 6. États, sommeil, comportement

### 6.1 États (`Monster.state`)

| État | Comportement | Portée de détection |
|---|---|---|
| `sleep` | immobile, ne regarde rien ; réveil selon bruit et proximité | ×0.25 (et seulement dans `wake_range`) |
| `idle` | debout sur place, orientation aléatoire, pivote parfois | ×0.6 |
| `guard` | tient sa case, **ne dort jamais** (sentinelle, garde) ; poursuit puis revient | ×1 |
| `patrol` | boucle dans un rayon de 6 autour de sa case | ×1 |
| `wander` | erre au hasard dans le chunk | ×1 |
| `hunt` | a une cible (`has_target`), comportement actuel | ×1 |
| `flee` | passif qui s'éloigne du joueur | — |

Un monstre créé par un chunk n'est jamais en `hunt` : c'est le joueur qui déclenche.

### 6.2 Réveil

À chaque tour d'un dormant (toutes les `IDLE_COST` ≈ 5 s, donc coût négligeable : pas de planificateur spécial) :

- le joueur est dans `wake_range` × facteur de posture (accroupi ×0.5, sprint ×1.5) **et** la case du monstre est visible : réveil avec `p = 0.15` par tour (aléatoire d'exécution, pas de génération) ;
- un **bruit** réveille automatiquement dans son rayon : sprint 8, combat au corps à corps 10, hurlement (`zombie_screecher`, `experiment_screamer`) 35, explosion 25 (futur : armes à feu 40) ;
- un dormant frappé se réveille ; un réveillé **alerte les membres de son groupe** dans `pack_radius` (ou 4 par défaut) ;
- `zombie_morgue`, `zombie_grave`, `zombie_bather`, `experiment_stalker` : **embuscade** (§7) : ne se réveillent que si le joueur est à ≤ 2 cases.

### 6.3 Pourquoi ça rend le monde vivant

- Un hôpital est **silencieux et effrayant** : la plupart dorment, on peut s'y faufiler accroupi ; un coup dans la salle de chirurgie réveille le bloc.
- Les groupes ont des **rôles spatiaux** (affinités) : lits, comptoirs, bureaux, chaises, tombes, conteneurs.
- Les gardes ne dorment pas : un bunker se franchit en force ou en silence, jamais « par hasard ».
- Les passifs (cerfs, renards) donnent de la vie sans danger ; les territoriaux (sanglier, ours) punissent l'imprudence.

---

## 7. Capacités

Existantes (`MonsterData`) : attaque spéciale, effets d'état (`bleed`, `poison`, `acid`, drain de stamina), tir à distance, hurlement, meute, infection. Nouvelles, à introduire **au fil des jalons** (colonne « Jal. ») ; avant leur implémentation, le monstre garde sa fiche de base et la capacité est ignorée (pas d'erreur) :

| Code | Effet | Jal. |
|---|---|---|
| `ARMOR(n)` | réduit chaque coup reçu de `n` PV (min 1) ; les poings font 6 | 6a |
| `DORMANT` | état de départ `sleep` | 6b |
| `GUARD` | ne dort jamais, revient à son poste | 6b |
| `AMBUSH` | invisible / immobile tant que le joueur n'est pas à ≤ 2 cases, puis attaque gratuite | 6b |
| `ERRATIC` | 30 % des déplacements au hasard (ivrogne, patients, sujets de test) | 6b |
| `EXPLODE(type)` | à la mort : `acid`, `gas`, `fire`, `frag`, `electric`, rayon 1 à 2, dégâts sur zones | 6c |
| `AURA_RAD` | rayon 2 : irradie (poison long, aucun PV direct) | 6c |
| `COLD_AURA` / `FIRE_AURA` | rayon 1 : drain de stamina / brûlure (dps) | 6c |
| `REGEN(x)` | `x` PV par seconde tant qu'il n'a pas été touché depuis 5 s | 6c |
| `LEAP` | bond de 2-3 cases en ligne vers le joueur (coût : attaque) | 6c |
| `CHARGE` | si ≥ 4 cases en ligne droite : charge, dégâts ×1.5 | 6c |
| `GRAB` | agrippe : le joueur ne se déplace pas tant qu'il ne se libère pas (jet sur Force, plus tard) | 6c |
| `CONSTRICT` | variante de GRAB avec dégâts continus (python) | 6c |
| `SPLIT` | chaque coup fait apparaître un petit monstre adjacent (PV divisés) | 6c |
| `SWARM` | essaim : PV très faibles, `pack_radius` large, arrive en nombre | 6c |
| `THROW(type)` | tir à courbe (grenade, bocal d'acide), zone 1 | 6c |
| `BURST` | tir en rafale de 3 : 3 tirages de zone à dégâts réduits | 6c |
| `SUMMON` | appelle `n` zombies proches (officier, maître zombie) | 6d |
| `RAISE` | relève un cadavre en zombie (nécromancien, demande des cadavres) | 6d |
| `STEALTH` | détection du joueur ÷ 2 ; ne se signale pas par « Vous apercevez » avant 3 cases | 6d |
| `BLIND_HEARING` | détecte au bruit seulement (troglodyte) | 6d |
| `SWIM` | peut traverser l'eau profonde (nageur, crocodile) | 6d |
| `AQUATIC` | reste dans l'eau (requin, piranha) ; nécessite le pathfinding aquatique | 6d |
| `FLY` | ignore le terrain (corbeau, chauve-souris, essaim) | 6d |
| `SPORE` | nuage de spores à l'impact (poison / infection) | 6d |
| `LOOT_CARRIER` | porte un objet spécial, lâché à la mort | 6 (loot) |

---

## 8. Bestiaire

Légende : PV · pas = `move_cost` en secondes · Dég. = dégâts de l'attaque normale · **État** : D = dormant fréquent, G = garde, P = passif, T = territorial. Les 14 monstres existants sont marqués ★ (valeurs inchangées). Tuile par défaut : `mon_<id>` (exceptions dans `MISSING_SPRITE.md`).

### 8.1 Zombies communs et variantes génériques

| id | Nom | PV | Pas | Dég. | Remarques |
|---|---|---|---|---|---|
| zombie ★ | Zombie | 20 | 1.2 | 4 | morsure infectieuse |
| zombie_child ★ | Zombie enfant | 15 | 1.0 | 2 | |
| zombie_fast ★ | Zombie rapide | 25 | 0.7 | 3 | |
| zombie_crawler ★ | Zombie rampant | 18 | 2.2 | 3 | vise les jambes |
| zombie_brute ★ | Zombie brute | 80 | 1.5 | 8 | |
| zombie_hulk ★ | Zombie colosse | 180 | 1.3 | 14 | |
| zombie_spitter ★ | Zombie cracheur | 30 | 1.4 | 3 | acide à distance |
| zombie_screecher ★ | Zombie hurleur | 25 | 1.3 | 3 | hurlement 35 |
| zombie_electric ★ | Zombie électrique | 45 | 1.3 | 4 | drain de stamina |
| zombie_soldier ★ | Zombie soldat | 60 | 1.3 | 7 | |
| zombie_dog ★ | Chien zombie | 28 | 0.7 | 4 | saignement |
| wolf ★ | Loup | 35 | 0.8 | 6 | meute 12 |
| bear ★ | Ours | 130 | 1.1 | 12 | T |
| giant_spider ★ | Veuve noire géante | 45 | 1.0 | 4 | poison |
| zombie_civilian | Zombie civil | 20 | 1.2 | 4 | partout en ville, base de la plupart des affixes |
| zombie_tough | Zombie costaud | 45 | 1.4 | 6 | ARMOR 1 |
| zombie_waif | Zombie décharné | 12 | 0.6 | 3 | très rapide, très fragile |
| zombie_grabber | Zombie agrippeur | 40 | 1.5 | 4 | GRAB |
| zombie_acidic | Zombie acide | 40 | 1.4 | 5 | `acid` 50 % ; EXPLODE(acid) petit |
| zombie_bloated | Zombie gonflé | 45 | 2.0 | 3 | EXPLODE(gas) rayon 2, poison |
| zombie_gasbag | Zombie ballon | 30 | 2.2 | 2 | EXPLODE(gas) rayon 3 |
| zombie_predator | Zombie prédateur | 70 | 0.7 | 11 | LEAP, STEALTH ; élite rare |
| zombie_necro | Nécromancien zombie | 60 | 1.4 | 4 | RAISE ; reste derrière les autres |
| zombie_master | Maître zombie | 90 | 1.3 | 6 | SUMMON ; autorité sur les zombies à 15 cases |

### 8.2 Civils, foyer et ville

| id | Nom | PV | Pas | Dég. | Remarques | Lieux |
|---|---|---|---|---|---|---|
| zombie_pajamas | Zombie en pyjama | 18 | 1.3 | 3 | D (dort dans les lits) | maisons, motel, appartements |
| zombie_elder | Zombie âgé | 14 | 1.8 | 3 | lent, fragile | maisons, église, hôpital |
| zombie_teen | Zombie adolescent | 18 | 0.9 | 3 | | maisons, école, parking |
| zombie_homeowner | Propriétaire zombie | 30 | 1.3 | 6 | batte | maisons, cabanon |
| zombie_bather | Zombie de baignoire | 16 | 1.4 | 3 | AMBUSH (dans la baignoire) | maisons |
| zombie_hoarder | Zombie collectionneur | 40 | 1.6 | 5 | LOOT_CARRIER, rare | maisons, appartements |
| zombie_tenant | Locataire zombie | 20 | 1.2 | 4 | | appartements |
| zombie_scavenger | Pillard zombie | 28 | 0.9 | 5 | LOOT_CARRIER | rues, entrepôts, parkings |
| zombie_drunk | Ivrogne zombie | 24 | 1.5 | 4 | ERRATIC | bar, rues |
| zombie_biker | Motard zombie | 32 | 0.8 | 5 | meute 10 | routes, relais routier, bar |
| zombie_driver | Automobiliste zombie | 20 | 1.2 | 4 | | routes, parkings, barrages, péages |
| zombie_trucker | Routier zombie | 50 | 1.5 | 8 | | relais routier, routes |
| zombie_tourist | Touriste zombie | 20 | 1.2 | 3 | | motel, aire de repos, aéroport, ski |
| zombie_camper | Campeur zombie | 22 | 1.2 | 4 | | camping, aire de repos |
| zombie_hiker | Randonneur zombie | 24 | 1.0 | 4 | | forêt, taïga, cabane, camping |
| zombie_survivor | Survivant zombie | 40 | 1.1 | 6 | équipé (sac, couteau) | cabane de l'île, bunker, nature |
| zombie_miner | Mineur zombie | 50 | 1.5 | 9 | pioche | grottes, volcan |
| zombie_mayor | Maire zombie | 90 | 1.2 | 6 | **unique** : scream rayon 20 | mairie |

### 8.3 Commerces, services, bureaux

| id | Nom | PV | Pas | Dég. | Remarques | Lieux |
|---|---|---|---|---|---|---|
| zombie_clerk | Employé zombie | 22 | 1.2 | 4 | | supermarché, épicerie, quincaillerie, station, motel, camping |
| zombie_shopper | Client zombie | 20 | 1.2 | 4 | | supermarché, épicerie, parking |
| zombie_stocker | Magasinier zombie | 28 | 1.2 | 5 | | entrepôt, supermarché |
| zombie_butcher | Boucher zombie | 45 | 1.4 | 8 | saignement 40 % | épicerie, supermarché |
| zombie_pharmacist | Pharmacien zombie | 22 | 1.2 | 3 | loot médicaments | pharmacie |
| zombie_cook | Cuisinier zombie | 28 | 1.2 | 6 | couteau, saignement 30 % | restaurant, maisons |
| zombie_waiter | Serveur zombie | 20 | 1.0 | 3 | rapide | restaurant, bar |
| zombie_bartender | Barman zombie | 32 | 1.3 | 5 | derrière le comptoir | bar |
| zombie_mechanic | Mécanicien zombie | 35 | 1.3 | 7 | clé à molette | station, quincaillerie, hangar, usine |
| zombie_receptionist | Réceptionniste zombie | 20 | 1.2 | 3 | | motel, camping |
| zombie_banker | Banquier zombie | 20 | 1.2 | 3 | | banque |
| zombie_bank_guard | Garde de banque zombie | 55 | 1.3 | 7 | ARMOR 1, tir pistolet | banque |
| zombie_clerical | Fonctionnaire zombie | 20 | 1.2 | 3 | | mairie, usine, port |
| zombie_security | Agent de sécurité zombie | 35 | 1.2 | 5 | matraque | mairie, aéroport, centrale, labo, banque, port |
| zombie_janitor | Concierge zombie | 26 | 1.3 | 4 | | école, mairie, hôpital, appartements |
| zombie_toll_clerk | Péagiste zombie | 22 | 1.2 | 3 | | péage |

### 8.4 Éducation, culte, funéraire

| id | Nom | PV | Pas | Dég. | Remarques | Lieux |
|---|---|---|---|---|---|---|
| zombie_student | Élève zombie | 16 | 0.9 | 3 | meute 8 | école |
| zombie_teacher | Professeur zombie | 24 | 1.2 | 4 | cri de ralliement rayon 12 | école |
| zombie_churchgoer | Fidèle zombie | 20 | 1.4 | 3 | D, assis sur les chaises | église, chapelle |
| zombie_priest | Prêtre zombie | 30 | 1.3 | 4 | cri rayon 15 | église, chapelle |
| zombie_mourner | Endeuillé zombie | 18 | 1.5 | 3 | | cimetière |
| zombie_gravedigger | Fossoyeur zombie | 50 | 1.5 | 9 | pelle | cimetière |
| zombie_grave | Zombie de tombe | 35 | 1.6 | 6 | AMBUSH (sort d'une tombe) | cimetière |

### 8.5 Santé

| id | Nom | PV | Pas | Dég. | Remarques |
|---|---|---|---|---|---|
| zombie_patient | Patient zombie | 18 | 1.4 | 3 | D, dans les lits d'hôpital |
| zombie_nurse | Infirmier zombie | 24 | 1.1 | 4 | morsure infectieuse 30 % ; lâche des médicaments |
| zombie_doctor | Médecin zombie | 26 | 1.2 | 4 | médicaments |
| zombie_surgeon | Chirurgien zombie | 40 | 1.1 | 8 | scalpel : saignement 50 % |
| zombie_orderly | Brancardier zombie | 60 | 1.4 | 7 | costaud, ARMOR 1 |
| zombie_paramedic | Ambulancier zombie | 32 | 1.0 | 5 | rapide ; aussi casernes et routes |
| zombie_psych | Patient psychiatrique zombie | 30 | 0.9 | 5 | ERRATIC, cri rayon 20 |
| zombie_morgue | Zombie de morgue | 30 | 1.6 | 5 | AMBUSH, infection 60 % |
| zombie_quarantine | Zombie de quarantaine | 35 | 1.3 | 5 | infection 70 % ; aussi poste-frontière, labo |
| patient_zero | Patient zéro | 200 | 1.0 | 12 | **unique** (hôpital ou labo) : infection 90 %, cri rayon 30 |

### 8.6 Ordre public et secours

| id | Nom | PV | Pas | Dég. | Remarques |
|---|---|---|---|---|---|
| zombie_cop | Policier zombie | 40 | 1.2 | 5 | ARMOR 1, pistolet (portée 6, recharge 6 s) |
| zombie_swat | Zombie d'intervention | 75 | 1.2 | 8 | ARMOR 3, BURST |
| zombie_prisoner | Détenu zombie | 35 | 1.1 | 6 | dans les cellules |
| zombie_fireman | Pompier zombie | 70 | 1.4 | 9 | ARMOR 2, hache, immunisé au feu |
| zombie_border_guard | Garde-frontière zombie | 55 | 1.2 | 7 | fusil (portée 8) |

### 8.7 Militaire

| id | Nom | PV | Pas | Dég. | Remarques | Lieux |
|---|---|---|---|---|---|---|
| zombie_soldier_armored | Soldat blindé zombie | 110 | 1.5 | 9 | ARMOR 4 | bunker, silo, avant-poste, barrage |
| zombie_sniper | Tireur d'élite zombie | 40 | 1.3 | 14 | G, tir portée 18, recharge 12 s | tour de contrôle, avant-poste, bunker, porte-avions |
| zombie_officer | Officier zombie | 65 | 1.2 | 8 | cri de ralliement (alerte rayon 20), pack 15 | bunker, poste-frontière, porte-avions |
| zombie_combat_medic | Médecin militaire zombie | 50 | 1.0 | 5 | loot médical | bunker |
| zombie_commando | Commando zombie | 90 | 0.8 | 11 | STEALTH, ARMOR 2 | silo, bunker profond, base arctique |
| zombie_flamer | Lance-flammes zombie | 70 | 1.6 | 6 | tir de feu portée 4, EXPLODE(fire) | bunker, silo, barrage |
| zombie_grenadier | Grenadier zombie | 60 | 1.5 | 6 | THROW(frag) portée 5, EXPLODE(frag) | barrage, avant-poste |
| zombie_heavy_gunner | Mitrailleur zombie | 100 | 1.9 | 6 | BURST portée 10 | barrage, poste-frontière, silo, porte-avions |
| zombie_engineer | Sapeur zombie | 55 | 1.3 | 6 | pièges (futur) | bunker, poste-frontière |
| zombie_pilot_mil | Pilote militaire zombie | 35 | 1.2 | 4 | | héliport, porte-avions, aéroport |
| zombie_sentry | Sentinelle zombie | 85 | 1.4 | 9 | **G**, ARMOR 2 | entrée de bunker, centrale, silo |
| zombie_bio_op | Bio-opérateur zombie | 150 | 1.0 | 13 | ARMOR 3, REGEN 0.3 | bunker profond, labo, silo |
| zombie_armored_brute | Brute blindée | 200 | 1.7 | 18 | ARMOR 5, CHARGE | silo, base arctique |
| zombie_commander | Commandant zombie | 220 | 1.2 | 14 | **unique** : cri de ralliement, SUMMON | silo, bunker profond |

### 8.8 Science et industrie

| id | Nom | PV | Pas | Dég. | Remarques | Lieux |
|---|---|---|---|---|---|---|
| zombie_scientist | Scientifique zombie | 22 | 1.2 | 4 | | labo, centrale, recherche |
| zombie_technician | Technicien zombie | 30 | 1.2 | 5 | décharge (drain de stamina) | labo, centrale, radio |
| zombie_hazmat | Zombie en combinaison NBC | 70 | 1.5 | 6 | ARMOR 2, immunisé acide/poison | labo, centrale, égouts, usine, quarantaine |
| zombie_researcher | Chercheur zombie | 26 | 1.2 | 3 | seringue (portée 6, poison) | labo |
| zombie_lab_guard | Garde de labo zombie | 60 | 1.2 | 7 | ARMOR 2, tir | labo |
| zombie_lab_subject | Sujet de test zombie | 40 | 1.0 | 6 | ERRATIC | labo |
| zombie_cryo | Zombie cryogénisé | 60 | 1.7 | 7 | COLD_AURA | labo, base arctique |
| zombie_reactor_tech | Technicien de réacteur zombie | 50 | 1.4 | 6 | AURA_RAD faible | centrale |
| zombie_irradiated | Zombie irradié | 55 | 1.3 | 6 | AURA_RAD | centrale, contamination |
| zombie_glowing | Zombie luisant | 80 | 1.2 | 8 | AURA_RAD fort | cœur de réacteur |
| zombie_lab_director | Directeur de labo zombie | 120 | 1.1 | 8 | **unique**, ARMOR 1, badge (loot) | labo |
| zombie_worker | Ouvrier zombie | 30 | 1.3 | 5 | | usine, entrepôt, égouts |
| zombie_welder | Soudeur zombie | 35 | 1.4 | 5 | étincelles (feu, portée 3) | usine |
| zombie_foreman | Contremaître zombie | 55 | 1.3 | 8 | cri rayon 12 | usine, entrepôt, port |
| zombie_electrician | Électricien zombie | 35 | 1.3 | 5 | décharge | poste électrique, centrale, barrage |
| zombie_sewer_worker | Égoutier zombie | 40 | 1.3 | 6 | poison 30 % | station d'épuration |
| zombie_dam_engineer | Ingénieur de barrage zombie | 45 | 1.3 | 6 | | barrage |

### 8.9 Expériences ratées (labos, bunkers, hôpitaux profonds, recherche marine)

| id | Nom | PV | Pas | Dég. | Remarques |
|---|---|---|---|---|---|
| experiment_bloated | Expérience gonflée | 50 | 2.0 | 3 | EXPLODE(acid) rayon 2 |
| experiment_chimera | Chimère | 90 | 0.8 | 11 | LEAP, saignement |
| experiment_flesh_mass | Masse de chair | 140 | 2.2 | 10 | REGEN, GRAB |
| experiment_blob | Blob | 60 | 1.6 | 5 | SPLIT |
| experiment_stalker | Traqueur | 70 | 0.7 | 12 | AMBUSH, STEALTH |
| experiment_crawler | Rampant mutant | 45 | 1.0 | 7 | vise les jambes |
| experiment_homunculus | Homoncule | 18 | 0.6 | 4 | SWARM, rapide |
| experiment_screamer | Hurleur de laboratoire | 40 | 1.3 | 4 | hurlement 40 |
| experiment_parasite | Parasite | 25 | 0.7 | 3 | LEAP, infection 60 % |
| experiment_acid_hound | Chien d'acide | 45 | 0.7 | 6 | tir d'acide portée 5, EXPLODE(acid) |
| experiment_clone | Clone raté | 70 | 1.2 | 8 | ERRATIC |
| experiment_slime | Limon toxique | 75 | 2.4 | 6 | poison, traînée d'acide (futur) |
| experiment_swarm | Essaim de laboratoire | 12 | 0.5 | 2 | SWARM, FLY |
| experiment_tyrant | Tyran | 320 | 1.4 | 25 | REGEN, CHARGE, ARMOR 3 ; labo profond |
| experiment_nightmare | Cauchemar | 260 | 0.9 | 20 | **unique**, STEALTH, cri rayon 40 |

### 8.10 Faune normale et mutante

| id | Nom | PV | Pas | Dég. | État | Remarques |
|---|---|---|---|---|---|---|
| deer | Cerf | 45 | 0.9 | 6 | P | fuit ; se défend acculé |
| boar | Sanglier | 55 | 1.0 | 8 | T | CHARGE |
| fox | Renard | 18 | 0.7 | 3 | P | |
| coyote | Coyote | 25 | 0.8 | 5 | meute 10 | |
| dog_feral | Chien errant | 28 | 0.8 | 5 | meute 8 | |
| crow | Corbeau | 8 | 0.6 | 2 | | FLY, volée (pack 14) |
| rat_giant | Rat géant | 14 | 0.8 | 3 | | saignement 15 %, meute 8 |
| wolf_mutant | Loup mutant | 70 | 0.7 | 10 | meute 14 | saignement 50 % |
| bear_mutant | Ours mutant | 220 | 1.1 | 18 | T | REGEN 0.2 |
| deer_mutant | Cerf mutant | 90 | 0.8 | 12 | T | CHARGE |
| boar_mutant | Sanglier mutant | 110 | 0.9 | 13 | | CHARGE |
| crow_mutant | Corbeau mutant | 20 | 0.5 | 4 | | FLY, hurlement 15 |
| rat_irradiated | Rat irradié | 25 | 0.8 | 5 | | AURA_RAD faible |
| cockroach_giant | Cafard géant | 20 | 0.9 | 3 | | SWARM |
| ant_giant | Fourmi géante | 35 | 0.8 | 6 | | meute 10, acide |
| ant_queen | Reine fourmi | 160 | 1.6 | 12 | | SUMMON (fourmis) ; fourmilière (futur) |
| spider_mutant | Araignée irradiée | 80 | 0.8 | 9 | | poison long, LEAP |
| spider_cave | Araignée des cavernes | 50 | 0.9 | 7 | | AMBUSH |
| bat_swarm | Nuée de chauves-souris | 10 | 0.5 | 2 | | FLY, SWARM |
| bat_giant | Chauve-souris géante | 40 | 0.6 | 6 | | FLY |
| snake | Serpent | 15 | 0.9 | 4 | | poison 40 % |
| snake_rattle | Serpent à sonnette | 20 | 0.8 | 5 | | poison 70 %, AMBUSH |
| snake_mutant | Serpent mutant | 60 | 0.8 | 9 | | poison long |
| frog_mutant | Grenouille mutante | 30 | 0.8 | 5 | | LEAP, SPORE (marais) |
| leech_swarm | Nuée de sangsues | 10 | 1.2 | 2 | | SWARM, saignement |
| alligator | Alligator | 140 | 1.3 | 16 | | SWIM, GRAB |
| alligator_mutant | Alligator mutant | 220 | 1.0 | 22 | | SWIM, GRAB, REGEN |

### 8.11 Eau, côtes, mer

Les monstres `AQUATIC` / `SWIM` ne sont activés qu'avec le pathfinding nautique (6d) : avant, seuls leurs équivalents de rive (crabes, goélands, noyés) apparaissent.

| id | Nom | PV | Pas | Dég. | Remarques |
|---|---|---|---|---|---|
| zombie_swimmer | Zombie nageur | 35 | 1.6 | 5 | SWIM : traverse l'eau profonde |
| zombie_drowned | Zombie noyé | 30 | 1.8 | 5 | SWIM, AMBUSH (sort de l'eau) ; lacs, rivières, marais |
| zombie_sailor | Marin zombie | 35 | 1.3 | 6 | port, marina, phare, plateforme |
| zombie_dockworker | Docker zombie | 40 | 1.4 | 7 | port |
| zombie_stowaway | Clandestin zombie | 28 | 1.3 | 5 | D, AMBUSH dans les conteneurs |
| zombie_captain | Capitaine zombie | 70 | 1.2 | 8 | cri rayon 15 |
| zombie_fisherman | Pêcheur zombie | 28 | 1.2 | 5 | harpon (GRAB court) |
| zombie_diver | Plongeur zombie | 55 | 1.7 | 7 | SWIM, ARMOR 1 |
| zombie_oil_worker | Ouvrier pétrolier zombie | 45 | 1.4 | 7 | plateforme |
| zombie_lighthouse_keeper | Gardien de phare zombie | 55 | 1.3 | 7 | G |
| zombie_oceanographer | Océanographe zombie | 24 | 1.2 | 3 | station de recherche |
| zombie_pirate | Pirate zombie | 50 | 1.2 | 9 | sabre, saignement 40 % |
| zombie_smuggler | Contrebandier zombie | 40 | 1.1 | 6 | pistolet |
| pirate_captain | Capitaine pirate | 160 | 1.1 | 14 | **unique**, BURST, cri rayon 20 |
| crab_giant | Crabe géant | 70 | 1.5 | 9 | ARMOR 2 ; plages |
| seagull_mutant | Goéland mutant | 12 | 0.6 | 3 | FLY, volée |
| piranha_swarm | Banc de piranhas | 20 | 0.6 | 3 | AQUATIC, SWARM, saignement |
| eel_electric | Anguille électrique | 40 | 0.8 | 6 | AQUATIC, drain de stamina |
| jellyfish | Méduse | 25 | 1.4 | 3 | AQUATIC, poison |
| shark | Requin | 160 | 0.7 | 20 | AQUATIC, saignement |
| shark_mutant | Requin mutant | 280 | 0.6 | 28 | AQUATIC, REGEN |
| squid_giant | Calmar géant | 240 | 1.0 | 18 | AQUATIC, GRAB |
| kraken | Kraken | 600 | 1.2 | 35 | **unique**, pleine mer, GRAB |
| zombie_passenger | Passager zombie | 20 | 1.2 | 3 | aéroport (D dans les bancs) |
| zombie_flight_attendant | Hôtesse zombie | 22 | 1.1 | 3 | aéroport |
| zombie_baggage | Bagagiste zombie | 35 | 1.3 | 6 | aéroport |
| zombie_controller | Contrôleur aérien zombie | 20 | 1.2 | 3 | tour de contrôle |
| zombie_pilot | Pilote zombie | 30 | 1.2 | 4 | aéroport, héliport, plateforme |

### 8.12 Climats et lieux extrêmes

| id | Nom | PV | Pas | Dég. | Climat / lieu | Remarques |
|---|---|---|---|---|---|---|
| wolf_arctic | Loup arctique | 50 | 0.7 | 8 | froid | meute 14 |
| bear_polar | Ours polaire | 190 | 1.0 | 16 | froid | T, saignement |
| mutant_yeti | Yéti | 240 | 1.1 | 20 | froid, rare | CHARGE, COLD_AURA, STEALTH |
| zombie_frozen | Zombie gelé | 50 | 1.8 | 6 | froid | COLD_AURA faible |
| zombie_skier | Skieur zombie | 28 | 0.7 | 4 | station de ski | rapide |
| lion | Lion | 120 | 0.7 | 15 | savane | meute 10, LEAP |
| hyena | Hyène | 45 | 0.7 | 7 | savane | meute 14, saignement |
| vulture_mutant | Vautour mutant | 35 | 0.6 | 6 | désert, savane | FLY |
| scorpion_giant | Scorpion géant | 85 | 0.9 | 10 | désert | poison long, ARMOR 1 |
| sandworm | Ver des sables | 400 | 1.0 | 30 | désert | AMBUSH, GRAB ; rare |
| zombie_mummified | Zombie momifié | 55 | 1.5 | 7 | désert | faible au feu (×2) |
| jaguar | Jaguar | 80 | 0.6 | 12 | jungle | LEAP, STEALTH |
| python_giant | Python géant | 130 | 1.2 | 8 | jungle | CONSTRICT |
| tarantula_giant | Tarentule géante | 70 | 0.8 | 8 | jungle | poison, LEAP |
| monkey_mutant | Singe mutant | 35 | 0.6 | 5 | jungle | meute 12, ERRATIC |
| mosquito_swarm | Nuée de moustiques | 8 | 0.5 | 1 | jungle, marais | FLY, SWARM, infection 10 % |
| crocodile | Crocodile | 180 | 1.2 | 20 | jungle | SWIM, GRAB |
| zombie_overgrown | Zombie envahi | 70 | 1.7 | 7 | jungle | SPORE |
| zombie_charred | Zombie calciné | 60 | 1.4 | 8 | volcan, incendie | FIRE_AURA, immunisé au feu |
| fire_hound | Chien de feu | 55 | 0.7 | 8 | volcan | FIRE_AURA, EXPLODE(fire) |
| magma_crawler | Rampant de magma | 120 | 1.8 | 12 | volcan | FIRE_AURA, ARMOR 2 |
| skeleton | Squelette | 25 | 1.2 | 5 | ruines, cimetière | résiste aux balles (futur) |
| skeleton_brute | Squelette brute | 90 | 1.4 | 11 | ruines | ARMOR 1 |
| mummy | Momie | 85 | 1.6 | 9 | ruines | faible au feu |
| ruin_guardian | Gardien des ruines | 250 | 1.8 | 22 | ruines | G, ARMOR 4 |
| troglodyte | Troglodyte | 55 | 0.9 | 8 | grottes | BLIND_HEARING |

### 8.13 Humains hostiles (hors périmètre du jalon 6, réservé)

`bandit`, `raider`, `cannibal`, `cultist`, `hermit` (cabane de l'île), `sniper_survivor`. Ils demandent des PNJ (équipement, dialogue, factions) : un jalon dédié. Les emplacements existent déjà dans les tables (§11) sous forme de `zombie_survivor`.

---

## 9. Affixes : toutes les combinaisons

Un **affixe** modifie un monstre de base. Un monstre créé a 0 à 2 affixes. Nom composé : `{nom}` + adjectif accordé en genre (`gender` du monstre : « Policier zombie gelé », « Infirmière zombie irradiée »). Un monstre déjà « de base mutant » (ex. `zombie_irradiated`) n'accepte pas l'affixe correspondant.

| Affixe | Adjectif m / f | PV | Pas | Dég. | Effet | Condition d'apparition |
|---|---|---|---|---|---|---|
| frozen | gelé / gelée | ×1.3 | ×1.3 | ×1 | COLD_AURA faible, immunisé froid | climat froid ; labo cryo ; base arctique |
| charred | calciné / calcinée | ×1.1 | ×1 | ×1.1 | FIRE_AURA, immunisé feu | volcan, incendie, contamination feu |
| irradiated | irradié / irradiée | ×1.3 | ×1 | ×1 | AURA_RAD | contamination radiation |
| toxic | toxique / toxique | ×1.1 | ×1 | ×1 | poison 30 % sur coup ; EXPLODE(gas) petit | contamination toxique ; usine ; égouts |
| electrified | électrifié / électrifiée | ×1.2 | ×1 | ×1 | décharge (drain de stamina) | poste électrique ; orage (futur) |
| armored | blindé / blindée | ×1.5 | ×1.2 | ×1 | ARMOR +2 | militaire, police, intervention |
| mummified | momifié / momifiée | ×1.1 | ×1.2 | ×1 | faible au feu ×2, ne s'infecte pas | désert, ruines |
| overgrown | envahi / envahie | ×1.2 | ×1.3 | ×1 | SPORE | jungle, marais |
| rotten | putréfié / putréfiée | ×0.8 | ×1.4 | ×1 | infection +20 % | marais, morgue, cave humide, vieux cadavres |
| bloated | gonflé / gonflée | ×1.5 | ×1.6 | ×0.6 | EXPLODE(gas) | égouts, marais, port |
| feral | enragé / enragée | ×0.9 | ×0.7 | ×1.2 | détection ×1.3 ; ne dort jamais | proche de contamination, nuit (futur) |
| alpha | alpha | ×1.8 | ×0.9 | ×1.3 | pack buff (alliés à 8 cases : dégâts ×1.1) ; **un par groupe au plus** | groupes ≥ 4 monstres, 8 % |
| veteran | vétéran / vétérane | ×1.3 | ×1 | ×1.2 | +1 ARMOR | lieux rares, profondeur |
| infested | grouillant / grouillante | ×1 | ×1 | ×1 | à la mort : 1 à 3 rats ou asticots | entrepôts, égouts, caves |

### 9.1 Compatibilité (affixe × famille)

✔ = autorisé · ✘ = interdit · ○ = autorisé mais rare (÷3).

| Affixe | zombie civil / dressed | zombie spécial | animal | mutant | experiment | skeleton | aquatic |
|---|---|---|---|---|---|---|---|
| frozen | ✔ | ○ | ✔ | ○ | ✘ | ✘ | ✘ |
| charred | ✔ | ○ | ✔ | ○ | ✘ | ✘ | ✘ |
| irradiated | ✔ | ✔ | ✔ | ✘ | ○ | ✘ | ○ |
| toxic | ✔ | ✔ | ✔ | ○ | ○ | ✘ | ✔ |
| electrified | ✔ | ○ | ○ | ○ | ○ | ✘ | ✔ |
| armored | ✔ (military, police, security) | ✘ | ✘ | ✘ | ✘ | ✔ | ✘ |
| mummified | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ |
| overgrown | ✔ | ✔ | ✔ | ○ | ✘ | ✘ | ✔ |
| rotten | ✔ | ✔ | ✔ | ✘ | ✘ | ✘ | ✔ |
| bloated | ✔ | ○ | ✘ | ✘ | ✘ | ✘ | ○ |
| feral | ✔ | ✔ | ✔ | ✔ | ○ | ✘ | ✔ |
| alpha | ✔ | ✔ | ✔ | ✔ | ✔ | ✘ | ✔ |
| veteran | ✔ | ✔ | ✘ | ✔ | ✔ | ✔ | ✘ |
| infested | ✔ | ○ | ✘ | ✘ | ✘ | ✘ | ✘ |

### 9.2 Probabilités de base (par monstre tiré)

`P(affixe) = base(contexte) × proportion` : contamination → `irradiated` / `toxic` / `charred` avec p = niveau × 0.8 ; climat froid → `frozen` 0.25 pour les zombies civils en extérieur ; désert → `mummified` 0.2 ; jungle/marais → `overgrown` 0.2 ; entrepôts et égouts → `infested` 0.1 ; groupes ≥ 4 → un `alpha` 0.08 ; lieux « rares » (`rare` dans la règle) → `veteran` 0.1.

### 9.3 Exemples de combinaisons (non exhaustif, juste pour fixer le ton)

- Policier zombie **gelé** (commissariat de taïga), Infirmier zombie **irradié** (clinique près de la centrale), Soldat zombie **calciné** (barrage près d'un volcan).
- Pompier zombie **toxique** (caserne près de l'usine), Scientifique zombie **momifié** (labo en plein désert), Loup arctique **alpha**.
- Technicien zombie **électrifié** (poste électrique), Ouvrier zombie **grouillant** (entrepôt), Marin zombie **gonflé** (port).
- Garde de labo **vétéran irradié** : cumul de deux affixes, au plus un de contamination.

Nombre total de variantes réalisables ≈ (bases compatibles × affixes) : de l'ordre de plusieurs centaines, toutes calculées, jamais écrites à la main.

---

## 10. Groupes de spawn (`spawn_groups.json`)

Format : `monstre:poids`. Un nom entre crochets est un groupe inclus.

### 10.1 Ville, foyer, commerce

| Groupe | Contenu |
|---|---|
| `amb_street` | zombie_civilian:6, zombie:5, zombie_elder:2, zombie_teen:2, zombie_child:1, zombie_fast:1, zombie_drunk:1, zombie_crawler:1, zombie_scavenger:1 |
| `amb_yard` | zombie_civilian:4, zombie_homeowner:2, zombie_child:2, zombie_elder:1, dog_feral:1, crow:1 |
| `home_any` | zombie_civilian:5, zombie_homeowner:3, zombie_elder:2, zombie_teen:2, zombie_child:2, zombie_hoarder:1 |
| `home_bed` | zombie_pajamas:6, zombie_elder:2, zombie_child:1 |
| `home_bath` | zombie_bather:3, zombie_pajamas:1 |
| `home_kitchen` | zombie_civilian:3, zombie_cook:1, zombie_homeowner:1 |
| `shed_group` | zombie_homeowner:3, zombie_mechanic:1, rat_giant:2, zombie_civilian:1 |
| `apartments_g` | zombie_tenant:8, zombie_pajamas:3, zombie_elder:2, zombie_child:2, zombie_hoarder:1 |
| `shop_staff` | zombie_clerk:6, zombie_stocker:2, zombie_janitor:1 |
| `shop_customers` | zombie_shopper:8, zombie_elder:2, zombie_teen:2, zombie_child:1 |
| `meat_counter` | zombie_butcher:1 |
| `pharma_g` | zombie_pharmacist:4, zombie_clerk:2, zombie_shopper:2, zombie_nurse:1 |
| `hardware_g` | zombie_mechanic:4, zombie_clerk:3, zombie_homeowner:2 |
| `bar_g` | zombie_drunk:6, zombie_civilian:3, zombie_biker:1 |
| `bar_counter` | zombie_bartender:1 |
| `resto_kitchen` | zombie_cook:5, zombie_waiter:1 |
| `resto_hall` | zombie_civilian:5, zombie_waiter:4, zombie_elder:1, zombie_child:1 |
| `bank_staff` | zombie_banker:5, zombie_bank_guard:2 |
| `bank_vault` | zombie_bank_guard:3, zombie_swat:1 |
| `motel_g` | zombie_tourist:4, zombie_pajamas:4, zombie_trucker:1 |
| `motel_counter` | zombie_receptionist:1 |
| `gas_g` | zombie_clerk:3, zombie_mechanic:3, zombie_trucker:2, zombie_driver:3, zombie_biker:1 |
| `parking_g` | zombie_driver:5, zombie_shopper:3, zombie_teen:2, zombie_scavenger:1 |

### 10.2 Services publics, éducation, culte, funéraire

| Groupe | Contenu |
|---|---|
| `police_staff` | zombie_cop:8, zombie_security:1, zombie_civilian:2 |
| `police_cells` | zombie_prisoner:8, zombie_cop:2 |
| `police_swat` | zombie_swat:3, zombie_cop:3 |
| `fire_staff` | zombie_fireman:8, zombie_paramedic:2 |
| `school_class` | zombie_student:10, zombie_teacher:2 |
| `school_hall` | zombie_student:6, zombie_janitor:2, zombie_teacher:1 |
| `church_nave` | zombie_churchgoer:8, zombie_elder:3 |
| `church_altar` | zombie_priest:1 |
| `cemetery_g` | zombie_mourner:4, zombie_gravedigger:1, zombie_morgue:1 |
| `cemetery_graves` | zombie_grave:5, zombie_morgue:2 |
| `town_hall_g` | zombie_clerical:8, zombie_security:2, zombie_janitor:1 |

### 10.3 Santé (hôpital, clinique)

| Groupe | Contenu |
|---|---|
| `hosp_waiting` | zombie_civilian:6, zombie_elder:3, zombie_child:2, zombie_patient:3 |
| `hosp_ward` | zombie_patient:8, zombie_pajamas:2, zombie_nurse:3 |
| `hosp_staff` | zombie_nurse:6, zombie_doctor:4, zombie_orderly:2, zombie_paramedic:1 |
| `hosp_surgery` | zombie_surgeon:4, zombie_nurse:3, zombie_doctor:2, experiment_parasite:1 |
| `hosp_psych` | zombie_psych:8, zombie_orderly:2, zombie_nurse:1 |
| `hosp_morgue` | zombie_morgue:8, zombie_surgeon:1 |
| `hosp_quarantine` | zombie_quarantine:6, zombie_hazmat:3 |
| `hosp_basement` | experiment_bloated:3, experiment_parasite:3, experiment_flesh_mass:1 |

### 10.4 Industrie, énergie, entrepôts

| Groupe | Contenu |
|---|---|
| `factory_floor` | zombie_worker:8, zombie_welder:2, zombie_foreman:1, zombie_mechanic:2 |
| `factory_office` | zombie_clerical:4, zombie_foreman:2, zombie_security:1 |
| `factory_leak` | zombie_gasbag:3, zombie_acidic:3, zombie_hazmat:1 |
| `warehouse_g` | zombie_stocker:6, zombie_worker:3, zombie_scavenger:2, rat_giant:3, zombie_foreman:1 |
| `sewage_g` | zombie_sewer_worker:6, rat_giant:6, zombie_hazmat:1, experiment_slime:1 |
| `sewage_basin_g` | leech_swarm:3, zombie_drowned:4, alligator_mutant:1 |
| `substation_g` | zombie_electrician:5, zombie_electric:4, zombie_technician:1 |
| `npp_staff` | zombie_reactor_tech:4, zombie_technician:3, zombie_scientist:2, zombie_security:2 |
| `npp_reactor_g` | zombie_irradiated:4, zombie_glowing:3, zombie_reactor_tech:3 |
| `npp_yard_g` | zombie_security:3, zombie_hazmat:2, wolf_mutant:3, deer_mutant:2, zombie_irradiated:1 |
| `npp_guard_g` | zombie_security:5, zombie_soldier:2, zombie_sentry:1 |

### 10.5 Rural, camping, routes

| Groupe | Contenu |
|---|---|
| `farm_house_g` | zombie_farmer:3, zombie_civilian:3, zombie_elder:2, zombie_pajamas:2, zombie_child:1 |
| `farm_field_g` | zombie_farmhand:4, zombie_farmer:2, crow:4, boar:1, zombie_civilian:1 |
| `barn_g` | zombie_farmhand:3, zombie_farmer:1, rat_giant:3, boar:1 |
| `ranch_g` | zombie_cowboy:4, zombie_farmer:2, zombie_farmhand:2 |
| `pasture_g` | zombie_cow:5, zombie_horse:3, zombie_cowboy:1 |
| `stable_g` | zombie_horse:4, zombie_cowboy:2 |
| `cabin_g` | zombie_hiker:3, zombie_civilian:2, bear:1, wolf:1 |
| `camp_g` | zombie_camper:6, zombie_hiker:2, zombie_child:2, bear:1 |
| `camp_office_g` | zombie_clerk:3, zombie_camper:2 |
| `rest_g` | zombie_tourist:4, zombie_driver:3, zombie_camper:2 |
| `truck_g` | zombie_trucker:5, zombie_mechanic:2, zombie_driver:2, zombie_biker:2, zombie_clerk:2 |
| `truck_lot_g` | zombie_trucker:4, zombie_driver:2, rat_giant:1 |
| `roadblock_g` | zombie_soldier:3, zombie_cop:3, zombie_driver:4, zombie_grenadier:1, zombie_flamer:1 |
| `toll_g` | zombie_toll_clerk:3, zombie_driver:4, zombie_cop:1 |
| `checkpoint_g` | zombie_border_guard:5, zombie_soldier:3, zombie_officer:1, zombie_quarantine:2, zombie_driver:3, zombie_engineer:1 |
| `bridge_toll_g` | zombie_toll_clerk:3, zombie_driver:3, zombie_drowned:1 |

`zombie_cow` (Vache zombie : 120 PV, pas 1.6, dég. 9, coup de sabot) et `zombie_horse` (Cheval zombie : 90 PV, pas 0.6, dég. 11, CHARGE) rejoignent le bestiaire de la section 8.2 / 8.10 au jalon 6b.

### 10.6 Militaire et secret

| Groupe | Contenu |
|---|---|
| `bunker_g` | zombie_soldier:6, zombie_soldier_armored:3, zombie_sentry:2, zombie_sniper:1, zombie_officer:1, zombie_combat_medic:1, zombie_engineer:1 |
| `bunker_deep` | zombie_bio_op:3, zombie_commando:2, zombie_armored_brute:1, experiment_stalker:2 |
| `silo_g` | zombie_soldier_armored:4, zombie_commando:3, zombie_flamer:2, zombie_heavy_gunner:2, zombie_officer:1, zombie_armored_brute:1 |
| `radio_g` | zombie_technician:4, zombie_soldier:2, zombie_sniper:1 |
| `outpost_g` | zombie_soldier:4, zombie_sniper:1, zombie_mummified:2, scorpion_giant:2 |
| `lab_staff` | zombie_scientist:6, zombie_technician:3, zombie_researcher:3, zombie_hazmat:2 |
| `lab_guard` | zombie_lab_guard:5, zombie_security:2, zombie_soldier:1 |
| `lab_subjects` | zombie_lab_subject:5, experiment_crawler:2, experiment_homunculus:2, zombie_cryo:1 |
| `lab_failed` | experiment_bloated:3, experiment_chimera:2, experiment_flesh_mass:1, experiment_blob:2, experiment_stalker:1, experiment_acid_hound:2, experiment_screamer:1 |
| `lab_deep` | experiment_tyrant:1, zombie_bio_op:2, experiment_chimera:2, experiment_clone:2 |
| `arctic_g` | zombie_cryo:3, zombie_commando:2, zombie_soldier_armored:3, wolf_arctic:3, zombie_frozen:4, bear_polar:1 |
| `carrier_g` | zombie_pilot_mil:4, zombie_sailor:4, zombie_soldier:3, zombie_heavy_gunner:1, zombie_officer:1, zombie_sniper:1 |

### 10.7 Mer, côtes, air

| Groupe | Contenu |
|---|---|
| `port_dock` | zombie_dockworker:6, zombie_sailor:3, zombie_foreman:1, zombie_swimmer:2, seagull_mutant:3, rat_giant:2 |
| `port_container` | zombie_stowaway:4, zombie_dockworker:2 |
| `port_office_g` | zombie_clerical:3, zombie_captain:1, zombie_security:1 |
| `airport_runway_g` | zombie_pilot:2, zombie_baggage:3, zombie_mechanic:2, crow:3 |
| `airport_terminal_g` | zombie_passenger:8, zombie_flight_attendant:2, zombie_security:3, zombie_tourist:2, zombie_baggage:1 |
| `airport_hangar_g` | zombie_mechanic:4, zombie_pilot:2, rat_giant:1 |
| `airport_tower_g` | zombie_controller:4, zombie_security:1 |
| `airport_apron_g` | zombie_passenger:4, zombie_pilot:2, zombie_baggage:2, zombie_pilot_mil:1 |
| `lighthouse_g` | zombie_lighthouse_keeper:1, zombie_fisherman:2, seagull_mutant:3, zombie_swimmer:2 |
| `oil_g` | zombie_oil_worker:6, zombie_diver:2, zombie_security:2, zombie_swimmer:2, zombie_pilot:1 |
| `hermit_g` | zombie_survivor:2, zombie_hiker:1, rat_giant:2 |
| `dam_g` | zombie_dam_engineer:4, zombie_electrician:2, zombie_worker:2, zombie_drowned:3 |
| `marina_g` | zombie_sailor:4, zombie_fisherman:3, zombie_tourist:3, zombie_drowned:2 |
| `shipwreck_g` | zombie_drowned:5, zombie_sailor:3 |
| `pirate_g` | zombie_pirate:6, zombie_smuggler:3, zombie_sailor:2 |
| `research_g` | zombie_oceanographer:4, zombie_scientist:3, zombie_diver:2 |
| `island_village_g` | zombie_fisherman:4, zombie_civilian:4, zombie_swimmer:2, crab_giant:2 |

### 10.8 Lieux extrêmes (jalon 15)

| Groupe | Contenu |
|---|---|
| `ski_g` | zombie_skier:6, zombie_tourist:3, zombie_paramedic:1, wolf_arctic:1 |
| `volcano_g` | zombie_charred:5, fire_hound:3, magma_crawler:1, zombie_miner:2 |
| `ruins_g` | skeleton:6, mummy:3, skeleton_brute:2, ruin_guardian:1 |
| `cave_g` | bat_swarm:4, troglodyte:3, spider_cave:3, zombie_miner:3, bear:1 |
| `oasis_g` | zombie_tourist:2, snake_rattle:2, vulture_mutant:2, hyena:2 |

---

## 11. Table lieu → population (`place_spawns.json`)

Notation : `groupe  mode  d=densité/100 cases  dorm=part dormante`. Mode `A:f_x` = `affinity` sur le meuble `f_x` avec `p` par meuble. Les plans notés « à créer » sont des prérequis (§16).

### 11.1 Maisons et dépendances (`houses.json`)

| Plan | Règles |
|---|---|
| `house_small`, `house_family`, `house_bungalow` | `home_any F d=0.8 dorm=0.6` ; `home_bed A:f_bed p=0.45 dorm=0.9` ; `home_bath A:f_bathtub p=0.2` ; `home_kitchen A:f_oven p=0.3` |
| `shed` | `shed_group F d=1.2 dorm=0.3` |

### 11.2 Bâtiments de ville (`urban.json`)

| Plan | Règles |
|---|---|
| `urban_apartments` | `apartments_g F d=1.0 dorm=0.6` ; `home_bed A:f_bed p=0.5 dorm=0.9` ; `home_bath A:f_bathtub p=0.2` |
| `urban_grocery` | `shop_staff F d=0.5 dorm=0.2` ; `shop_customers F d=0.7 dorm=0.4` ; `meat_counter A:f_counter p=0.15` |
| `urban_supermarket` | `shop_staff F d=0.5` ; `shop_customers F d=0.9 dorm=0.4` ; `meat_counter A:f_counter p=0.1` ; `parking_g P d=0.4` |
| `urban_pharmacy` | `pharma_g F d=0.9 dorm=0.3` |
| `urban_hardware` | `hardware_g F d=0.7 dorm=0.3` ; `warehouse_g P d=0.1` |
| `urban_bar` | `bar_g F d=1.1 dorm=0.5` ; `bar_counter A:f_counter p=0.2` |
| `urban_restaurant` | `resto_kitchen F d=0.5 dorm=0.2` ; `resto_hall F d=0.8 dorm=0.5` |
| `urban_police` | `police_staff F d=1.2 dorm=0.4` ; `police_cells A:f_bed p=0.7 dorm=0.2` ; `police_swat F d=0.3 rare=0.15 dorm=0.1` |
| `urban_school` | `school_class A:f_desk p=0.5 dorm=0.7` ; `school_hall F d=0.5 dorm=0.4` |
| `urban_church` | `church_nave A:f_bench p=0.6 dorm=0.9` ; `church_altar A:f_altar p=0.6 dorm=0.5` |
| `urban_parking` | `parking_g P d=0.5 dorm=0.3` |
| `urban_town_hall` | `town_hall_g F d=0.9 dorm=0.5` ; unique `zombie_mayor` (§13) |
| `urban_fire_station` | `fire_staff F d=0.9 dorm=0.4` ; `fire_staff A:f_locker p=0.3 dorm=0.8` |
| `urban_bank` | `bank_staff F d=0.8 dorm=0.4` ; `bank_vault A:f_safe p=0.6 dorm=0.2` |
| `urban_hospital` (à créer) | `hosp_waiting A:f_chair p=0.5 dorm=0.7` ; `hosp_ward A:f_hospital_bed p=0.7 dorm=0.9` ; `hosp_staff A:f_desk p=0.5 dorm=0.4` ; `hosp_surgery A:f_surgery_table p=0.8 dorm=0.3` ; `hosp_morgue A:f_morgue_drawer p=0.6 dorm=0.95` ; `hosp_psych A:f_cell_bed p=0.7 dorm=0.4` ; `hosp_quarantine A:f_quarantine_bed p=0.8 dorm=0.2 rare=0.25` ; `hosp_basement F min_depth=1 d=0.8 rare=0.3` ; unique `patient_zero` rare |
| `urban_clinic` (à créer, petite) | `hosp_waiting A:f_chair p=0.5` ; `hosp_ward A:f_hospital_bed p=0.6` ; `hosp_staff A:f_desk p=0.5` |
| `urban_nursing_home` (à créer) | `hosp_ward A:f_hospital_bed p=0.8 dorm=0.9` ; `home_any F d=0.6` avec poids vers `zombie_elder` |
| `urban_garage` (à créer) | `hardware_g F d=0.8` ; `zombie_mechanic A:f_machinery_heavy p=0.4` |

### 11.3 Lieux spéciaux existants (`places.json`, `big_places.json`, `access_places.json`)

| Plan | Règles |
|---|---|
| `gas_station` | `gas_g F d=0.8` ; `gas_g P d=0.15` |
| `motel_office` | `motel_counter A:f_counter p=0.4` ; `motel_g F d=0.6` |
| `motel_wing` | `motel_g A:f_bed p=0.5 dorm=0.9` ; `home_bath A:f_bathtub p=0.15` |
| `farm_field` | `farm_field_g N d=0.5` (champ) |
| `farmhouse` | `farm_house_g F d=0.8 dorm=0.5` ; `home_bed A:f_bed p=0.4 dorm=0.9` |
| `barn` | `barn_g F d=0.8 dorm=0.4` |
| `pasture` | `pasture_g N d=0.35` |
| `stable` | `stable_g F d=0.8 dorm=0.5` |
| `npp_turbine` | `npp_staff F d=0.7 dorm=0.3` ; `zombie_electrician A:f_machinery_light p=0.3` |
| `npp_transformers` | `substation_g N d=0.3` ; contamination forte |
| `npp_storage` | `npp_reactor_g F d=0.6` ; `warehouse_g F d=0.2` |
| `npp_yard` | `npp_yard_g P d=0.4` |
| `npp_reactor` | `npp_reactor_g F d=1.0 dorm=0.1 contaminate=false` ; `zombie_glowing A:f_console p=0.2` ; unique `reactor_horror` rare |
| `npp_control` | `npp_staff A:f_console p=0.6 dorm=0.4` |
| `npp_guard` | `npp_guard_g P d=0.5 dorm=0.1` (garde, ne dort pas) |
| `npp_gate` | `npp_guard_g P d=0.4` ; `npp_guard_g F d=0.8` |
| `npp_parking` | `parking_g P d=0.3` ; `zombie_security P d=0.1` |
| `cabin`, `hermit_cabin` (île) | `cabin_g F d=0.7 dorm=0.6` ; île : `hermit_g F d=0.8` ; `home_bed A:f_bed p=0.4 dorm=0.9` |
| `camp_office` | `camp_office_g F d=0.6` |
| `camp_sites` | `camp_g F d=0.8 dorm=0.7` ; `camp_g N d=0.2` |
| `cemetery` | `cemetery_g N d=0.3` ; `cemetery_graves A:t_grave p=0.12 dorm=0.9` (terrain `t_grave`) |
| `chapel` | `church_nave A:f_chair p=0.6 dorm=0.9` ; `church_altar A:f_counter p=0.5` |
| `ranch` (via `farmhouse`, `stable`, `pasture`) | voir lignes correspondantes ; `ranch_g N d=0.2` |
| `warehouse` | `warehouse_g F d=0.7 dorm=0.4` ; `warehouse_g P d=0.15` |
| `factory_hall` | `factory_floor F d=0.9 dorm=0.4` ; `factory_leak F d=0.2 rare=0.2` |
| `factory_office` | `factory_office F d=0.8` |
| `factory_yard` | `factory_floor P d=0.2` |
| `sewage_basin` | `sewage_basin_g W d=0.2` (eau, 6d) ; sinon `sewage_g N d=0.2` |
| `sewage_building` | `sewage_g F d=1.0` ; `experiment_slime F d=0.05 rare=0.2` |
| `sewage_yard` | `sewage_g P d=0.3` |
| `substation` | `substation_g P d=0.3` ; `substation_g F d=1.0` |
| `bunker_entrance` | `bunker_g F d=0.9 dorm=0.1` ; `zombie_sentry` garde (`G`) à la porte ; `bunker_deep` en sous-sol (`min_depth=1`) |
| `desert_outpost` | `outpost_g F d=0.9 dorm=0.2` ; `outpost_g N d=0.1` |
| `lighthouse` | `lighthouse_g F d=0.6` ; `lighthouse_g N d=0.1` |
| `oil_platform` | `oil_g P d=0.35` ; `oil_g F d=0.8` |

### 11.4 Routes et lieux de route (jalon 12)

| Plan | Règles |
|---|---|
| `road_toll_plaza` | `toll_g any d=0.8 dorm=0.3` ; `zombie_toll_clerk A:f_counter p=0.5` |
| `road_roadblock` | `roadblock_g any d=1.4 dorm=0.2` ; `zombie_driver A:f_machinery_heavy p=0.5` |
| `road_checkpoint` | `checkpoint_g any d=1.2 dorm=0.2` ; `zombie_border_guard A:f_desk p=0.6` ; `zombie_stowaway A:f_container p=0.3` |
| `road_bridge_toll` | `bridge_toll_g any d=0.8 dorm=0.3` |
| `road_rest_area` | `rest_g any d=0.5` ; `zombie_tourist A:f_chair p=0.4 dorm=0.8` |
| `road_truck_store` | `truck_g F d=0.7` |
| `road_truck_lot` | `truck_lot_g any d=0.5` ; `zombie_trucker A:f_machinery_heavy p=0.4` |

### 11.5 Côte et air (jalon 11)

| Plan | Règles |
|---|---|
| `port_quay_a/b/c` | `port_dock P d=0.35` ; `port_container A:f_container p=0.2 dorm=0.8` ; `zombie_dockworker A:f_machinery_heavy p=0.4` |
| `port_warehouse` | `warehouse_g F d=0.7 dorm=0.4` |
| `port_office` | `port_office_g F d=0.7` ; `port_office_g A:f_desk p=0.5` |
| `port_yard` | `port_container A:f_container p=0.25` ; `port_dock P d=0.2` |
| `airport_runway`, `airport_runway_taxi` | `airport_runway_g P d=0.12` |
| `airport_apron` | `airport_apron_g any d=0.3` ; `airport_apron_g A:f_machinery_heavy p=0.5` (avions) |
| `airport_hangar` | `airport_hangar_g F d=0.7 dorm=0.4` |
| `airport_terminal` | `airport_terminal_g A:f_bench p=0.5 dorm=0.8` ; `airport_terminal_g F d=0.6` |
| `airport_tower` | `airport_tower_g F d=0.9 dorm=0.3` |

### 11.6 Lieux prévus (jalons 13 à 15)

| Lieu | Groupes |
|---|---|
| `radio_tower` | `radio_g F d=0.8` ; gardes `G` |
| `bunker` (étages) | niveau 0 `bunker_g` ; niveau −1 à −2 `bunker_deep` |
| `missile_silo` | `silo_g F d=1.0 dorm=0.1` ; niveaux inférieurs `bunker_deep` + `zombie_commander` unique |
| `lab` (3 à 4 niveaux) | z=0 `lab_staff` + `lab_guard` ; z=−1 `lab_staff` + `lab_subjects` ; z=−2 `lab_failed` ; z=−3 `lab_deep` ; chaque niveau : `A:f_cage` → `lab_failed`, `A:f_cryo_pod` → `lab_subjects`, `A:f_lab_table` → `lab_staff` ; uniques `zombie_lab_director`, `experiment_nightmare` |
| `aircraft_carrier` | `carrier_g P d=0.5` (pont) ; `carrier_g F d=0.8` (îlot) ; `zombie_pilot_mil A:f_machinery_heavy p=0.5` |
| `lighthouse_island` | `lighthouse_g` + mutants marins |
| `cargo_wreck` | `shipwreck_g` + `zombie_stowaway A:f_container` |
| `marina` | `marina_g P d=0.4` |
| `hydro_dam` | `dam_g F d=0.8` ; `dam_g W` (eau) |
| `island_village` | `island_village_g F d=0.6` ; `island_village_g N d=0.2` |
| `shipwreck_field` | `shipwreck_g W` ; requins (`eco_ocean_deep`) |
| `pirate_base` | `pirate_g F d=0.9` ; `pirate_captain` unique |
| `research_station` | `research_g F d=0.8` ; contamination « expérience » marine |
| `oasis` | `oasis_g N d=0.3` |
| `ski_resort` | `ski_g any d=0.4` |
| `volcano_site` | `volcano_g N d=0.5` ; contamination feu |
| `ancient_ruins` | `ruins_g any d=0.5 dorm=0.8` |
| `cave_entrance` | `cave_g any d=0.6 dorm=0.6` |
| `arctic_base` | `arctic_g any d=0.7` |
| lieux par climat | climat chaud : affixe `mummified` ; froid : affixe `frozen` |

---

## 12. Écologie ambiante (`ecology.json`)

Appliquée aux cases `nature` / `paved` hors bâtiments. Densité en monstres pour 100 cases (avant réglage de population).

| Contexte | Groupe | Densité | Sommeil |
|---|---|---|---|
| Rue, trottoir (ville) | `amb_street` | 0.25 | 0.4 |
| Jardin (ville) | `amb_yard` | 0.15 | 0.3 |
| Route entre villes | `eco_road` | 0.08 | 0.3 |
| Plaine tempérée | `eco_temperate_plain` | 0.04 | — |
| Forêt tempérée | `eco_temperate_forest` | 0.06 | — |
| Marais | `eco_swamp` | 0.06 | — |
| Taïga | `eco_taiga` | 0.05 | — |
| Toundra | `eco_tundra` | 0.03 | — |
| Désert | `eco_desert` | 0.025 | — |
| Savane | `eco_savanna` | 0.05 | — |
| Jungle | `eco_jungle` | 0.08 | — |
| Plage | `eco_beach` | 0.06 | — |
| Berge de lac / rivière | `eco_shore_river` | 0.05 | — |
| Eau peu profonde | `eco_water_shallow` | 0.04 | — |
| Eau profonde (lac) | `eco_lake_deep` | 0.03 | — |
| Océan peu profond | `eco_ocean_shallow` | 0.03 | — |
| Océan profond | `eco_ocean_deep` | 0.015 | — |

| Groupe | Contenu |
|---|---|
| `eco_temperate_plain` | deer:4, fox:2, crow:3, coyote:2, boar:1, zombie_hiker:1, zombie_civilian:1, zombie_dog:1 |
| `eco_temperate_forest` | deer:3, boar:3, wolf:3, bear:2, fox:2, giant_spider:1, zombie_hiker:1 |
| `eco_swamp` | frog_mutant:4, snake:3, alligator:2, leech_swarm:2, zombie_drowned:2, zombie_bloated:1 |
| `eco_taiga` | wolf:4, deer:2, zombie_hiker:1, zombie_frozen:1 |
| `eco_tundra` | wolf_arctic:4, bear_polar:1, zombie_frozen:2, mutant_yeti:0.1 (rare) |
| `eco_desert` | snake_rattle:4, scorpion_giant:4, vulture_mutant:3, zombie_mummified:3, sandworm:0.1 (rare) |
| `eco_savanna` | lion:3, hyena:4, vulture_mutant:2, zombie:2, snake_rattle:1 |
| `eco_jungle` | jaguar:3, python_giant:3, tarantula_giant:3, monkey_mutant:3, mosquito_swarm:2, zombie_overgrown:3, crocodile:1 |
| `eco_beach` | crab_giant:5, seagull_mutant:4, zombie_swimmer:2, zombie_drowned:1 |
| `eco_shore_river` | zombie_drowned:3, snake:2, boar:1 |
| `eco_water_shallow` | piranha_swarm:3, eel_electric:1, zombie_drowned:2 |
| `eco_lake_deep` | eel_electric:2, zombie_drowned:3 |
| `eco_ocean_shallow` | jellyfish:4, shark:1, zombie_swimmer:2, crab_giant:1 |
| `eco_ocean_deep` | shark:3, squid_giant:2, shark_mutant:1, zombie_swimmer:1 |
| `eco_road` | zombie_driver:5, zombie_trucker:2, zombie_biker:2, zombie_cop:1, crow:2, zombie_scavenger:1 |
| `eco_contaminated_radiation` | wolf_mutant:3, deer_mutant:2, boar_mutant:2, bear_mutant:1, rat_irradiated:3, crow_mutant:2, zombie_irradiated:2 |
| `eco_contaminated_toxic` | experiment_slime:2, rat_giant:3, zombie_gasbag:2, zombie_acidic:2, wolf_mutant:1 |
| `eco_contaminated_experiment` | experiment_stalker:1, experiment_crawler:2, experiment_acid_hound:2, experiment_homunculus:2, zombie_lab_subject:2 |
| `eco_contaminated_fire` | fire_hound:3, zombie_charred:3, magma_crawler:1 |
| `eco_contaminated_cursed` | skeleton:4, mummy:2, skeleton_brute:1 |

Règle de base : en dehors des villes, la faune hostile augmente avec la distance à la ville la plus proche (×1 près, ×1.6 au-delà de 40 cellules). Les eaux sont inertes tant que `AQUATIC` n'existe pas (6d).

---

## 13. Uniques et scènes

### 13.1 Uniques (« légendaires »)

Un unique existe **au plus une fois par monde** (par cellule de région) : tirage `mix(seed, LAYER_SPAWN, rx, ry, hash(id))` avec probabilité de lieu ; non réapparition après la mort (drapeau stocké avec `_populated`).

| Unique | Lieu | Particularité | Probabilité du lieu |
|---|---|---|---|
| `zombie_mayor` | mairie | cri de ralliement, clé de la ville (loot) | 0.5 |
| `patient_zero` | hôpital ou labo | infection 90 % ; décline la cause de l'épidémie | 0.15 |
| `zombie_lab_director` | labo | badge d'accès (loot) | 0.8 |
| `experiment_nightmare` | labo profond | pas de lumière, cri rayon 40 | 0.3 |
| `zombie_commander` | silo, bunker profond | SUMMON de soldats | 0.5 |
| `reactor_horror` | cœur de réacteur | amas de zombies irradiés fusionnés (PV 500, REGEN, AURA_RAD) | 0.3 |
| `pirate_captain` | base pirate | BURST, cri rayon 20 | 0.7 |
| `kraken` | pleine mer | rare, 6d | 0.05 par région océanique |
| `ant_queen` | fourmilière | SUMMON | rare |
| `alpha_wolf` | forêt, taïga | loup alpha de grande taille, meute 16 | 0.08 |

### 13.2 Scènes (mises en scène par affinités)

- **Hôpital** : salle d'attente pleine de civils assis (dormants), couloir de brancardiers, bloc opératoire (chirurgien + deux infirmiers), morgue (rangée de tiroirs, embuscade), sous-sol d'expériences.
- **Commissariat** : cellules occupées (détenus), accueil avec policiers, armurerie (rare : intervention).
- **Église** : fidèles assis dans les bancs (`f_bench`), prêtre à l'autel.
- **École** : chaque classe a ses élèves aux bureaux (`f_desk`) ; le hurlement du professeur réveille la classe.
- **Cimetière** : zombies de tombe en embuscade près des `t_grave`, fossoyeur en patrouille.
- **Aéroport** : passagers assis dans le terminal, équipe au sol sur le tarmac, sniper dans la tour.
- **Port** : clandestins dans les conteneurs, dockers aux grues.
- **Barrage routier** : voitures (`f_machinery_heavy`) avec leurs conducteurs, grenadier et lance-flammes derrière la barrière.
- **Centrale** : la contamination monte vers le cœur ; gardes à l'entrée qui ne dorment pas.
- **Bunker / silo** : sentinelles en poste, puis sous-sols de plus en plus hostiles.
- **Labo** : étage par étage, du personnel normal aux ratés ; les cages (`f_cage`) renferment les expériences.

---

## 14. Équilibrage et plafonds

| Réglage | Valeur proposée |
|---|---|
| Plafond de monstres par chunk | 12 (20 pour les grands lieux : centrale, aéroport) |
| Budget de menace par chunk (`Σ threat`) | 30 ordinaire, 60 grands lieux |
| Plafond global de monstres chargés | 300 (au-delà : ambiants non créés) |
| Zone sûre autour du départ | 12 cases |
| Espacement mini entre monstres d'une règle | 2 cases |
| `population` (option de partie) | 0 aucun · 0.5 · 1 · 1.5 · 2 (multiplie les densités) |
| Espérance en ville moyenne | ~1 zombie par maison sur 2, 3 à 6 par commerce, 8 à 14 pour hôpital / école |
| Ambiance sauvage | 1 monstre pour ~2 chunks de forêt, 1 pour ~6 de désert |

`threat` indicatif : zombie ordinaire 1, spéciaux 2-3, élites 4-6, expériences 5-9, uniques 10.

Progression : la rareté du lieu monte avec le danger. Maisons et commerces ≈ menace 1-3 ; hôpital, police, usine ≈ 3-5 ; bunker, centrale ≈ 5-8 ; silo, labo profond, uniques ≈ 8-10.

---

## 15. Persistance, performance, évolutions

- **Sauvegarde (jalon 7)** : `meta.json` garde `generator_version` ; par chunk, seulement ce qui diffère : `populated` (booléen) et la liste de monstres vivants `to_dict()` `{id, cell, hp, state, affixes, has_target, ...}`. Un chunk peuplé non modifié ne stocke rien (il se régénère identique, uniques tués exceptés : stocker leur id).
- **Coût du tour des monstres** : `World._on_time_advanced` boucle sur les monstres chargés : avec la propriété par chunk (≤ 49 chunks chargés), c'est borné. Les dormants coûtent un test de distance toutes les 5 s.
- **Temps gelé hors des chunks chargés** : simple et acceptable au départ. Évolution (6d) : « rattrapage » à la recharge (un chunk absent depuis plus d'une heure de jeu perd 30 % de ses ambiants et en gagne selon l'écologie : la faune migre).
- **Errance entre lieux, hordes sur les routes** (`RouteMap`) : hors périmètre de ce document (`WORLD_GEN.md` §11) ; la structure (états `wander`, `hunt`) est prête.
- **Jour / nuit (hors périmètre)** : plus de dormants le jour, `feral` plus fréquent la nuit.

---

## 16. Plans, mobilier, terrains et sprites à créer

### 16.1 Plans à créer (ASCII 24×24, façade au sud)

| Plan | Taille | Jalon | Remarque |
|---|---|---|---|
| `urban_hospital` | 1 cellule | 6b | salle d'attente, chambres, bloc, morgue, quarantaine ; bâtiment de ville (rayon ≥ 4, zones centre / mi-distance) |
| `urban_clinic` | 1 cellule | 6b | version réduite pour villages |
| `urban_nursing_home` | 1 cellule | 6b | maison de retraite |
| `urban_garage` | 1 cellule | 6b | atelier, fosse (meuble) |
| `lab_*` (étages) | plusieurs | 13 | accueil, couloirs, salles de test, cages, cryo ; sous-sols = étages (`z`) |
| `bunker_*`, `silo_*`, `radio_*` | plusieurs | 13 | |
| `carrier_*`, `dam_*`, `marina_*`, `pirate_*`, `research_*` | plusieurs | 14 | |
| `ski_*`, `volcano_*`, `ruins_*`, `cave_*`, `arctic_*`, `oasis_*` | plusieurs | 15 | |

Les plans existants (houses, urban, places, big_places, access_places, road_*) n'ont **pas besoin d'être modifiés** pour le jalon 6a-6b : la population se branche sur leur id et leur mobilier.

### 16.2 Mobilier à ajouter à `furniture.json` (à la FIN, ne rien renuméroter)

`f_hospital_bed` (lit d'hôpital), `f_gurney` (brancard), `f_surgery_table`, `f_morgue_drawer`, `f_cell_bed` (lit de contention), `f_quarantine_bed`, `f_lab_table`, `f_cryo_pod`, `f_cage`, `f_vat` (cuve d'expérience), `f_server` (baie informatique), `f_garage_pit`. Chaque meuble : `tile` + `color` de repli ; leurs tuiles sont listées dans `MISSING_SPRITE.md`.

La limite de 255 meubles n'est pas en danger (actuellement 24).

### 16.3 Terrains

Aucun nouveau terrain pour 6a-6c. `t_grave` existe déjà (affinité des zombies de tombe).

### 16.4 Marqueur de spawn (optionnel, 6b)

Une entrée de palette peut porter `"spawn": "<groupe>"` (ex. `"Z": {"terrain": "t_floor", "spawn": "hosp_morgue"}`) : `MapgenDB` compile un troisième tableau d'octets (indice de groupe) ; le générateur le lit comme un mode `marker`. À n'utiliser que pour les scènes que les affinités ne couvrent pas.

### 16.5 Sprites

Voir `MISSING_SPRITE.md`, section « Jalon 6 ». Rappel : `tools/build_ultica_pack.py` ne copie que les ids de sa liste `IDS` : y ajouter les ids de monstres (et le script réécrit `tiles.json` : remettre d'abord tous les ids déjà utilisés, voir l'avertissement du fichier).

---

## 17. Plan de réalisation et tests

### 6a — Données et chunks propriétaires

- `monsters.json` : migration des 14 monstres + les bases du §8.1 à 8.3 ; `MonsterDB` ; `MonsterData.create` en façade.
- `ChunkManager` : `_populated`, `_monster_store`, restauration ; `Monster.to_dict/from_dict`.
- `SpawnGenerator` : couche **ambiante** seulement (§12) ; plafond par chunk ; zone sûre.
- Remplacer les monstres de test de `main.gd` (garder `SPAWN_BESTIARY` pour le debug).
- **Tests** : `test_spawn.gd` (toutes les entrées de `spawn_groups.json` pointent sur des monstres existants ; cycles de groupes ; zones valides des tables ; plafonds), déterminisme de la liste de monstres sur 5 seeds dans 3 ordres, un monstre déchargé puis rechargé est identique, un monstre tué ne réapparaît pas, `test_monsters.gd` toujours vert.

### 6b — Couche lieu, sommeil, affinités

- `place_spawns.json` pour **tous les plans existants** (§11.1 à 11.5) ; mode `affinity`.
- États `sleep` / `idle` / `guard` ; bruit et réveil (§6.2) ; capacités `ARMOR`, `DORMANT`, `GUARD`, `AMBUSH`, `ERRATIC`.
- Plans `urban_hospital`, `urban_clinic`, `urban_nursing_home`, `urban_garage` ; mobilier correspondant ; poids de zonage dans `towns.json`.
- Affixes simples : `armored`, `frozen`, `mummified`, `overgrown`, `rotten`, `feral`, `alpha`, `veteran`, `infested`.
- **Tests** : tout plan listé dans `place_spawns.json` existe ; tout meuble d'affinité existe ; chaque lieu produit des monstres cohérents (≥ 95 % des tirages dans le thème) ; aucune apparition dans un mur, sur une porte ou dans la zone sûre.

### 6c — Contamination, mutants, expériences

- `ContaminationMap`, `emits` dans `specials.json`, substitutions, groupes `eco_contaminated_*`.
- Capacités `EXPLODE`, `AURA_RAD`, `COLD_AURA`, `FIRE_AURA`, `REGEN`, `LEAP`, `CHARGE`, `GRAB`, `SPLIT`, `SWARM`, `THROW`, `BURST` ; affixes `irradiated`, `toxic`, `charred`, `electrified`, `bloated`.
- Sources : centrale, usine, station d'épuration, bunker. (Labo, silo : au jalon 13.)
- **Tests** : la contamination est nulle loin des sources et monte vers elles ; déterminisme sur instance neuve ; **mesure** (µs) comme `perf routes`.

### 6d — Capacités avancées et eau

- `SUMMON`, `RAISE`, `STEALTH`, `BLIND_HEARING`, `SWIM`, `AQUATIC`, `FLY`, `SPORE`.
- Pathfinding nautique (PathFinder : cases d'eau pour `AQUATIC` ; `SWIM` ajoute les cases d'eau profonde).
- Faune marine (§12), uniques `kraken`, `pirate_captain`.
- Rattrapage et migration de la faune (§15).

---

## 18. Risques et questions ouvertes

- **Coût de la contamination** : lire les lieux des régions voisines force `SpecialMap.region_data` de ces régions (donc leurs routes). Mitigation : population faite dans la file `process_queue` (jamais d'un bloc), cache de sources par région, mesure avec le banc `benchmark_region`. Si c'est trop cher, ramener le rayon des sources sous 16 cellules et ne lire que la région courante + les 4 voisines directes.
- **Seams de région** : une source proche d'une frontière doit influencer les deux côtés ; le calcul sur régions voisines l'assure, au prix du risque précédent.
- **Équilibrage à l'aveugle** : densités, PV et probabilités à ajuster en jeu avec `SPAWN_BESTIARY` et un mode debug (touche dédiée : afficher sur la mini-carte le nombre de monstres par chunk).
- **Poings à 6 dégâts** : `ARMOR` ≥ 4 rend certains monstres presque invulnérables tant que le joueur n'a pas d'arme. Les `ARMOR` élevés (soldat blindé, brute blindée, tyran) ne devraient apparaître qu'une fois le combat enrichi, sinon limiter leur densité ou les remplacer par des variantes sans armure.
- **Aquatiques** : sans pathfinding nautique, ne rien faire apparaître dans l'eau (déjà prévu).
- **Hostilité des animaux** : `passive` et `territorial` demandent de nouveaux tours dans `Monster.take_turn` (6b).
- **Nom et genre** : champ `gender` obligatoire dans les fiches pour accorder les affixes.
- **Humains hostiles** : jalon séparé (§8.13).
- **Lisibilité** : trop de variantes visuelles identiques perdent le joueur ; le repli par teinte aide, mais les uniques et élites gagneront à avoir de vrais sprites.

---

## 19. À reporter dans les autres documents

### `WORLD_GEN.md`
- §4.7 : « Population (jalon 6) : `SpawnGenerator` à partir du plan et de la contamination, voir `MONSTER_SPAWN.md`. »
- §5 (données) : lignes `spawn_groups.json`, `place_spawns.json`, `ecology.json`, `monsters.json`, `monster_affixes.json`.
- §9 : jalon 6 découpé en 6a à 6d.
- §10 : `test_spawn.gd`.

### `GAME_DESIGN.md`
- « Monstres (`MonsterData`...) » : mention du passage en JSON et de la population par lieu.
- « Architecture » : `data/monster_db.gd`, `worldgen/spawn_generator.gd`, `worldgen/contamination_map.gd`.
- « Limites connues » : ARMOR et poings, aquatiques, humains hostiles.
- Statut : jalon 6 « en conception » puis « fait » par sous-jalon.
