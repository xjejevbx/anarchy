extends Node2D
## Racine du jeu : assemble le monde, le joueur, les monstres et le HUD.

# --- Réglages de la partie (la saisie de la seed viendra avec le menu de création) ---
const WORLD_SEED_TEXT: String = "cataclysme"  # nombre ou texte : même seed = même monde
const USE_TEST_ARENA: bool = false           # true : ancienne carte fermée 60x40 (debug)
const SPAWN_BESTIARY: bool = false            # true : tous les types de monstres près du départ (debug) ; false : 3 zombies seulement 
# Scénario de départ (le menu de création de partie viendra plus tard) :
#   "default" : en lisière de la ville la plus proche de l'origine (sinon pleine nature)
#   "island"  : perdu sur une petite île (SettlementMap.island_spawn_cell ; repli sur "default" s'il n'y en a pas près de l'origine)
const START_SCENARIO: String = "default"

# Monstres de test : [id MonsterData, décalage par rapport au départ]. Tous dans les ~30 cases (chunks proches chargés au démarrage).
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


func _ready() -> void:
	var world := World.new()
	world.world_seed = WorldRng.seed_from_text(WORLD_SEED_TEXT)
	world.use_arena = USE_TEST_ARENA
	add_child(world)

	# Point de départ : déterministe selon la seed (lisière de la ville la plus proche, sinon pleine nature ; une île selon le scénario) ;
	# (5, 5) dans l'arène.
	var spawn: Vector2i = ChunkGenerator.SPAWN_POS
	var scenario_note: String = ""
	if not USE_TEST_ARENA:
		var settlement: SettlementMap = SettlementMap.for_seed(world.world_seed)
		spawn = settlement.spawn_cell()
		if START_SCENARIO == "island":
			if settlement.has_island_spawn():
				spawn = settlement.island_spawn_cell()
				scenario_note = " Scénario : perdu sur une île."
			else:
				scenario_note = " Aucune île trouvée près de l'origine : départ par défaut."

	var player := Player.new()
	player.world = world
	player.grid_pos = spawn
	world.player = player
	world.add_entity(player)  # dans le calque trié par Y, avec les monstres et les arbres

	var inventory_ui := InventoryUI.new()
	inventory_ui.player = player
	add_child(inventory_ui)

	var minimap := MiniMapUI.new()
	minimap.player = player
	minimap.seed_text = WORLD_SEED_TEXT
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

	var spawn_town: Dictionary = {}
	if not USE_TEST_ARENA:
		var spawn_key: Vector3i = ChunkManager.key_of(spawn)
		spawn_town = SettlementMap.for_seed(world.world_seed).town_at(Vector2i(spawn_key.x, spawn_key.y))
	var spawn_note: String = (" en lisière de « %s »" % spawn_town["name"]) if not spawn_town.is_empty() else ""
	EventBus.message_logged.emit("Monde : seed « %s » (%d)%s. Départ en (%d, %d)%s.%s m : carte de debug." % \
		[WORLD_SEED_TEXT, world.world_seed, ", arène de test" if USE_TEST_ARENA else "", spawn.x, spawn.y, spawn_note, scenario_note])

	# Monstres de test (placés relativement au joueur ; survolez-les ou utilisez x pour voir leurs compétences)
	var roster: Array = BASE_MONSTERS.duplicate()
	if SPAWN_BESTIARY:
		roster.append_array(BESTIARY_MONSTERS)
	for entry: Array in roster:
		world.spawn_monster(MonsterData.create(String(entry[0])), spawn + (entry[1] as Vector2i))

	# Objets de test au sol, autour du joueur : i = inventaire, g = ramasser
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
