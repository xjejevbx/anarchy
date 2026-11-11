extends SceneTree
## Test de l'axe vertical (préparation des étages, jalon 6b). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_vertical.gd
## Code de sortie 0 = tout est bon. Vérifie : terrains verticaux, étages sans plan (roche sous la surface, vide au-dessus), hook des plans
## d'étage, escaliers des paires hôpital / clinique / silo / labo / bunker (descente et montée à la même case, connectivité, refus hors
## escalier), RNG à 4 coordonnées compatible avec l'existant, un seul étage chargé à la fois (ChunkManager.level), monstres et objets au sol
## rangés par étage.

var _failures: int = 0


func _initialize() -> void:
	_check_terrains()
	_check_rng()
	_check_levels()
	_check_stairs()
	_check_manager(WorldRng.seed_from_text("cataclysme"))
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check_terrains() -> void:
	for id in ["t_rock", "t_air", "t_stairs_up", "t_stairs_down"]:
		_check(TerrainDB.has_id(id), "terrain %s défini" % id)
	var rock: int = TerrainDB.index_of("t_rock")
	var air: int = TerrainDB.index_of("t_air")
	_check(not TerrainDB.is_walkable(rock) and TerrainDB.is_opaque(rock), "roche : ni praticable ni transparente")
	_check(not TerrainDB.is_walkable(air) and not TerrainDB.is_opaque(air), "vide : non praticable, transparent")
	_check(TerrainDB.z_link(TerrainDB.index_of("t_stairs_up")) == 1 and TerrainDB.z_link(TerrainDB.index_of("t_stairs_down")) == -1, "escaliers : liaison +1 / -1")
	_check(TerrainDB.z_link(TerrainDB.index_of("t_grass")) == 0 and TerrainDB.z_link(-1) == 0, "terrain ordinaire et index invalide : aucune liaison")
	_check(TerrainDB.index_of("t_grass") == 0 and TerrainDB.index_of("t_pier") < rock, "les terrains existants gardent leur index (les verticaux sont à la suite)")


func _check_rng() -> void:
	_check(WorldRng.mix(1, 2, 3, 4, 5) == WorldRng.mix(1, 2, 3, 4, 5, 0), "mix : la 4e coordonnée à 0 ne change rien")
	_check(WorldRng.mix(1, 2, 3, 4, 5) != WorldRng.mix(1, 2, 3, 4, 5, 1), "mix : la 4e coordonnée sépare les flux")
	_check(WorldRng.mix(1, 2, 3, 4, 5, 7) == WorldRng.mix(1, 2, 3, 4, 5, 7), "mix : stable avec la 4e coordonnée")
	_check(WorldRng.mix(1, 2, 3, 4, 0) != WorldRng.mix(1, 2, 3, 4, 1), "mix : l'étage (c) sépare les flux")


func _all_equal(data: PackedByteArray, value: int) -> bool:
	for b in data:
		if b != value:
			return false
	return true


func _check_levels() -> void:
	var rock: int = TerrainDB.index_of("t_rock")
	var air: int = TerrainDB.index_of("t_air")
	for text in ["1", "42", "cataclysme"]:
		var world_seed: int = WorldRng.seed_from_text(text)
		var spawn_key: Vector3i = ChunkManager.key_of(SettlementMap.for_seed(world_seed).spawn_cell())
		var keys: Array[Vector3i] = [Vector3i(0, 0, 0), spawn_key]
		for base in keys:
			var below := Vector3i(base.x, base.y, -1)
			var above := Vector3i(base.x, base.y, 1)
			var below_data: PackedByteArray = ChunkGenerator.generate(world_seed, below)
			var below_plan: Dictionary = ChunkGenerator.level_plan(world_seed, below)
			if below_plan.is_empty():
				_check(_all_equal(below_data, rock), "seed %d %s : étage -1 sans plan = roche pleine" % [world_seed, base])
				_check(_all_equal(ChunkGenerator.generate_furniture(world_seed, below), 0), "seed %d %s : pas de mobilier dans la roche" % [world_seed, base])
			else:
				_check(not _all_equal(below_data, rock), "seed %d %s : plan d'étage superposé à la roche" % [world_seed, base])
			_check(_all_equal(ChunkGenerator.generate(world_seed, Vector3i(base.x, base.y, -5)), rock), "seed %d %s : étage -5 = roche pleine" % [world_seed, base])
			_check(_all_equal(ChunkGenerator.generate(world_seed, above), air), "seed %d %s : étage +1 sans plan = vide" % [world_seed, base])
			_check(not _all_equal(ChunkGenerator.generate(world_seed, base), rock), "seed %d %s : la surface n'est pas de la roche" % [world_seed, base])
			_check(ChunkGenerator.fingerprint(world_seed, below) == ChunkGenerator.fingerprint(world_seed, below), "seed %d %s : étage répétable" % [world_seed, base])
			_check(SpawnGenerator.generate(world_seed, below, ChunkGenerator.generate(world_seed, below), PackedByteArray()).is_empty(), "seed %d %s : aucun monstre généré dans la roche" % [world_seed, base])
	# Convention des plans d'étage : « <id>@<z> ».
	_check(MapgenDB.plan_by_id("urban_hospital@-1") >= 0, "plan de sous-sol « urban_hospital@-1 » défini")
	_check(MapgenDB.plan_by_id("urban_hospital") >= 0, "le plan de surface existe")


