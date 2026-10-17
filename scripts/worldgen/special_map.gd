class_name SpecialMap
extends RefCounted
## Lieux spéciaux : station-service, motel, ferme... (docs/WORLD_GEN.md §5.4, jalon 4). FONCTION PURE de (seed, région) :
## les lieux d'une région ne dépendent que de la seed et de la région, jamais d'une autre région déjà générée.
##
## Une EMPREINTE (cellules macro d'un chunk chacune, facade au sud) est placée dans une région, sans jamais franchir sa frontière.
## Pour chaque lieu, trié par (priorité décroissante, id), `max_per_region` fois : avec la probabilité `chance`, jusqu'à `attempts`
## tentatives (rotation et position tirées par WorldRng.rng_for(seed, LAYER_SPECIAL, région, id)). Une tentative est valide si, sous toute
## l'empreinte : cellule hors ville, hors rue ou route (SettlementMap.cell_type sans lieux), biome autorisé, cellule libre (aucun autre lieu) ;
## et si la facade (côté tourné vers la route) touche une route (near_road), et la distance à la ville la plus proche est dans
## [min_town_distance, max_town_distance]. La rotation tourne la facade vers la route ; le plan de chaque cellule tourne avec elle.
## Réglages : data/worldgen/specials.json. Plans : data/worldgen/mapgen/places.json.

const PATH: String = "res://data/worldgen/specials.json"
const FAR: int = 1 << 30

static var _config: Dictionary = {}

var world_seed: int = 0

var _settlement_ref: WeakRef   # faible : SettlementMap possède cette instance
var _world_map: WorldMap
var _region_size: int
var _attempts: int
var _places: Array[Dictionary] = []   # triés (priorité décroissante, puis id)
var _by_id: Dictionary = {}
var _regions: Dictionary = {}         # Vector2i (région) -> {cells: {cellule: {place, plan, rot}}, placed: [...]}
var _errors: Array[String] = []


static func _load_config() -> void:
	if not _config.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SpecialMap : %s introuvable ou invalide." % PATH)
		return
	_config = parsed


func _init(settlement: SettlementMap) -> void:
	world_seed = settlement.world_seed
	_settlement_ref = weakref(settlement)
	_world_map = WorldMap.for_seed(world_seed)
	_load_config()
	_region_size = SettlementMap.region_size_cells()
	_attempts = int(_config.get("attempts", 40))
	var defs: Dictionary = _config.get("places", {})
	for id: String in defs:
		_add_place(id, defs[id])
	_places.sort_custom(_place_before)


func _settlement() -> SettlementMap:
	return _settlement_ref.get_ref() as SettlementMap


func _fail(message: String) -> void:
	_errors.append(message)
	push_error("SpecialMap : " + message)


func _add_place(id: String, def: Dictionary) -> void:
	var cells: Array[Dictionary] = []
	var width: int = 1
	var height: int = 1
	for c: Dictionary in def.get("cells", []):
		var off: Array = c.get("offset", [0, 0])
		var offset := Vector2i(int(off[0]), int(off[1]))
		var mapgen_id: String = String(c.get("mapgen", ""))
		if MapgenDB.plan_by_id(mapgen_id) < 0:
			_fail("%s : plan « %s » introuvable." % [id, mapgen_id])
			return
		cells.append({"offset": offset, "mapgen": mapgen_id})
		width = maxi(width, offset.x + 1)
		height = maxi(height, offset.y + 1)
	if cells.is_empty():
		_fail("%s : aucune cellule." % id)
		return
	var biomes: Array[int] = []
	for biome in def.get("biomes", []):
		var kind: int = RouteMap.KIND_IDS.find(String(biome))
		if kind < 0:
			_fail("%s : biome inconnu « %s »." % [id, biome])
			return
		biomes.append(kind)
	var place: Dictionary = {
		"id": id, "name": String(def.get("name", id)), "priority": int(def.get("priority", 0)),
		"chance": float(def.get("chance", 1.0)), "biomes": biomes, "near_road": bool(def.get("near_road", false)),
		"min_town_distance": int(def.get("min_town_distance", -1)), "max_town_distance": int(def.get("max_town_distance", -1)),
		"max_per_region": int(def.get("max_per_region", 1)), "cells": cells, "width": width, "height": height,
		"hash": WorldRng.seed_from_text(id),
	}
	_by_id[id] = place
	_places.append(place)


static func _place_before(a: Dictionary, b: Dictionary) -> bool:
	if a["priority"] != b["priority"]:
		return a["priority"] > b["priority"]
	return String(a["id"]) < String(b["id"])


# --- Requêtes ---

func errors() -> Array[String]:
	return _errors


## Ids des lieux, dans l'ordre de placement.
func place_ids() -> Array[String]:
	var out: Array[String] = []
	for p in _places:
		out.append(String(p["id"]))
	return out


func place_name(id: String) -> String:
	return String((_by_id.get(id, {}) as Dictionary).get("name", id))


func place_needs_road(id: String) -> bool:
	return bool((_by_id.get(id, {}) as Dictionary).get("near_road", false))


func biome_ok(id: String, kind: int) -> bool:
	return (_by_id.get(id, {}) as Dictionary).get("biomes", []).has(kind)


func _region_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / _region_size), floori(float(cell.y) / _region_size))


## {place, plan (id du plan), rot} si la cellule fait partie d'un lieu, sinon {}.
func special_cell(cell: Vector2i) -> Dictionary:
	var cells: Dictionary = region_data(_region_of(cell))["cells"]
	return cells.get(cell, {})


