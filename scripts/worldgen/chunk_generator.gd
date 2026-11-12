class_name ChunkGenerator
extends RefCounted
## Génère le terrain d'un chunk. FONCTION PURE de (seed, clé de chunk, mode) : aucune dépendance à l'ordre
## de génération, aucun état global (docs/WORLD_GEN.md §3). Monde normal : biomes, lacs et rivières (WorldMap), puis villes
## et rues par-dessus (SettlementMap). Maisons, routes entre villes, lieux spéciaux et pistes (jalon 10) se posent par-dessus le terrain naturel.
## Jalon 12 : un lieu « sur la route » (péage, barrage...) se pose PAR-DESSUS la chaussée de sa cellule (ses '.' gardent la route).
## Jalon 6b (axe vertical) : un chunk à z != 0 n'est PLUS la copie de la surface. Étage z < 0 : roche pleine (t_rock). Étage z > 0 : vide (t_air).
## Un lieu définit ses étages avec des plans nommés "<id du plan de surface>@<z>" (ex. "urban_hospital@-1") : le plan (même rotation que
## celui de la surface) se superpose à la roche ou au vide ; ses '.' gardent la roche / le vide. Terrain ET mobilier suivent la même règle.
## Arène de test : géométrie fixe multi-zones/multi-étages définie dans scripts/worldgen/test_arena.gd (TestArena).

# --- Arène de test (menu principal > « Arène de test ») : toute la géométrie est dans TestArena. ---
const TEST_ARENA = preload("res://scripts/worldgen/test_arena.gd")   # évite de dépendre du cache des class_name
const SPAWN_POS: Vector2i = Vector2i(5, 5)    # départ de l'arène (voir TestArena.SPAWN_POS)


## Un octet par case (index TerrainDB), rangées de haut en bas : indice = y local * 24 + x local.
static func generate(world_seed: int, key: Vector3i, arena: bool = false) -> PackedByteArray:
	if arena:
		return TEST_ARENA.generate(world_seed, key)
	var data := PackedByteArray()
	data.resize(Chunk.CELLS)
	if key.z != 0:
		_fill_level(world_seed, key, data)
		return data
	var world_map: WorldMap = WorldMap.for_seed(world_seed)
	var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
	var cell_coord := Vector2i(key.x, key.y)  # une cellule macro = un chunk
	var cell_type: int = settlement.cell_type(cell_coord)
	var mask: int = settlement.road_mask(cell_coord) if cell_type == SettlementMap.CellType.ROAD else 0
	var wild_road: bool = cell_type == SettlementMap.CellType.ROAD and settlement.is_wild_road(cell_coord)
	var track_mask: int = settlement.track_mask(cell_coord) if cell_type == SettlementMap.CellType.NONE else -1
	var spawn: Vector2i = settlement.spawn_cell()
	var house: Dictionary = settlement.cell_plan(cell_coord) \
			if cell_type == SettlementMap.CellType.LOT or cell_type == SettlementMap.CellType.SPECIAL \
				or cell_type == SettlementMap.CellType.ROAD else {}
	var house_plan: int = int(house.get("plan", -1))
	var house_rot: int = int(house.get("rot", 0))
	var near_spawn: bool = absi(ChunkManager.key_of(spawn).x - key.x) <= 1 and absi(ChunkManager.key_of(spawn).y - key.y) <= 1
	var grass: int = TerrainDB.index_of("t_grass")
	var tree: int = TerrainDB.index_of("t_tree")
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var cell := Vector2i(key.x * Chunk.SIZE + lx, key.y * Chunk.SIZE + ly)
			var index: int = world_map.terrain_at(cell, key.z)
			match cell_type:
				SettlementMap.CellType.ROAD:
					index = settlement.road_terrain(mask, lx, ly, index, wild_road)
				SettlementMap.CellType.LOT, SettlementMap.CellType.YARD, SettlementMap.CellType.SPECIAL:
					index = settlement.lot_terrain(index, cell)
			if track_mask >= 0:
				index = settlement.track_terrain(track_mask, lx, ly, index)
			if house_plan >= 0:
				var plan_terrain: int = MapgenDB.terrain_at(house_plan, MapgenDB.plan_index(lx, ly, house_rot))
				if plan_terrain != MapgenDB.NATURE:
					index = plan_terrain
			if near_spawn and index == tree and Vector2(cell).distance_to(Vector2(spawn)) <= WorldMap.SPAWN_CLEAR_RADIUS:
				index = grass  # le point de départ est dégagé
			data[ly * Chunk.SIZE + lx] = index
	return data


# --- Étages (axe vertical) ---

## {plan: indice MapgenDB, rot} du plan d'étage « <id du plan de surface>@<z> » de ce chunk, {} s'il n'y en a pas.
static func level_plan(world_seed: int, key: Vector3i) -> Dictionary:
	var info: Dictionary = SettlementMap.for_seed(world_seed).cell_plan(Vector2i(key.x, key.y))
	if info.is_empty():
		return {}
	var plan: int = MapgenDB.plan_by_id("%s@%d" % [MapgenDB.plan_id(int(info["plan"])), key.z])
	if plan < 0:
		return {}
	return {"plan": plan, "rot": int(info["rot"])}


## Étage z != 0 : roche pleine sous la surface, vide au-dessus, plus le plan d'étage du lieu s'il en a un.
static func _fill_level(world_seed: int, key: Vector3i, data: PackedByteArray) -> void:
	var base: int = TerrainDB.index_of("t_rock" if key.z < 0 else "t_air")
	data.fill(base)
	var info: Dictionary = level_plan(world_seed, key)
	if info.is_empty():
		return
	var plan: int = info["plan"]
	var rot: int = info["rot"]
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var t: int = MapgenDB.terrain_at(plan, MapgenDB.plan_index(lx, ly, rot))
			if t != MapgenDB.NATURE:
				data[ly * Chunk.SIZE + lx] = t


## Empreinte (FNV-1a 64 bits) du contenu d'un chunk : sert au test de déterminisme.
static func fingerprint(world_seed: int, key: Vector3i, arena: bool = false) -> int:
	var h: int = -3750763034362895579
	for byte: int in generate(world_seed, key, arena):
		h = (h ^ byte) * 1099511628211
	for byte: int in generate_furniture(world_seed, key, arena):
		h = (h ^ byte) * 1099511628211
	return h


## Mobilier d'un chunk (un octet par case : 0 = rien, sinon index FurnitureDB). FONCTION PURE comme generate().
## À z != 0 : seulement celui du plan d'étage du lieu (voir level_plan).
static func generate_furniture(world_seed: int, key: Vector3i, arena: bool = false) -> PackedByteArray:
	if arena:
		return TEST_ARENA.generate_furniture(key)
	var data := PackedByteArray()
	data.resize(Chunk.CELLS)
	var plan: int
	var rot: int
	if key.z != 0:
		var level: Dictionary = level_plan(world_seed, key)
		if level.is_empty():
			return data
		plan = level["plan"]
		rot = level["rot"]
	else:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var house: Dictionary = settlement.cell_plan(Vector2i(key.x, key.y))
		if house.is_empty():
			return data
		plan = house["plan"]
		rot = house["rot"]
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			data[ly * Chunk.SIZE + lx] = MapgenDB.furniture_at(plan, MapgenDB.plan_index(lx, ly, rot))
	return data
