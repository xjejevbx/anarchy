extends Node
## Test des toits (jalon 8). À lancer via sa scène (autoloads GameClock / EventBus) :
##   godot --headless --path <projet> res://tests/test_roofs.tscn
## Vérifie l'empreinte dérivée du terrain (flood fill depuis les bords), la connaissance du toit dès qu'une case est vue,
## l'absence de toit sous terre, le choix des sprites de raccord et le masquage du toit du bâtiment du joueur.

var _failures: int = 0


func _ready() -> void:
	GameClock.elapsed_points = 0.0
	_check_mask()
	_check_known()
	_check_underground()
	_check_sprites()
	_check_world_state()
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	get_tree().quit(_failures)


## Terrain synthétique : une maison fermée (murs, une porte au sud, une fenêtre au nord) dans une prairie.
func _house_terrain() -> PackedByteArray:
	var terrain := PackedByteArray()
	terrain.resize(Chunk.CELLS)
	var grass: int = TerrainDB.index_of("t_grass")
	var wall: int = TerrainDB.index_of("t_wall_house")
	var floor_tile: int = TerrainDB.index_of("t_floor")
	var door: int = TerrainDB.index_of("t_door")
	var window: int = TerrainDB.index_of("t_window")
	for i in Chunk.CELLS:
		terrain[i] = grass
	for y in range(4, 12):
		for x in range(4, 12):
			var wall_cell: bool = x == 4 or x == 11 or y == 4 or y == 11
			terrain[y * Chunk.SIZE + x] = wall if wall_cell else floor_tile
	terrain[11 * Chunk.SIZE + 7] = door     # façade sud
	terrain[4 * Chunk.SIZE + 7] = window    # mur nord
	return terrain


func _check_mask() -> void:
	var terrain: PackedByteArray = _house_terrain()
	var mask: PackedByteArray = Chunk.roof_mask(terrain)
	_check(mask.size() == Chunk.CELLS, "empreinte : une valeur par case")
	_check(mask[7 * Chunk.SIZE + 7] == Chunk.ROOF_COVER, "empreinte : l'intérieur est couvert")
	_check(mask[6 * Chunk.SIZE + 6] == Chunk.ROOF_COVER, "empreinte : les murs du bâtiment sont couverts")
	_check(mask[11 * Chunk.SIZE + 7] == Chunk.ROOF_OPENING, "empreinte : la porte perce le toit")
	_check(mask[4 * Chunk.SIZE + 7] == Chunk.ROOF_OPENING, "empreinte : la fenêtre perce le toit")
	_check(mask[0] == Chunk.ROOF_NONE, "empreinte : l'extérieur n'est pas couvert")

	# Une simple clôture ne ferme aucune zone : pas de toit.
	var fence := PackedByteArray()
	fence.resize(Chunk.CELLS)
	var grass: int = TerrainDB.index_of("t_grass")
	var wall: int = TerrainDB.index_of("t_wall_house")
	for i in Chunk.CELLS:
		fence[i] = grass
	for x in Chunk.SIZE:
		fence[12 * Chunk.SIZE + x] = wall
	var fence_mask: PackedByteArray = Chunk.roof_mask(fence)
	var covered: int = 0
	for value in fence_mask:
		if value != Chunk.ROOF_NONE:
			covered += 1
	_check(covered == 0, "empreinte : une clôture ouverte ne crée pas de toit")


func _check_known() -> void:
	var chunk := Chunk.new()
	chunk.key = Vector3i.ZERO
	chunk.terrain = _house_terrain()
	chunk.seen = PackedByteArray()
	chunk.seen.resize(Chunk.CELLS)
	chunk.build_roof()
	_check(chunk.roof.size() == Chunk.CELLS, "toit : l'empreinte est calculée au chargement")
	_check(not chunk.roof_known, "toit : inconnu tant qu'aucune case du bâtiment n'a été vue")
	chunk.mark_seen(5 * Chunk.SIZE + 5)
	_check(chunk.roof_known, "toit : connu dès qu'une de ses cases est vue")
	chunk.free()


