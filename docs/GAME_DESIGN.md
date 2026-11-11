# Projet : clone de Cataclysm: DDA, plus joli (Godot 4.4, GDScript)

Tileset provisoire : UltiCa (CC BY-SA 3.0, voir `assets/ultica/CREDITS.txt`). Docs liées : `WORLD_GEN.md` (monde), `MONSTER_SPAWN.md` (monstres et population), `MISSING_SPRITE.md` (sprites), `EFFETS_VISUELS.md` (rendu).

Les anciens fichiers `JALON_*.md`, `MISSING_SPRITE_JALON*.md` et `PATCH_GAME_DESIGN_*.md` sont fusionnés dans ces documents et peuvent être supprimés.

## Règles de jeu

### Temps et stamina
- 1 point d'action = 1 seconde in-game (60 = 1 min). Horloge : autoload `GameClock`.
- Chaque tranche de 30 % de stamina perdue ajoute +10 % à la durée de TOUTES les actions (max +30 %). Coût réel = base × (1 + pénalité).

### Charge (style CDDA)
ratio = poids porté / capacité (`CAPACITY_BASE` 20 kg + `capacity_bonus` de l'équipement).
- ratio < 1 : se déplacer et attendre REGAGNENT de la stamina (`regen_max × (1 − ratio)` ; `MOVE_REGEN_MAX` 0,6, `WAIT_REGEN_MAX` 0,85).
- ratio = 1 : effet nul. ratio > 1 : perte `2,0 × dépassement + 4,0 × dépassement²` par pas ou par attente.
- Attendre coûte 1 pt, comme un déplacement.

### Déplacement, diagonales, vue
- **Diagonales du joueur au clavier** : normalement « Bas + gauche » = deux pas orthogonaux (2 actions, les monstres peuvent agir entre les deux). Si les deux cases de l'angle sont bloquées (deux arbres, deux murs...), le joueur se faufile directement en diagonale entre les deux obstacles : ce pas compte aussi pour DEUX déplacements (temps, stamina). Le déplacement automatique applique la même règle, mais ne se faufile qu'entre deux cases connues.
- **Monstres** : A* à 8 directions (`PathFinder`). Un pas diagonal est permis si l'une des deux cases de l'angle est praticable, place le monstre tout de suite sur la case en diagonale et lui coûte le temps et la stamina de DEUX pas. À temps égal, A* préfère la diagonale à l'escalier.
- **Mêlée** : le joueur frappe en orthogonal seulement (`World.are_adjacent`) ; un monstre frappe en orthogonal ou en diagonale (règle de l'angle, `Monster._can_melee`).
- **Vue** : shadowcasting, rayon 20 ; murs, arbres et portes bloquent. Brouillard : visible / mémoire (assombri) / jamais vu (noir). Les monstres hors de vue sont cachés et ne repèrent le joueur que s'ils sont dans son champ de vision ; sinon ils vont à la dernière position connue. Un monstre frappé sait où est le joueur.
- **Touche maintenue** = marche automatique intelligente (`AutoPath`) : tout droit tant que c'est libre, sinon chemin court contournant les obstacles connus. Délai 0,25 s puis 1 action / 0,07 s. S'arrête si un ennemi apparaît ou si le joueur est blessé.
- **Double-clic** sur une case VISIBLE et praticable à pied : déplacement automatique (un vrai pas par action). S'arrête si ennemi, blessure, chemin bloqué ou touche pressée.
- **Esquive automatique du décor** (option du menu `|`, activée par défaut) : un appui sur une direction orthogonale bloquée par le décor contourne l'obstacle (détour de 6 pas et 3 cases de côté au plus, terrain réel des cases, jamais dans l'eau si on n'y est pas déjà).
- **Zoom** `+` / `-` : 5 paliers (0,125 à 0,75, cases de 128 px). Le champ de vision ne change pas, le brouillard couvre plus de cases.
- **Alerte « Vous apercevez X »** : une fois par monstre ; revient s'il est resté hors de vue au moins `World.ALERT_REARM_POINTS` (5 s). La marche automatique s'arrête à chaque apparition.
- **Ordre des tours** : le joueur agit TOUJOURS en premier (il change de case, `update_fov()`), puis `GameClock.advance()` fait jouer les monstres dont le moment d'action est arrivé (`World._on_time_advanced`). Un monstre prêt à frapper ne frappe donc pas un joueur qui vient de s'éloigner.

### Posture (touche `|`)
| Posture | Durée du pas | Stamina / pas | Détection par les monstres |
|---|---|---|---|
| Marche | ×1 | charge seule | ×1 |
| Sprint | ×0,7 | −1 | ×1,5 |
| Accroupi | ×1,5 | +0,3 | ×0,5 |

Changer de posture est gratuit. Constantes `POSTURE_*` de `player.gd`. À la nage, durée et stamina de posture sont ignorées (la détection reste modifiée). Le sprint fait du bruit (rayon 8, réveille les dormeurs).

### Nage (jalon 9b)
Toute eau se traverse à la nage. Champ `swim` (`shallow` / `deep`) de `terrain.json` (`TerrainDB.swim_depth`). `walkable` = praticable À PIED : l'eau profonde ne l'est pas. Depuis le jalon 6d, les monstres ont un domaine de déplacement (`World.monster_can_enter`) : les marcheurs restent sur les gués, `SWIM` traverse aussi l'eau profonde, `AQUATIC` ne quitte pas l'eau et `FLY` ignore le terrain sauf murs et fenêtres. `World.can_player_enter` laisse entrer le joueur. Constantes `SWIM_*` et `DROWN_*` dans `player.gd`.
- **Pas** : posture ignorée (×1) ; stamina −1,0 (peu profonde) ou −2,5 (profonde), plus la perte de surcharge. Même à vide, nager épuise.
- **Attendre, eau peu profonde** = « Flotter » (planche) : même récupération qu'à terre, perte si ratio > 1.
- **Attendre, eau profonde** = « Surplace » : −1,0 + surcharge, jamais de récupération. Les gestes d'inventaire coûtent aussi ce surplace.
- **Noyade** : stamina à 0 à la fin d'une action dans l'eau (déplacement, attente, étape d'inventaire, attaque) → −2,0 PV × durée (secondes) au torse. Arrête la marche automatique. Fin : terre ferme, ou flotter jusqu'à regagner de la stamina.
- **Marche automatique** : une touche maintenue ne s'engage jamais en eau profonde depuis la rive ; dans l'eau, elle nage tout droit tant que stamina ≥ 20 (`SWIM_REPEAT_MIN_STAMINA`). Le double-clic ne vise pas l'eau profonde.
- Journal : entrée dans l'eau, changement de profondeur, « Vous reprenez pied » ; sprite teinté de bleu.

### Santé, monstres, effets
- **Corps** (`data/body_parts.json`) : tête 40, torse 60, bras 40 ×2, jambes 50 ×2 PV. Mort si tête ou torse à 0. Les membres à 0 PV n'ont pas encore d'effet (à venir : bras = dégâts, jambes = vitesse).
- **Monstres** (jalon 6, détails dans `MONSTER_SPAWN.md`) : bestiaire en JSON (`MonsterDB`, **183 types** : `monsters.json`, `monsters_places.json`, `monsters_mutants.json`, `monsters_aquatic.json`) ; `MonsterData` reste en façade. Chacun a un « prochain moment d'action », agit puis attend le coût de son action. Tables de zones touchées (poids = %). Infobulle au survol (et mode regard) : coûts, dégâts, probabilités par partie, capacités, modificateurs. Compétences : attaque spéciale, effets d'état, tir à distance, hurlement, meute.
- **Population** : chaque chunk reçoit ses monstres à son premier chargement (`SpawnGenerator`, fonction pure de la seed) : couche **lieu** (`place_spawns.json`, 92 plans : le dormeur dans son lit, le fidèle sur son banc) puis couche **ambiante** (`ecology.json` : rues, routes, jardins, faune par biome et par type d'eau). Un chunk déchargé met ses monstres en réserve (`ChunkManager._monster_store`) et les rend tels quels ; un monstre tué ne réapparaît pas. Depuis 6d, un chunk resté absent plus d'une heure de jeu voit sa faune ambiante migrer (30 % de partants, remplacés par un tirage frais ; uniques et monstres de lieux restent). Plafonds : 12 monstres et menace 30 par chunk (20 et 60 pour un lieu), 300 monstres chargés, aucun monstre à moins de 12 cases du départ. Réglage `POPULATION` de `main.gd`.
- **Comportements** (`behavior`) : `hostile`, `passive` (cerf, renard : fuit, se défend acculé), `territorial` (sanglier, ours : ne repère le joueur qu'à 5 cases, abandonne à 10).
- **États** (`Monster.state`) : `idle`, `sleep` (immobile, « Zzz » ; réveil quand le joueur approche à `wake_range` × posture et visible, 15 % par tour de 5 s ; au bruit : sprint 8 cases, combat 10, hurlement ; coup reçu ; voisin qui se réveille), `guard` (ne dort jamais, tient son poste, abandonne la poursuite à 8 cases).
- **Orientation des monstres** (`Monster.facing`, 4 directions ; flèche rouge au sol, plus grande et plus vive quand le joueur est dans sa zone d'attaque) : un monstre ne frappe en mêlée que la case en face de lui et ses deux diagonales avant (`Monster.in_front_arc`). Si le joueur est à portée mais sur son flanc ou dans son dos, il **pivote** : `TURN_STEPS_PER_ACTION` (1) quart de tour par action, pour `move_cost × TURN_COST_FACTOR` (1,0) secondes et la même variation de stamina qu'un pas. Se déplacer l'oriente (gratuit) ; un tir l'oriente vers la cible (gratuit) ; orientation de départ au hasard.
- **Capacités** (`abilities`) : agissent `ARMOR(n)` (chaque coup reçu perd n PV, 1 minimum ; les poings font 6), `DORMANT`, `GUARD`, `AMBUSH` (ne se réveille qu'à 2 cases), `ERRATIC` (30 % de pas au hasard), `EXPLODE(type)` à la mort, `AURA_RAD` / `FIRE_AURA` / `COLD_AURA`, `REGEN(x)`, `LEAP`, `CHARGE`, `GRAB` / `CONSTRICT` (drain de stamina seulement), `SPLIT`, `SWARM`, `THROW(type)`, `BURST`. Jalon 6d : `SUMMON` (renforts), `RAISE` (relève un cadavre), `STEALTH` (visible à 3 cases), `BLIND_HEARING` (entend la marche, le sprint et les coups), `SWIM` / `AQUATIC` / `FLY` (domaines de déplacement), `SPORE` (empoisonne au coup). Seule `LOOT_CARRIER` reste lue et ignorée (loot, jalon à part).
- **Affixes** (`monster_affixes.json`, 14 : gelé, calciné, irradié, toxique, électrifié, blindé, momifié, envahi, putréfié, gonflé, enragé, alpha, vétéran, grouillant) : 0 à 2 par monstre, nom accordé au genre (« Réceptionniste zombie gelée »), PV, vitesse, dégâts, armure, capacités.
- **Contamination** (jalon 6c, `ContaminationMap`) : les sources (centrale, laboratoire, silo, bunker, usine, station d'épuration, plateforme pétrolière, volcan, station de recherche, ruines) contaminent les chunks alentour ; les monstres tirés sont remplacés par leur variante mutante (loup → loup mutant...) et, au-dessus de 0,6, la faune ambiante devient mutante.
- **Explosions** (`World.explode`, types `acid`, `gas`, `fire`, `frag`, `electric`) : blessent le joueur et les monstres du rayon ; un monstre tué par une explosion peut exploser à son tour.
- **Effets d'état** (`StatusEffects`) : saignement, poison, acide, irradiation, brûlure, engelure (dégâts/s sur une partie du corps pendant une durée), drain de stamina. Branchés sur `EventBus.time_advanced`.
- **Infection** (`Infection`) : morsure infectieuse → progression 0→1 sur 1 h de jeu (`DURATION`) ; stades fièvre / délire / terminale (drain de stamina, puis PV du torse). À 1 : mort et un zombie se relève. Antibiotiques : guérison complète jusqu'à 75 % (`CURE_LIMIT`), sinon recul de 15 %.
- **Utiliser** (touche `u` dans le monde, `UseUI`) : liste les objets à champ `use` de `items.json` (antibiotiques), 1 unité consommée si effet.
- **Stats** (`data/stats.json`) : Force, Dextérité, Intelligence, Perception (base 8), affichées dans l'écran personnage, sans effet pour l'instant.
- **Jauge de suspense** (PLUS TARD) : 0-100 % comme si quelqu'un pariait sur notre survie (PV, stamina, menaces, charge...).

### Inventaire (style Project Zomboid)
- Objet = nom, poids (kg), taille [longueur, largeur] (cm), id de tuile UltiCa.
- **Conteneurs** : poids propre, taille max d'objet (rotation permise), limite de poids RÉEL du contenu, `weight_ratio` (contenu pèse réel / ratio, équipé ou simplement porté). Un conteneur n'entre dans un autre que vide ; un conteneur rangé ne reçoit rien. Un sac ramassé reste sur soi (jamais rangé auto).
- « Sur soi » = hors conteneur, poids plein. Portée : case du joueur + 8 autour.
- Équipement : 1 objet par emplacement (tête, haut, veste, jambes, pieds, dos), affiché sur le sprite. Ramasser range dans le meilleur conteneur équipé, sinon sur soi ; on peut se surcharger.
- **Coûts de base** (× pénalité) : ramasser = 1 + 0,8 × poids réel ; équiper/retirer = 3 + 0,4 × poids ; ranger/sortir/poser depuis un conteneur = 1 + 0,4 × poids ; **poser au sol un objet « sur soi » = gratuit**.
- **Temps net** (`InventoryLedger`) : les modifications sont immédiates, mais à la fermeture on compare l'état de départ et final : objet remis en place = 0 ; objet déplacé plusieurs fois = déplacement net seulement (depuis le sol = ramassage). Popup « Coût en temps » : Validé (Entrée), Annulé (Échap, rouvre), Tout annuler (`U`). Aucun déplacement net = pas de popup.
- **Ramassage préparé** : rien ne change dans le monde avant validation ; objets choisis grisés « déplacé vers l'inventaire », `u`/`U` annulent. Ramasser + équiper = ramassage + équipement.
- **Poser** : l'objet quitte l'inventaire tout de suite mais n'apparaît au sol qu'à la validation (liste « À POSER AU SOL »). Objets au sol rangés par étage.
- **Chaque unité est sa propre action** (4 conserves = 4 étapes, chacune avec coût de base + poids de CETTE unité).
- **Validation animée** : étapes jouées une à une (`STEP_DELAY` 0,6 s dans `inventory_ui.gd`), bannière en haut ; le temps de chaque étape passe à ce moment (`Player.spend_inventory_time`), les monstres avancent. Une touche saute l'animation ; la mort arrête la séquence. Cases nommées par leur chiffre du pavé (case 4 = gauche).

## Monde procédural (détails : `WORLD_GEN.md`)
- Monde infini, chunks de 24 × 24, **déterministe** (seed + coordonnées). **Sauvegarde = seed + deltas** (jalon 7, fait : `docs/WORLD_GEN.md` §7). Pas de `randi()` global dans la génération.
- Contenu en données (`data/worldgen/*.json`). Clés de chunk `Vector3i` avec `z`.
- **Statut** : jalons 1-5, 6a-6d, 7, 9, 9b, 10-15 faits (chunks, biomes, villes, routes, maisons, lieux spéciaux et grands lieux, planète, nage, climats/îles/accès, zonage urbain, lieux de route, militaire, mer, rural, sauvegarde/chargement ; monstres, population par lieu, contamination, capacités avancées, faune aquatique et uniques). **8 en cours** : escaliers utilisables et sous-sols d'hôpital, clinique, bunker, silo, labo, centrale, PC, dépôt et grotte faits ; restent portes/fenêtres, toits, carte du joueur et sprites. Le loot (`drops`, `LOOT_CARRIER`) reste à faire.
- **Axe vertical** (jalon 6b, escaliers au jalon 8) : UN seul étage simulé à la fois (`ChunkManager.level`, `World.get_level()`, `World.change_level`) ; terrains `t_rock` / `t_air` / escaliers (`terrain_vertical.json`) ; plans d'étage nommés `<plan>@<z>` ; escaliers utilisables par `<` / `>` (`World.use_stairs`).
- **Climat** : `WorldMap.climate_at` = TEMPERATE / HOT / COLD (bandes de latitude), valable partout, mer comprise.
- **Îles** : `island_size(cellule)` (0 = océan, `max_cells` ou plus = continent). Pas de ville sur une petite île. Départ île : `SettlementMap.island_spawn_cell()`.
- **Accès des lieux** (`specials.json`, `access`) : `road`, `track` (piste de terre ≤ 12 cellules, la route gagne un embranchement), `helipad`, `pier`, `on_road` (lieu posé SUR une route : péage, barrage), `none` (atteint à la nage). Plusieurs modes : un tiré par tentative.
- Réglages de debug en haut de `main.gd` : `USE_TEST_ARENA`, `SPAWN_BESTIARY`, `POPULATION`, `SHOW_MISSING_SPRITES`. En jeu normal, la seed et le scénario (`default` ou `island`, repli sur default si pas d'île) viennent du menu de création (`SaveMenuUI`).
- **Sauvegardes** (`user://saves/`) : menu principal au lancement ; liste triée par date, emplacements `partie-1`, `partie-2`... ; chargement, suppression, écrasement avec confirmation ; seed vide = aléatoire (affichée et copiable). `F5` rouvre l'écran en jeu, `F2` copie la seed. Une sauvegarde incompatible (`version` ou `generator_version`) est refusée.

## Contrôles
**Convention** : touche seule en MINUSCULE (`u`), avec Maj en MAJUSCULE (`U`). Touches spéciales : Entrée, Échap.
- **Déplacement** : pavé 8/2/4/6 (diagonales 7/9/1/3) ou flèches (= 8/2/4/6 orthogonal, aussi dans les menus). Espace, `.`, `5` = attendre (dans l'eau : flotter / surplace). On entre en eau profonde par un appui, jamais en touche maintenue depuis la rive.
- **Escaliers** (jalon 8) : `<` monter, `>` descendre, sur la case de l'escalier. Le changement d'étage coûte une action ; les monstres de l'étage quitté passent en réserve.
- `m` carte de DEBUG (`+`/`-` zoom, 8/2/4/6 et 7/9/1/3 déplacer, `5` recentrer). `m`, `w`, `x`, `c`, `u`(menu), `+`, `-` détectés par le CARACTÈRE tapé (`KeyUtil.is_letter`, AZERTY/QWERTY).
- `x` ou Maj + pavé/flèches : **mode regard** (`LookUI`) : la caméra bouge, pas le joueur, aucun temps ne passe. Panneau : biome, lieu, terrain, mobilier, objets, monstre (visible) ; mémoire pour les cases vues ; rien pour l'inconnu. `5` recentrer, `*` y aller, `+`/`-` zoom, `x`/Échap quitter.
- `c` écran personnage (onglets Stats / Corps, 4/6 ou flèches). `|` menu de posture et de déplacement (posture suivante présélectionnée ; `|` ou 8/2 change, Entrée valide, Échap ferme ; ligne « Esquive automatique du décor »). `u` menu « utiliser ».
- `i` inventaire, `g` ramasser (une seule case avec objets : liste ; sinon overlay 1-9 du pavé), `G` les 9 cases en une liste. **Ramassage et inventaire sont deux écrans séparés.**
- **Inventaire** : `e` équiper/retirer, `r` ranger, `t` sortir, `g` poser, `u` annuler l'objet, `U` tout annuler.
- **Ramassage** : Entrée/`g` ramasser (rangement auto), `w` en main, `W` équiper directement, `u`/`U` annuler.
- **Popup de validation** : Entrée = Validé, Échap = Annulé, `U` = tout annuler ; `u` seul ne fait rien.
- **Sélection multiple** : `4` ou `+` ajoute l'objet (+1 s'il y est déjà, jusqu'à la pile), `-` retire 1. Curseur sur un conteneur : `6` = 1 unité de chaque, Entrée = toute la sélection (ce qui ne rentre pas reste sélectionné). `6` sur un objet sélectionné le retire. Avec sélection : `e`, `t`, `r`, `g` s'appliquent au lot ; depuis le sol Entrée/`w`/`W`.
- **Souris** : lecture seule dans les menus (infobulle du diviseur de poids) ; double-clic gauche dans le monde = s'y rendre.
- **Écran des sauvegardes** (menu principal au lancement, `F5` en jeu) : 8/2 ou flèches choisir, Entrée valider, Échap reprendre (quitter au menu principal) ; `L` charger, `Suppr` supprimer, `C` copier la seed ; saisie de seed au clavier (`Ctrl+V` colle, vide = aléatoire), 4/6 ou Entrée change le scénario. En jeu, sauvegarder sur une sauvegarde existante demande confirmation ; créer une nouvelle partie aussi (progression non sauvegardée perdue).

## Architecture (`scripts/`)
- `main.gd` : au lancement, lit la demande de `GameSession` puis affiche soit le menu des sauvegardes (`SaveMenuUI`), soit une partie neuve/chargée ; assemble monde, joueur, UI, monstres de debug et objets de test (seulement pour une partie neuve) ; `F5` menu, `F2` copie de la seed. Autoloads `EventBus`, `GameClock` (dans cet ordre, Projet > Paramètres > Globaux) ; `GameSession` (classe à variables statiques) transporte la demande à travers `reload_current_scene()`.
- `save/save_game.gd` : format `user://saves/<slot>/` (`meta.json` + `chunks/<cx>_<cy>_<z>.json`), liste/suppression/compatibilité, sérialisation du joueur (`player_to_dict`, `apply_player`), `load_world` (AVANT le joueur) et restauration des deltas. `game_session.gd` : demande `MENU` / `NEW_GAME` / `LOAD` conservée à travers `reload_current_scene()`.
- `world/` : `world.gd` (monde infini, délègue la carte au `ChunkManager`, objets au sol par étage, monstres, file d'actions, FOV, bruit `make_noise`, explosions `explode`, division `spawn_split`, `restore_monster` ; calques : chunks, objets, `entities` triées par Y, `fx`, `fog`, overlay de choix de case, case ciblée ; `world_seed`/`seed_text`/`scenario`/`use_arena`/`population` fixés AVANT `add_child`), `fov.gd`, `fog_layer.gd`, `auto_path.gd`.
- `worldgen/` : `world_rng`, `terrain_db`, `furniture_db`, `mapgen_db`, `world_map`, `settlement_map` (villes, rues, zonage urbain, pistes), `route_map`, `special_map` (lieux, accès, lieux sur la route), `contamination_map`, `spawn_generator`, `chunk_generator`, `chunk`, `chunk_manager` (charge rayon 3, génération immédiate rayon 2, déchargement > 4, cases vues et monstres gardés par clé 3D, étage actif `level`), `path_finder` (A* borné 1500 cases / rayon 40, 8 directions). Voir `WORLD_GEN.md`.
- `entities/` : `player.gd` (déplacement, esquive du décor, combat de base 6 dégâts / 2 pts, stamina, charge, nage, noyade, répétition de touche, actions d'inventaire, `START_EQUIPMENT` / `START_LOOSE`), `monster.gd` (états, orientation, capacités), `status_effects.gd`, `infection.gd`.
- `data/` : `item.gd`, `item_db.gd` + `items.json`, `inventory.gd`, `inventory_ledger.gd`, `monster_data.gd`, `monster_db.gd` + `monsters*.json` + `monster_affixes.json`, `body_part_db.gd` + `body_parts.json`, `stat_db.gd` + `stats.json`.
- `ui/` : `hud.gd`, `inventory_ui.gd`, `character_ui.gd`, `posture_ui.gd`, `use_ui.gd`, `look_ui.gd`, `minimap_ui.gd`, `save_menu_ui.gd` (menu principal / sauvegardes), `key_util.gd`.
- `render/` : `ultica_tiles.gd` (id de tuile → sprite, variantes pondérées, décalages), `fx.gd` (effets visuels).
- `tools/build_ultica_pack.py` : régénère `assets/` (copie les PNG des ids de `IDS` depuis I-am-Erk/CDDA-tilesets, écrit `tiles.json`). **Attention** : voir `MISSING_SPRITE.md`.
- `tests/` (à lancer sur demande, `godot --headless --path <projet> --script res://tests/<nom>.gd`) : `test_worldgen_determinism`, `test_swimming`, `test_body`, `test_monsters`, `test_pathfinder`, `test_spawn`, `test_vertical`, `test_contamination`, `test_jalon10` à `test_jalon15` (sauf 6). `test_save` et `test_jalon6d` utilisent les autoloads et se lancent via leur scène : `godot --headless --path <projet> res://tests/test_save.tscn` et `... res://tests/test_jalon6d.tscn`.

## Conventions
- Tout est construit par code (seule scène : racine avec `main.gd`). Constantes d'équilibrage en haut des scripts.
- Nœuds positionnés sur le coin haut-gauche de leur case ; décalages de sprites via `UlticaTiles`.
- Pixel art : filtre de texture géré sur `World` (voir `world.gd`).
- Tuile ou meuble sans sprite : carré de la `color` du JSON (repli) ; monstre sans sprite : `mon_zombie` (ou `mon_wolf`) teinté.

## Limites connues / à faire
- **Murs** : arêtes, coins, T et extrémités (`ChunkManager.wall_sprite`) ; croisement en + : repli `t_wall_unconnected` ; orientation des T et extrémités à vérifier à l'œil. Porte praticable et opaque, sans état ouvert/fermé (jalon 8) ; fenêtre bloquante mais transparente.
- **Monde** : voir `WORLD_GEN.md` §11 (réglages « à l'aveugle » des lieux et des îles, pistes absentes de la mini-carte, `t_helipad` sans sprite, mini-carte et mode regard lisent la surface).
- **Nage** : pas de vêtements mouillés ni de noyade par le poids, monstres non nageurs, pas de nage automatique depuis la rive, pas d'indicateur HUD. Valeurs `SWIM_*` / `DROWN_DAMAGE_PER_SECOND` à régler en jeu.
- **Vêtements** : calques `overlay_male_worn_*` dans l'ordre `ItemDB.WORN_DRAW_ORDER` (pas de `layering.json`, superpositions approximatives), version « male » seulement. Icônes de vêtements = calque porté ; sac en rideau / militaire = icônes provisoires.
- **Inventaire** : clavier seulement ; poser uniquement sur la case du joueur ; pas de transfert partiel d'une pile depuis le sol.
- **Combat et monstres** : `Player._attack` affiche toujours « −6 PV » même si l'armure réduit le coup ; `ARMOR` élevé presque invulnérable aux poings ; `GRAB` / `CONSTRICT` ne drainent que la stamina ; `THROW` ignore la ligne de vue ; tir à distance, hurlement et meute ignorent la zone d'attaque ; frapper un monstre ne le fait pas pivoter ; un monstre qui ne voit pas le joueur ne pivote pas ; contourner un monstre en sprint non garanti (régler `TURN_COST_FACTOR`) ; temps gelé hors des chunks chargés (rattrapage de la faune au retour, jalon 6d) ; un monstre en réserve perd sa cible ; `FLY` ne vaut que pour le déplacement ; les aquatiques n'attaquent que depuis l'eau ; cadavres et délais de `SUMMON` / `RAISE` non sauvegardés ; humains hostiles : jalon à part. Détails : `MONSTER_SPAWN.md`.
- Canopées d'arbres (96×96) cachent parfois ce qui est derrière ; survol des monstres par case.
- **Sauvegarde** : écrasement non atomique (coupure possible en cours d'écriture) ; pas d'auto-save ni d'export/import de fichier ; sauvegarde d'un autre `generator_version` refusée sans migration ; seuls les chunks marqués modifiés sont écrits (toute modification hors des API de `ChunkManager` doit être marquée) ; la partie en cours n'est pas sauvegardée automatiquement avant un chargement ou une nouvelle partie (confirmation seulement).
- **Feuille de route** : inventaire (fait) → génération du monde (jalons 1-5, 9-15 faits) → monstres (6a-6d faits, loot à faire) → sauvegarde (7, fait) → **8** (étages, toits, portes) → combat plus riche → import complet d'UltiCa (TileMapLayer) → jauge de suspense.
