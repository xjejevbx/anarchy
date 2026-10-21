class_name ChunkGenerator
extends RefCounted
## Génère le terrain d'un chunk. FONCTION PURE de (seed, clé de chunk, mode) : aucune dépendance à l'ordre
## de génération, aucun état global (docs/WORLD_GEN.md §3). Monde normal : biomes, lacs et rivières (WorldMap), puis villes
## et rues par-dessus (SettlementMap). Maisons, routes entre villes, lieux spéciaux et pistes (jalon 10) se posent par-dessus le terrain naturel.
## Jalon 12 : un lieu « sur la route » (péage, barrage...) se pose PAR-DESSUS la chaussée de sa cellule (ses '.' gardent la route).

# --- Arène de test (ancienne carte fermée 60 x 40, option debug USE_TEST_ARENA) ---
const ARENA_WIDTH: int = 60
const ARENA_HEIGHT: int = 40
const SPAWN_POS: Vector2i = Vector2i(5, 5)    # départ du joueur dans l'arène
const ARENA_CLEAR_RADIUS: float = 3.5         # pas d'arbre autour du départ
const ARENA_TREE_DENSITY: float = 0.12


## Un octet par case (index TerrainDB), rangées de haut en bas : indice = y local * 24 + x local.
static func generate(world_seed: int, key: Vector3i, arena: bool = false) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(Chunk.CELLS)
	if arena:
		_fill_arena(world_seed, key, data)
		return data
	var world_map: WorldMap = WorldMap.for_seed(world_seed)
	var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
	var cell_coord := Vector2i(key.x, key.y)  # une cellule macro = un chunk
	var cell_type: int = settlement.cell_type(cell_coord) if key.z == 0 else SettlementMap.CellType.NONE
	var mask: int = settlement.road_mask(cell_coord) if cell_type == SettlementMap.CellType.ROAD else 0
	var wild_road: bool = cell_type == SettlementMap.CellType.ROAD and settlement.is_wild_road(cell_coord)
	var track_mask: int = settlement.track_mask(cell_coord) if cell_type == SettlementMap.CellType.NONE and key.z == 0 else -1
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


static func _fill_arena(world_seed: int, key: Vector3i, data: PackedByteArray) -> void:
	var grass: int = TerrainDB.index_of("t_grass")
	var tree: int = TerrainDB.index_of("t_tree")
	var wall: int = TerrainDB.index_of("t_wall_arena")
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var cell := Vector2i(key.x * Chunk.SIZE + lx, key.y * Chunk.SIZE + ly)
			var index: int = grass
			if cell.x <= 0 or cell.y <= 0 or cell.x >= ARENA_WIDTH - 1 or cell.y >= ARENA_HEIGHT - 1:
				index = wall
			elif Vector2(cell).distance_to(Vector2(SPAWN_POS)) > ARENA_CLEAR_RADIUS \
					and WorldRng.chance(world_seed, WorldRng.LAYER_TERRAIN, cell.x, cell.y, key.z, ARENA_TREE_DENSITY):
				index = tree
			data[ly * Chunk.SIZE + lx] = index


## Empreinte (FNV-1a 64 bits) du contenu d'un chunk : sert au test de déterminisme.
static func fingerprint(world_seed: int, key: Vector3i, arena: bool = false) -> int:
	var h: int = -3750763034362895579
	for byte: int in generate(world_seed, key, arena):
		h = (h ^ byte) * 1099511628211
	for byte: int in generate_furniture(world_seed, key, arena):
		h = (h ^ byte) * 1099511628211
	return h


## Mobilier d'un chunk (un octet par case : 0 = rien, sinon index FurnitureDB). FONCTION PURE comme generate().
static func generate_furniture(world_seed: int, key: Vector3i, arena: bool = false) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(Chunk.CELLS)
	if arena or key.z != 0:
		return data
	var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
	var house: Dictionary = settlement.cell_plan(Vector2i(key.x, key.y))
	if house.is_empty():
		return data
	var plan: int = house["plan"]
	var rot: int = house["rot"]
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			data[ly * Chunk.SIZE + lx] = MapgenDB.furniture_at(plan, MapgenDB.plan_index(lx, ly, rot))
	return data
