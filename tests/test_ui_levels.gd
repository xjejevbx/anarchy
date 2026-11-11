extends Node
## Test des cartes par étage (jalon 8). À lancer via sa scène (autoloads GameClock / EventBus) :
##   godot --headless --path <projet> res://tests/test_ui_levels.tscn
## Vérifie que la mini-carte suit l'étage actif : génération du plan sous terre (roche hors plan), séparation des
## tuiles entre surface et sous-sol, ouverture directe au zoom « 1 case = 1 échantillon » sous terre, et que le
## mode regard annonce l'étage et distingue les informations de surface sous terre.

var _failures: int = 0


func _ready() -> void:
	GameClock.elapsed_points = 0.0
	_check_levels()
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	get_tree().quit(_failures)


func _check_levels() -> void:
	var world := World.new()
	world.world_seed = WorldRng.seed_from_text("carte-par-etage")
	world.seed_text = "carte-par-etage"
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

	var map := MiniMapUI.new()
	map.player = player
	map.seed_text = world.seed_text
	add_child(map)
	MiniMapUI._prepare_caches(world.world_seed)

	# Chunk de sous-sol SANS plan : tout doit être de la roche. On évite les lieux qui ont un plan @-1.
	var key := Vector3i(120, 120, -1)
	while not ChunkGenerator.level_plan(world.world_seed, key).is_empty():
		key.x += 1
	var cell := Vector2i(key.x * Chunk.SIZE + 12, key.y * Chunk.SIZE + 12)
	var arrays: Dictionary = map._chunk_arrays(key)
	var index: int = ChunkManager.index_of(cell)
	_check(TerrainDB.id_of((arrays["terrain"] as PackedByteArray)[index]) == "t_rock",
		"sous-sol sans plan : la case est de la roche")

	# Tuile de mini-carte calculée pour cet étage, puis la même en surface : couleurs et entrées de cache distinctes.
	var tx: int = floori(float(cell.x) / MiniMapUI.TILE)
	var ty: int = floori(float(cell.y) / MiniMapUI.TILE)
	var local := Vector2i(cell.x - tx * MiniMapUI.TILE, cell.y - ty * MiniMapUI.TILE)
	var rock_color: Color = TerrainDB.color_of(TerrainDB.index_of("t_rock"))
	map._level = -1
	var under_tex: ImageTexture = map._compute_tile(Vector4i(-1, MiniMapUI.TERRAIN_ZOOM_INDEX, tx, ty))
	var under_color: Color = under_tex.get_image().get_pixel(local.x, local.y)
	_check(under_color.is_equal_approx(rock_color), "mini-carte sous terre : roche colorée comme t_rock")
	map._level = 0
	var surface_tex: ImageTexture = map._compute_tile(Vector4i(0, MiniMapUI.TERRAIN_ZOOM_INDEX, tx, ty))
	var surface_color: Color = surface_tex.get_image().get_pixel(local.x, local.y)
	_check(not surface_color.is_equal_approx(rock_color), "mini-carte : la surface n'est pas colorée comme la roche")
	_check(under_tex != surface_tex, "mini-carte : tuiles de surface et de sous-sol distinctes")

	# Ouverture sous terre : zoom sur le plan, pas le zoom « monde » de la surface.
	world.change_level(-1)
	EventBus.minimap_requested.emit()
	_check(map._is_open, "mini-carte : s'ouvre sous terre")
	_check(map._level == -1, "mini-carte : affiche l'étage actif (-1)")
	_check(map._zoom_index == MiniMapUI.TERRAIN_ZOOM_INDEX, "mini-carte : ouverture au zoom du plan (1 case par échantillon)")
	map._close()

	# Mode regard : en-tête et informations de surface étiquetées quand on est sous terre.
	var look := LookUI.new()
	look.player = player
	add_child(look)
	look._cursor = player.grid_pos
	look._build_lines()
	var text: String = _lines_text(look)
	_check(text.contains("étage -1"), "mode regard : l'en-tête indique l'étage actif")
	_check(text.contains("Biome (surface)"), "mode regard : le biome est marqué « surface » sous terre")

	# Retour en surface : le mode regard lit de nouveau la surface.
	world.change_level(0)
	look._build_lines()
	text = _lines_text(look)
	_check(text.contains("surface") and text.contains("Biome :"), "mode regard : retour en surface")

	world.queue_free()


func _lines_text(look: LookUI) -> String:
	var text: String = ""
	for line: Dictionary in look._lines:
		text += String(line.get("text", "")) + "\n"
	return text


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