## Escaliers (jalon 8) : chaque descente de plan de surface et la montée de son sous-sol occupent la MÊME case locale,
## puis un monde réel descend et remonte par deltas de terrain (sans dépendre de l'emplacement des lieux).
func _check_stairs() -> void:
	var pairs: Array = [
		["urban_hospital", "urban_hospital@-1", Vector2i(9, 15)],
		["urban_clinic", "urban_clinic@-1", Vector2i(16, 16)],
		["missile_silo", "missile_silo@-1", Vector2i(12, 15)],
		["lab_building", "lab_building@-1", Vector2i(7, 15)],
		["bunker", "bunker@-1", Vector2i(16, 10)],
	]
	for pair: Array in pairs:
		_check_stair_pair(String(pair[0]), String(pair[1]), pair[2])

	var world_seed: int = WorldRng.seed_from_text("cataclysme")
	var world := World.new()
	world.world_seed = world_seed
	root.add_child(world)
	var cell: Vector2i = SettlementMap.for_seed(world_seed).spawn_cell() + Vector2i(1, 0)
	world.chunks.update_around(cell)
	var down: int = TerrainDB.index_of("t_stairs_down")
	var up: int = TerrainDB.index_of("t_stairs_up")
	world.chunks.set_terrain(cell, down)
	world.chunks.set_level(-1)
	world.chunks.update_around(cell)
	world.chunks.set_terrain(cell, up)
	world.chunks.set_level(0)
	world.chunks.update_around(cell)
	_check(world.stair_link(cell) == -1, "surface : la case porte une descente")
	_check(not world.use_stairs(cell, 1), "surface : monter est refusé")
	var player := Player.new()
	player.world = world
	player.grid_pos = cell
	world.player = player
	world.add_entity(player)
	var before: float = GameClock.elapsed_points
	player._use_stairs(-1)
	_check(world.get_level() == -1, "le joueur est passé à l'étage -1")
	_check(GameClock.elapsed_points > before, "le changement d'étage coûte une action")
	_check(world.stair_link(cell) == 1, "sous-sol : la case porte une montée")
	_check(not world.use_stairs(cell, -1), "sous-sol : descendre est refusé")
	before = GameClock.elapsed_points
	player._use_stairs(1)
	_check(world.get_level() == 0, "le joueur est revenu à la surface")
	_check(GameClock.elapsed_points > before, "la remontée coûte une action")
	var plain: Vector2i = cell + Vector2i(1, 0)
	_check(not world.use_stairs(plain, -1), "une case sans escalier est refusée")
	world.queue_free()


## Escalier d'un plan de surface et de son sous-sol : même case locale, tout le sol atteignable (surface depuis la porte,
## sous-sol depuis l'escalier).
func _check_stair_pair(surface_id: String, basement_id: String, stair: Vector2i) -> void:
	var surface_plan: int = MapgenDB.plan_by_id(surface_id)
	var basement_plan: int = MapgenDB.plan_by_id(basement_id)
	_check(surface_plan >= 0 and basement_plan >= 0, "plans %s / %s présents" % [surface_id, basement_id])
	if surface_plan < 0 or basement_plan < 0:
		return
	var plan_index: int = stair.y * Chunk.SIZE + stair.x
	_check(TerrainDB.z_link(MapgenDB.terrain_at(surface_plan, plan_index)) == -1, "%s : descente à la case %s" % [surface_id, stair])
	_check(TerrainDB.z_link(MapgenDB.terrain_at(basement_plan, plan_index)) == 1, "%s : montée à la même case %s" % [basement_id, stair])
	_check(_plan_floor_reachable(basement_plan, stair, false), "%s : tout le sol est atteignable depuis l'escalier" % basement_id)
	var front: Vector2i = _front_door_outside(surface_plan)
	_check(front.x >= 0 and _plan_floor_reachable(surface_plan, front, true),
			"%s : tout le sol est atteignable depuis la porte (escalier compris)" % surface_id)


## Case devant la porte de façade (la porte la plus au sud) du plan non tourné ; (-1, -1) s'il n'y en a pas.
func _front_door_outside(plan: int) -> Vector2i:
	var door: int = TerrainDB.index_of("t_door")
	var best := Vector2i(-1, -1)
	for y in Chunk.SIZE:
		for x in Chunk.SIZE:
			if MapgenDB.terrain_at(plan, y * Chunk.SIZE + x) == door:
				best = Vector2i(x, y)
	if best.y < 0 or best.y + 1 >= Chunk.SIZE:
		return Vector2i(-1, -1)
	return best + Vector2i.DOWN


