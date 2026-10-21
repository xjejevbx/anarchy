extends SceneTree
## Test du jalon 13 (lieux militaires et secrets). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_jalon13.gd
## Code de sortie 0 = tout est bon. Complète tests/test_worldgen_determinism.gd (structure des plans et accessibilité du sol dans les
## 4 rotations, déterminisme des régions) et tests/test_jalon10.gd (accès : pistes, héliports).

const PLACE_SIZES: Dictionary = {
	"radio_tower": 1, "military_outpost": 1, "military_base": 6, "military_camp": 1, "supply_depot": 2,
	"missile_silo": 1, "research_lab": 2, "bunker": 1, "radar_station": 1,
}
const TRACK_PLACES: Array[String] = ["radio_tower", "missile_silo", "research_lab", "bunker", "radar_station"]
const PLAN_IDS: Array[String] = [
	"radio_tower", "military_outpost", "base_barracks", "base_hq", "base_armory", "base_yard", "base_gate", "base_motor",
	"military_camp", "depot_hall", "depot_yard", "missile_silo", "lab_building", "lab_pad", "bunker", "radar_station",
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
	var helipad: int = TerrainDB.index_of("t_helipad")
	var pad: int = MapgenDB.plan_by_id("lab_pad")
	_check(pad >= 0 and MapgenDB.has_terrain(pad, helipad), "plan lab_pad : contient un héliport")
	for id in ["radio_tower", "missile_silo", "lab_building", "bunker", "radar_station"]:
		var plan: int = MapgenDB.plan_by_id(id)
		_check(plan >= 0 and MapgenDB.has_door(plan), "plan %s : a une porte (accès par piste)" % id)
		if plan < 0:
			continue
		# La piste démarre au centre du bord sud : la porte de façade est en colonne 11, un chemin de terre la prolonge jusqu'au bord.
		var dirt: int = TerrainDB.index_of("t_dirt")
		_check(MapgenDB.terrain_at(plan, (MapgenDB.SIZE - 1) * MapgenDB.SIZE + 11) == dirt, "plan %s : chemin de terre au bord sud (colonne 11)" % id)


func _check_places(seeds: Array[int]) -> void:
	var counts: Dictionary = {}
	var access_counts: Dictionary = {}
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var specials: SpecialMap = settlement.specials()
		_check(specials.errors().is_empty(), "seed %d : specials.json valide %s" % [world_seed, str(specials.errors())])
		for id in PLACE_SIZES:
			_check(specials.place_ids().has(id) and not specials.place_is_common(id), "seed %d : lieu « %s » défini et rare" % [world_seed, id])
		for id in TRACK_PLACES:
			_check(specials.place_access_options(id).has("track"), "seed %d : « %s » accessible par piste" % [world_seed, id])
		var bad_size: int = 0
		var bad_zone: int = 0
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
					if not specials.zone_ok(id, footprint) or not specials.climate_ok(id, footprint):
						bad_zone += 1
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
		_check(bad_zone == 0, "seed %d : zone et climat respectés (%d anomalies)" % [world_seed, bad_zone])
		_check(bad_access == 0, "seed %d : accès respectés (route devant la façade, héliport dans le plan) : %d anomalies" % [world_seed, bad_access])
		_check(bad_track == 0, "seed %d : pistes continues de la porte à une route : %d anomalies" % [world_seed, bad_track])
	for id in PLACE_SIZES:
		var n: int = int(counts.get(id, 0))
		if n == 0:
			print("  AVERTISSEMENT - aucun lieu « %s » sur 5 seeds x 7 x 7 régions (rare : chance, attempts, biomes ou distances à régler)" % id)
		else:
			print("       lieux « %s » : %d" % [id, n])
	print("       accès tirés : %s" % str(access_counts))


## Même contrôle que tests/test_jalon10.gd : piste qui démarre devant une porte du lieu (ou aucune si la porte donne déjà sur une route),
## cellules voisines et reliées dans les deux sens, finit contre une route dont l'embranchement est dessiné.
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
