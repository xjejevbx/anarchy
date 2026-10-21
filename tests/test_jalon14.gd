extends SceneTree
## Test du jalon 14 (mer et eau : porte-avions, station en mer, repaire de pirates, marina, barrage, épaves, île). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_jalon14.gd
## Code de sortie 0 = tout est bon. Complète tests/test_worldgen_determinism.gd (structure des plans dans les 4 rotations, déterminisme des
## régions) et tests/test_jalon10.gd (zones, accès : jetées, héliports).

const PLACE_SIZES: Dictionary = {
	"aircraft_carrier": 28, "research_station": 1, "pirate_base": 2, "hydro_dam": 2, "marina": 1,
	"island_village": 4, "lighthouse_island": 1, "cargo_wreck": 2, "shipwreck_field": 2,
}
const PLAN_IDS: Array[String] = [
	"carrier_bow_n", "carrier_bow_s", "carrier_deck_a", "carrier_deck_b", "carrier_deck_pad", "carrier_deck_s", "carrier_tower",
	"carrier_stern_n", "carrier_stern_s", "marina", "pirate_fort", "pirate_dock", "dam_wall", "dam_power", "research_station",
	"wreck_a", "wreck_b", "debris_a", "debris_b",
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
	var pier: int = TerrainDB.index_of("t_pier")
	var helipad: int = TerrainDB.index_of("t_helipad")
	for id in ["marina", "pirate_fort", "pirate_dock"]:
		var plan: int = MapgenDB.plan_by_id(id)
		_check(plan >= 0 and MapgenDB.has_terrain(plan, pier), "plan %s : contient une jetée" % id)
	for id in ["carrier_deck_pad", "research_station"]:
		var plan: int = MapgenDB.plan_by_id(id)
		_check(plan >= 0 and MapgenDB.has_terrain(plan, helipad), "plan %s : contient un héliport" % id)
	for id in ["marina", "pirate_fort", "carrier_tower"]:
		var plan: int = MapgenDB.plan_by_id(id)
		_check(plan >= 0 and MapgenDB.has_door(plan), "plan %s : a une porte" % id)
	for id in ["wreck_a", "wreck_b", "debris_a", "debris_b"]:
		var plan: int = MapgenDB.plan_by_id(id)
		_check(plan >= 0 and not MapgenDB.has_door(plan), "plan %s : épave sans porte (ouverte à la nage)" % id)


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
		var bad_access: int = 0
		var bad_biome: int = 0
		for ry in range(-HALF_REGIONS, HALF_REGIONS + 1):
			for rx in range(-HALF_REGIONS, HALF_REGIONS + 1):
				for place: Dictionary in specials.region_places(Vector2i(rx, ry)):
					var id: String = place["id"]
					if not PLACE_SIZES.has(id):
						continue
					counts[id] = int(counts.get(id, 0)) + 1
					var footprint: Array = place["cells"]
					var access: String = place["access"]
					var rot: int = place["rot"]
					access_counts[access] = int(access_counts.get(access, 0)) + 1
					if footprint.size() != int(PLACE_SIZES[id]):
						bad_size += 1
					if not specials.zone_ok(id, footprint) or not specials.climate_ok(id, footprint):
						bad_zone += 1
					for cell: Vector2i in footprint:
						if not specials.biome_ok(id, world_map.cell_kind(cell)):
							bad_biome += 1
					match access:
						"pier":
							if not specials.front_water(id, footprint, rot):
								bad_access += 1
						"helipad":
							var has_pad: bool = false
							for cell: Vector2i in footprint:
								var info: Dictionary = settlement.special_plan(cell)
								if not info.is_empty() and MapgenDB.has_terrain(int(info["plan"]), TerrainDB.index_of("t_helipad")):
									has_pad = true
							if not has_pad:
								bad_access += 1
					if id == "aircraft_carrier" or id == "research_station":
						for cell: Vector2i in footprint:
							if world_map.cell_kind(cell) != WorldMap.Kind.OCEAN_DEEP:
								bad_zone += 1
					if id == "island_village" or id == "lighthouse_island":
						for cell: Vector2i in footprint:
							if not world_map.is_small_island(cell):
								bad_zone += 1
		_check(bad_size == 0, "seed %d : empreintes de la bonne taille (%d anomalies)" % [world_seed, bad_size])
		_check(bad_zone == 0, "seed %d : zones respectées (pleine mer, île, côte) et climats : %d anomalies" % [world_seed, bad_zone])
		_check(bad_biome == 0, "seed %d : biomes respectés sous chaque cellule : %d anomalies" % [world_seed, bad_biome])
		_check(bad_access == 0, "seed %d : accès respectés (jetée sur l'eau, héliport dans le plan) : %d anomalies" % [world_seed, bad_access])
	for id in PLACE_SIZES:
		var n: int = int(counts.get(id, 0))
		if n == 0:
			print("  AVERTISSEMENT - aucun lieu « %s » sur 5 seeds x 7 x 7 régions (rare : chance, attempts, zone ou biomes à régler)" % id)
		else:
			print("       lieux « %s » : %d" % [id, n])
	print("       accès tirés : %s" % str(access_counts))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
