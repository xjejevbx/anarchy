extends SceneTree
## Test de l'axe vertical (préparation des étages, jalon 6b). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_vertical.gd
## Code de sortie 0 = tout est bon. Vérifie : terrains verticaux, étages sans plan (roche sous la surface, vide au-dessus), hook des plans
## d'étage, escaliers (descente / montée à la même case, refus hors escalier), RNG à 4 coordonnées compatible avec l'existant, un seul étage
## chargé à la fois (ChunkManager.level), monstres et objets au sol rangés par étage.

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


## Escaliers (jalon 8) : la descente de l'hôpital et la montée du sous-sol occupent la MÊME case du plan,
## puis un monde réel descend et remonte par deltas de terrain (sans dépendre de l'emplacement des hôpitaux).
func _check_stairs() -> void:
	var surface_plan: int = MapgenDB.plan_by_id("urban_hospital")
	var basement_plan: int = MapgenDB.plan_by_id("urban_hospital@-1")
	_check(surface_plan >= 0 and basement_plan >= 0, "plans d'escalier de l'hôpital présents")
	if surface_plan < 0 or basement_plan < 0:
		return
	var stair := Vector2i(9, 15)
	var plan_index: int = stair.y * Chunk.SIZE + stair.x
	_check(TerrainDB.z_link(MapgenDB.terrain_at(surface_plan, plan_index)) == -1, "hôpital : descente à la case (9, 15)")
	_check(TerrainDB.z_link(MapgenDB.terrain_at(basement_plan, plan_index)) == 1, "sous-sol : montée à la même case (9, 15)")

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
