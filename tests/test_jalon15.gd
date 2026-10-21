extends SceneTree
## Test du jalon 15 (rural et divers : lieux par climat, volcan, ruines, grotte, oasis, station de ski, base arctique). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_jalon15.gd
## Code de sortie 0 = tout est bon. Complète tests/test_worldgen_determinism.gd (structure des plans dans les 4 rotations, déterminisme des
## régions) et tests/test_jalon10.gd (accès : pistes, héliports).

const PLACE_SIZES: Dictionary = {
	"ski_resort": 2, "volcano_site": 4, "arctic_base": 2, "jungle_temple": 1, "ancient_ruins": 2, "oasis": 1,
	"cave_entrance": 1, "nomad_camp": 1, "trapper_cabin": 1,
}
# Climat imposé (index WorldMap.Climate) pour les lieux « par climat » ; les autres n'en ont pas.
const PLACE_CLIMATES: Dictionary = {
	"ski_resort": WorldMap.Climate.COLD, "arctic_base": WorldMap.Climate.COLD, "trapper_cabin": WorldMap.Climate.COLD,
	"jungle_temple": WorldMap.Climate.HOT, "oasis": WorldMap.Climate.HOT, "nomad_camp": WorldMap.Climate.HOT,
}
const PLAN_IDS: Array[String] = [
	"oasis", "ski_lodge", "ski_slope", "volcano_nw", "volcano_ne", "volcano_sw", "volcano_se", "ruins_a", "ruins_b", "cave",
	"arctic_hq", "arctic_pad", "temple", "nomad_camp",
]
const HALF_REGIONS: int = 3

var _failures: int = 0


func _initialize() -> void:
	var seeds: Array[int] = []
	for text in ["1", "42", "cataclysme", "", "-7"]:
		seeds.append(WorldRng.seed_from_text(text))
	_check_plans()
	_check_places(seeds)
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check_plans() -> void:
	var errors: Array[String] = MapgenDB.errors()
	_check(errors.is_empty(), "plans : aucune erreur de chargement %s" % str(errors))
	for id in PLAN_IDS:
		_check(MapgenDB.plan_by_id(id) >= MapgenDB.plan_count(), "plan %s chargé (après les plans de maison)" % id)
	for id in ["oasis", "ski_lodge", "cave", "arctic_hq", "temple", "nomad_camp"]:
		var plan: int = MapgenDB.plan_by_id(id)
		_check(plan >= 0 and MapgenDB.has_door(plan), "plan %s : a une porte (accès par piste)" % id)
	var pad: int = MapgenDB.plan_by_id("arctic_pad")
	_check(pad >= 0 and MapgenDB.has_terrain(pad, TerrainDB.index_of("t_helipad")), "plan arctic_pad : contient un héliport")
	var lava: int = TerrainDB.index_of("t_reactor")
	var lava_cells: int = 0
	for id in ["volcano_nw", "volcano_ne", "volcano_sw", "volcano_se"]:
		var plan: int = MapgenDB.plan_by_id(id)
		_check(plan >= 0 and not MapgenDB.has_door(plan), "plan %s : sans porte" % id)
		for i in MapgenDB.SIZE * MapgenDB.SIZE:
			if plan >= 0 and MapgenDB.terrain_at(plan, i) == lava:
				lava_cells += 1
	_check(lava_cells > 100, "volcan : un cratère de lave sur les quatre plans (%d cases)" % lava_cells)


func _check_places(seeds: Array[int]) -> void:
	var counts: Dictionary = {}
	var access_counts: Dictionary = {}
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var specials: SpecialMap = settlement.specials()
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		_check(specials.errors().is_empty(), "seed %d : specials.json valide %s" % [world_seed, str(specials.errors())])
		for id in PLACE_SIZES:
			_check(specials.place_ids().has(id) and not specials.place_is_common(id), "seed %d : lieu « %s » défini et rare" % [world_seed, id])
		var bad_size: int = 0
		var bad_zone: int = 0
		var bad_climate: int = 0
		var bad_access: int = 0
		var bad_track: int = 0
		for ry in range(-HALF_REGIONS, HALF_REGIONS + 1):
			for rx in range(-HALF_REGIONS, HALF_REGIONS + 1):
				for place: Dictionary in specials.region_places(Vector2i(rx, ry)):
					var id: String = place["id"]
					if not PLACE_SIZES.has(id):
						continue
					counts[id] = int(counts.get(id, 0)) + 1
					var footprint: Array = place["cells"]
					var access: String = place["access"]
					access_counts[access] = int(access_counts.get(access, 0)) + 1
					if footprint.size() != int(PLACE_SIZES[id]):
						bad_size += 1
					if not specials.zone_ok(id, footprint):
						bad_zone += 1
					for cell: Vector2i in footprint:
						if not specials.biome_ok(id, world_map.cell_kind(cell)):
							bad_zone += 1
						if PLACE_CLIMATES.has(id) and world_map.cell_climate(cell) != int(PLACE_CLIMATES[id]):
							bad_climate += 1
					if not specials.place_access_options(id).has(access):
						bad_access += 1
					match access:
						"road":
							if not specials.front_touches_road(footprint, int(place["rot"])):
								bad_access += 1
						"track":
							if not _track_is_sound(settlement, specials, place):
								bad_track += 1
						"helipad":
							var has_pad: bool = false
							for cell: Vector2i in footprint:
								var info: Dictionary = settlement.special_plan(cell)
								if not info.is_empty() and MapgenDB.has_terrain(int(info["plan"]), TerrainDB.index_of("t_helipad")):
									has_pad = true
							if not has_pad:
								bad_access += 1
		_check(bad_size == 0, "seed %d : empreintes de la bonne taille (%d anomalies)" % [world_seed, bad_size])
		_check(bad_zone == 0, "seed %d : zone et biomes respectés (%d anomalies)" % [world_seed, bad_zone])
		_check(bad_climate == 0, "seed %d : lieux par climat (froid / chaud) respectés (%d anomalies)" % [world_seed, bad_climate])
		_check(bad_access == 0, "seed %d : accès respectés (route, héliport) : %d anomalies" % [world_seed, bad_access])
		_check(bad_track == 0, "seed %d : pistes continues de la porte à une route : %d anomalies" % [world_seed, bad_track])
	for id in PLACE_SIZES:
		var n: int = int(counts.get(id, 0))
		if n == 0:
			print("  AVERTISSEMENT - aucun lieu « %s » sur 5 seeds x 7 x 7 régions (rare : chance, attempts, climat ou biomes à régler)" % id)
		else:
			print("       lieux « %s » : %d" % [id, n])
	print("       accès tirés : %s" % str(access_counts))


## Même contrôle que tests/test_jalon10.gd.
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
		if settlement.track_mask(cell) < 0:
			return false
		if i + 1 < cells.size():
			var step: Vector2i = (cells[i + 1] as Vector2i) - cell
			var forward: int = SettlementMap.DIRS.find(step)
			var backward: int = SettlementMap.DIRS.find(-step)
			if forward < 0 or (settlement.track_mask(cell) & (1 << forward)) == 0 \
					or (settlement.track_mask(cells[i + 1]) & (1 << backward)) == 0:
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
