extends SceneTree
## Test de la génération du monde (docs/WORLD_GEN.md §3 et §5.1, jalons 1-2). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_worldgen_determinism.gd
## Code de sortie 0 = tout est bon. Affiche aussi la répartition des biomes (pour régler data/worldgen/biomes.json).

const RANGE: int = 4          # chunks de -4 à +4 dans les deux axes (81 chunks)
const SURVEY_HALF: int = 3000 # relevé des biomes : de -3000 à +3000 cases
const SURVEY_STEP: int = 40   # un échantillon toutes les 40 cases (150 x 150)

var _failures: int = 0


func _initialize() -> void:
	var seeds: Array[int] = []
	for text in ["1", "42", "cataclysme", "", "-7"]:
		seeds.append(WorldRng.seed_from_text(text))
	var keys: Array[Vector3i] = []
	for y in range(-RANGE, RANGE + 1):
		for x in range(-RANGE, RANGE + 1):
			keys.append(Vector3i(x, y, 0))

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

	# --- Terrains de route ---
	for id in ["t_pavement", "t_pavement_y", "t_sidewalk", "t_bridge"]:
		_check(TerrainDB.is_walkable(TerrainDB.index_of(id)), "%s praticable" % id)

	# --- Répartition des biomes (relevé grossier) : rivières, gués, lacs, forêts, plaines, marais ---
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
		_check(water_ratio > 0.01 and water_ratio < 0.60, "seed %d : eau = %.1f %% de la surface (attendu 1 à 60 %%)" % [world_seed, water_ratio * 100.0])
		var line: String = "       répartition :"
		for kind in WorldMap.kind_count():
			totals[kind] += counts[kind]
			line += " %s %.1f%%" % [WorldMap.kind_name(kind).get_slice(" ", 0), 100.0 * counts[kind] / samples]
		print(line)
	for kind in [WorldMap.Kind.PLAIN, WorldMap.Kind.FOREST, WorldMap.Kind.SWAMP, WorldMap.Kind.LAKE_DEEP, WorldMap.Kind.RIVER_DEEP, WorldMap.Kind.RIVER_SHALLOW]:
		_check(totals[kind] > 0, "biome présent dans le relevé : %s" % WorldMap.kind_name(kind))

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


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
