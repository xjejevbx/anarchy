extends SceneTree
## Test du jalon 11 (zonage urbain, bâtiments de ville, port et aéroport). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_jalon11.gd
## Code de sortie 0 = tout est bon. Complète tests/test_worldgen_determinism.gd (qui valide déjà la structure de TOUS les plans de
## lieux, urban.json et medical.json compris : murs dans le chunk, sol atteignable depuis la porte dans les 4 rotations) et tests/test_jalon10.gd
## (accès des lieux, pistes). Jalon 6b : les 4 bâtiments médicaux (medical.json) font partie des bâtiments de ville.

const URBAN_IDS: Array[String] = [
	"urban_apartments", "urban_grocery", "urban_supermarket", "urban_pharmacy", "urban_hardware", "urban_bar", "urban_restaurant",
	"urban_police", "urban_school", "urban_church", "urban_parking", "urban_town_hall", "urban_fire_station", "urban_bank",
	"urban_hospital", "urban_clinic", "urban_nursing_home", "urban_garage",
]
const COAST_BUILDING_IDS: Array[String] = ["port_warehouse", "port_office", "airport_hangar", "airport_terminal", "airport_tower"]
const COAST_OPEN_IDS: Array[String] = ["port_quay_a", "port_quay_b", "port_quay_c", "port_yard", "airport_runway", "airport_runway_taxi", "airport_apron"]
const ZONES: Array[String] = ["center", "mid", "outskirts"]
const HALF_REGIONS: int = 3
const DOOR_SAMPLE: int = 80   # nombre de parcelles urbaines dont on génère le chunk pour contrôler la porte

var _failures: int = 0
var _zone_defs: Dictionary = {}


func _initialize() -> void:
	var seeds: Array[int] = []
	for text in ["1", "42", "cataclysme", "", "-7"]:
		seeds.append(WorldRng.seed_from_text(text))
	_check_plans()
	_check_config()
	_check_zones(seeds)
	_check_coast_places(seeds)
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check_plans() -> void:
	var errors: Array[String] = MapgenDB.errors()
	_check(errors.is_empty(), "plans : aucune erreur de chargement %s" % str(errors))
	for id in URBAN_IDS:
		_check_building(id)
	for id in COAST_BUILDING_IDS:
		_check_building(id)
	for id in COAST_OPEN_IDS:
		_check(MapgenDB.plan_by_id(id) >= MapgenDB.plan_count(), "plan %s chargé (après les plans de maison)" % id)


func _check_building(id: String) -> void:
	var plan: int = MapgenDB.plan_by_id(id)
	_check(plan >= MapgenDB.plan_count(), "plan %s chargé (après les plans de maison)" % id)
	if plan < 0:
		return
	_check(MapgenDB.has_door(plan), "plan %s : a une porte" % id)
	var furniture: int = 0
	for i in MapgenDB.SIZE * MapgenDB.SIZE:
		if MapgenDB.furniture_at(plan, i) != 0:
			furniture += 1
	_check(furniture > 0, "plan %s : a du mobilier (%d cases)" % [id, furniture])


func _check_config() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/worldgen/towns.json"))
	_check(typeof(parsed) == TYPE_DICTIONARY, "towns.json lisible")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_zone_defs = (parsed as Dictionary).get("zones", {})
	var used: Dictionary = {}
	for zone in ZONES:
		_check(_zone_defs.has(zone), "towns.json : zone « %s » définie" % zone)
		var def: Dictionary = _zone_defs.get(zone, {})
		var chance: float = float(def.get("urban_chance", -1.0))
		_check(chance >= 0.0 and chance <= 1.0, "zone %s : urban_chance entre 0 et 1 (%.2f)" % [zone, chance])
		var buildings: Array = def.get("buildings", [])
		_check(not buildings.is_empty(), "zone %s : au moins un bâtiment" % zone)
		for entry: Dictionary in buildings:
			var plan_name: String = String(entry.get("plan", ""))
			used[plan_name] = true
			_check(URBAN_IDS.has(plan_name), "zone %s : plan « %s » connu" % [zone, plan_name])
			_check(float(entry.get("weight", 0.0)) > 0.0, "zone %s : poids de %s positif" % [zone, plan_name])
	for id in URBAN_IDS:
		_check(used.has(id), "%s apparaît dans au moins une zone" % id)
	var limits: Dictionary = (parsed as Dictionary).get("zone_limits", {})
	_check(int(limits.get("center", 0)) > 0 and int(limits.get("center", 0)) < int(limits.get("mid", 0)), "zone_limits : center < mid")
	var scales: Dictionary = (parsed as Dictionary).get("size_urban_scale", {})
	_check(float(scales.get("hamlet", 1.0)) == 0.0, "size_urban_scale : les hameaux n'ont que des maisons")


