# Projet : clone de Cataclysm: Dark Days Ahead, plus joli (Godot 4.4, GDScript)

Tileset provisoire : UltiCa (CC BY-SA 3.0, voir assets/ultica/CREDITS.txt). Les vrais tilesets viendront plus tard.

## Règles de jeu décidées (à respecter)
- **Temps** : 1 point d'action = 1 seconde in-game ; 60 points = 1 minute. Horloge : autoload `GameClock`.
- **Stamina** : tous les 30 % de stamina perdue, TOUTES les actions durent +10 % de plus (max +30 %, paliers : 0/+10/+20/+30).
  Coût réel d'une action = coût de base × (1 + pénalité).
- **Charge portée (style CDDA)** : ratio = poids porté / capacité. Le poids porté vient de l'inventaire, la capacité =
  `CAPACITY_BASE` (20 kg) + bonus d'équipement (`capacity_bonus`, optionnel dans les données).
  - ratio < 1 : se déplacer ET attendre REGAGNENT de la stamina, de moins en moins vite (`regen_max × (1 − ratio)`).
  - ratio = 1 : effet nul.
  - ratio > 1 : se déplacer ET attendre FONT PERDRE de la stamina, de plus en plus vite
	(`2.0 × dépassement + 4.0 × dépassement²`).
  - Attendre coûte 1 pt comme un déplacement, avec un peu plus de gain (`WAIT_REGEN_MAX = 0.85` vs `MOVE_REGEN_MAX = 0.6`).
