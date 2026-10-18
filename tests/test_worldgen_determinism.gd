extends SceneTree
## Test de la génération du monde (docs/WORLD_GEN.md §3 et §5.1, jalons 1-5 et 9). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_worldgen_determinism.gd
## Code de sortie 0 = tout est bon. Affiche aussi la répartition des biomes (pour régler data/worldgen/biomes.json).

const RANGE: int = 4          # chunks de -4 à +4 dans les deux axes (81 chunks)
const SURVEY_HALF: int = 3000 # relevé des biomes : de -3000 à +3000 cases
const SURVEY_STEP: int = 40   # un échantillon toutes les 40 cases (150 x 150)
const PLANET_HALF: int = 60000 # relevé planétaire (jalon 9) : de -60000 à +60000 cases
const PLANET_STEP: int = 500   # un échantillon toutes les 500 cases (240 x 240)

var _failures: int = 0


func _initialize() -> void:
	var seeds: Array[int] = []
	for text in ["1", "42", "cataclysme", "", "-7"]:
		seeds.append(WorldRng.seed_from_text(text))
	var keys: Array[Vector3i] = []
	for y in range(-RANGE, RANGE + 1):
		for x in range(-RANGE, RANGE + 1):
			keys.append(Vector3i(x, y, 0))

	# --- Ordre des natures de case : WorldMap.Kind = RouteMap.KIND_IDS = "kinds" de biomes.json ---
	_check_kind_order()

	# --- Déterminisme des chunks (3 ordres de génération, 2 passes) ---
	for world_seed in seeds:
		var in_order: Dictionary = _fingerprints(world_seed, keys)
		var reversed_keys: Array[Vector3i] = keys.duplicate()
		reversed_keys.reverse()
		var by_distance: Array[Vector3i] = keys.duplicate()
		by_distance.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			return a.x * a.x + a.y * a.y < b.x * b.x + b.y * b.y)
		_check(in_order == _fingerprints(world_seed, reversed_keys), "seed %d : ordre normal = ordre inversé" % world_seed)
		_check(in_order == _fingerprints(world_seed, by_distance), "seed %d : ordre normal = ordre par distance" % world_seed)
		_check(in_order == _fingerprints(world_seed, keys), "seed %d : deux générations identiques" % world_seed)
	_check(_fingerprints(seeds[0], keys) != _fingerprints(seeds[1], keys), "seeds 1 et 42 : mondes différents")

	# --- Carte macro : même résultat avec une instance neuve (rien ne dépend d'un état partagé) ---
	for world_seed in seeds:
		var cached: WorldMap = WorldMap.for_seed(world_seed)
		var fresh := WorldMap.new(world_seed)
		var same: bool = cached.spawn_cell() == fresh.spawn_cell()
		for y in range(-12, 13):
			for x in range(-12, 13):
				if cached.cell_kind(Vector2i(x, y)) != fresh.cell_kind(Vector2i(x, y)):
					same = false
		_check(same, "seed %d : carte macro et départ identiques sur une instance neuve" % world_seed)

	# --- Point de départ (lisière d'une ville si possible) : praticable, hors de l'eau, déterministe ---
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var spawn: Vector2i = settlement.spawn_cell()
		_check(spawn == SettlementMap.new(world_seed).spawn_cell(), "seed %d : départ identique sur une instance neuve" % world_seed)
		var spawn_kind: int = WorldMap.for_seed(world_seed).kind_at(spawn)
		_check(not WorldMap.is_deep_water(spawn_kind), "seed %d : départ hors de l'eau profonde et de l'océan (%s)" % [world_seed, WorldMap.kind_name(spawn_kind)])
		var spawn_chunk: Vector3i = ChunkManager.key_of(spawn)
		var data: PackedByteArray = ChunkGenerator.generate(world_seed, spawn_chunk)
		var terrain: int = data[ChunkManager.index_of(spawn)]
		_check(TerrainDB.is_walkable(terrain), "seed %d : départ %s praticable (%s)" % [world_seed, spawn, TerrainDB.id_of(terrain)])
		var near: Dictionary = settlement.nearest_town()
		print("       départ : %s%s" % [spawn, (" en lisière de « %s »" % near["name"]) if not near.is_empty() else " en pleine nature"])
		# Déterminisme autour du départ (là où se trouvent les villes) : 2 ordres de génération.
		var around: Array[Vector3i] = []
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				around.append(Vector3i(spawn_chunk.x + dx, spawn_chunk.y + dy, 0))
		var around_reversed: Array[Vector3i] = around.duplicate()
		around_reversed.reverse()
		_check(_fingerprints(world_seed, around) == _fingerprints(world_seed, around_reversed), "seed %d : chunks autour du départ identiques dans 2 ordres" % world_seed)

	# --- Villes et rues ---
	var region_count: int = 7
	var half_regions: int = 3
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var fresh_settlement := SettlementMap.new(world_seed)
		var same_towns: bool = true
		var towns: Array[Dictionary] = []
		for ry in range(-half_regions, half_regions + 1):
			for rx in range(-half_regions, half_regions + 1):
				var list: Array = settlement.towns_in_region(Vector2i(rx, ry))
				if list != fresh_settlement.towns_in_region(Vector2i(rx, ry)):
					same_towns = false
				for t: Dictionary in list:
					towns.append(t)
		_check(same_towns, "seed %d : villes identiques sur une instance neuve" % world_seed)
		_check(towns.size() >= 5, "seed %d : %d villes dans %d x %d régions (attendu au moins 5)" % [world_seed, towns.size(), region_count, region_count])
		var roads: int = 0
		var isolated: int = 0
		var asymmetric: int = 0
		var on_lake: int = 0
		var centers_ok: bool = true
		for t in towns:
			var center: Vector2i = t["center"]
			if settlement.cell_type(center) != SettlementMap.CellType.ROAD:
				centers_ok = false
			var radius: int = t["radius"]
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var cell: Vector2i = center + Vector2i(dx, dy)
					if settlement.cell_type(cell) != SettlementMap.CellType.ROAD:
						continue
					roads += 1
					var kind: int = WorldMap.for_seed(world_seed).cell_kind(cell)
					if kind == WorldMap.Kind.LAKE_DEEP or kind == WorldMap.Kind.LAKE_SHALLOW:
						on_lake += 1
					var mask: int = settlement.road_mask(cell)
					if mask == 0:
						isolated += 1
					for i in SettlementMap.DIRS.size():
						var neighbor: Vector2i = cell + SettlementMap.DIRS[i]
						if (mask & (1 << i)) != 0 and (settlement.road_mask(neighbor) & (1 << ((i + 2) % 4))) == 0:
							asymmetric += 1
		_check(centers_ok, "seed %d : le centre de chaque ville est une rue" % world_seed)
		_check(on_lake == 0, "seed %d : aucune rue sur un lac" % world_seed)
		_check(asymmetric == 0, "seed %d : connexions des rues symétriques" % world_seed)
		_check(isolated * 20 <= roads, "seed %d : peu de rues isolées (%d sur %d)" % [world_seed, isolated, roads])

	# --- Routes entre villes (jalon 3b) ---
	var route_regions: Array[Vector2i] = []   # fenêtre 5 x 5 régions pour le déterminisme
	for ry in range(-2, 3):
		for rx in range(-2, 3):
			route_regions.append(Vector2i(rx, ry))
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var routes: RouteMap = settlement.routes()
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		var total_towns: int = 0
		var unlinked: int = 0
		var bad_paths: int = 0
		var path_on_lake: int = 0
		var path_on_ocean: int = 0
		for ry in range(-half_regions, half_regions + 1):
			for rx in range(-half_regions, half_regions + 1):
				for t: Dictionary in settlement.towns_in_region(Vector2i(rx, ry)):
					var center: Vector2i = t["center"]
					total_towns += 1
					var partners: Array[Vector2i] = routes.partners_of(center)
					if partners.is_empty():
						unlinked += 1
					for other: Vector2i in partners:
						var path: Array[Vector2i] = routes.path_between(center, other)
						var first: Vector2i = path[0]
						var last: Vector2i = path[path.size() - 1]
						if not ((first == center and last == other) or (first == other and last == center)):
							bad_paths += 1
						for i in path.size():
							if i > 0 and absi(path[i].x - path[i - 1].x) + absi(path[i].y - path[i - 1].y) != 1:
								bad_paths += 1
							var nature: int = world_map.cell_kind(path[i])
							if nature == WorldMap.Kind.LAKE_DEEP or nature == WorldMap.Kind.LAKE_SHALLOW:
								path_on_lake += 1
							if WorldMap.is_ocean(nature):
								path_on_ocean += 1
		_check(unlinked == 0, "seed %d : toute ville reliée à au moins une autre (%d villes, %d isolées)" % [world_seed, total_towns, unlinked])
		_check(bad_paths == 0, "seed %d : chaque route va d'un centre de ville à l'autre, case par case (%d anomalies)" % [world_seed, bad_paths])
		_check(path_on_ocean == 0, "seed %d : aucune route sur l'océan" % world_seed)
		var route_cells: int = 0
		var bad_cells: int = 0
		var isolated_cells: int = 0
		var asymmetric_cells: int = 0
		var cells_on_lake: int = 0
		for ry in range(-3, 4):
			for rx in range(-3, 4):
				for cell: Vector2i in routes.region_cells(Vector2i(rx, ry)):
					route_cells += 1
					var cell_nature: int = world_map.cell_kind(cell)
					if cell_nature == WorldMap.Kind.LAKE_DEEP or cell_nature == WorldMap.Kind.LAKE_SHALLOW:
						cells_on_lake += 1
					if not settlement.town_at(cell).is_empty() or settlement.cell_type(cell) != SettlementMap.CellType.ROAD:
						bad_cells += 1
					var route_mask: int = settlement.road_mask(cell)
					if route_mask == 0:
						isolated_cells += 1
					for i in SettlementMap.DIRS.size():
						var next_cell: Vector2i = cell + SettlementMap.DIRS[i]
						if (route_mask & (1 << i)) != 0 and (settlement.road_mask(next_cell) & (1 << ((i + 2) % 4))) == 0:
							asymmetric_cells += 1
		_check(route_cells > 0, "seed %d : %d cellules de route hors ville sur 7 x 7 régions" % [world_seed, route_cells])
		_check(path_on_lake == 0 and cells_on_lake == 0, "seed %d : aucune route sur un lac" % world_seed)
		_check(bad_cells == 0, "seed %d : les cellules de route sont des ROAD hors emprise de ville" % world_seed)
		_check(asymmetric_cells == 0, "seed %d : connexions des routes symétriques" % world_seed)
		_check(isolated_cells == 0, "seed %d : aucune cellule de route isolée" % world_seed)
		# Déterminisme : 3 ordres de génération, sur des instances neuves (caches vides).
		var reference: Dictionary = _route_prints(SettlementMap.new(world_seed), route_regions)
		var reversed_regions: Array[Vector2i] = route_regions.duplicate()
		reversed_regions.reverse()
		var by_distance_regions: Array[Vector2i] = route_regions.duplicate()
		by_distance_regions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x * a.x + a.y * a.y < b.x * b.x + b.y * b.y)
		_check(reference == _route_prints(SettlementMap.new(world_seed), reversed_regions), "seed %d : routes identiques, ordre inversé" % world_seed)
		_check(reference == _route_prints(SettlementMap.new(world_seed), by_distance_regions), "seed %d : routes identiques, ordre par distance" % world_seed)
		_check(reference == _route_prints(settlement, route_regions), "seed %d : routes identiques sur l'instance partagée" % world_seed)
	# Coût du calcul des routes : 1re région (villes + routes à froid), puis 6 régions voisines (ce qu'on vit en marchant).
	for world_seed in seeds:
		var bench_settlement := SettlementMap.new(world_seed)
		var bench: RouteMap = bench_settlement.routes()
		var cold: Dictionary = bench.benchmark_region(Vector2i.ZERO)
		var walk_total: int = 0
		var walk_max: int = 0
		for step in range(1, 7):
			var m: Dictionary = bench.benchmark_region(Vector2i(step, 0))
			var us: int = int(m["towns_us"]) + int(m["routes_us"])
			walk_total += us
			walk_max = maxi(walk_max, us)
		print("       perf routes seed %d : 1re région %.1f ms (villes %.1f + routes %.1f, %d A*) ; 6 régions voisines : moyenne %.1f ms, max %.1f ms" % [
			world_seed, (int(cold["towns_us"]) + int(cold["routes_us"])) / 1000.0, int(cold["towns_us"]) / 1000.0,
			int(cold["routes_us"]) / 1000.0, int(cold["astar_runs"]), walk_total / 6000.0, walk_max / 1000.0])

	# --- Terrains de route ---
	for id in ["t_pavement", "t_pavement_y", "t_sidewalk", "t_bridge"]:
		_check(TerrainDB.is_walkable(TerrainDB.index_of(id)), "%s praticable" % id)

	# --- Maisons (jalon 3c) ---
	_check_house_plans()
	_warn_missing_sprites()
	for world_seed in seeds:
		var house_settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var checked: int = 0
		var problems: int = 0
		for ry in range(-half_regions, half_regions + 1):
			for rx in range(-half_regions, half_regions + 1):
				for t: Dictionary in house_settlement.towns_in_region(Vector2i(rx, ry)):
					var radius: int = t["radius"]
					for dy in range(-radius, radius + 1):
						for dx in range(-radius, radius + 1):
							if checked >= 40:
								continue
							var lot: Vector2i = (t["center"] as Vector2i) + Vector2i(dx, dy)
							var house: Dictionary = house_settlement.lot_plan(lot)
							if house.is_empty():
								continue
							checked += 1
							if not _house_is_sound(world_seed, lot, int(house["rot"])):
								problems += 1
		_check(checked > 0, "seed %d : des maisons sont générées (%d contrôlées)" % [world_seed, checked])
		_check(problems == 0, "seed %d : maisons contrôlées (porte côté rue, case devant la porte praticable, mobilier présent) : %d anomalies" % [world_seed, problems])

	# --- Lieux spéciaux (jalon 4) ---
	_check_special_plans()
	var special_regions: Array[Vector2i] = []   # fenêtre 3 x 3 régions pour le déterminisme
	for ry in range(-1, 2):
		for rx in range(-1, 2):
			special_regions.append(Vector2i(rx, ry))
	var region_size: int = SettlementMap.region_size_cells()
	for world_seed in seeds:
		var place_settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var specials: SpecialMap = place_settlement.specials()
		var place_world: WorldMap = WorldMap.for_seed(world_seed)
		var counts: Dictionary = {}
		var placed_total: int = 0
		var out_of_region: int = 0
		var bad_site: int = 0
		var no_road: int = 0
		var chunk_checked: int = 0
		var chunk_problems: int = 0
		for ry in range(-3, 4):
			for rx in range(-3, 4):
				var region := Vector2i(rx, ry)
				for place: Dictionary in specials.region_places(region):
					var place_id: String = place["id"]
					placed_total += 1
					counts[place_id] = int(counts.get(place_id, 0)) + 1
					var footprint: Array = place["cells"]
					for cell: Vector2i in footprint:
						if Vector2i(floori(float(cell.x) / region_size), floori(float(cell.y) / region_size)) != region:
							out_of_region += 1
						if not specials.biome_ok(place_id, place_world.cell_kind(cell)) or place_settlement.cell_type(cell, true, false) != SettlementMap.CellType.NONE:
							bad_site += 1
						if chunk_checked < 30:
							var info: Dictionary = place_settlement.special_plan(cell)
							if not info.is_empty() and MapgenDB.has_door(int(info["plan"])):
								chunk_checked += 1
								if not _house_is_sound(world_seed, cell, int(info["rot"])):
									chunk_problems += 1
					if specials.place_needs_road(place_id) and not specials.front_touches_road(footprint, int(place["rot"])):
						no_road += 1
		_check(specials.errors().is_empty(), "seed %d : specials.json valide %s" % [world_seed, str(specials.errors())])
		_check(placed_total > 0, "seed %d : %d lieux spéciaux sur 7 x 7 régions" % [world_seed, placed_total])
		for place_id in specials.place_ids():
			_check(int(counts.get(place_id, 0)) > 0 or not specials.place_is_common(place_id), "seed %d : au moins un lieu « %s » (%d ; lieux rares exemptés)" % [world_seed, place_id, int(counts.get(place_id, 0))])
		_check(out_of_region == 0, "seed %d : aucune empreinte ne franchit une frontière de région" % world_seed)
		_check(bad_site == 0, "seed %d : empreintes sur terrain libre (hors ville, rue, route), biome autorisé (%d anomalies)" % [world_seed, bad_site])
		_check(no_road == 0, "seed %d : chaque lieu near_road a une route devant sa façade" % world_seed)
		_check(chunk_problems == 0, "seed %d : bâtiments des lieux contrôlés (porte côté route, case devant praticable) : %d sur %d en défaut" % [world_seed, chunk_problems, chunk_checked])
		# Déterminisme : 3 ordres de génération, sur des instances neuves (caches vides).
		var special_reference: Dictionary = _special_prints(SettlementMap.new(world_seed), special_regions)
		var special_reversed: Array[Vector2i] = special_regions.duplicate()
		special_reversed.reverse()
		var special_by_distance: Array[Vector2i] = special_regions.duplicate()
		special_by_distance.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x * a.x + a.y * a.y < b.x * b.x + b.y * b.y)
		_check(special_reference == _special_prints(SettlementMap.new(world_seed), special_reversed), "seed %d : lieux identiques, ordre inversé" % world_seed)
		_check(special_reference == _special_prints(SettlementMap.new(world_seed), special_by_distance), "seed %d : lieux identiques, ordre par distance" % world_seed)
		_check(special_reference == _special_prints(place_settlement, special_regions), "seed %d : lieux identiques sur l'instance partagée" % world_seed)

	# --- Répartition des biomes autour de l'origine (relevé grossier) : rivières, gués, lacs, forêts, plaines, marais ---
	var totals: Array[int] = []
	totals.resize(WorldMap.kind_count())
	for world_seed in seeds:
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		var counts: Array[int] = []
		counts.resize(WorldMap.kind_count())
		var samples: int = 0
		for y in range(-SURVEY_HALF, SURVEY_HALF, SURVEY_STEP):
			for x in range(-SURVEY_HALF, SURVEY_HALF, SURVEY_STEP):
				counts[world_map.kind_at(Vector2i(x, y))] += 1
				samples += 1
		var water: int = counts[WorldMap.Kind.LAKE_DEEP] + counts[WorldMap.Kind.LAKE_SHALLOW] + counts[WorldMap.Kind.RIVER_DEEP] + counts[WorldMap.Kind.RIVER_SHALLOW]
		var water_ratio: float = float(water) / float(samples)
		_check(water_ratio > 0.01 and water_ratio < 0.60, "seed %d : lacs et rivières = %.1f %% de la surface autour de l'origine (attendu 1 à 60 %%)" % [world_seed, water_ratio * 100.0])
		var line: String = "       répartition :"
		for kind in WorldMap.kind_count():
			totals[kind] += counts[kind]
			line += " %s %.1f%%" % [WorldMap.kind_name(kind).get_slice(" ", 0), 100.0 * counts[kind] / samples]
		print(line)
	for kind in [WorldMap.Kind.PLAIN, WorldMap.Kind.FOREST, WorldMap.Kind.SWAMP, WorldMap.Kind.LAKE_DEEP, WorldMap.Kind.RIVER_DEEP, WorldMap.Kind.RIVER_SHALLOW]:
		_check(totals[kind] > 0, "biome présent dans le relevé : %s" % WorldMap.kind_name(kind))

	# --- Planète (jalon 9) : océans et climats sur un relevé de 120 000 x 120 000 cases ---
	_check_planet(seeds)

	# --- Terrains : l'eau profonde bloque, l'eau peu profonde se traverse ---
	_check(not TerrainDB.is_walkable(TerrainDB.index_of("t_water_dp")), "eau profonde non praticable")
	_check(TerrainDB.is_walkable(TerrainDB.index_of("t_water_sh")), "eau peu profonde praticable")

	# --- Arène : bordure en murs, intérieur praticable ---
	var wall: int = TerrainDB.index_of("t_wall_arena")
	var arena_data: PackedByteArray = ChunkGenerator.generate(0, Vector3i(0, 0, 0), true)
	_check(arena_data[0] == wall, "arène : la case (0,0) est un mur")
	_check(arena_data[5 * Chunk.SIZE + 5] != wall, "arène : la case (5,5) est praticable")

	# --- RNG de base ---
	_check(WorldRng.mix(1, 2, 3, 4, 5) == WorldRng.mix(1, 2, 3, 4, 5), "mix : stable")
	_check(WorldRng.mix(1, 2, 3, 4, 5) != WorldRng.mix(1, 2, 3, 4, 6), "mix : sensible à chaque paramètre")
	_check(WorldRng.seed_from_text("42") == 42, "seed_from_text : un entier reste tel quel")
	_check(WorldRng.seed_from_text("abc") == WorldRng.seed_from_text("abc"), "seed_from_text : texte stable")

	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _fingerprints(world_seed: int, keys: Array[Vector3i]) -> Dictionary:
	var result: Dictionary = {}
	for key in keys:
		result[key] = ChunkGenerator.fingerprint(world_seed, key)
	return result