func _check_zones(seeds: Array[int]) -> void:
	var counts: Dictionary = {}
	var total_urban: int = 0
	var total_houses: int = 0
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var fresh := SettlementMap.new(world_seed)
		var same: bool = true
		var hamlet_urban: int = 0
		var bad_zone: int = 0
		var bad_rule: int = 0
		var bad_door: int = 0
		var door_checked: int = 0
		for ry in range(-HALF_REGIONS, HALF_REGIONS + 1):
			for rx in range(-HALF_REGIONS, HALF_REGIONS + 1):
				for town: Dictionary in settlement.towns_in_region(Vector2i(rx, ry)):
					var radius: int = town["radius"]
					var center: Vector2i = town["center"]
					for dy in range(-radius, radius + 1):
						for dx in range(-radius, radius + 1):
							var cell: Vector2i = center + Vector2i(dx, dy)
							var info: Dictionary = settlement.lot_plan(cell)
							if info != fresh.lot_plan(cell):
								same = false
							if info.is_empty():
								continue
							var plan: int = info["plan"]
							if plan < MapgenDB.plan_count():
								total_houses += 1
								continue
							total_urban += 1
							var id: String = MapgenDB.plan_id(plan)
							counts[id] = int(counts.get(id, 0)) + 1
							var zone: String = settlement.lot_zone(cell)
							if not ZONES.has(zone):
								bad_zone += 1
							elif not _allowed(zone, id, radius):
								bad_rule += 1
							if String(town["size_id"]) == "hamlet":
								hamlet_urban += 1
							if door_checked < DOOR_SAMPLE:
								door_checked += 1
								if not _lot_door_ok(world_seed, cell, int(info["rot"])):
									bad_door += 1
		_check(same, "seed %d : bâtiments des parcelles identiques sur une instance neuve" % world_seed)
		_check(bad_zone == 0, "seed %d : chaque parcelle urbaine a une zone valide (%d anomalies)" % [world_seed, bad_zone])
		_check(bad_rule == 0, "seed %d : bâtiment présent dans la table de sa zone, rayon minimal respecté (%d anomalies)" % [world_seed, bad_rule])
		_check(hamlet_urban == 0, "seed %d : aucun bâtiment de ville dans un hameau (%d)" % [world_seed, hamlet_urban])
		_check(bad_door == 0, "seed %d : %d bâtiments contrôlés (porte côté rue, case devant praticable, mobilier) : %d anomalies" % [world_seed, door_checked, bad_door])
	_check(total_urban > 0, "des bâtiments de ville sont générés (%d, contre %d maisons)" % [total_urban, total_houses])
	for id in URBAN_IDS:
		var n: int = int(counts.get(id, 0))
		if n == 0:
			print("  AVERTISSEMENT - aucun « %s » sur 5 seeds x 7 x 7 régions (poids ou taille minimale de ville à revoir)" % id)
		else:
			print("       %s : %d" % [id, n])


## Le bâtiment est-il autorisé dans cette zone pour une ville de ce rayon (table de towns.json) ?
func _allowed(zone: String, id: String, radius: int) -> bool:
	var buildings: Array = (_zone_defs.get(zone, {}) as Dictionary).get("buildings", [])
	for entry: Dictionary in buildings:
		if String(entry.get("plan", "")) == id and int(entry.get("min_radius", 0)) <= radius:
			return true
	return false


## Même contrôle que test_worldgen_determinism : porte de façade côté rue, case devant praticable, mobilier présent.
func _lot_door_ok(world_seed: int, lot: Vector2i, rot: int) -> bool:
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


func _check_coast_places(seeds: Array[int]) -> void:
	var counts: Dictionary = {"port": 0, "airport": 0}
	var sizes: Dictionary = {"port": 6, "airport": 12}
	for world_seed in seeds:
		var specials: SpecialMap = SettlementMap.for_seed(world_seed).specials()
		_check(specials.errors().is_empty(), "seed %d : specials.json valide %s" % [world_seed, str(specials.errors())])
		for id in ["port", "airport"]:
			_check(specials.place_ids().has(id), "seed %d : lieu « %s » défini" % [world_seed, id])
		var bad: int = 0
		for ry in range(-HALF_REGIONS, HALF_REGIONS + 1):
			for rx in range(-HALF_REGIONS, HALF_REGIONS + 1):
				for place: Dictionary in specials.region_places(Vector2i(rx, ry)):
					var id: String = place["id"]
					if not sizes.has(id):
						continue
					counts[id] = int(counts[id]) + 1
					var footprint: Array = place["cells"]
					if footprint.size() != int(sizes[id]):
						bad += 1
					if not specials.zone_ok(id, footprint):
						bad += 1
					if String(place["access"]) == "road" and not specials.front_touches_road(footprint, int(place["rot"])):
						bad += 1
		_check(bad == 0, "seed %d : port et aéroport respectent empreinte, zone côtière et accès route (%d anomalies)" % [world_seed, bad])
	for id in ["port", "airport"]:
		if int(counts[id]) == 0:
			print("  AVERTISSEMENT - aucun « %s » sur 5 seeds x 7 x 7 régions (rare, côtier et très encombrant : chance, attempts, biomes à régler)" % id)
		else:
			print("       lieux « %s » : %d" % [id, counts[id]])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