func _check_underground() -> void:
	var chunk := Chunk.new()
	chunk.key = Vector3i(0, 0, -1)
	chunk.terrain = _house_terrain()
	chunk.seen = PackedByteArray()
	chunk.seen.resize(Chunk.CELLS)
	chunk.build_roof()
	_check(chunk.roof.is_empty() and not chunk.roof_known, "toit : aucun toit sous terre")
	chunk.free()


func _check_sprites() -> void:
	var manager := ChunkManager.new()
	var chunk := Chunk.new()
	chunk.key = Vector3i.ZERO
	chunk.roof = PackedByteArray()
	chunk.roof.resize(Chunk.CELLS)
	for y in range(5, 8):
		for x in range(5, 8):
			chunk.roof[y * Chunk.SIZE + x] = Chunk.ROOF_COVER
	manager.chunks[chunk.key] = chunk
	_check(manager.roof_at(Vector2i(6, 6)) == Chunk.ROOF_COVER, "toit : roof_at lit l'empreinte du chunk")
	_check(manager.roof_sprite(Vector2i(6, 6)) == "t_shingle_flat_roof_center", "toit : pièce centrale")
	_check(manager.roof_sprite(Vector2i(5, 6)) == "t_shingle_flat_roof_t_connection_w", "toit : jonction en T")
	_check(manager.roof_sprite(Vector2i(5, 5)) == "t_shingle_flat_roof_corner_nw", "toit : coin nord-ouest")
	_check(manager.roof_sprite(Vector2i(5, 7)) == "t_shingle_flat_roof_corner_sw", "toit : coin sud-ouest")
	for i in Chunk.CELLS:
		chunk.roof[i] = Chunk.ROOF_NONE
	for x in range(5, 8):
		chunk.roof[10 * Chunk.SIZE + x] = Chunk.ROOF_COVER
	_check(manager.roof_sprite(Vector2i(6, 10)) == "t_shingle_flat_roof_edge_ew", "toit : bord est-ouest")
	for y in range(12, 15):
		chunk.roof[y * Chunk.SIZE + 10] = Chunk.ROOF_COVER
	_check(manager.roof_sprite(Vector2i(10, 13)) == "t_shingle_flat_roof_edge_ns", "toit : bord nord-sud")
	_check(manager.roof_sprite(Vector2i(6, 13)) == "t_shingle_flat_roof_unconnected", "toit : tuile isolée")
	manager.chunks.erase(chunk.key)
	chunk.free()


func _check_world_state() -> void:
	var world := World.new()
	world.world_seed = WorldRng.seed_from_text("toits")
	world.seed_text = "toits"
	world.population = 0.0
	add_child(world)
	var player := Player.new()
	player.world = world
	player.grid_pos = SettlementMap.for_seed(world.world_seed).spawn_cell()
	world.player = player
	world.add_entity(player)
	world.update_fov()

	var key: Vector3i = ChunkManager.key_of(player.grid_pos)
	var original := world.chunks.chunks.get(key) as Chunk
	var fake := Chunk.new()
	fake.key = Vector3i(key.x, key.y, 0)
	fake.roof = PackedByteArray()
	fake.roof.resize(Chunk.CELLS)
	fake.roof[ChunkManager.index_of(player.grid_pos)] = Chunk.ROOF_COVER
	world.chunks.chunks[fake.key] = fake
	world.refresh_roof_state()
	_check(world.roof_hidden_chunk == fake.key, "toit : le bâtiment du joueur est masqué")
	_check(world.visible_roof_chunks.has(fake.key), "toit : une case de toit visible rend le toit clair")
	world.view_is_preview = true
	world.refresh_roof_state()
	_check(world.roof_hidden_chunk == World.NO_ROOF_CHUNK, "toit : aucun toit masqué pendant un aperçu")
	_check(world.visible_roof_chunks.is_empty(), "toit : un aperçu ne rend aucun toit visible")
	world.view_is_preview = false

	if original != null:
		world.chunks.chunks[fake.key] = original
	else:
		world.chunks.chunks.erase(fake.key)
	fake.free()
	world.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
