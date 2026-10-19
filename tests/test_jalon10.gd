extends SceneTree
## Test du jalon 10 (climats, îles, zones, accès des lieux : pistes, héliports, jetées). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_jalon10.gd
## Code de sortie 0 = tout est bon. Complète tests/test_worldgen_determinism.gd (qui couvre le déterminisme des lieux et des pistes
## via l'empreinte des régions).

const CLIMATE_HALF: int = 60000
const CLIMATE_STEP: int = 3000
const PLACE_HALF_REGIONS: int = 3   # régions de -3 à +3 (7 x 7)

var _failures: int = 0


func _initialize() -> void:
	var seeds: Array[int] = []
	for text in ["1", "42", "cataclysme", "", "-7"]:
		seeds.append(WorldRng.seed_from_text(text))
	_check_terrains()
	_check_climates(seeds)
	_check_islands(seeds)
	_check_places(seeds)
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check_terrains() -> void:
	for id in ["t_helipad", "t_pier"]:
		_check(TerrainDB.has_id(id), "terrain %s défini" % id)
		if TerrainDB.has_id(id):
			var index: int = TerrainDB.index_of(id)
			_check(TerrainDB.is_walkable(index) and TerrainDB.swim_depth(index) == TerrainDB.SWIM_NONE, "%s : praticable à pied, sans nage" % id)
	var errors: Array[String] = MapgenDB.errors()
	_check(errors.is_empty(), "plans : aucune erreur de chargement %s" % str(errors))
	for id in ["bunker_entrance", "desert_outpost", "lighthouse", "oil_platform"]:
		_check(MapgenDB.plan_by_id(id) >= 0, "plan %s chargé" % id)


func _check_climates(seeds: Array[int]) -> void:
	var ids: Array[String] = []
	for key: String in WorldMap.Climate.keys():
		ids.append(key.to_lower())
	_check(ids == WorldMap.CLIMATE_IDS, "CLIMATE_IDS suit l'ordre de WorldMap.Climate")
	var counts: Array[int] = [0, 0, 0]
	for world_seed in seeds:
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		var fresh := WorldMap.new(world_seed)
		var same: bool = true
		var coherent: bool = true
		var cell_ok: bool = true
		for y in range(-CLIMATE_HALF, CLIMATE_HALF, CLIMATE_STEP):
			for x in range(-CLIMATE_HALF, CLIMATE_HALF, CLIMATE_STEP):
				var cell := Vector2i(x, y)
				var climate: int = world_map.climate_at(cell)
				counts[climate] += 1
				if climate != fresh.climate_at(cell):
					same = false
				# La nature d'une case de terre chaude / froide / tempérée doit s'accorder avec le climat.
				match world_map.kind_at(cell):
					WorldMap.Kind.JUNGLE, WorldMap.Kind.DESERT, WorldMap.Kind.SAVANNA:
						coherent = coherent and climate == WorldMap.Climate.HOT
					WorldMap.Kind.TUNDRA, WorldMap.Kind.TAIGA:
						coherent = coherent and climate == WorldMap.Climate.COLD
					WorldMap.Kind.PLAIN, WorldMap.Kind.FOREST, WorldMap.Kind.SWAMP:
						coherent = coherent and climate == WorldMap.Climate.TEMPERATE
				var macro := Vector2i(floori(float(x) / Chunk.SIZE), floori(float(y) / Chunk.SIZE))
				if world_map.cell_climate(macro) != world_map.climate_at(macro * Chunk.SIZE + WorldMap.CELL_CENTER):
					cell_ok = false
		_check(same, "seed %d : climat identique sur une instance neuve" % world_seed)
		_check(coherent, "seed %d : nature des terres chaudes / froides / tempérées cohérente avec le climat" % world_seed)
		_check(cell_ok, "seed %d : cell_climate = climat du centre de la cellule" % world_seed)
	for climate in 3:
		_check(counts[climate] > 0, "climat « %s » présent dans le relevé" % WorldMap.climate_name(climate))
	print("       relevé climat : tempéré %d, chaud %d, froid %d (échantillons)" % [counts[0], counts[1], counts[2]])


