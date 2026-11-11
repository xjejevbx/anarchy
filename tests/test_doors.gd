extends Node
## Test des portes et fenêtres actionnables (jalon 8). À lancer via sa scène (autoloads GameClock / EventBus) :
##   godot --headless --path <projet> res://tests/test_doors.tscn
## Vérifie : états fermé/ouvert des terrains (praticable, opaque), liaisons open_into / close_into, coûts et bruits,
## ouverture au contact par le joueur, fermeture avec la touche o, refus de fermer une case occupée, vue qui s'ouvre,
## chemin automatique à travers une porte fermée connue, et conservation de l'état par delta de chunk (déchargement/rechargement).

var _failures: int = 0


func _ready() -> void:
	_check_terrains()
	_check_world()
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	get_tree().quit(_failures)


func _check_terrains() -> void:
	var door: int = TerrainDB.index_of("t_door")
	var door_open: int = TerrainDB.index_of("t_door_o")
	var window: int = TerrainDB.index_of("t_window")
	var window_open: int = TerrainDB.index_of("t_window_open")

	_check(not TerrainDB.is_walkable(door) and TerrainDB.is_opaque(door), "porte fermée : bloque le passage et la vue")
	_check(TerrainDB.is_walkable(door_open) and not TerrainDB.is_opaque(door_open), "porte ouverte : passage libre et transparent")
	_check(not TerrainDB.is_walkable(window) and not TerrainDB.is_opaque(window), "fenêtre fermée : bloque le passage, pas la vue")
	_check(TerrainDB.is_walkable(window_open) and not TerrainDB.is_opaque(window_open), "fenêtre ouverte : passage libre et transparent")

	_check(TerrainDB.is_door(door) and TerrainDB.is_door(door_open), "portes marquées comme telles (même ouvertes)")
	_check(not TerrainDB.is_door(window) and not TerrainDB.is_door(window_open), "fenêtres distinctes des portes")
	_check(TerrainDB.open_into(door) == door_open and TerrainDB.close_into(door_open) == door, "porte : liaison fermé <-> ouvert")
	_check(TerrainDB.open_into(window) == window_open and TerrainDB.close_into(window_open) == window, "fenêtre : liaison fermé <-> ouvert")
	_check(TerrainDB.open_into(door_open) < 0 and TerrainDB.close_into(door) < 0, "un état ouvert ne s'ouvre pas, un état fermé ne se ferme pas")
	_check(TerrainDB.open_into(TerrainDB.index_of("t_floor")) < 0, "un terrain ordinaire n'est pas actionnable")

	_check(is_equal_approx(TerrainDB.open_cost(door), 1.0) and TerrainDB.open_noise(door) == 4, "porte : 1 point, bruit 4")
	_check(is_equal_approx(TerrainDB.close_cost(door_open), 1.0) and TerrainDB.close_noise(door_open) == 3, "porte : fermeture 1 point, bruit 3")
	_check(is_equal_approx(TerrainDB.open_cost(window), 2.0) and TerrainDB.open_noise(window) == 5, "fenêtre : 2 points, bruit 5")
	_check(is_equal_approx(TerrainDB.close_cost(window_open), 2.0) and TerrainDB.close_noise(window_open) == 5, "fenêtre : fermeture 2 points, bruit 5")
	_check(TerrainDB.open_cost(door_open) == 0.0 and TerrainDB.close_noise(door) == 0, "coût / bruit nuls hors de l'état concerné")

	var plans: int = MapgenDB.plan_count()
	_check(plans > 0 and MapgenDB.has_door(0), "les plans de maison utilisent toujours la porte fermée")


