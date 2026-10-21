extends SceneTree
## Test du jalon 12 (lieux sur la route : péage, barrage, poste-frontière, péage de pont ; aire de repos et relais routier). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_jalon12.gd
## Code de sortie 0 = tout est bon. Complète tests/test_worldgen_determinism.gd (structure des plans, déterminisme des régions : les lieux
## sur la route sont dans l'empreinte de région) et tests/test_jalon10.gd (lieux ordinaires).

const ROAD_PLACE_IDS: Array[String] = ["toll_plaza", "roadblock", "border_checkpoint", "road_bridge_toll"]
const ROADSIDE_PLACE_IDS: Array[String] = ["rest_area", "truck_stop"]
const PLAN_IDS: Array[String] = ["road_toll_plaza", "road_roadblock", "road_checkpoint", "road_bridge_toll", "road_rest_area",
	"road_truck_store", "road_truck_lot"]
const HALF_REGIONS: int = 3
const CHUNK_SAMPLE: int = 12   # nombre de chunks générés pour contrôler la superposition du plan à la route

var _failures: int = 0


func _initialize() -> void:
	var seeds: Array[int] = []
	for text in ["1", "42", "cataclysme", "", "-7"]:
		seeds.append(WorldRng.seed_from_text(text))
	_check_plans()
	_check_road_places(seeds)
	_check_roadside_places(seeds)
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check_plans() -> void:
	var errors: Array[String] = MapgenDB.errors()
	_check(errors.is_empty(), "plans : aucune erreur de chargement %s" % str(errors))
	for id in PLAN_IDS:
		_check(MapgenDB.plan_by_id(id) >= MapgenDB.plan_count(), "plan %s chargé (après les plans de maison)" % id)
	# Les plans « sur la route » gardent la chaussée : ils laissent de la nature (NATURE) au centre de la route.
	for id in ["road_toll_plaza", "road_roadblock", "road_checkpoint", "road_bridge_toll"]:
		var plan: int = MapgenDB.plan_by_id(id)
		if plan < 0:
			continue
		var nature: int = 0
		for i in MapgenDB.SIZE * MapgenDB.SIZE:
			if MapgenDB.terrain_at(plan, i) == MapgenDB.NATURE:
				nature += 1
		_check(nature > MapgenDB.SIZE * MapgenDB.SIZE / 2, "plan %s : laisse la route visible (%d cases de nature)" % [id, nature])