func _route_prints(settlement: SettlementMap, regions: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for region in regions:
		result[region] = settlement.routes().region_fingerprint(region)
	return result


## Les trois listes de natures de case doivent avoir EXACTEMENT le même ordre : l'énumération WorldMap.Kind, RouteMap.KIND_IDS
## (coûts de route, biomes de specials.json) et "kinds" de biomes.json (couleurs, noms). Un décalage fausse tout sans erreur visible.
func _check_kind_order() -> void:
	var enum_ids: Array[String] = []
	for kind_name: String in WorldMap.Kind.keys():
		enum_ids.append(kind_name.to_lower())
	_check(enum_ids == RouteMap.KIND_IDS, "RouteMap.KIND_IDS suit l'ordre de WorldMap.Kind")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/worldgen/biomes.json"))
	var json_ids: Array[String] = []
	if typeof(parsed) == TYPE_DICTIONARY:
		for entry: Dictionary in parsed.get("kinds", []):
			json_ids.append(String(entry.get("id", "")))
	_check(json_ids == enum_ids, "\"kinds\" de biomes.json suit l'ordre de WorldMap.Kind")
	_check(WorldMap.kind_count() == enum_ids.size(), "WorldMap.kind_count() = nombre de natures de case (%d)" % enum_ids.size())
	var unknown: Array[String] = []
	for id: String in SettlementMap.route_config().get("costs", {}):
		if not enum_ids.has(id):
			unknown.append(id)
	_check(unknown.is_empty(), "towns.json : tous les coûts de route portent sur une nature connue %s" % str(unknown))
	_check(RouteMap.KIND_IDS.find("plain") == WorldMap.Kind.PLAIN and RouteMap.KIND_IDS.find("forest") == WorldMap.Kind.FOREST,
		"plaine et forêt (biomes des lieux spéciaux) ont le bon indice")


## Relevé à grande échelle (jalon 9) : l'océan existe, la terre aussi, et les trois familles de climat (tempéré, chaud, froid) apparaissent
## sur l'ensemble des seeds. Les parts d'océan sont AFFICHÉES pour régler biomes.json (la cible de WORLD_GEN.md §16 : 40 à 75 %) ;
## le contrôle reste large (5 à 95 %) tant que ces réglages n'ont pas été validés à l'œil avec la mini-carte.
func _check_planet(seeds: Array[int]) -> void:
	var temperate_total: int = 0
	var hot_total: int = 0
	var cold_total: int = 0
	for world_seed in seeds:
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		var ocean: int = 0
		var land: int = 0
		var temperate: int = 0
		var hot: int = 0
		var cold: int = 0
		for y in range(-PLANET_HALF, PLANET_HALF, PLANET_STEP):
			for x in range(-PLANET_HALF, PLANET_HALF, PLANET_STEP):
				var kind: int = world_map.kind_at(Vector2i(x, y))
				if WorldMap.is_ocean(kind):
					ocean += 1
					continue
				land += 1
				match kind:
					WorldMap.Kind.JUNGLE, WorldMap.Kind.DESERT, WorldMap.Kind.SAVANNA:
						hot += 1
					WorldMap.Kind.TUNDRA, WorldMap.Kind.TAIGA:
						cold += 1
					WorldMap.Kind.PLAIN, WorldMap.Kind.FOREST, WorldMap.Kind.SWAMP:
						temperate += 1
		var total: int = ocean + land
		var ocean_ratio: float = float(ocean) / float(total)
		print("       planète seed %d : océan %.1f %% ; terre : tempéré %d, chaud %d, froid %d (échantillons)" % [world_seed, ocean_ratio * 100.0, temperate, hot, cold])
		_check(ocean_ratio > 0.05 and ocean_ratio < 0.95, "seed %d : océan = %.1f %% de la planète (contrôle large 5 à 95 %% ; cible 40 à 75 %%)" % [world_seed, ocean_ratio * 100.0])
		_check(land > 0, "seed %d : il y a de la terre" % world_seed)
		temperate_total += temperate
		hot_total += hot
		cold_total += cold
	_check(temperate_total > 0, "climat tempéré présent (plaine, forêt ou marais)")
	_check(hot_total > 0, "climat chaud présent (jungle, désert ou savane)")
	_check(cold_total > 0, "climat froid présent (toundra ou taïga)")


## Contrôle d'une maison générée (chunk réel) : porte de façade côté rue, case devant la porte praticable, mobilier présent.
func _house_is_sound(world_seed: int, lot: Vector2i, rot: int) -> bool:
	var key := Vector3i(lot.x, lot.y, 0)
	var terrain: PackedByteArray = ChunkGenerator.generate(world_seed, key)
	var furniture: PackedByteArray = ChunkGenerator.generate_furniture(world_seed, key)
	var door: int = TerrainDB.index_of("t_door")
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: int = -1000
	var has_furniture: bool = false
	for i in Chunk.CELLS:
		if furniture[i] != 0:
			has_furniture = true
		if terrain[i] != door:
			continue
		var lx: int = i % Chunk.SIZE
		var ly: int = floori(float(i) / Chunk.SIZE)
		var score: int = ly
		match rot:
			1:
				score = -lx
			2:
				score = -ly
			3:
				score = lx
		if score > best_score:
			best_score = score
			best = Vector2i(lx, ly)
	if best.x < 0 or not has_furniture:
		return false
	var front: Vector2i = best + SettlementMap.HOUSE_FRONTS[rot]
	if front.x < 0 or front.y < 0 or front.x >= Chunk.SIZE or front.y >= Chunk.SIZE:
		return false
	return TerrainDB.is_walkable(terrain[front.y * Chunk.SIZE + front.x])


## Case du chunk correspondant à une case du plan non tourné (quarts de tour horaires).
func _rotate_plan_cell(cell: Vector2i, rot: int) -> Vector2i:
	var last: int = Chunk.SIZE - 1
	match rot:
		1:
			return Vector2i(last - cell.y, cell.x)
		2:
			return Vector2i(last - cell.x, last - cell.y)
		3:
			return Vector2i(cell.y, last - cell.x)
	return cell


func _check_house_plans() -> void:
	var wall: int = TerrainDB.index_of("t_wall_house")
	var door: int = TerrainDB.index_of("t_door")
	var floor_terrain: int = TerrainDB.index_of("t_floor")
	var errors: Array[String] = MapgenDB.errors()
	_check(errors.is_empty(), "plans de maison : aucune erreur de chargement %s" % str(errors))
	_check(MapgenDB.plan_count() >= 4, "au moins 4 plans de maison valides (%d)" % MapgenDB.plan_count())
	var last: int = Chunk.SIZE - 1
	for plan in MapgenDB.plan_count():
		var plan_name: String = MapgenDB.plan_id(plan)
		var structure_ok: bool = true
		var front_door: Vector2i = Vector2i(-1, -1)
		for py in Chunk.SIZE:
			for px in Chunk.SIZE:
				var t: int = MapgenDB.terrain_at(plan, py * Chunk.SIZE + px)
				var f: int = MapgenDB.furniture_at(plan, py * Chunk.SIZE + px)
				if (t == wall or t == door) and (px < 1 or py < 1 or px > last - 1 or py > last - 1):
					structure_ok = false
				if f != 0 and t != floor_terrain:
					structure_ok = false
				if t == door and py > front_door.y:
					front_door = Vector2i(px, py)
		_check(structure_ok, "plan %s : murs à l'intérieur du chunk, mobilier posé sur du sol" % plan_name)
		var has_front: bool = front_door.x >= 0 and front_door.y < last
		_check(has_front, "plan %s : porte de façade présente" % plan_name)
		if not has_front:
			continue
		var access_ok: bool = true
		var mapping_ok: bool = true
		for rot in 4:
			var walk := PackedByteArray()
			walk.resize(Chunk.CELLS)
			var visited := PackedByteArray()
			visited.resize(Chunk.CELLS)
			var used: Dictionary = {}
			for ly in Chunk.SIZE:
				for lx in Chunk.SIZE:
					var plan_cell: int = MapgenDB.plan_index(lx, ly, rot)
					used[plan_cell] = true
					var terrain_here: int = MapgenDB.terrain_at(plan, plan_cell)
					var open: bool = terrain_here == MapgenDB.NATURE or TerrainDB.is_walkable(terrain_here)
					walk[ly * Chunk.SIZE + lx] = 1 if open and FurnitureDB.is_walkable(MapgenDB.furniture_at(plan, plan_cell)) else 0
			if used.size() != Chunk.CELLS:
				mapping_ok = false
			var start: Vector2i = _rotate_plan_cell(front_door + Vector2i.DOWN, rot)
			var stack: Array[Vector2i] = []
			if walk[start.y * Chunk.SIZE + start.x] == 1:
				visited[start.y * Chunk.SIZE + start.x] = 1
				stack.append(start)
			else:
				access_ok = false
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
			for ly in Chunk.SIZE:
				for lx in Chunk.SIZE:
					var cell_index: int = ly * Chunk.SIZE + lx
					if MapgenDB.terrain_at(plan, MapgenDB.plan_index(lx, ly, rot)) == floor_terrain and walk[cell_index] == 1 and visited[cell_index] == 0:
						access_ok = false
		_check(mapping_ok, "plan %s : la rotation couvre chaque case du chunk une fois (4 rotations)" % plan_name)
		_check(access_ok, "plan %s : tout le sol est atteignable depuis la porte (4 rotations)" % plan_name)


## Avertit (sans échec) des tuiles absentes du pack : il faut alors régénérer assets/ avec tools/build_ultica_pack.py.
func _warn_missing_sprites() -> void:
	var missing: Array[String] = []
	var i: int = 0
	while TerrainDB.id_of(i) != "":
		var tile: String = TerrainDB.tile_of(i)
		if tile != "" and UlticaTiles.pick_sprite(tile, "fg", 0) == "":
			missing.append("%s (%s)" % [TerrainDB.id_of(i), tile])
		i += 1
	for f in range(1, FurnitureDB.count() + 1):
		var furniture_tile: String = FurnitureDB.tile_of(f)
		if UlticaTiles.pick_sprite(furniture_tile, "fg", 0) == "":
			missing.append("%s (%s)" % [FurnitureDB.id_of(f), furniture_tile])
	if not missing.is_empty():
		print("  AVERTISSEMENT - tuiles absentes du pack (relancer tools/build_ultica_pack.py) : ", ", ".join(missing))


func _special_prints(settlement: SettlementMap, regions: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for region in regions:
		result[region] = settlement.specials().region_fingerprint(region)
	return result


## Tout le sol du plan est-il atteignable depuis la case devant la porte de façade, pour la rotation donnée ?
func _plan_floor_reachable(plan: int, rot: int, front_door: Vector2i, floor_terrain: int) -> bool:
	var walk := PackedByteArray()
	walk.resize(Chunk.CELLS)
	var visited := PackedByteArray()
	visited.resize(Chunk.CELLS)
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var plan_cell: int = MapgenDB.plan_index(lx, ly, rot)
			var terrain_here: int = MapgenDB.terrain_at(plan, plan_cell)
			var open: bool = terrain_here == MapgenDB.NATURE or TerrainDB.is_walkable(terrain_here)
			walk[ly * Chunk.SIZE + lx] = 1 if open and FurnitureDB.is_walkable(MapgenDB.furniture_at(plan, plan_cell)) else 0
	var start: Vector2i = _rotate_plan_cell(front_door + Vector2i.DOWN, rot)
	if walk[start.y * Chunk.SIZE + start.x] != 1:
		return false
	var stack: Array[Vector2i] = [start]
	visited[start.y * Chunk.SIZE + start.x] = 1
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
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var cell_index: int = ly * Chunk.SIZE + lx
			if MapgenDB.terrain_at(plan, MapgenDB.plan_index(lx, ly, rot)) == floor_terrain and walk[cell_index] == 1 and visited[cell_index] == 0:
				return false
	return true


## Plans des lieux spéciaux (ceux qui suivent les plans de maison) : structure, et accès au sol pour les bâtiments.
func _check_special_plans() -> void:
	var wall: int = TerrainDB.index_of("t_wall_house")
	var door: int = TerrainDB.index_of("t_door")
	var floor_terrain: int = TerrainDB.index_of("t_floor")
	var last: int = Chunk.SIZE - 1
	_check(MapgenDB.total_count() > MapgenDB.plan_count(), "plans de lieux spéciaux chargés (%d)" % (MapgenDB.total_count() - MapgenDB.plan_count()))
	for plan in range(MapgenDB.plan_count(), MapgenDB.total_count()):
		var plan_name: String = MapgenDB.plan_id(plan)
		var structure_ok: bool = true
		var front_door: Vector2i = Vector2i(-1, -1)
		for py in Chunk.SIZE:
			for px in Chunk.SIZE:
				var t: int = MapgenDB.terrain_at(plan, py * Chunk.SIZE + px)
				var f: int = MapgenDB.furniture_at(plan, py * Chunk.SIZE + px)
				if (t == wall or t == door) and (px < 1 or py < 1 or px > last - 1 or py > last - 1):
					structure_ok = false
				if f != 0 and t != floor_terrain:
					structure_ok = false
				if t == door and py > front_door.y:
					front_door = Vector2i(px, py)
		_check(structure_ok, "lieu %s : murs à l'intérieur du chunk, mobilier posé sur du sol" % plan_name)
		if front_door.x < 0:
			continue  # pas de bâtiment (champ...)
		var access_ok: bool = front_door.y < last
		for rot in 4:
			if access_ok and not _plan_floor_reachable(plan, rot, front_door, floor_terrain):
				access_ok = false
		_check(access_ok, "lieu %s : tout le sol est atteignable depuis la porte (4 rotations)" % plan_name)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
