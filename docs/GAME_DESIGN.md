# Projet : clone de Cataclysm: Dark Days Ahead, plus joli (Godot 4.4, GDScript)

Tileset provisoire : UltiCa (CC BY-SA 3.0, `assets/ultica/CREDITS.txt`). Autres docs : `WORLD_GEN.md` (monde procédural), `MISSING_SPRITE.md` (sprites).

## Règles de jeu décidées (à respecter)

### Temps, stamina, charge
- **Temps** : 1 point d'action = 1 s in-game ; 60 points = 1 min. Autoload `GameClock`.
- **Stamina** : tous les 30 % perdus, TOUTES les actions durent +10 % (max +30 %). Coût réel = coût de base × (1 + pénalité).
- **Charge (style CDDA)** : ratio = poids porté / capacité (`CAPACITY_BASE` 20 kg + `capacity_bonus` d'équipement).
  - ratio < 1 : marcher ET attendre regagnent de la stamina, de moins en moins (`regen_max × (1 − ratio)`) ; ratio = 1 : nul ;
    ratio > 1 : perte `2,0 × dépassement + 4,0 × dépassement²`.
  - Attendre dure 1 pt comme un pas, avec plus de gain (`WAIT_REGEN_MAX` 0,85 vs `MOVE_REGEN_MAX` 0,6).

### Nage (jalon 9b)
- Toute eau se traverse à la nage ; `swim` (`shallow` / `deep`) dans `terrain.json` (`TerrainDB.swim_depth`). `walkable` = praticable À PIED : l'eau profonde ne l'est pas,
  donc les monstres ne nagent pas ; `World.can_player_enter` laisse entrer le joueur. Constantes `SWIM_*`, `DROWN_*` en haut de `player.gd`.
- **Pas** : posture ignorée (durée ×1) ; stamina −1,0 (eau peu profonde) ou −2,5 (profonde) par pas, + perte de surcharge. Même à vide, nager épuise.
- **Attendre** : eau peu profonde = « Flotter » (planche : récupération comme à terre ; perte si ratio > 1) ; eau profonde = « Surplace » (−1,0 + surcharge, jamais de récupération).
  Les gestes d'inventaire en eau profonde coûtent aussi ce surplace.
- **Noyade** : stamina à 0 à la fin d'une action dans l'eau → −2,0 PV (torse) × durée en s ; message « Vous vous noyez », arrêt de la touche maintenue / marche auto.
  Fin : terre ferme, ou flotter en eau peu profonde jusqu'à regagner de la stamina.
- **Marche auto** : une touche maintenue ne s'engage jamais dans l'eau profonde depuis la rive ; une fois dedans, elle nage tout droit tant que stamina ≥ 20
  (`SWIM_REPEAT_MIN_STAMINA`). Le double-clic ne vise pas l'eau profonde. Journal : entrée dans l'eau, changement de profondeur, « Vous reprenez pied » ; sprite teinté de bleu.

### Déplacements, monstres, vue
- **Diagonales** : « bas + gauche » = deux pas orthogonaux (2 actions, les monstres peuvent agir entre). Joueur ET monstres (A* 4 directions). Mêlée en orthogonal (`World.are_adjacent`).
- **Monstres** : l'infobulle montre coût de déplacement et d'attaques (spéciale comprise). Chacun a un « prochain moment d'action » et attend le coût de son action.
- **Vue** : shadowcasting rayon 20 ; murs et arbres bloquent. Brouillard : visible / mémoire (assombri) / jamais vu (noir). Monstres hors de vue cachés ; ils ne repèrent le joueur que
  s'ils sont dans son champ de vision (vue symétrique), sinon vont à la dernière position connue. Un monstre frappé sait où tu es.
- **Touche maintenue** (marche auto intelligente, `AutoPath` : tout droit tant que c'est libre, sinon chemin court contournant les obstacles connus) = répétition (0,25 s puis 1 action / 0,07 s).
  S'arrête si un ennemi apparaît ou si le joueur est blessé (relâcher et réappuyer).
- **Double-clic** sur une case VISIBLE et praticable à pied : déplacement auto (un vrai pas par action). S'arrête si ennemi, blessure, chemin bloqué ou touche.
- **Alerte « Vous apercevez X »** : une fois par monstre ; revient s'il est resté dans le brouillard ≥ `World.ALERT_REARM_POINTS` (5 s). La marche auto s'arrête à chaque apparition.
- **Posture** (`|`) : Marche (réf.) ; Sprint (durée ×0,7, stamina −1/pas, détection ×1,5) ; Accroupi (durée ×1,5, stamina +0,3/pas, détection ×0,5). Gratuit. Constantes `POSTURE_*`. À la nage : durée et stamina ignorées, détection modifiée.
- **Zoom** `+` / `−` : 5 paliers (0,125 à 0,75, cases de 128 px). Le champ de vision ne change pas ; le brouillard couvre plus de cases.
- **Jauge de suspense** (PLUS TARD) : 0-100 %, comme si quelqu'un pariait sur notre survie (100 % = on ne sait pas quand tu mourras). Calculée (PV, stamina, menaces, charge...).

### Inventaire (style Project Zomboid)
- Objet = nom, poids (kg), taille [longueur, largeur] (cm), id de tuile UltiCa.
- **Conteneurs** : poids propre, taille max d'objet (rotation permise), limite de poids RÉEL, `weight_ratio` (contenu = réel / ratio, équipé ou non ; sac militaire ÷3, sac en rideau ÷1,2).
  « Sur soi » = hors conteneur, poids plein. Conteneur dans conteneur : seulement VIDE ; un conteneur rangé ne peut rien recevoir. Un sac ramassé reste sur soi. (Plus tard : holster sur ceinture.)
- **Portée** : case du joueur + 8 autour, sans coût. **Équipement** : 1 objet par emplacement (tête, haut, veste, jambes, pieds, dos), affiché sur le sprite.
- Ramasser → meilleur conteneur équipé (réduction la plus forte), sinon sur soi ; surcharge possible.
- **Coûts de base** (× pénalité) : ramasser 1 + 0,8 × poids réel ; équiper/retirer 3 + 0,4 × poids ; ranger / sortir / poser DEPUIS un conteneur 1 + 0,4 × poids ; **poser au sol un objet « sur soi » = gratuit**.
- **Temps net** (`InventoryLedger`) : modifications immédiates, mais à la fermeture on compare départ et fin : objet remis en place = 0 ; objet déplacé plusieurs fois = déplacement net (depuis le sol = ramassage).
  Popup « Coût en temps : x s » : « Validé » (le temps passe) ou « Annulé » (rouvre, rien n'est défait). Aucun déplacement net = pas de popup. Temps cumulé affiché en direct.
- **Ramassage préparé** : rien n'est modifié avant validation ; objets choisis listés et grisés (« déplacé vers l'inventaire (auto / en main / équipé) » ou « n/m »), `U` annule. Ramasser + équiper = ramassage + équipement.
- **Poser au sol** : l'objet quitte l'inventaire tout de suite mais n'apparaît au sol qu'à la validation (liste « À POSER AU SOL », `u` pour reprendre).
- **Chaque objet est sa propre action** (4 conserves = 4 étapes, coût base + poids de CETTE unité). Idem ranger, sortir, équiper, poser.
- **Validation animée** : étapes jouées une à une (`STEP_DELAY` 0,6 s dans `inventory_ui.gd`, futur réglage), bannière en haut (« Dépôt de X au sol (case 5) (2/4) » + icône de chargement).
  **Le temps de chaque étape passe à ce moment** (`Player.spend_inventory_time`) : les monstres avancent. Une touche saute l'animation (le temps passe quand même) ; mort = arrêt. Cases nommées par le pavé numérique (« case 4 » = gauche).
- **Annuler** : `u` = objet sous le curseur (sol : ramassage préparé ; inventaire : retour au départ), `U` = tout. Popup : « Validé [Entrée] », « Annulé [Échap] » (continuer), « Tout annuler [U] » (rien ne change, aucune seconde perdue).

### Personnage
- **Stats** : `data/stats.json` (Force, Dextérité, Intelligence, Perception, base 8), écran `c` ; sans effet pour l'instant. Ajout = une entrée JSON.
- **Santé par parties du corps (style CDDA)** : `data/body_parts.json` (`BodyPartDB`) : Tête 40, Torse 60, Bras g./d. 40, Jambes g./d. 50 (total 280, valeurs « à l'aveugle »).
  **Mort quand tête ou torse tombe à 0** (`vital`). Membre à 0 = « hors d'usage », SANS effet pour l'instant (à venir : bras = dégâts, jambes = vitesse). Pas sous 0, excédent perdu.
  `Player.body`, `part_hp()`, `total_hp()`, `take_damage(montant, partie)`. HUD : PV totaux (`health_changed`). La noyade blesse le torse.
- **Attaques localisées** : `MonsterData.attack_zones` / `special_zones` = poids par partie (lus en %). Zombie, Griffure : Tête 10, Torse 36, Bras 20/20, Jambes 7/7 ; Morsure : Tête 20, Torse 26, Bras 22/22, Jambes 5/5.
  Le journal donne la partie touchée ; probabilités visibles au survol ou en regard (`Monster.get_tooltip_lines()`).
- **Mode regard** (`LookUI`, `x` ou `Maj` + pavé / flèches) : la CAMÉRA bouge, pas le joueur ; aucun temps ne passe ; rien n'est révélé (`FogLayer.look_offset` étend seulement la zone dessinée).
  Curseur = calque de choix de case (`show_pick_overlay`), distance max 40. Panneau à droite : case VISIBLE = biome, ville / lieu, terrain, mobilier, praticabilité, objets au sol, monstre (PV, coûts, probabilités) ;
  case VUE = terrain et mobilier ; JAMAIS VUE = rien. Touches : pavé / flèches (avec ou sans Maj) déplacent le curseur, `5` recentre, `*` quitte et lance le déplacement auto vers la case
  (comme le double-clic : `Player.travel_to`, case visible et praticable à pied), `+` / `−` zoom, `x` / Échap quittent.

## Monde procédural (plan : `WORLD_GEN.md`)
- Infini, par chunks de 24 × 24, **déterministe** (une seed = un monde). Sauvegarde = seed + deltas par chunk. Pas de `randi()` global. Contenu en données (`data/worldgen/*.json`).
  Étages prévus plus tard (clés de chunk avec `z`).
- Statut : jalons 1, 2, 3 (a/b/c), 4, 5, 9, 9b faits ; 6 à 8 ensuite, puis 10 à 15.
- Réglages de partie en haut de `main.gd` : `WORLD_SEED_TEXT`, `USE_TEST_ARENA` (true = arène fermée 60 × 40).

## Contrôles
**Convention** : jamais « Maj+u » ; touche seule en MINUSCULE (`u`), avec Maj en MAJUSCULE (`U`). Touches spéciales : Entrée, Échap.
- **Déplacement** : pavé (8/2/4/6, diagonales 7/9/1/3) ou flèches (= 8/2/4/6) ; espace / `.` / `5` = attendre (dans l'eau : flotter / surplace). On entre en eau profonde par un appui, jamais en touche maintenue depuis la rive.
  Les flèches valent 8/2/4/6 dans les menus.
- `m` = carte de DEBUG (montre l'inexploré) : `+`/`−` zoom, 8/2/4/6 ou flèches + 7/9/1/3 déplacent la vue, `5` recentre, `m`/Échap ferme. `m` et `w` détectés par le CARACTÈRE tapé (`KeyUtil.is_letter`, AZERTY/QWERTY).
- `i` = inventaire. `g` = ramasser : une seule case à portée avec objets → sa liste ; sinon overlay 1-9 (disposition du pavé). `G` = les 9 cases en une liste. Ramassage et inventaire = deux écrans séparés.
- **Inventaire** : `e` équiper/retirer, `r` ranger, `t` sortir, `g` poser, `u` annuler l'objet, `U` tout annuler.
- **Ramassage** : Entrée/`g` ramasser (auto), `w` en main, `W` équiper directement, `u` / `U`. (`w`/`W` détectés par caractère.)
- **Popup de validation** : Entrée = Validé, Échap = Annulé, `U` = tout annuler ; `u` seul ne fait rien.
- **Sélection multiple** : `4` (ou `+`) ajoute l'objet sous le curseur (+1 s'il y est déjà, jusqu'à la pile), `−` retire 1. Curseur sur un conteneur : `6` = 1 unité de chaque objet, Entrée = toute la sélection ;
  ce qui ne rentre pas reste sélectionné. `6` sur un objet sélectionné = le retire. Avec sélection : `e` équiper/retirer (ex. jean + sac à dos), `t` sortir, `r` ranger auto, `g` poser ;
  Depuis le sol, Entrée/`w`/`W` s'appliquent à la sélection. Les objets équipés sont sélectionnables.
- **Souris** : lecture seule dans les menus (survol du diviseur de poids = infobulle du conteneur) ; dans le monde, double-clic gauche = s'y rendre.
- Zoom `+` / `−` (par caractère, pavé accepté). `c` = écran personnage (onglets Stats / Corps, 4 / 6 ou flèches, `c`/Échap ferme). `|` = menu de posture (suivante présélectionnée, `|` ou 8/2 changent, Entrée valide, Échap ferme).
  `x` ou `Maj` + pavé / flèches = mode regard.

## Architecture (scripts/)
- `main.gd` : assemble monde, joueur, HUD, zombies de test. `autoload/event_bus.gd` (`EventBus`), `autoload/game_clock.gd` (`GameClock`) : à déclarer dans cet ordre (Projet > Paramètres > Globaux).
- `world/world.gd` : monde infini (carte via `ChunkManager`), objets au sol, monstres, file d'actions, FOV. Requêtes : `is_walkable` (à pied), `swim_depth` / `is_deep_water` / `can_player_enter`.
  Calques : chunks (sol), objets au sol, `entities` (arbres + joueur + monstres triés par Y), `fog` (z 10), overlay de choix de case. Case hors chunks chargés = inconnue (ni praticable, opaque). `world_seed` / `use_arena` avant `add_child`.
- `worldgen/` (détails dans `WORLD_GEN.md`) : `world_rng`, `terrain_db` (+ `terrain.json`), `chunk_generator`, `chunk`, `chunk_manager` (charge rayon 3, génération immédiate rayon 2, décharge > 4, mémoire des cases vues),
  `path_finder` (A* borné 1500 cases / rayon 40), `world_map` (+ `biomes.json`), `settlement_map` (+ `towns.json`), `route_map`, `special_map` (+ `specials.json`), `mapgen_db` (+ `mapgen/*.json`), `furniture_db` (+ `furniture.json`).
- `ui/` : `minimap_ui` (carte debug `m`, routes jusqu'au zoom `ROUTES_MAX_ZOOM`), `inventory_ui` (inventaire i, sol g / G, ramassages préparés, séquence de validation, sélection `_held`, infobulles),
  `character_ui` (`c`), `posture_ui` (`|`), `look_ui` (regard), `hud` (stats, journal, infobulle monstres), `key_util`.
- `world/` : `fov.gd` (shadowcasting), `fog_layer.gd` (rangées fusionnées, zone selon fenêtre et zoom), `auto_path.gd` (BFS 4 directions sur cases connues).
- `data/` : `inventory_ledger`, `item_db` + `items.json`, `item`, `inventory`, `stat_db` + `stats.json`, `body_part_db` + `body_parts.json`, `monster_data` (zombie en code, à passer en JSON/.tres).
- `entities/player.gd` : déplacement, combat de base (6 dégâts, 2 pts), stamina, charge, nage / noyade (fonctions statiques `swim_*`, `drown_damage`), répétition de touche, actions d'inventaire sans temps,
  `spend_inventory_time`, `body`, `take_damage`, `try_zoom`, `travel_to`. Kit de départ : `START_EQUIPMENT`, `START_LOOSE`. `entities/monster.gd` : IA.
- `render/ultica_tiles.gd` : id de tuile → sprite, variantes pondérées, décalages. `tools/build_ultica_pack.py` : régénère `assets/` depuis CDDA-tilesets (ajouter un id dans `IDS`, relancer).
- `tests/` : `test_worldgen_determinism.gd`, `test_swimming.gd`, `test_body.gd` (lancés à la demande).

## Conventions
- Tout est construit par code (seule `main.tscn` avec `main.gd`). Constantes d'équilibrage en haut des scripts.
- Nœuds positionnés sur le coin haut-gauche de leur case ; décalages de sprites via `UlticaTiles`. Rendu pixel art (filtre sur `World`).

## Limites connues / à faire
- Murs : arêtes, coins, T, extrémités (`ChunkManager.wall_sprite`) ; croisement en + : repli `t_wall_unconnected` ; orientation des T / extrémités à vérifier à l'œil. Porte : praticable et opaque, sans état ouvert/fermé (jalon 8) ; fenêtre : bloque le passage, laisse voir.
- Nage : pas de vêtements mouillés, pas de noyade due au poids, monstres ne nagent pas, pas de nage auto depuis la rive ni de double-clic vers l'eau profonde, pas d'indicateur HUD. Valeurs posées « à l'aveugle » (`SWIM_*`, `DROWN_DAMAGE_PER_SECOND`).
- Vêtements : calques `overlay_male_worn_*` dans l'ordre `ItemDB.WORN_DRAW_ORDER` (pas de `layering.json`, un sac peut se superposer mal) ; version « male » seulement.
- Icônes : vêtements = calque porté ; sac en rideau / militaire = icônes provisoires. Inventaire au clavier seulement.
- Poser : case du joueur seulement ; ramasser : 9 cases ; pas de transfert partiel d'une pile.
- Canopées d'arbres (96×96) peuvent cacher ce qui est derrière. Survol des monstres par case.
- Membres à 0 PV sans effet ; pas de soin ni régénération par partie ; PV max fixes.
- Regard : sous Windows, `Maj` + pavé avec VerrNum peut ne pas arriver comme Maj enfoncé ; utiliser `x` puis le pavé sans Maj. Objets et monstres hors de vue non mémorisés.
- Feuille de route : inventaire (fini) → monde procédural (jalons 1-5, 9, 9b faits) → jalon 10 → combat plus riche → import complet d'UltiCa (TileMapLayer) → jauge de suspense.