func is_special(cell: Vector2i) -> bool:
	return (region_data(_region_of(cell))["cells"] as Dictionary).has(cell)


## Lieux placés dans la région : [{id, origin, rot, cells: Array[Vector2i]}].
func region_places(region: Vector2i) -> Array:
	return region_data(region)["placed"]


## Empreinte des lieux d'une région (test de déterminisme).
func region_fingerprint(region: Vector2i) -> int:
	var cells: Dictionary = region_data(region)["cells"]
	var origin: Vector2i = region * _region_size
	var h: int = -3750763034362895579
	for y in _region_size:
		for x in _region_size:
			var value: int = 0
			var info: Dictionary = cells.get(origin + Vector2i(x, y), {})
			if not info.is_empty():
				value = (MapgenDB.plan_by_id(String(info["plan"])) + 1) * 8 + int(info["rot"]) + 1
			h = (h ^ value) * 1099511628211
	return h


# --- Placement ---

func region_data(region: Vector2i) -> Dictionary:
	if not _regions.has(region):
		_regions[region] = _generate(region)
	return _regions[region]


func _generate(region: Vector2i) -> Dictionary:
	var settlement: SettlementMap = _settlement()
	var low: Vector2i = region * _region_size
	var cells: Dictionary = {}
	var placed: Array = []
	for place: Dictionary in _places:
		var rng: RandomNumberGenerator = WorldRng.rng_for(world_seed, WorldRng.LAYER_SPECIAL, region.x, region.y, int(place["hash"]))
		for n in int(place["max_per_region"]):
			if rng.randf() >= float(place["chance"]):
				continue
			for attempt in _attempts:
				var rot: int = rng.randi_range(0, 3)
				var dims: Vector2i = _dims(place, rot)
				if dims.x > _region_size or dims.y > _region_size:
					break
				var origin: Vector2i = low + Vector2i(rng.randi_range(0, _region_size - dims.x), rng.randi_range(0, _region_size - dims.y))
				var footprint: Array[Vector2i] = _footprint(place, origin, rot)
				if _fits(settlement, place, footprint, rot, cells):
					var plan_cells: Array = place["cells"]
					for i in footprint.size():
						cells[footprint[i]] = {"place": place["id"], "plan": (plan_cells[i] as Dictionary)["mapgen"], "rot": rot}
					placed.append({"id": place["id"], "origin": origin, "rot": rot, "cells": footprint})
					break
	return {"cells": cells, "placed": placed}


static func _dims(place: Dictionary, rot: int) -> Vector2i:
	var w: int = place["width"]
	var h: int = place["height"]
	return Vector2i(h, w) if rot % 2 == 1 else Vector2i(w, h)


## Cellule de l'empreinte tournée de `rot` quarts de tour horaires (même transformation que les plans).
static func _rotate_offset(offset: Vector2i, rot: int, w: int, h: int) -> Vector2i:
	match rot:
		1:
			return Vector2i(h - 1 - offset.y, offset.x)
		2:
			return Vector2i(w - 1 - offset.x, h - 1 - offset.y)
		3:
			return Vector2i(offset.y, w - 1 - offset.x)
	return offset


## Cellules du monde de l'empreinte, dans l'ordre des cellules du lieu.
func _footprint(place: Dictionary, origin: Vector2i, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Dictionary in place["cells"]:
		out.append(origin + _rotate_offset(c["offset"], rot, int(place["width"]), int(place["height"])))
	return out


func _fits(settlement: SettlementMap, place: Dictionary, footprint: Array[Vector2i], rot: int, taken: Dictionary) -> bool:
	var biomes: Array = place["biomes"]
	for cell in footprint:
		if taken.has(cell) or not settlement.town_at(cell).is_empty():
			return false
		if not biomes.has(_world_map.cell_kind(cell)):
			return false
		if settlement.cell_type(cell, true, false) != SettlementMap.CellType.NONE:
			return false
	if bool(place["near_road"]) and not front_touches_road(footprint, rot):
		return false
	return _town_distance_ok(settlement, place, footprint)


## Une cellule voisine de la facade (côté HOUSE_FRONTS[rot]) est-elle une rue ou une route ?
func front_touches_road(footprint: Array, rot: int) -> bool:
	var settlement: SettlementMap = _settlement()
	var inside: Dictionary = {}
	for c in footprint:
		inside[c] = true
	var front: Vector2i = SettlementMap.HOUSE_FRONTS[rot]
	for c: Vector2i in footprint:
		var next: Vector2i = c + front
		if not inside.has(next) and settlement.cell_type(next, true, false) == SettlementMap.CellType.ROAD:
			return true
	return false


func _town_distance_ok(settlement: SettlementMap, place: Dictionary, footprint: Array[Vector2i]) -> bool:
	var min_d: int = place["min_town_distance"]
	var max_d: int = place["max_town_distance"]
	if min_d < 0 and max_d < 0:
		return true
	var reach: int = ceili(float(maxi(max_d, min_d) + 1) / float(_region_size)) + 1
	var region: Vector2i = _region_of(footprint[0])
	var nearest: int = FAR
	for ry in range(region.y - reach, region.y + reach + 1):
		for rx in range(region.x - reach, region.x + reach + 1):
			for town: Dictionary in settlement.towns_in_region(Vector2i(rx, ry)):
				var center: Vector2i = town["center"]
				var radius: int = town["radius"]
				for cell in footprint:
					var d: int = maxi(absi(cell.x - center.x), absi(cell.y - center.y)) - radius
					nearest = mini(nearest, maxi(d, 0))
	if min_d >= 0 and nearest < min_d:
		return false
	return max_d < 0 or nearest <= max_d
