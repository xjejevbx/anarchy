extends Node2D
## Racine du jeu : au lancement, affiche l'écran des sauvegardes (nouvelle partie avec seed/scénario, chargement) ;
## une fois la partie créée ou chargée, assemble le monde, le joueur et les interfaces.
## F5 ouvre l'écran des sauvegardes en jeu ; F2 copie la seed dans le presse-papiers.

# --- Réglages de debug (une nouvelle partie normale utilise le menu : seed et scénario) ---
const USE_TEST_ARENA: bool = false           # true : ancienne carte fermée 60x40 (debug), avec 3 zombies de test
const SPAWN_BESTIARY: bool = false            # true : tous les types de monstres près du départ (debug) ; false : population normale seulement
# Densité de monstres (jalon 6a) : multiplie les densités de data/worldgen/ecology.json. 0 = aucun monstre, 1 = normal, 2 = très peuplé.
const POPULATION: float = 1.0
# true : au lancement d'une partie, un écran liste les sprites demandés par les données mais absents de assets/tiles.json
# (MissingSpritesUI, SpriteAudit). Rien ne s'affiche si tout est chargé. Mettre false pour ne plus l'afficher.
const SHOW_MISSING_SPRITES: bool = true

# Monstres de test : [id MonsterData, décalage par rapport au départ]. Tous dans les ~30 cases (chunks proches chargés au démarrage).
# BASE_MONSTERS : seulement dans l'arène de test (le monde normal a sa propre population, voir SpawnGenerator).
const BASE_MONSTERS: Array = [
	["zombie", Vector2i(9, 3)], ["zombie", Vector2i(15, 9)], ["zombie", Vector2i(5, 15)],
]
const BESTIARY_MONSTERS: Array = [
	["zombie_child", Vector2i(-10, 6)], ["zombie_fast", Vector2i(18, -8)], ["zombie_crawler", Vector2i(-6, 12)],
	["zombie_brute", Vector2i(22, 12)], ["zombie_spitter", Vector2i(-14, -9)], ["zombie_screecher", Vector2i(12, -16)],
	["zombie_electric", Vector2i(-18, 14)], ["zombie_soldier", Vector2i(24, -4)], ["zombie_dog", Vector2i(-8, -14)],
	["wolf", Vector2i(-24, 4)], ["wolf", Vector2i(-26, 7)], ["wolf", Vector2i(-23, 9)],
	["giant_spider", Vector2i(8, 22)], ["bear", Vector2i(-20, -20)], ["zombie_hulk", Vector2i(28, 24)],
]

var _world: World
var _player: Player


func _ready() -> void:
	var request: Dictionary = GameSession.take()
	match int(request.get("mode", GameSession.Request.MENU)):
		GameSession.Request.LOAD:
			_start_loaded(String(request.get("slot", "")))
		GameSession.Request.NEW_GAME:
			_start_new(String(request.get("seed_text", "")), String(request.get("scenario", "default")))
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
	world.scenario = scenario
	world.use_arena = USE_TEST_ARENA
	world.population = POPULATION
	add_child(world)

	# Point de départ : déterministe selon la seed (lisière de la ville la plus proche, sinon pleine nature ; une île selon le scénario) ;
	# (5, 5) dans l'arène.
	var spawn: Vector2i = ChunkGenerator.SPAWN_POS
	var scenario_note: String = ""
	if not USE_TEST_ARENA:
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

	var spawn_town: Dictionary = {}
	if not USE_TEST_ARENA:
		var spawn_key: Vector3i = ChunkManager.key_of(spawn)
		spawn_town = SettlementMap.for_seed(world.world_seed).town_at(Vector2i(spawn_key.x, spawn_key.y))
	var spawn_note: String = (" en lisière de « %s »" % spawn_town["name"]) if not spawn_town.is_empty() else ""
	EventBus.message_logged.emit("Monde : seed « %s » (%d)%s. Départ en (%d, %d)%s.%s m : carte de debug." % \
		[clean_seed, world.world_seed, ", arène de test" if USE_TEST_ARENA else "", spawn.x, spawn.y, spawn_note, scenario_note])

	# Monstres de test (placés relativement au joueur ; survolez-les ou utilisez x pour voir leurs compétences).
	# Monde normal : la population vient des chunks (SpawnGenerator) ; l'arène de test garde ses 3 zombies.
	var roster: Array = []
	if USE_TEST_ARENA:
		roster.append_array(BASE_MONSTERS)
	if SPAWN_BESTIARY:
		roster.append_array(BESTIARY_MONSTERS)
	for entry: Array in roster:
		world.spawn_monster(MonsterData.create(String(entry[0])), spawn + (entry[1] as Vector2i))

	# Objets de test au sol, autour du joueur : i = inventaire, g = ramasser (seulement pour une nouvelle partie).
	var at := func(dx: int, dy: int) -> Vector2i: return spawn + Vector2i(dx, dy)
	world.add_ground_item(at.call(1, 0), Item.create("backpack_military"))
	world.add_ground_item(at.call(1, 0), Item.create("backpack"))
	world.add_ground_item(at.call(1, 0), Item.create("bag_curtain"))
	world.add_ground_item(at.call(0, 1), Item.create("jacket_light"))
	world.add_ground_item(at.call(0, 1), Item.create("pants_cargo"))
	world.add_ground_item(at.call(0, 1), Item.create("hat_ball"))
	world.add_ground_item(at.call(-1, 0), Item.create("2x4"))
	world.add_ground_item(at.call(-1, 0), Item.create("sheet_metal_small"))
	world.add_ground_item(at.call(-1, 0), Item.create("pipe"))
	world.add_ground_item(at.call(-1, 0), Item.create("stick"))
	world.add_ground_item(at.call(0, -1), Item.create("can_beans", 4))
	world.add_ground_item(at.call(0, -1), Item.create("bottle_plastic", 2))
	world.add_ground_item(at.call(0, -1), Item.create("rope_6"))
	world.add_ground_item(at.call(1, 1), Item.create("antibiotics", 3))


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
	if SHOW_MISSING_SPRITES:
		var sprite_report := MissingSpritesUI.new()
		sprite_report.player = player
		add_child(sprite_report)
		sprite_report.show_report()

	var save_menu := SaveMenuUI.new()  # F5 en jeu (écran des sauvegardes)
	save_menu.player = player
	add_child(save_menu)


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode == KEY_F2 and _world != null:
		var seed_value: String = _world.seed_text if _world.seed_text != "" else str(_world.world_seed)
		DisplayServer.clipboard_set(seed_value)
		EventBus.message_logged.emit("Seed copiée dans le presse-papiers : « %s »." % seed_value)
		get_viewport().set_input_as_handled()