func _check_road_places(seeds: Array[int]) -> void:
	var counts: Dictionary = {}
	var n_east_west: int = 0
	var n_north_south: int = 0
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var fresh := SettlementMap.new(world_seed)
		var specials: SpecialMap = settlement.specials()
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		_check(specials.errors().is_empty(), "seed %d : specials.json valide %s" % [world_seed, str(specials.errors())])
		for id in ROAD_PLACE_IDS:
			_check(specials.place_ids().has(id) and specials.place_is_on_road(id), "seed %d : lieu « %s » défini en accès on_road" % [world_seed, id])
		var bad_road: int = 0
		var bad_axis: int = 0
		var bad_border: int = 0
		var bad_site: int = 0
		var bad_plan: int = 0
		var bad_spacing: int = 0
		var same: bool = true
		var sampled: int = 0
		var bad_chunk: int = 0
		var region_size: int = SettlementMap.region_size_cells()
		for ry in range(-HALF_REGIONS, HALF_REGIONS + 1):
			for rx in range(-HALF_REGIONS, HALF_REGIONS + 1):
				var region := Vector2i(rx, ry)
				var places: Array = specials.region_road_places(region)
				if places != fresh.specials().region_road_places(region):
					same = false
				for i in places.size():
					var place: Dictionary = places[i]
					var id: String = place["id"]
					var cell: Vector2i = place["cell"]
					var rot: int = place["rot"]
					var axis: int = place["axis"]
					counts[id] = int(counts.get(id, 0)) + 1
					if axis == 0:
						n_east_west += 1
					else:
						n_north_south += 1
					# Une vraie route entre villes, droite, SANS embranchement de piste (road_mask inclut les pistes).
					if not settlement.is_wild_road(cell) or settlement.cell_type(cell) != SettlementMap.CellType.ROAD:
						bad_road += 1
					var expected: int = (SettlementMap.DIR_N | SettlementMap.DIR_S) if axis == 1 else (SettlementMap.DIR_E | SettlementMap.DIR_W)
					if settlement.road_mask(cell) != expected:
						bad_road += 1
					if rot % 2 != axis:
						bad_axis += 1
					var local: Vector2i = cell - region * region_size
					if local.x <= 0 or local.y <= 0 or local.x >= region_size - 1 or local.y >= region_size - 1:
						bad_border += 1
					var kind: int = world_map.cell_kind(cell)
					if not specials.biome_ok(id, kind):
						bad_site += 1
					match specials.place_road_site(id):
						"bridge":
							if not WorldMap.is_water(kind):
								bad_site += 1
						"bridge_end":
							var ends: Array[Vector2i] = []
							ends.append(Vector2i.LEFT if axis == 0 else Vector2i.UP)
							ends.append(Vector2i.RIGHT if axis == 0 else Vector2i.DOWN)
							if WorldMap.is_water(kind) or not (WorldMap.is_water(world_map.cell_kind(cell + ends[0])) \
									or WorldMap.is_water(world_map.cell_kind(cell + ends[1]))):
								bad_site += 1
					var info: Dictionary = settlement.cell_plan(cell)
					if info.is_empty() or int(info["rot"]) != rot or not MapgenDB.plan_id(int(info["plan"])).begins_with("road_"):
						bad_plan += 1
					for j in range(i + 1, places.size()):
						var d: Vector2i = (places[j]["cell"] as Vector2i) - cell
						if maxi(absi(d.x), absi(d.y)) < SpecialMap.ROAD_SPACING:
							bad_spacing += 1
					if sampled < CHUNK_SAMPLE:
						sampled += 1
						if not _chunk_has_overlay(world_seed, cell):
							bad_chunk += 1
		_check(same, "seed %d : lieux sur la route identiques sur une instance neuve" % world_seed)
		_check(bad_road == 0, "seed %d : chaque lieu est sur une route entre villes droite, sans piste branchée (%d anomalies)" % [world_seed, bad_road])
		_check(bad_axis == 0, "seed %d : rotation alignée sur l'axe de la route (%d anomalies)" % [world_seed, bad_axis])
		_check(bad_border == 0, "seed %d : jamais sur la bordure de la région (%d anomalies)" % [world_seed, bad_border])
		_check(bad_site == 0, "seed %d : biome et road_site respectés (pont, bout de pont) (%d anomalies)" % [world_seed, bad_site])
		_check(bad_plan == 0, "seed %d : cell_plan() renvoie le plan du lieu (%d anomalies)" % [world_seed, bad_plan])
		_check(bad_spacing == 0, "seed %d : espacement minimal de %d cellules (%d anomalies)" % [world_seed, SpecialMap.ROAD_SPACING, bad_spacing])
		_check(bad_chunk == 0, "seed %d : %d chunks générés contiennent le plan (clôture, mur ou mobilier) sur la chaussée : %d anomalies" % [world_seed, sampled, bad_chunk])
	print("       lieux sur la route : %s (routes est-ouest %d, nord-sud %d)" % [str(counts), n_east_west, n_north_south])
	for id in ROAD_PLACE_IDS:
		if int(counts.get(id, 0)) == 0:
			print("  AVERTISSEMENT - aucun « %s » sur 5 seeds x 7 x 7 régions (rare : chance, biomes, road_site ou min_town_distance à régler)" % id)


## Le chunk généré contient-il des cases du plan (mur, porte, clôture) ou du mobilier posé sur la route ?
func _chunk_has_overlay(world_seed: int, cell: Vector2i) -> bool:
	var key := Vector3i(cell.x, cell.y, 0)
	var terrain: PackedByteArray = ChunkGenerator.generate(world_seed, key)
	var furniture: PackedByteArray = ChunkGenerator.generate_furniture(world_seed, key)
	var wall: int = TerrainDB.index_of("t_wall_house")
	var fence: int = TerrainDB.index_of("t_fence")
	var structure: bool = false
	for i in Chunk.CELLS:
		if terrain[i] == wall or terrain[i] == fence:
			structure = true
			break
	var has_furniture: bool = false
	for i in Chunk.CELLS:
		if furniture[i] != 0:
			has_furniture = true
			break
	return structure and has_furniture


func _check_roadside_places(seeds: Array[int]) -> void:
	var counts: Dictionary = {}
	for world_seed in seeds:
		var specials: SpecialMap = SettlementMap.for_seed(world_seed).specials()
		for id in ROADSIDE_PLACE_IDS:
			_check(specials.place_ids().has(id) and specials.place_needs_road(id), "seed %d : lieu « %s » défini, accès route seul" % [world_seed, id])
		var bad: int = 0
		for ry in range(-HALF_REGIONS, HALF_REGIONS + 1):
			for rx in range(-HALF_REGIONS, HALF_REGIONS + 1):
				for place: Dictionary in specials.region_places(Vector2i(rx, ry)):
					var id: String = place["id"]
					if not ROADSIDE_PLACE_IDS.has(id):
						continue
					counts[id] = int(counts.get(id, 0)) + 1
					var footprint: Array = place["cells"]
					if footprint.size() != (2 if id == "truck_stop" else 1):
						bad += 1
					if not specials.front_touches_road(footprint, int(place["rot"])):
						bad += 1
		_check(bad == 0, "seed %d : aire de repos et relais routier : empreinte et route devant la façade (%d anomalies)" % [world_seed, bad])
	print("       lieux au bord de la route : %s" % str(counts))
	for id in ROADSIDE_PLACE_IDS:
		if int(counts.get(id, 0)) == 0:
			print("  AVERTISSEMENT - aucun « %s » sur 5 seeds x 7 x 7 régions (rare : chance ou distances à régler)" % id)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
