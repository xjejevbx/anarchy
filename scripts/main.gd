extends Node2D
## Racine du jeu : assemble le monde, le joueur, les monstres et le HUD.

# --- Réglages de la partie (la saisie de la seed viendra avec le menu de création) ---
const WORLD_SEED_TEXT: String = "cataclysme"  # nombre ou texte : même seed = même monde
const USE_TEST_ARENA: bool = false           # true : ancienne carte fermée 60x40 (debug)


func _ready() -> void:
	var world := World.new()
	world.world_seed = WorldRng.seed_from_text(WORLD_SEED_TEXT)
	world.use_arena = USE_TEST_ARENA
	add_child(world)

	# Point de départ : déterministe selon la seed (première terre sèche dégagée) ; (5, 5) dans l'arène.
	var spawn: Vector2i = ChunkGenerator.SPAWN_POS if USE_TEST_ARENA else WorldMap.for_seed(world.world_seed).spawn_cell()

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

	var hud := CanvasLayer.new()
	hud.set_script(load("res://scripts/ui/hud.gd"))
	add_child(hud)

	EventBus.message_logged.emit("Monde : seed « %s » (%d)%s. Départ en (%d, %d). m : carte de debug." % [WORLD_SEED_TEXT, world.world_seed, ", arène de test" if USE_TEST_ARENA else "", spawn.x, spawn.y])

	# Quelques zombies pour tester (placés relativement au joueur)
	world.spawn_monster(MonsterData.zombie(), spawn + Vector2i(9, 3))
	world.spawn_monster(MonsterData.zombie(), spawn + Vector2i(15, 9))
	world.spawn_monster(MonsterData.zombie(), spawn + Vector2i(5, 15))

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
