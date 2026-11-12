extends Node2D
## Racine du jeu : au lancement, affiche le menu principal (partie rapide à seed aléatoire, arène de test,
## sauvegardes, nouvelle partie avec seed/scénario) ; une fois la partie créée ou chargée, assemble le monde,
## le joueur et les interfaces. F5 ouvre l'écran des sauvegardes en jeu ; F2 copie la seed dans le presse-papiers.

# --- Réglages de debug ---
# Densité de monstres (jalon 6a) : multiplie les densités de data/worldgen/ecology.json. 0 = aucun monstre, 1 = normal, 2 = très peuplé.
const POPULATION: float = 1.0
# true : au lancement d'une partie, un écran liste les sprites demandés par les données mais absents de assets/tiles.json
# (MissingSpritesUI, SpriteAudit). Rien ne s'affiche si tout est chargé. Mettre false pour ne plus l'afficher.
const SHOW_MISSING_SPRITES: bool = true
# Réglage effectif, modifiable avant l'ajout du nœud (tests headless) : true par défaut, voir SHOW_MISSING_SPRITES.
var show_missing_sprites: bool = SHOW_MISSING_SPRITES

# Arène de test : géométrie, bestiaire et objets sont centralisés dans TestArena (voir son en-tête).
# Préchargés pour ne pas dépendre du cache des class_name en mode headless.
const TEST_ARENA = preload("res://scripts/worldgen/test_arena.gd")
const ARENA_GUIDE_SCRIPT = preload("res://scripts/ui/arena_guide_ui.gd")

var _world: World
var _player: Player


func _ready() -> void:
	var request: Dictionary = GameSession.take()
	match int(request.get("mode", GameSession.Request.MENU)):
		GameSession.Request.LOAD:
			_start_loaded(String(request.get("slot", "")))
		GameSession.Request.NEW_GAME:
			_start_new(String(request.get("seed_text", "")), String(request.get("scenario", "default")))
		GameSession.Request.ARENA:
			_start_arena()
		_:
			_show_main_menu()


func _show_main_menu(error: String = "") -> void:
	var menu := SaveMenuUI.new()
	menu.main_mode = true
	menu.notice = ("Chargement impossible : " + error) if error != "" else ""
	add_child(menu)


func _start_loaded(slot: String) -> void:
	var meta: Dictionary = SaveGame.read_meta(slot)
	var reason: String = SaveGame.compatibility_error(meta)
	if reason != "":
		_show_main_menu(reason)
		return
	var world := World.new()
	add_child(world)
	var result: Dictionary = SaveGame.load_world(world, slot)
	if not bool(result.get("ok", false)):
		world.queue_free()
		_show_main_menu(String(result.get("error", "sauvegarde illisible")))
		return
	var loaded: Dictionary = result["meta"]
	var player: Player = _create_player(world, SaveGame.saved_spawn(loaded))
	SaveGame.apply_player(player, loaded.get("player", {}))
	_build_ui(world, player)
	player.emit_status()
	EventBus.message_logged.emit("Partie « %s » chargée : seed « %s » (%d), %s. Position (%d, %d)." % [
		slot, world.seed_text, world.world_seed, GameClock.get_time_string(), player.grid_pos.x, player.grid_pos.y])


func _start_new(seed_text: String, scenario: String) -> void:
	_start_game(seed_text, scenario, false)


## Arène de test du menu principal : seed fixe, pas de génération procédurale, contenu de démonstration.
func _start_arena() -> void:
	_start_game(TEST_ARENA.SEED_TEXT, "default", true)