func _check_islands(seeds: Array[int]) -> void:
	var seeds_with_island: int = 0
	for world_seed in seeds:
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var found: bool = settlement.has_island_spawn()
		var fresh_settlement := SettlementMap.new(world_seed)
		_check(found == fresh_settlement.has_island_spawn() and settlement.island_spawn_cell() == fresh_settlement.island_spawn_cell(),
			"seed %d : départ sur une île identique sur une instance neuve" % world_seed)
		# Les villes ne sont jamais sur une petite île.
		var towns_on_island: int = 0
		for ry in range(-PLACE_HALF_REGIONS, PLACE_HALF_REGIONS + 1):
			for rx in range(-PLACE_HALF_REGIONS, PLACE_HALF_REGIONS + 1):
				for town: Dictionary in settlement.towns_in_region(Vector2i(rx, ry)):
					if world_map.is_small_island(town["center"]):
						towns_on_island += 1
		_check(towns_on_island == 0, "seed %d : aucune ville sur une petite île" % world_seed)
		if not found:
			print("       seed %d : aucune île de départ trouvée près de l'origine" % world_seed)
			continue
		seeds_with_island += 1
		var spawn: Vector2i = settlement.island_spawn_cell()
		var macro := Vector2i(floori(float(spawn.x) / Chunk.SIZE), floori(float(spawn.y) / Chunk.SIZE))
		var size: int = world_map.island_size(macro)
		_check(size >= world_map.island_spawn_min_cells() and size < world_map.island_max_cells(),
			"seed %d : île de départ de %d cellules (entre %d et %d)" % [world_seed, size, world_map.island_spawn_min_cells(), world_map.island_max_cells() - 1])
		var data: PackedByteArray = ChunkGenerator.generate(world_seed, Vector3i(macro.x, macro.y, 0))
		var terrain: int = data[ChunkManager.index_of(spawn)]
		_check(TerrainDB.is_walkable(terrain) and TerrainDB.swim_depth(terrain) == TerrainDB.SWIM_NONE,
			"seed %d : case de départ de l'île %s praticable à pied (%s)" % [world_seed, spawn, TerrainDB.id_of(terrain)])
		# Cohérence de l'île : toutes ses cellules ont la même taille (instance neuve, autre cellule d'abord) et sont cernées d'océan.
		var cells: Array[Vector2i] = world_map.island_cells(macro)
		var inside: Dictionary = {}
		for c in cells:
			inside[c] = true
		var fresh_map := WorldMap.new(world_seed)
		var consistent: bool = cells.size() == size
		var surrounded: bool = true
		for i in range(cells.size() - 1, -1, -1):  # de la dernière à la première : un autre ordre de découverte
			if fresh_map.island_size(cells[i]) != size:
				consistent = false
		for c in cells:
			for dir in WorldMap.DIRS4:
				var next: Vector2i = c + dir
				if not inside.has(next) and not WorldMap.is_ocean(world_map.cell_kind(next)):
					surrounded = false
		_check(consistent, "seed %d : toutes les cellules de l'île ont la même taille, dans un autre ordre aussi" % world_seed)
		_check(surrounded, "seed %d : l'île est entièrement entourée d'océan" % world_seed)
		print("       seed %d : île de départ en %s (%d cellules)" % [world_seed, spawn, size])
	_check(seeds_with_island > 0, "au moins une seed offre une île de départ près de l'origine (sinon régler planet.islands de biomes.json)")