func _check_world() -> void:
	GameClock.elapsed_points = 0.0
	var world := World.new()
	world.world_seed = WorldRng.seed_from_text("portes-jalon8")
	world.seed_text = "portes-jalon8"
	world.population = 0.0
	add_child(world)
	var spawn: Vector2i = SettlementMap.for_seed(world.world_seed).spawn_cell()
	world.safe_centers.append(spawn)
	var player := Player.new()
	player.world = world
	player.grid_pos = spawn
	world.player = player
	world.add_entity(player)
	world.update_fov()

	var door: int = TerrainDB.index_of("t_door")
	var door_open: int = TerrainDB.index_of("t_door_o")
	var window: int = TerrainDB.index_of("t_window")
	var window_open: int = TerrainDB.index_of("t_window_open")
	var floor: int = TerrainDB.index_of("t_floor")
	var left: Vector2i = spawn + Vector2i(3, 0)
	var cell: Vector2i = left + Vector2i.RIGHT
	var right: Vector2i = cell + Vector2i.RIGHT
	for c: Vector2i in [left, cell, right]:
		world.chunks.set_terrain(c, floor)
		world.chunks.set_furniture(c, 0)
	world.chunks.set_terrain(cell, door)
	player.grid_pos = left
	world.update_fov()

	_check(not world.is_walkable(cell) and world.is_opaque(cell), "porte fermée du monde : infranchissable et opaque")
	_check(not world.monster_can_enter(cell, World.DOMAIN_WALK), "un marcheur ne peut pas traverser une porte fermée")
	_check(world.openable_state(cell) == 1 and world.is_closed_openable(cell), "porte fermée détectée comme actionnable")
	_check(world.visible_cells.has(cell) and not world.visible_cells.has(right), "la porte fermée est visible mais cache la case derrière")

	# Le déplacement automatique connaît la porte (case déjà vue derrière) et la traverse : elle s'ouvrira au contact.
	world.chunks.mark_seen(right)
	var path: Array[Vector2i] = AutoPath.find(world, left, right, 8)
	_check(path.size() >= 2 and path.has(cell), "le chemin automatique traverse une porte fermée connue")

	# Ouverture au contact : coûte une action, ne déplace pas le joueur, révèle la pièce et fait du bruit.
	player._facing = Vector2i.RIGHT
	var before: float = GameClock.elapsed_points
	player._try_move(Vector2i.RIGHT)
	_check(world.chunks.terrain_index(cell) == door_open, "pousser la porte fermée l'ouvre")
	_check(player.grid_pos == left, "ouvrir la porte ne déplace pas le joueur")
	_check(GameClock.elapsed_points > before, "ouvrir la porte coûte une action")
	_check(world.is_walkable(cell) and not world.is_opaque(cell), "porte ouverte : franchissable et transparente")
	_check(world.monster_can_enter(cell, World.DOMAIN_WALK), "un marcheur peut traverser une porte ouverte")
	_check(world.visible_cells.has(right), "ouvrir la porte révèle la case derrière")
	_check(world.noise_cell == cell and world.noise_radius == 4, "ouvrir la porte fait du bruit (rayon 4)")
	_check(world.openable_state(cell) == -1, "porte ouverte détectée comme refermable")

	# Le pas suivant entre dans l'ouverture, puis le joueur la dépasse et la referme avec o (dernier déplacement = est).
	var open_delta: Dictionary = world.chunks.terrain_delta(ChunkManager.key_of(cell))
	_check(int(open_delta.get(ChunkManager.index_of(cell), -1)) == door_open, "l'état ouvert est enregistré comme delta de terrain")
	player._try_move(Vector2i.RIGHT)
	_check(player.grid_pos == cell, "le joueur entre dans la porte ouverte")
	player._try_move(Vector2i.RIGHT)
	_check(player.grid_pos == right, "le joueur traverse la porte ouverte")
	before = GameClock.elapsed_points
	player._toggle_openable()
	_check(world.chunks.terrain_index(cell) == door, "la touche o ferme la porte voisine")
	_check(GameClock.elapsed_points > before, "fermer la porte coûte une action")

	# Une case occupée ne se ferme pas.
	world.chunks.set_terrain(cell, door_open)
	world.player.grid_pos = cell
	var blocked: Dictionary = world.toggle_openable(cell)
	_check(not bool(blocked.get("changed", true)) and world.chunks.terrain_index(cell) == door_open, "impossible de fermer une porte sur un occupant")
	world.player.grid_pos = right
	world.chunks.set_terrain(cell, door)

	# Fenêtre : transparente même fermée, ouverte on peut la franchir ; coût et bruit plus élevés.
	var win: Vector2i = right + Vector2i(0, 3)
	var win_side: Vector2i = win + Vector2i.LEFT
	for c: Vector2i in [win_side, win, win + Vector2i.RIGHT]:
		world.chunks.set_terrain(c, floor)
		world.chunks.set_furniture(c, 0)
	world.chunks.set_terrain(win, window)
	world.player.grid_pos = win_side
	world.update_fov()
	_check(not world.is_walkable(win) and not world.is_opaque(win), "fenêtre fermée du monde : infranchissable mais transparente")
	_check(world.visible_cells.has(win + Vector2i.RIGHT), "la fenêtre fermée laisse voir derrière")
	before = GameClock.elapsed_points
	var win_info: Dictionary = world.toggle_openable(win)
	_check(bool(win_info.get("changed", false)) and bool(win_info.get("opened", false)), "la fenêtre s'ouvre")
	_check(is_equal_approx(float(win_info.get("cost", 0.0)), 2.0), "ouvrir une fenêtre coûte 2 points")
	_check(world.chunks.terrain_index(win) == window_open and world.is_walkable(win), "fenêtre ouverte : franchissable")
	_check(world.noise_radius == 5 and world.noise_cell == win, "ouvrir une fenêtre fait du bruit (rayon 5)")
	world.player.grid_pos = right
	var win_close: Dictionary = world.toggle_openable(win)
	_check(bool(win_close.get("changed", false)) and not bool(win_close.get("opened", true)), "la fenêtre se referme")
	_check(world.chunks.terrain_index(win) == window and not world.is_walkable(win), "fenêtre refermée : de nouveau infranchissable")

	# Delta conservé : on décharge la surface, puis on la recharge (le terrain régénéré doit reprendre l'état sauvegardé).
	world.chunks.set_terrain(cell, door_open)
	var key: Vector3i = ChunkManager.key_of(cell)
	world.chunks.set_level(1)
	world.chunks.update_around(cell)
	world.chunks.set_level(0)
	world.chunks.update_around(cell)
	_check(world.chunks.terrain_index(cell) == door_open, "l'état de la porte survit au déchargement / rechargement du chunk")
	_check(world.chunks.terrain_delta(key).has(ChunkManager.index_of(cell)), "le delta de porte est conservé")
	_check(world.chunks.modified_keys().has(key), "le chunk modifié est marqué pour la sauvegarde")

	world.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