- **Nage (jalon 9b)** : l'eau n'est plus un mur. Toute eau (peu profonde, de marais, profonde) se traverse à la NAGE ; le champ `swim`
  (`shallow` / `deep`) de `terrain.json` donne la profondeur (`TerrainDB.swim_depth`). « Praticable » (`walkable`) veut dire praticable À PIED :
  l'eau profonde ne l'est pas, donc les monstres ne nagent pas (ils restent sur les gués) ; `World.can_player_enter` laisse entrer le joueur.
  Constantes `SWIM_*` et `DROWN_*` en haut de `player.gd`.
  - **Pas à la nage** : la posture est ignorée (durée d'un pas ×1), et chaque pas COÛTE de la stamina : eau peu profonde −1,0, eau profonde −2,5,
	plus la perte de surcharge habituelle si ratio > 1. Même à vide, nager épuise.
  - **Attendre en eau peu profonde = faire la planche** : même récupération qu'attendre à terre (`WAIT_REGEN_MAX × (1 − ratio)`) ; si l'inventaire
	est trop plein (ratio > 1), on PERD de la stamina comme à terre. Action nommée « Flotter ».
  - **Attendre en eau profonde = surplace** : −1,0 de stamina + surcharge, jamais de récupération. Les gestes d'inventaire en eau profonde coûtent aussi ce surplace.
  - **Noyade** : quand la stamina est à 0 à la fin d'une action faite dans l'eau (déplacement, attente, étape d'inventaire, attaque), le joueur perd
	`2,0 PV × durée de l'action en secondes`. Le message « Vous vous noyez » s'affiche, et la touche maintenue / marche automatique s'arrête (comme pour toute blessure).
	Remonter sur la terre ferme ou, en eau peu profonde, flotter jusqu'à regagner de la stamina met fin à la noyade.
  - **Marche automatique** : une touche maintenue ne s'engage jamais dans l'eau profonde depuis la rive ; une fois dans l'eau, elle continue à nager tout droit
	tant que la stamina reste ≥ 20 (`SWIM_REPEAT_MIN_STAMINA`). Le double-clic ne vise pas l'eau profonde (« Impossible de s'y rendre »).
	Le journal annonce l'entrée dans l'eau, le changement de profondeur et « Vous reprenez pied » ; le sprite est teinté en bleu pendant la nage.
- **Diagonales** : pas de déplacement diagonal spécial. « Bas + gauche » = deux pas orthogonaux (2 actions, chacune avec son
  temps/sa stamina, les monstres peuvent agir entre les deux). Valable pour le joueur ET les monstres (A* en 4 directions).
  La mêlée ne porte qu'en orthogonal (`World.are_adjacent`). Sans ça, un zombie rattrapait un joueur qui fuyait en diagonale.
- **Monstres** : affichent au survol leur coût de déplacement et le coût de leurs attaques (dont la spéciale) pour la stratégie.
  Chaque monstre a un « prochain moment d'action » ; il agit puis attend le coût de son action.
- **Vue** : champ de vision par shadowcasting (rayon 20). Murs et arbres bloquent la vue. Brouillard : visible / mémoire
  (assombri) / jamais vu (noir). Les monstres hors de vue sont cachés et ne repèrent le joueur que s'ils sont dans son champ
  de vision (vue symétrique) ; sinon ils vont à la dernière position connue. Un monstre frappé sait où tu es.
- **Touche maintenue** (marche automatique INTELLIGENTE : tout droit tant que c'est libre, sinon un chemin court qui contourne les arbres et obstacles connus, `AutoPath`) = appuis répétés (délai 0,25 s puis 1 action / 0,07 s). La répétition s'arrête quand un ennemi
  apparaît dans la vue ou quand le joueur est blessé (il faut relâcher et réappuyer).
- **Inventaire (style Project Zomboid)** : un objet = nom, poids (kg), taille [longueur, largeur] (cm), id de tuile UltiCa.
  - Conteneurs (sacs, vêtements à poches) : poids propre fixe, taille max d'objet (longueur/largeur, l'objet peut être tourné),
	limite de poids de contenu RÉEL, et `weight_ratio` : le contenu pèse réel / ratio, que le conteneur soit équipé ou
	simplement porté sur soi (sac militaire ÷3, sac en rideau ÷1,2).
  - « Sur soi » = hors conteneur, poids plein, sans limite de taille.
  - Conteneur dans un conteneur : seulement s'il est VIDE ; et un conteneur lui-même rangé dans un autre ne peut rien
	recevoir. Un sac ramassé n'est jamais rangé automatiquement (il reste sur soi). Exception prévue plus tard : holster
	attaché à une ceinture.
  - Portée : la case du joueur + les 8 autour sont « à portée de main » (aucun coût supplémentaire).
  - Équipement : 1 objet par emplacement (tête, haut, veste, jambes, pieds, dos). Les vêtements s'affichent sur le sprite.
  - Ramasser va dans le meilleur conteneur équipé qui convient (réduction la plus forte), sinon sur soi. On peut se surcharger.
  - Coûts de base (points d'action, x pénalité de stamina) : ramasser = 1 + 0,8 x poids réel ; équiper/retirer = 3 + 0,4 x poids ;
	ranger / sortir / poser DEPUIS un conteneur = 1 + 0,4 x poids ; **poser au sol un objet « sur soi » = gratuit**.
  - **Le temps n'est PAS compté geste par geste** : les modifications sont immédiates, mais à la fermeture de l'inventaire on
	compare l'état de départ et l'état final (`InventoryLedger`) : un objet remis à sa place ne coûte rien, un objet déplacé
	plusieurs fois ne coûte que son déplacement net (origine -> destination ; depuis le sol = ramassage). Une popup affiche
	« Coût en temps : x secondes » avec « Validé » (le temps passe d'un coup) ou « Annulé » (rouvre l'inventaire, rien n'est
	défait). Aucun déplacement net = pas de popup. L'écran affiche le temps cumulé en direct.
  - **Ramassage préparé** : rien n'est modifié dans le monde avant la validation. Les objets choisis restent listés, grisés
	« déplacé vers l'inventaire (rangement auto / en main / équipé) » (ou « n/m déplacés »), et `U` annule. Ramasser puis équiper
	directement coûte ramassage + équipement.
  - **Poser au sol** : l'objet quitte l'inventaire tout de suite (poids à jour) mais n'apparaît au sol qu'à la validation ; il est
	listé dans « À POSER AU SOL » avec `U` pour le reprendre.
  - **Chaque objet est sa propre action** : une pile de 4 conserves = 4 étapes, chacune avec son coût (base + poids de CETTE
	unité : 4 conserves coûtent donc 4 x la base de manipulation). Idem pour ranger, sortir, équiper et poser.
  - **Validation animée** : à « Validé », les étapes sont jouées une par une avec un délai (`STEP_DELAY` en haut de
	`inventory_ui.gd`, 0,6 s ; deviendra une option de jeu), bannière centrée en haut (« Dépôt de X au sol (case 5)  (2/4) » +
	icône de chargement). **Le temps de chaque étape passe à ce moment-là** (`Player.spend_inventory_time`) : les monstres
	avancent entre deux étapes. Une touche saute l'animation (le temps passe quand même) ; si le joueur meurt, la séquence
	s'arrête. Les cases sont nommées par leur chiffre du pavé numérique (« AU SOL (case 4) » = case de gauche).
  - **Annuler** : `u` annule les déplacements de l'objet sous le curseur (au sol : le ramassage préparé ; en inventaire :
	retour à son emplacement de départ), `U` remet tout à zéro. La popup propose « Validé [Entrée] », « Annulé [Échap] »
	(continuer) et « Tout annuler [U] » (rien ne change, aucune seconde perdue).
- **Posture** (touche `|`) : Marche (référence), Sprint (pas ×0,7 de durée, stamina −1 par pas, les monstres te détectent de ×1,5 plus loin), Accroupi (pas ×1,5, stamina +0,3 par pas, détection ×0,5). Changer de posture est gratuit. Valeurs : constantes `POSTURE_*` de `player.gd`. À la nage, durée et stamina de la posture sont ignorées (la détection par les monstres reste modifiée).
- **Stats du joueur** : `data/stats.json` (Force, Dextérité, Intelligence, Perception, base 8) affichées dans l'écran personnage (`c`) ; elles n'ont pas encore d'effet. Pour en ajouter : une entrée dans le JSON.
- **Zoom** : `+` / `-` (5 paliers de 0,125 à 0,75, cases de 128 px). Le champ de vision ne change pas : le brouillard couvre simplement plus de cases.
- **Double-clic** sur une case VISIBLE et praticable à pied : déplacement automatique (un vrai pas par action, les monstres jouent). Il s'arrête si un ennemi apparaît, si le joueur est blessé, si le chemin est bloqué ou à la moindre touche.
- **Alerte « Vous apercevez X »** : une fois par monstre ; elle revient seulement s'il est resté dans le brouillard au moins `World.ALERT_REARM_POINTS` (5 s). La marche automatique s'arrête, elle, à chaque apparition.
- **Jauge de suspense** (PLUS TARD) : indicateur 0-100 % comme si quelqu'un nous observait et pariait sur nos chances de survie
  (100 % = on ne sait pas quand tu vas mourir, 0 % = déjà mort). Valeur calculée (PV, stamina, menaces, charge, etc.).

## Monde procédural (plan : `docs/WORLD_GEN.md`)
- Monde infini, généré par chunks de 24 x 24 cases, **déterministe** : une seed = un monde, même après sauvegarde / rechargement.
- Sauvegarde = seed + modifications (deltas par chunk) ; le terrain se régénère. Pas de `randi()` global dans la génération.
- Contenu en données (`data/worldgen/*.json`) : villes, routes, motels, fermes, centrales nucléaires, etc.
- Étages / sous-sols / tour radio prévus plus tard : les clés de chunk portent déjà une coordonnée `z`.
- Statut : **jalons 1 et 2 faits** (chunks, A* borné, arène de test en option ; biomes, lacs, rivières, gués, mini-carte de debug) ; **jalon 3 fait** : 3a (villes et rues, départ en lisière de ville), 3b (routes entre villes, ponts) et 3c (maisons avec intérieur et mobilier) ; **jalon 4 fait** : lieux spéciaux (station-service, motel, ferme) ; **jalon 5 fait** : grands lieux (centrale nucléaire, ranch, usine, station d'épuration, camping, entrepôt, cimetière, chapelle, poste électrique, cabane) ; **jalon 9 fait** : monde planétaire (océans, plages, climats par bandes de latitude : toundra, taïga, désert, savane, jungle ; pas de relief ni de neige ; correctif : aucune rue de ville sur un lac ni sur l'océan, `SettlementMap._is_water_body`) ; **jalon 9b fait** : nage et noyade (voir « Nage » dans les règles) ; jalons 6 à 8 ensuite, puis 10 à 15 (jalon 10 : modes de placement par climat, île, pleine mer, côte, et accès des lieux sans route : piste, héliport, jetée).
- Réglages de partie en haut de `main.gd` : `WORLD_SEED_TEXT` (nombre ou texte) et `USE_TEST_ARENA` (true = ancienne carte fermée 60 x 40).

## Contrôles
**Convention d'affichage des touches** : dans l'UI et ici on n'écrit jamais « Maj+u » : une touche seule s'écrit en MINUSCULE (`u`),
la même touche avec Maj s'écrit en MAJUSCULE (`U`). Le joueur fait la différence. Les touches spéciales gardent leur nom (Entrée, Échap).
Déplacement : pavé numérique (8/2/4/6, diagonales 7/9/1/3) **ou flèches** (= 8/2/4/6, orthogonal) ; espace / `.` / `5` pavé = attendre (dans l'eau : flotter ou faire du surplace). On entre à la nage dans l'eau profonde par un appui de touche, jamais en touche maintenue depuis la rive.
Les flèches valent aussi 8/2/4/6 dans les menus (naviguer, sélectionner, valider, choisir la case).
`m` = carte du monde de DEBUG (montre aussi l'inexploré) : `+`/`-` zoom, 8/2/4/6 ou flèches pour déplacer la vue et 7/9/1/3 en diagonale., `5` recentrer, `m`/Échap fermer
(`m` et `w` sont détectés par le CARACTÈRE tapé, pas par la position : `KeyUtil.is_letter`, indépendant de la disposition AZERTY / QWERTY). `i` = inventaire. `g` = ramasser : s'il y a des objets sur une seule case à portée, sa liste s'ouvre ; sinon un overlay
affiche les chiffres 1-9 (disposition du pavé) sur les cases contenant des objets. `G` = les 9 cases dans une seule liste.
Menus : 8/2 (ou flèches) naviguer, Échap fermer. **Ramassage (g) et inventaire (i) sont deux écrans séparés** : on ne passe
pas de l'un à l'autre.
Inventaire : `e` équiper/retirer, `r` ranger, `t` sortir, `g` poser au sol, `u` annuler l'objet sous le curseur, `U` tout annuler.
Ramassage : Entrée/`g` ramasser (rangement auto), `w` prendre en main (sur soi, sans conteneur), `W` équiper directement,
`u` annuler l'objet, `U` tout annuler. (`w`/`W` : même détection par caractère.)
Popup de validation : Entrée = Validé, Échap = Annulé (on continue), `U` = tout annuler ; `u` seul ne fait rien.
Sélection multiple : `4` (ou `+`) ajoute l'objet sous le curseur à la sélection (+1 s'il y est déjà, jusqu'à la taille de la
pile), `-` retire 1. Curseur sur un conteneur : `6` = déplace 1 unité de chaque objet sélectionné, `Entrée` = déplace toute la
sélection ; ce qui ne rentre pas reste sélectionné. `6` sur un objet sélectionné = le retire de la sélection. Avec une
sélection : `e` équiper/retirer (ex. un jean et un sac à dos d'un coup), `t` sortir, `r` ranger auto, `g` poser au sol ; les objets
équipés (sac équipé, etc.) sont sélectionnables comme les autres (même quantités). Depuis le sol, `Entrée`/`w`/`W` s'appliquent à la sélection.
Souris : lecture seule dans les menus (survol du diviseur dans « Poids : 0.40 kg ÷ 2 × 4 = 0.80 kg » = infobulle du conteneur) ; dans le monde, double-clic gauche sur une case visible = s'y rendre.
Zoom `+` / `-` (par le caractère tapé, donc aussi en AZERTY ; pavé numérique accepté). `c` = écran du personnage (4 / 6 ou flèches : onglets, `c` / Échap : fermer). `|` = menu de posture (Marche / Sprint / Accroupi) : la posture suivante est présélectionnée, `|` ou 8 / 2 changent la sélection, Entrée valide, Échap ferme.

## Architecture (scripts/)
- `main.gd` : assemble monde, joueur, HUD, zombies de test.
- `autoload/event_bus.gd` (`EventBus`) : signaux globaux. `autoload/game_clock.gd` (`GameClock`).
  Les deux sont à déclarer dans Projet > Paramètres > Globaux, dans cet ordre.
- `world/world.gd` : monde infini (délègue la carte au `ChunkManager`), objets au sol, monstres, file d'actions, FOV. Requêtes de terrain : `is_walkable` (à pied), `swim_depth` / `is_deep_water` / `can_player_enter` (nage, jalon 9b).
  Calques : chunks (sol), objets au sol, `entities` (arbres + joueur + monstres, triés par Y), `fog` (FogLayer, z_index 10), overlay de choix de case.
  Une case hors des chunks chargés est inconnue (ni praticable, opaque). `world_seed` et `use_arena` se fixent AVANT `add_child`.
- `worldgen/` : `world_rng.gd` (`WorldRng`, aléatoire déterministe `mix(seed, couche, x, y, z)`), `terrain_db.gd` (`TerrainDB`, lit
  `data/worldgen/terrain.json` ; champs `walkable` = à pied et `swim` = profondeur de nage), `chunk_generator.gd` (terrain d'un chunk = fonction pure de seed + clé), `chunk.gd` (`Chunk` 24 x 24 :
  terrain, cases vues, sprites d'arbres, rendu du sol), `chunk_manager.gd` (`ChunkManager` : charge rayon 3, génération immédiate
  rayon 2, déchargement au-delà de 4, mémoire des cases vues conservée), `path_finder.gd` (`PathFinder`, A* borné 1500 cases / rayon 40),
  `settlement_map.gd` (`SettlementMap` : villes par région de 32 x 32 cellules, rues en croix + grille, parcelles / jardins, géométrie des
  cellules de route (chaussée, trottoirs, lignes, ponts sur l'eau), point de départ en lisière de ville ; une rue ne traverse ni lac ni océan ; réglages `data/worldgen/towns.json`),
  `route_map.gd` (`RouteMap` : routes entre villes — graphe des plus proches voisines, A* sur les cellules macro avec coûts entiers par biome, cache par arête et par région ; `SettlementMap.cell_type()` les renvoie comme ROAD hors des villes ; réglages : section `routes` de `data/worldgen/towns.json`),
  `special_map.gd` (`SpecialMap` : lieux spéciaux placés par région, empreintes multi-cellules tournées vers la route, `data/worldgen/specials.json` ; `SettlementMap.cell_type()` renvoie SPECIAL pour leurs cellules, `cell_plan()` donne le plan à poser), `mapgen_db.gd` (`MapgenDB` : plans ASCII 24 x 24 de maisons, `data/worldgen/mapgen/houses.json`, compilés en terrain + mobilier et validés au chargement ; `SettlementMap.lot_plan()` choisit plan et rotation pour tourner la façade vers une rue), `furniture_db.gd` (`FurnitureDB` : mobilier, `data/worldgen/furniture.json`, un octet par case dans `Chunk.furniture`, dessiné par-dessus le sol ; praticable / opaque combinés au terrain par `ChunkManager`),
  `world_map.gd` (`WorldMap` : champs de bruit continus altitude / humidité / rivière -> nature d'une case (`Kind` : plaine, forêt, marais,
  lac profond / peu profond, rivière profonde / gué, berges), terrain d'une case, cellule macro, point de départ ; une instance par seed).
  Réglages en données : `data/worldgen/biomes.json` (bruits, seuils, densité d'arbres, couleurs de la mini-carte).
- `ui/minimap_ui.gd` (`MiniMapUI`) : mini-carte de debug (touche `m`), modale. Les routes entre villes s'y affichent jusqu'au zoom `ROUTES_MAX_ZOOM` (au-delà, le calcul de trop de régions serait long).
- `tests/test_worldgen_determinism.gd` : test de déterminisme (à lancer à la demande, voir l'en-tête du fichier). `tests/test_swimming.gd` : test de la nage (données de terrain, formules de stamina et de noyade).
- `world/fov.gd` (shadowcasting), `world/fog_layer.gd`.
- `data/inventory_ledger.gd` (`InventoryLedger`) : coût net des déplacements d'une session d'inventaire.
- `entities/player.gd` : déplacement, combat de base (6 dégâts, 2 pts), stamina, charge (`get_carry_weight/capacity` depuis
  l'inventaire), nage et noyade (fonctions statiques `swim_*`, `drown_damage`, testables sans scène), répétition de touche, actions d'inventaire sans temps (`pickup_item`, `drop_item`, `store_item`,
  `take_out_item`, `equip_item`, `unequip_slot`), formules de coût et `spend_inventory_time` (appelé à chaque étape de la validation). Kit de départ en constantes (`START_EQUIPMENT`, `START_LOOSE`).
- `data/items.json` + `data/item_db.gd` (`ItemDB`, emplacements) : objets définis en données. `data/item.gd` (`Item`, instance :
  id, quantité, contenu, poids, `can_hold`) et `data/inventory.gd` (`Inventory` : sur soi + équipement, poids total).
- `world/world.gd` gère aussi les objets au sol (`ground_items`, `add/remove_ground_item`, dessinés dans un calque au-dessus du sol).
- `ui/inventory_ui.gd` (`InventoryUI`) : écran inventaire (i), sol (g / G, choix de case via overlay `World.show_pick_overlay`), ramassages préparés,
  séquence de validation,
  sélection/déplacement d'objets (`_held`), pause du jeu, détails + coût de chaque action, infobulles au survol.
- `entities/monster.gd` + `data/monster_data.gd` : IA et données (zombie défini en code, à passer en JSON/.tres).
- `render/ultica_tiles.gd` (`UlticaTiles`) : accès aux sprites UltiCa (id de tuile -> sprite, variantes pondérées, décalages).
- `ui/character_ui.gd` (`CharacterUI`, touche `c`) : écran du personnage à onglets (Stats : caractéristiques + état). `data/stats.json` + `data/stat_db.gd` (`StatDB`) : définition des stats. `ui/posture_ui.gd` (`PostureUI`, touche `|`) : menu de posture.
- `world/auto_path.gd` (`AutoPath`) : BFS 4 directions sur les cases connues (marche automatique, double-clic). `world/fog_layer.gd` : brouillard dessiné par rangées fusionnées, zone calculée d'après la taille de fenêtre et le zoom.
- `ui/hud.gd` : texte de stats (posture comprise), journal de messages, infobulle des monstres.
- `tools/build_ultica_pack.py` : régénère assets/ultica (copie les PNG d'une liste d'ids CDDA depuis le dépôt
  I-am-Erk/CDDA-tilesets, dossier gfx/UltimateCataclysm, + écrit tiles.json). Ajouter un id dans IDS puis relancer.

## Conventions
- Tout est construit par code (pas de .tscn hormis la scène racine avec main.gd). Constantes d'équilibrage en haut des scripts.
- Nœuds positionnés sur le coin haut-gauche de leur case ; les décalages de sprites viennent de `UlticaTiles`.
- Le rendu est en pixel art : `texture_filter = NEAREST` posé sur `World`.

## Limites connues / à faire
- Murs : arêtes, coins, jonctions en T et extrémités (`ChunkManager.wall_sprite`) ; croisement en + : repli `t_wall_unconnected` (les plans l'évitent) ; orientation des sprites de T et d'extrémité à vérifier à l'œil. Porte : praticable et opaque, sans état ouvert / fermé (jalon 8) ; fenêtre : bloque le passage, laisse voir.
- Nage : pas de vêtements mouillés, pas de noyade due au poids (seule la stamina compte, la surcharge l'aggrave), les monstres ne nagent pas, pas de nage automatique depuis la rive ni de double-clic vers l'eau profonde, pas d'indicateur « nage » dans le HUD (journal et teinte du sprite seulement). Valeurs de stamina et de dégâts posées « à l'aveugle » : à régler en jeu (`SWIM_*`, `DROWN_DAMAGE_PER_SECOND`).
- Vêtements : calques `overlay_male_worn_*` posés sur le mannequin dans l'ordre `ItemDB.WORN_DRAW_ORDER` (approximation : pas
  de `layering.json` d'UltiCa, donc un sac peut se superposer mal). Seulement la version « male » pour l'instant.
- Icônes d'objets : les vêtements n'ont pas d'icône UltiCa, on réutilise le calque porté ; sac en rideau / sac militaire
  utilisent des icônes provisoires (`bag_plastic`, `backpack`). Interface inventaire : clavier seulement (pas de souris).
- Poser : uniquement sur la case du joueur ; ramasser : les 9 cases à portée ; pas de transfert partiel d'une pile (on prend toute la pile).
- Les canopées d'arbres (96×96) peuvent cacher ce qui est derrière. Survol des monstres par case, pas par sprite.
- Feuille de route : inventaire (terminé) -> **génération procédurale du monde (plan dans `docs/WORLD_GEN.md`, jalons 1 à 5, 9 et 9b faits)** -> jalon 10 (modes de placement) -> combat plus riche -> import complet d'UltiCa
  (TileMapLayer) -> jauge de suspense.