## Toutes les cases praticables du plan sont-elles atteignables depuis `start` (4 directions) ? `nature_walkable` : au sol,
## les « . » gardent le terrain naturel (praticable) ; en sous-sol, ils deviennent de la roche.
func _plan_floor_reachable(plan: int, start: Vector2i, nature_walkable: bool) -> bool:
	var walk := PackedByteArray()
	walk.resize(Chunk.CELLS)
	var visited := PackedByteArray()
	visited.resize(Chunk.CELLS)
	for y in Chunk.SIZE:
		for x in Chunk.SIZE:
			var index: int = y * Chunk.SIZE + x
			var terrain: int = MapgenDB.terrain_at(plan, index)
			var open: bool = (terrain == MapgenDB.NATURE and nature_walkable) or TerrainDB.is_walkable(terrain)
			walk[index] = 1 if open and FurnitureDB.is_walkable(MapgenDB.furniture_at(plan, index)) else 0
	if start.x < 0 or start.y < 0 or start.x >= Chunk.SIZE or start.y >= Chunk.SIZE:
		return false
	var start_index: int = start.y * Chunk.SIZE + start.x
	if walk[start_index] == 0:
		return false
	var stack: Array[Vector2i] = [start]
	visited[start_index] = 1
	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = current + step
			if next.x < 0 or next.y < 0 or next.x >= Chunk.SIZE or next.y >= Chunk.SIZE:
				continue
			var next_index: int = next.y * Chunk.SIZE + next.x
			if walk[next_index] == 1 and visited[next_index] == 0:
				visited[next_index] = 1
				stack.append(next)
	for index in Chunk.CELLS:
		if walk[index] == 1 and visited[index] == 0:
			return false
	return true


func _signature(world: World) -> Array[String]:
	var out: Array[String] = []
	for m in world.monsters:
		out.append("%s@%d,%d hp=%.1f z=%d" % [m.data.id, m.grid_pos.x, m.grid_pos.y, m.hp, m.z])
	out.sort()
	return out


func _check_manager(world_seed: int) -> void:
	var world := World.new()
	world.world_seed = world_seed
	root.add_child(world)
	var spawn: Vector2i = SettlementMap.for_seed(world_seed).spawn_cell()
	world.chunks.update_around(spawn)
	_check(world.get_level() == 0 and not world.chunks.chunks.is_empty(), "départ : étage 0, chunks chargés")
	var item_cell: Vector2i = spawn + Vector2i(1, 0)
	world.add_ground_item(item_cell, Item.create("stick"))
	var before: Array[String] = _signature(world)
	var seen_before: int = world.chunks.chunks.size()
	print("       étages : %d monstres, %d chunks à la surface" % [before.size(), seen_before])

	world.chunks.set_level(-1)
	world.chunks.update_around(spawn)
	var only_below: bool = true
	for key: Vector3i in world.chunks.chunks:
		if key.z != -1:
			only_below = false
	_check(only_below and not world.chunks.chunks.is_empty(), "étage -1 : seuls des chunks z = -1 sont chargés")
	_check(world.get_level() == -1 and world.monsters.is_empty(), "étage -1 : aucun monstre de la surface (en réserve)")
	_check(world.chunks.stored_monster_count() == before.size(), "les monstres de la surface sont en réserve (%d)" % world.chunks.stored_monster_count())
	_check(world.get_ground_items(item_cell).is_empty(), "étage -1 : l'objet posé à la surface n'y est pas")
	var spawn_below := Vector3i(ChunkManager.key_of(spawn).x, ChunkManager.key_of(spawn).y, -1)
	if ChunkGenerator.level_plan(world_seed, spawn_below).is_empty():
		_check(not world.is_walkable(spawn) and world.is_opaque(spawn), "étage -1 : la case sous le départ est de la roche")
	world.add_ground_item(item_cell, Item.create("pipe"))
	_check(world.get_ground_items(item_cell).size() == 1, "un objet posé à l'étage -1 y reste")

	world.chunks.set_level(0)
	world.chunks.update_around(spawn)
	var only_surface: bool = true
	for key: Vector3i in world.chunks.chunks:
		if key.z != 0:
			only_surface = false
	_check(only_surface, "retour en surface : seuls des chunks z = 0 sont chargés")
	_check(_signature(world) == before, "retour en surface : mêmes monstres, mêmes cases, mêmes PV, z = 0")
	_check(world.get_ground_items(item_cell).size() == 1 and (world.get_ground_items(item_cell)[0] as Item).id == "stick", "retour en surface : l'objet de la surface est toujours là")
	_check(world.chunks.stored_monster_count() == 0, "la réserve est vidée après restauration")
	world.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