func _check_places(seeds: Array[int]) -> void:
	var counts: Dictionary = {}
	var access_counts: Dictionary = {}
	var dirt: int = TerrainDB.index_of("t_dirt")
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var specials: SpecialMap = settlement.specials()
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		var bad_zone: int = 0
		var bad_climate: int = 0
		var bad_access: int = 0
		var bad_track: int = 0
		var bad_terrain: int = 0
		var terrain_checked: int = 0
		var helipad: int = TerrainDB.index_of("t_helipad")
		for ry in range(-PLACE_HALF_REGIONS, PLACE_HALF_REGIONS + 1):
			for rx in range(-PLACE_HALF_REGIONS, PLACE_HALF_REGIONS + 1):
				for place: Dictionary in specials.region_places(Vector2i(rx, ry)):
					var id: String = place["id"]
					var footprint: Array = place["cells"]
					var rot: int = place["rot"]
					var access: String = place["access"]
					counts[id] = int(counts.get(id, 0)) + 1
					access_counts[access] = int(access_counts.get(access, 0)) + 1
					if not specials.zone_ok(id, footprint):
						bad_zone += 1
					if not specials.climate_ok(id, footprint):
						bad_climate += 1
					if not specials.place_access_options(id).has(access):
						bad_access += 1
					match access:
						"road":
							if not specials.front_touches_road(footprint, rot):
								bad_access += 1
						"pier":
							if not specials.front_water(id, footprint, rot):
								bad_access += 1
						"helipad":
							var has_pad: bool = false
							for cell: Vector2i in footprint:
								var info: Dictionary = settlement.special_plan(cell)
								if not info.is_empty() and MapgenDB.has_terrain(int(info["plan"]), helipad):
									has_pad = true
							if not has_pad:
								bad_access += 1
						"track":
							if not _track_is_sound(settlement, specials, place):
								bad_track += 1
							else:
								var track_cells: Array = place["track_cells"]
								if not track_cells.is_empty() and terrain_checked < 20:
									terrain_checked += 1
									var cell: Vector2i = track_cells[0]
									var data: PackedByteArray = ChunkGenerator.generate(world_seed, Vector3i(cell.x, cell.y, 0))
									if data[12 * Chunk.SIZE + 12] != dirt:
										bad_terrain += 1
					# Zone « pleine mer » : aucune terre à moins de min_land_distance cellules de l'empreinte.
					if specials.place_zone(id) == "open_ocean":
						for cell: Vector2i in footprint:
							if world_map.cell_kind(cell) != WorldMap.Kind.OCEAN_DEEP:
								bad_zone += 1
		_check(bad_zone == 0, "seed %d : zones respectées (île, côte, pleine mer) : %d anomalies" % [world_seed, bad_zone])
		_check(bad_climate == 0, "seed %d : climats respectés : %d anomalies" % [world_seed, bad_climate])
		_check(bad_access == 0, "seed %d : accès respectés (route, jetée sur l'eau, héliport dans le plan) : %d anomalies" % [world_seed, bad_access])
		_check(bad_track == 0, "seed %d : pistes continues de la porte du lieu à une route, connexions symétriques : %d anomalies" % [world_seed, bad_track])
		_check(bad_terrain == 0, "seed %d : cellules de piste dessinées en terre au centre (%d contrôlées) : %d anomalies" % [world_seed, terrain_checked, bad_terrain])
	for id in ["bunker_entrance", "desert_outpost", "lighthouse", "hermit_cabin", "oil_platform"]:
		var n: int = int(counts.get(id, 0))
		if n == 0:
			print("  AVERTISSEMENT - aucun lieu « %s » sur 5 seeds x 7 x 7 régions (rare ou réglage à revoir : chance, attempts, biomes)" % id)
		else:
			print("       lieux « %s » : %d" % [id, n])
	print("       accès tirés : %s" % str(access_counts))


## Piste d'un lieu : démarre devant une porte du lieu (ou aucune piste si la porte donne déjà sur une route), cellules voisines deux à
## deux et reliées dans les deux sens, finit contre une route dont l'embranchement (road_mask) est dessiné.
func _track_is_sound(settlement: SettlementMap, specials: SpecialMap, place: Dictionary) -> bool:
	var id: String = place["id"]
	var footprint: Array = place["cells"]
	var cells: Array = place["track_cells"]
	var fronts: Array = specials.door_fronts(id, footprint, int(place["rot"]))
	if cells.is_empty():
		for pair: Dictionary in fronts:
			if settlement.cell_type(pair["to"], true, false) == SettlementMap.CellType.ROAD:
				return true
		return false
	var starts: bool = false
	for pair: Dictionary in fronts:
		if pair["to"] == cells[0]:
			starts = true
	if not starts:
		return false
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var mask: int = settlement.track_mask(cell)
		if mask < 0:
			return false
		if i + 1 < cells.size():
			var step: Vector2i = (cells[i + 1] as Vector2i) - cell
			var forward: int = SettlementMap.DIRS.find(step)
			var backward: int = SettlementMap.DIRS.find(-step)
			if forward < 0 or (mask & (1 << forward)) == 0 or (settlement.track_mask(cells[i + 1]) & (1 << backward)) == 0:
				return false
	var last: Vector2i = cells[cells.size() - 1]
	var last_mask: int = settlement.track_mask(last)
	for i in SettlementMap.DIRS.size():
		var neighbor: Vector2i = last + SettlementMap.DIRS[i]
		if (last_mask & (1 << i)) != 0 and settlement.cell_type(neighbor, true, false) == SettlementMap.CellType.ROAD:
			return (settlement.road_mask(neighbor) & (1 << ((i + 2) % 4))) != 0
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