func _start_game(seed_text: String, scenario: String, arena: bool) -> void:
	# Nouvelle partie depuis le menu en jeu : l'horloge et les gestionnaires globaux de l'ancienne partie ne doivent pas survivre.
	GameClock.elapsed_points = 0.0
	StatusEffects.reset()
	Infection.reset()
	var clean_seed: String = seed_text.strip_edges()
	if clean_seed == "":
		clean_seed = str((randi() << 32) ^ randi())
	var world := World.new()
	world.world_seed = WorldRng.seed_from_text(clean_seed)
	world.seed_text = clean_seed
	world.scenario = scenario if not arena else "default"
	world.use_arena = arena
	world.population = POPULATION
	add_child(world)

	# Point de départ : déterministe selon la seed (lisière de la ville la plus proche, sinon pleine nature ; une île selon le scénario) ;
	# (5, 5) dans l'arène de test.
	var spawn: Vector2i = TEST_ARENA.SPAWN_POS
	var scenario_note: String = ""
	var spawn_town: Dictionary = {}
	if arena:
		scenario_note = " Arène de test : guide en haut à gauche (F1), F3 valide une étape."
	else:
		var settlement: SettlementMap = SettlementMap.for_seed(world.world_seed)
		spawn = settlement.spawn_cell()
		if scenario == "island":
			if settlement.has_island_spawn():
				spawn = settlement.island_spawn_cell()
				scenario_note = " Scénario : perdu sur une île."
			else:
				scenario_note = " Aucune île trouvée près de l'origine : départ par défaut."
	world.safe_centers.append(spawn)  # aucun monstre ne naît à moins de 12 cases du départ (avant le premier chargement de chunk)

	var player: Player = _create_player(world, spawn)
	_build_ui(world, player)
	player.emit_status()

	if not arena:
		var spawn_key: Vector3i = ChunkManager.key_of(spawn)
		spawn_town = SettlementMap.for_seed(world.world_seed).town_at(Vector2i(spawn_key.x, spawn_key.y))
	var spawn_note: String = (" en lisière de « %s »" % spawn_town["name"]) if not spawn_town.is_empty() else ""
	EventBus.message_logged.emit("Monde : seed « %s » (%d)%s. Départ en (%d, %d)%s.%s" % \
		[clean_seed, world.world_seed, ", arène de test" if arena else "", spawn.x, spawn.y, spawn_note, scenario_note])

	if arena:
		_populate_arena(world, player)
		world.update_fov()   # les monstres et objets viennent d'être ajoutés : rafraîchit la vue et les signale


## Contenu de démonstration de l'arène : objets au sol (tous les étages) et bestiaire complet, endormi.
func _populate_arena(world: World, player: Player) -> void:
	for entry: Dictionary in TEST_ARENA.ground_items():
		var cell: Vector2i = entry["cell"]
		world.add_ground_item_at(int(entry.get("level", 0)), cell,
			Item.create(String(entry["item"]), int(entry.get("count", 1))))
	for entry: Dictionary in TEST_ARENA.bestiary():
		var cell: Vector2i = entry["cell"]
		var monster: Monster = world.spawn_monster_at({
			"monster": String(entry["monster"]), "cell": cell, "state": "sleep",
		})
		if monster == null:
			push_warning("TestArena : impossible de placer %s en (%d, %d)." % [entry["monster"], cell.x, cell.y])
	# Des antibiotiques dans l'inventaire de départ : l'étape « u » du guide est testable immédiatement,
	# même si les objets au sol permettent aussi de tester le ramassage.
	player.inventory.loose.append(Item.create("antibiotics", 3))
	player.refresh_inventory()


func _create_player(world: World, spawn: Vector2i) -> Player:
	var player := Player.new()
	player.world = world
	player.grid_pos = spawn
	world.player = player
	world.add_entity(player)  # dans le calque trié par Y, avec les monstres et les arbres
	_world = world
	_player = player
	return player


## Interfaces communes à une nouvelle partie et à une partie chargée.
func _build_ui(world: World, player: Player) -> void:
	var inventory_ui := InventoryUI.new()
	inventory_ui.player = player
	add_child(inventory_ui)

	var minimap := MiniMapUI.new()
	minimap.player = player
	minimap.seed_text = world.seed_text
	add_child(minimap)

	var character_ui := CharacterUI.new()
	character_ui.player = player
	add_child(character_ui)

	var posture_ui := PostureUI.new()
	posture_ui.player = player
	add_child(posture_ui)

	var use_ui := UseUI.new()     # menu « utiliser un objet » : touche u (antibiotiques...)
	use_ui.player = player
	add_child(use_ui)

	var look_ui := LookUI.new()   # mode regard : x ou Maj + pavé numérique
	look_ui.player = player
	add_child(look_ui)

	var hud := CanvasLayer.new()
	hud.set_script(load("res://scripts/ui/hud.gd"))
	add_child(hud)

	# Contrôle des sprites au lancement : ajouté APRÈS les autres interfaces pour recevoir les touches en premier (il bloque le joueur
	# tant qu'il est ouvert) et après le HUD (le message du journal est alors affiché).
	if show_missing_sprites:
		var sprite_report := MissingSpritesUI.new()
		sprite_report.player = player
		add_child(sprite_report)
		sprite_report.show_report()

	var save_menu := SaveMenuUI.new()  # F5 en jeu (écran des sauvegardes)
	save_menu.player = player
	add_child(save_menu)

	# Guide de test : seulement dans l'arène, ajouté en dernier pour recevoir F1 / F3 / F4 avant les autres interfaces.
	if world.use_arena:
		var guide = ARENA_GUIDE_SCRIPT.new()
		guide.player = player
		add_child(guide)


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode == KEY_F2 and _world != null:
		var seed_value: String = _world.seed_text if _world.seed_text != "" else str(_world.world_seed)
		DisplayServer.clipboard_set(seed_value)
		EventBus.message_logged.emit("Seed copiée dans le presse-papiers : « %s »." % seed_value)
		get_viewport().set_input_as_handled()
