extends Node
## Test des cartes et du mode regard par étage (jalon 8). À lancer via sa scène (autoloads GameClock / EventBus) :
##   godot --headless --path <projet> res://tests/test_ui_levels.tscn
## Vérifie que la mini-carte suit l'étage actif : génération du plan sous terre (roche hors plan), séparation des
## tuiles entre surface et sous-sol, ouverture directe au zoom « 1 case = 1 échantillon » sous terre, et que le
## mode regard annonce l'étage et distingue les informations de surface sous terre. Vérifie aussi la carte du joueur :
## seules les cases vues sont dessinées, cache séparé, repères posés/retirés et rattachés à leur étage, toits connus.
## Enfin, l'APERÇU d'un autre étage (mini-carte et mode regard) : changement réel d'étage, zoom borné au plan, aucune
## case révélée et restauration de l'étage actif à la fermeture.

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

	# Mode regard : ouvert à l'étage actif, il annonce l'étage et marque les informations de surface.
	var look := LookUI.new()
	look.player = player
	add_child(look)
	EventBus.look_requested.emit(Vector2i.ZERO)
	_check(look._is_open, "mode regard : s'ouvre")
	_check(look._active_level == -1 and look._level == -1, "mode regard : suit l'étage actif à l'ouverture")
	look._cursor = player.grid_pos
	look._build_lines()
	var text: String = _lines_text(look)
	_check(text.contains("étage -1"), "mode regard : l'en-tête indique l'étage actif")
	_check(text.contains("Biome (surface)"), "mode regard : le biome est marqué « surface » sous terre")

	# Aperçu : < / > changent réellement d'étage, sans champ de vision ni révélation de cases.
	var surface_seen_before: int = _seen_count(world.chunks.seen_of(ChunkManager.key_of(player.grid_pos, 0)))
	var top_seen_before: int = _seen_count(world.chunks.seen_of(ChunkManager.key_of(player.grid_pos, 1)))
	look._change_level(1)   # -1 -> 0 (surface)
	_check(look._level == 0 and world.get_level() == 0, "mode regard : aperçu de l'étage au-dessus")
	_check(world.view_is_preview and not player.visible, "mode regard : l'aperçu marque la vue et masque le joueur")
	_check(world.visible_cells.is_empty(), "mode regard : aucun champ de vision calculé en aperçu")
	_check(_seen_count(world.chunks.seen_of(ChunkManager.key_of(player.grid_pos, 0))) == surface_seen_before,
		"mode regard : l'aperçu ne révèle aucune case de surface")
	text = _lines_text(look)
	_check(text.contains("(aperçu)"), "mode regard : le panneau indique l'aperçu")

	look._change_level(1)   # 0 -> 1 (vide au-dessus de la surface)
	_check(look._level == 1 and world.get_level() == 1, "mode regard : aperçu de l'étage +1")
	_check(_seen_count(world.chunks.seen_of(ChunkManager.key_of(player.grid_pos, 1))) == top_seen_before,
		"mode regard : l'aperçu ne révèle aucune case de l'étage +1")

	look._close()
	_check(not look._is_open and world.get_level() == -1, "mode regard : la fermeture restaure l'étage actif")
	_check(not world.view_is_preview and player.visible, "mode regard : la fermeture réactive la vue et le joueur")
	_check(not world.visible_cells.is_empty(), "mode regard : la fermeture recalcule le champ de vision")

	# Retour en surface : le mode regard lit de nouveau la surface.
	world.change_level(0)
	EventBus.look_requested.emit(Vector2i.ZERO)
	look._cursor = player.grid_pos
	look._build_lines()
	text = _lines_text(look)
	_check(text.contains("surface") and text.contains("Biome :"), "mode regard : retour en surface")
	look._close()

	# --- Carte du joueur : seules les cases vues sont dessinées, repères par étage ---
	map._player_mode = false
	map._level = 0
	var player_key: int = MiniMapUI.PLAYER_LEVEL_KEY_OFFSET
	var spawn_tx: int = floori(float(spawn.x) / MiniMapUI.TILE)
	var spawn_ty: int = floori(float(spawn.y) / MiniMapUI.TILE)
	var spawn_local := Vector2i(spawn.x - spawn_tx * MiniMapUI.TILE, spawn.y - spawn_ty * MiniMapUI.TILE)
	var seen_tex: ImageTexture = map._compute_tile(Vector4i(player_key, MiniMapUI.TERRAIN_ZOOM_INDEX, spawn_tx, spawn_ty))
	var seen_color: Color = seen_tex.get_image().get_pixel(spawn_local.x, spawn_local.y)
	_check(not seen_color.is_equal_approx(MiniMapUI.COLOR_UNKNOWN), "carte du joueur : une case explorée est dessinée")
	var unseen := Vector2i(500000, 500000)
	var unseen_tx: int = floori(float(unseen.x) / MiniMapUI.TILE)
	var unseen_ty: int = floori(float(unseen.y) / MiniMapUI.TILE)
	var unseen_local := Vector2i(unseen.x - unseen_tx * MiniMapUI.TILE, unseen.y - unseen_ty * MiniMapUI.TILE)
	var unseen_tex: ImageTexture = map._compute_tile(Vector4i(player_key, MiniMapUI.TERRAIN_ZOOM_INDEX, unseen_tx, unseen_ty))
	var unseen_color: Color = unseen_tex.get_image().get_pixel(unseen_local.x, unseen_local.y)
	_check(unseen_color.is_equal_approx(MiniMapUI.COLOR_UNKNOWN), "carte du joueur : une case jamais vue reste inconnue")
	map._player_mode = true
	var player_tile_key: Vector4i = map._tile_key(MiniMapUI.TERRAIN_ZOOM_INDEX, spawn_tx, spawn_ty)
	map._player_mode = false
	var debug_tile_key: Vector4i = map._tile_key(MiniMapUI.TERRAIN_ZOOM_INDEX, spawn_tx, spawn_ty)
	_check(player_tile_key != debug_tile_key, "carte du joueur : cache de tuiles séparé de la carte de debug")

	EventBus.map_requested.emit()
	_check(map._is_open and map._player_mode, "carte du joueur : s'ouvre avec p")
	_check(map._level == 0 and map._zoom_index == MiniMapUI.TERRAIN_ZOOM_INDEX,
		"carte du joueur : surface au zoom 1 case par échantillon")
	map._close()

	_check(player.toggle_map_marker(spawn), "carte du joueur : repère posé")
	_check(player.has_map_marker(spawn, 0), "carte du joueur : repère présent à l'étage 0")
	_check(not player.has_map_marker(spawn, -1), "carte du joueur : repères séparés par étage")
	_check(not player.toggle_map_marker(spawn), "carte du joueur : repère retiré")
	_check(not player.has_map_marker(spawn, 0), "carte du joueur : repère absent après retrait")

	world.change_level(-1)
	_check(player.toggle_map_marker(spawn), "carte du joueur : repère posé sous terre")
	_check(player.has_map_marker(spawn, -1) and not player.has_map_marker(spawn, 0),
		"carte du joueur : repère rattaché au bon étage")
	world.change_level(0)

	# --- Aperçu d'étage par la carte et toits connus ---
	var stale := Vector4i(MiniMapUI.PREVIEW_LEVEL_KEY_OFFSET + 7, 0, 0, 0)
	MiniMapUI._tiles[stale] = null
	map._clear_all_preview_tiles()
	_check(not MiniMapUI._tiles.has(stale), "mini-carte : les tuiles d'aperçu sont invalidées")

	map._active_level = world.get_level()
	map._active_zoom_index = MiniMapUI.START_ZOOM_INDEX
	map._player_mode = false
	map._level = 0
	map._zoom_index = MiniMapUI.START_ZOOM_INDEX
	map._change_level(-1)
	_check(map._level == -1 and map._zoom_index <= MiniMapUI.TERRAIN_ZOOM_INDEX,
		"mini-carte : aperçu d'étage limité au zoom du plan")
	var preview_key: Vector4i = map._tile_key(MiniMapUI.TERRAIN_ZOOM_INDEX, unseen_tx, unseen_ty)
	_check(preview_key.x == MiniMapUI.PREVIEW_LEVEL_KEY_OFFSET - 1, "mini-carte : cache d'aperçu séparé de l'étage actif")
	var under_seen_before: int = _seen_count(world.chunks.seen_of(ChunkManager.key_of(unseen, -1)))
	var preview_tex: ImageTexture = map._compute_tile(preview_key)
	var preview_color: Color = preview_tex.get_image().get_pixel(unseen_local.x, unseen_local.y)
	_check(preview_color.is_equal_approx(MiniMapUI.COLOR_UNKNOWN),
		"mini-carte : un aperçu ne dessine pas les cases inconnues")
	_check(_seen_count(world.chunks.seen_of(ChunkManager.key_of(unseen, -1))) == under_seen_before,
		"mini-carte : l'aperçu ne révèle aucune case")
	map._change_level(1)
	_check(map._level == 0 and map._zoom_index == MiniMapUI.START_ZOOM_INDEX,
		"mini-carte : le retour à l'étage actif restaure le zoom")

	# Toit déjà aperçu : les cases non vues du bâtiment sont peintes en toit, portes et fenêtres restent lisibles.
	var roof_key := Vector3i(900, 900, 0)
	var roof_chunk := Chunk.new()
	roof_chunk.key = roof_key
	roof_chunk.terrain = PackedByteArray()
	roof_chunk.terrain.resize(Chunk.CELLS)
	var grass_index: int = TerrainDB.index_of("t_grass")
	for i in Chunk.CELLS:
		roof_chunk.terrain[i] = grass_index
	roof_chunk.seen = PackedByteArray()
	roof_chunk.seen.resize(Chunk.CELLS)
	roof_chunk.roof = PackedByteArray()
	roof_chunk.roof.resize(Chunk.CELLS)
	roof_chunk.seen[0] = 1
	roof_chunk.roof[0] = Chunk.ROOF_COVER
	roof_chunk.roof[1] = Chunk.ROOF_COVER
	roof_chunk.roof[2] = Chunk.ROOF_OPENING
	world.chunks.chunks[roof_key] = roof_chunk
	var roof_cell := Vector2i(900 * Chunk.SIZE, 900 * Chunk.SIZE)
	var roof_tx: int = floori(float(roof_cell.x) / MiniMapUI.TILE)
	var roof_ty: int = floori(float(roof_cell.y) / MiniMapUI.TILE)
	var roof_local := Vector2i(roof_cell.x - roof_tx * MiniMapUI.TILE, roof_cell.y - roof_ty * MiniMapUI.TILE)
	map._player_mode = true
	map._level = 0
	var roof_tex: ImageTexture = map._compute_tile(
		Vector4i(MiniMapUI.PLAYER_LEVEL_KEY_OFFSET, MiniMapUI.TERRAIN_ZOOM_INDEX, roof_tx, roof_ty))
	var roof_image: Image = roof_tex.get_image()
	_check(roof_image.get_pixel(roof_local.x + 1, roof_local.y).is_equal_approx(MiniMapUI.COLOR_ROOF),
		"carte du joueur : un toit aperçu couvre les cases non vues")
	_check(not roof_image.get_pixel(roof_local.x + 2, roof_local.y).is_equal_approx(MiniMapUI.COLOR_ROOF) \
		and not roof_image.get_pixel(roof_local.x + 2, roof_local.y).is_equal_approx(MiniMapUI.COLOR_UNKNOWN),
		"carte du joueur : une porte / fenêtre reste visible sous le toit")
	world.chunks.chunks.erase(roof_key)
	roof_chunk.free()

	world.queue_free()


func _lines_text(look: LookUI) -> String:
	var text: String = ""
	for line: Dictionary in look._lines:
		text += String(line.get("text", "")) + "\n"
	return text


## Nombre de cases marquées vues dans une empreinte de chunk (mémoire de la carte).
func _seen_count(seen: PackedByteArray) -> int:
	var count: int = 0
	for value in seen:
		if value != 0:
			count += 1
	return count


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
