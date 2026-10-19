class_name SpecialMap
extends RefCounted
## Lieux spéciaux : station-service, motel, ferme... (docs/WORLD_GEN.md §5.4, jalons 4 et 10). FONCTION PURE de (seed, région) :
## les lieux d'une région ne dépendent que de la seed et de la région, jamais d'une autre région déjà générée.
##
## Une EMPREINTE (cellules macro d'un chunk chacune, facade au sud) est placée dans une région, sans jamais franchir sa frontière.
## Pour chaque lieu, trié par (priorité décroissante, id), `max_per_region` fois : avec la probabilité `chance`, jusqu'à `attempts`
## tentatives (rotation, position, puis accès si le lieu en propose plusieurs, tirés par WorldRng.rng_for(seed, LAYER_SPECIAL, région, id)).
## Une tentative est valide si, sous toute l'empreinte : cellule hors ville, hors rue ou route (SettlementMap.cell_type sans lieux), biome
## autorisé, cellule libre (aucun autre lieu, aucune piste) ; et si les règles du lieu sont remplies :
##   - `climates` : climat de chaque cellule parmi ceux du lieu (WorldMap.cell_climate) ;
##   - `zone` : "land" (défaut, rien de plus), "island" (toute l'empreinte sur une petite île d'au moins `min_island_cells` cellules),
##     "coast" (de l'océan à une cellule de l'empreinte), "open_ocean" (aucune terre à moins de `min_land_distance` cellules) ;
##   - `access` : liste de modes, un est tiré par tentative : "road" (la façade touche une route), "track" (une piste de terre, de
##     `track_max_length` cellules au plus et dans la région, relie la porte à une route), "helipad" (le plan contient un héliport :
##     aucune piste), "pier" (la façade donne sur l'eau : le plan contient la jetée), "none" (aucun accès) ;
##   - la distance à la ville la plus proche est dans [min_town_distance, max_town_distance].
## La rotation tourne la facade vers la route (ou vers l'eau, ou la piste) ; le plan de chaque cellule tourne avec elle.
## Réglages : data/worldgen/specials.json. Plans : data/worldgen/mapgen/*.json.

const PATH: String = "res://data/worldgen/specials.json"
const FAR: int = 1 << 30
const ACCESS_IDS: Array[String] = ["road", "track", "helipad", "pier", "none"]
const ZONES: Array[String] = ["land", "island", "coast", "open_ocean"]

static var _config: Dictionary = {}

var world_seed: int = 0

var _settlement_ref: WeakRef   # faible : SettlementMap possède cette instance
var _world_map: WorldMap
var _region_size: int
var _attempts: int
var _track_max: int
var _places: Array[Dictionary] = []   # triés (priorité décroissante, puis id)
var _by_id: Dictionary = {}
var _regions: Dictionary = {}         # Vector2i (région) -> {cells: {cellule: {place, plan, rot}}, placed: [...], tracks: {cellule: masque}}
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
	_track_max = int(_config.get("track_max_length", 12))
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
	var has_door: bool = false
	var has_helipad: bool = false
	var has_pier: bool = false
	var helipad_terrain: int = TerrainDB.index_of("t_helipad") if TerrainDB.has_id("t_helipad") else -1
	var pier_terrain: int = TerrainDB.index_of("t_pier") if TerrainDB.has_id("t_pier") else -1
	for c: Dictionary in def.get("cells", []):
		var off: Array = c.get("offset", [0, 0])
		var offset := Vector2i(int(off[0]), int(off[1]))
		var mapgen_id: String = String(c.get("mapgen", ""))
		var plan: int = MapgenDB.plan_by_id(mapgen_id)
		if plan < 0:
			_fail("%s : plan « %s » introuvable." % [id, mapgen_id])
			return
		cells.append({"offset": offset, "mapgen": mapgen_id})
		width = maxi(width, offset.x + 1)
		height = maxi(height, offset.y + 1)
		has_door = has_door or MapgenDB.has_door(plan)
		has_helipad = has_helipad or (helipad_terrain >= 0 and MapgenDB.has_terrain(plan, helipad_terrain))
		has_pier = has_pier or (pier_terrain >= 0 and MapgenDB.has_terrain(plan, pier_terrain))
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
	var climates: Array[int] = []
	for climate in def.get("climates", []):
		var climate_index: int = WorldMap.CLIMATE_IDS.find(String(climate))
		if climate_index < 0:
			_fail("%s : climat inconnu « %s »." % [id, climate])
			return
		climates.append(climate_index)
	var zone: String = String(def.get("zone", "land"))
	if not ZONES.has(zone):
		_fail("%s : zone inconnue « %s »." % [id, zone])
		return
	# Accès : "access" (liste) ; l'ancien champ "near_road" (booléen) reste compris.
	var raw_access: Array = def.get("access", ["road"] if bool(def.get("near_road", false)) else ["none"])
	var access: Array[String] = []
	for mode in raw_access:
		var mode_id: String = String(mode)
		if not ACCESS_IDS.has(mode_id):
			_fail("%s : accès inconnu « %s »." % [id, mode_id])
			return
		access.append(mode_id)
	if access.is_empty():
		_fail("%s : liste d'accès vide (mettre \"none\")." % id)
		return
	if (access.has("track") or access.has("pier")) and not has_door:
		_fail("%s : accès piste / jetée mais aucun plan avec une porte." % id)
		return
	if access.has("helipad") and not has_helipad:
		_fail("%s : accès héliport mais aucun plan ne contient t_helipad." % id)
		return
	if access.has("pier") and not has_pier:
		_fail("%s : accès jetée mais aucun plan ne contient t_pier." % id)
		return
	var place: Dictionary = {
		"id": id, "name": String(def.get("name", id)), "priority": int(def.get("priority", 0)),
		"chance": float(def.get("chance", 1.0)), "biomes": biomes, "climates": climates, "zone": zone, "access": access,
		"min_land_distance": int(def.get("min_land_distance", 3)), "min_island_cells": int(def.get("min_island_cells", 1)),
		"track_max_length": int(def.get("track_max_length", _track_max)), "attempts": int(def.get("attempts", _attempts)),
		"min_town_distance": int(def.get("min_town_distance", -1)), "max_town_distance": int(def.get("max_town_distance", -1)),
		"max_per_region": int(def.get("max_per_region", 1)), "cells": cells, "width": width, "height": height,
		"hash": WorldRng.seed_from_text(id), "common": bool(def.get("common", true)),
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


## Lieu qui ne se place QUE le long d'une route (accès "road" seul).
func place_needs_road(id: String) -> bool:
	var access: Array = (_by_id.get(id, {}) as Dictionary).get("access", [])
	return access.size() == 1 and access[0] == "road"


## Modes d'accès possibles du lieu ("road", "track", "helipad", "pier", "none").
func place_access_options(id: String) -> Array:
	return (_by_id.get(id, {}) as Dictionary).get("access", [])


func place_zone(id: String) -> String:
	return String((_by_id.get(id, {}) as Dictionary).get("zone", "land"))


## Lieu assez fréquent pour être attendu dans toute fenêtre de 7 x 7 régions (faux : rare, exempté de ce contrôle du test).
func place_is_common(id: String) -> bool:
	return bool((_by_id.get(id, {}) as Dictionary).get("common", true))


func biome_ok(id: String, kind: int) -> bool:
	return (_by_id.get(id, {}) as Dictionary).get("biomes", []).has(kind)


## Les cellules de l'empreinte respectent-elles les climats du lieu (aucun climat listé = tous) ?
func climate_ok(id: String, footprint: Array) -> bool:
	return _climate_ok(_by_id.get(id, {}), footprint)


## Les cellules de l'empreinte respectent-elles la zone du lieu (île, côte, pleine mer) ?
func zone_ok(id: String, footprint: Array) -> bool:
	return _zone_ok(_by_id.get(id, {}), footprint)


## La façade (côté de la porte) donne-t-elle sur l'eau (lac ou océan) ?
func front_water(id: String, footprint: Array, rot: int) -> bool:
	return _front_water(_by_id.get(id, {}), footprint, rot)


## Cellules de l'empreinte qui ont une porte au bord de la façade : [{from: cellule du lieu, to: cellule devant la porte}].
func door_fronts(id: String, footprint: Array, rot: int) -> Array:
	return _door_fronts(_by_id.get(id, {}), footprint, rot)


func _region_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / _region_size), floori(float(cell.y) / _region_size))


## {place, plan (id du plan), rot} si la cellule fait partie d'un lieu, sinon {}.
func special_cell(cell: Vector2i) -> Dictionary:
	var cells: Dictionary = region_data(_region_of(cell))["cells"]
	return cells.get(cell, {})


func is_special(cell: Vector2i) -> bool:
	return (region_data(_region_of(cell))["cells"] as Dictionary).has(cell)


## Masque de connexions (bits SettlementMap.DIR_*) de la piste qui traverse la cellule, -1 si ce n'est pas une cellule de piste.
func track_mask(cell: Vector2i) -> int:
	var tracks: Dictionary = region_data(_region_of(cell))["tracks"]
	return int(tracks.get(cell, -1))


func is_track(cell: Vector2i) -> bool:
	return track_mask(cell) >= 0


## La cellule est-elle une piste reliée dans la direction `bit` (un bit SettlementMap.DIR_*) ?
func track_links(cell: Vector2i, bit: int) -> bool:
	var mask: int = track_mask(cell)
	return mask >= 0 and (mask & bit) != 0


## Lieux placés dans la région : [{id, origin, rot, cells: Array[Vector2i], access: String, track_cells: Array (dans l'ordre, de la porte à la route)}].
func region_places(region: Vector2i) -> Array:
	return region_data(region)["placed"]


## Empreinte des lieux et des pistes d'une région (test de déterminisme).
func region_fingerprint(region: Vector2i) -> int:
	var cells: Dictionary = region_data(region)["cells"]
	var tracks: Dictionary = region_data(region)["tracks"]
	var origin: Vector2i = region * _region_size
	var h: int = -3750763034362895579
	for y in _region_size:
		for x in _region_size:
			var value: int = 0
			var cell: Vector2i = origin + Vector2i(x, y)
			var info: Dictionary = cells.get(cell, {})
			if not info.is_empty():
				value = (MapgenDB.plan_by_id(String(info["plan"])) + 1) * 8 + int(info["rot"]) + 1
			elif tracks.has(cell):
				value = 100000 + int(tracks[cell])
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
	var tracks: Dictionary = {}
	for place: Dictionary in _places:
		var rng: RandomNumberGenerator = WorldRng.rng_for(world_seed, WorldRng.LAYER_SPECIAL, region.x, region.y, int(place["hash"]))
		for n in int(place["max_per_region"]):
			if rng.randf() >= float(place["chance"]):
				continue
			for attempt in int(place["attempts"]):
				var rot: int = rng.randi_range(0, 3)
				var dims: Vector2i = _dims(place, rot)
				if dims.x > _region_size or dims.y > _region_size:
					break
				var origin: Vector2i = low + Vector2i(rng.randi_range(0, _region_size - dims.x), rng.randi_range(0, _region_size - dims.y))
				var access: String = _pick_access(place, rng)
				var footprint: Array[Vector2i] = _footprint(place, origin, rot)
				var new_track: Dictionary = {}
				if _fits(settlement, place, footprint, rot, cells, tracks, access, region, new_track):
					var plan_cells: Array = place["cells"]
					for i in footprint.size():
						cells[footprint[i]] = {"place": place["id"], "plan": (plan_cells[i] as Dictionary)["mapgen"], "rot": rot}
					for track_cell: Vector2i in new_track:
						tracks[track_cell] = new_track[track_cell]
					placed.append({"id": place["id"], "origin": origin, "rot": rot, "cells": footprint, "access": access,
						"track_cells": new_track.keys()})
					break
	return {"cells": cells, "placed": placed, "tracks": tracks}


## Mode d'accès de la tentative. Un tirage n'a lieu que s'il y a le choix (les lieux à accès unique gardent leur suite de tirages).
func _pick_access(place: Dictionary, rng: RandomNumberGenerator) -> String:
	var options: Array = place["access"]
	if options.size() == 1:
		return String(options[0])
	return String(options[rng.randi_range(0, options.size() - 1)])


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


func _fits(settlement: SettlementMap, place: Dictionary, footprint: Array[Vector2i], rot: int, taken: Dictionary,
		tracks: Dictionary, access: String, region: Vector2i, out_track: Dictionary) -> bool:
	var biomes: Array = place["biomes"]
	for cell in footprint:
		if taken.has(cell) or tracks.has(cell) or not settlement.town_at(cell).is_empty():
			return false
		if not biomes.has(_world_map.cell_kind(cell)):
			return false
		if settlement.cell_type(cell, true, false) != SettlementMap.CellType.NONE:
			return false
	if not _climate_ok(place, footprint) or not _zone_ok(place, footprint):
		return false
	match access:
		"road":
			if not front_touches_road(footprint, rot):
				return false
		"pier":
			if not _front_water(place, footprint, rot):
				return false
	if not _town_distance_ok(settlement, place, footprint):
		return false
	if access == "track":  # le plus coûteux en dernier
		var track: Variant = _find_track(settlement, place, footprint, rot, region, taken, tracks)
		if track == null:
			return false
		for track_cell: Vector2i in (track as Dictionary):
			out_track[track_cell] = track[track_cell]
	return true


func _climate_ok(place: Dictionary, footprint: Array) -> bool:
	var climates: Array = place.get("climates", [])
	if climates.is_empty():
		return true
	for cell: Vector2i in footprint:
		if not climates.has(_world_map.cell_climate(cell)):
			return false
	return true


func _zone_ok(place: Dictionary, footprint: Array) -> bool:
	match String(place.get("zone", "land")):
		"island":
			var minimum: int = int(place["min_island_cells"])
			for cell: Vector2i in footprint:
				var size: int = _world_map.island_size(cell)
				if size < minimum or size >= _world_map.island_max_cells():
					return false
			return true
		"coast":
			for cell: Vector2i in footprint:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if WorldMap.is_ocean(_world_map.cell_kind(cell + Vector2i(dx, dy))):
							return true
			return false
		"open_ocean":
			var distance: int = int(place["min_land_distance"])
			var low: Vector2i = footprint[0]
			var high: Vector2i = footprint[0]
			for cell: Vector2i in footprint:
				low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
				high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
			for y in range(low.y - distance, high.y + distance + 1):
				for x in range(low.x - distance, high.x + distance + 1):
					if not WorldMap.is_ocean(_world_map.cell_kind(Vector2i(x, y))):
						return false
			return true
	return true


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


func _door_fronts(place: Dictionary, footprint: Array, rot: int) -> Array:
	var front: Vector2i = SettlementMap.HOUSE_FRONTS[rot]
	var inside: Dictionary = {}
	for c in footprint:
		inside[c] = true
	var out: Array = []
	var plan_cells: Array = place["cells"]
	for i in footprint.size():
		var cell: Vector2i = footprint[i]
		var next: Vector2i = cell + front
		if inside.has(next):
			continue
		var plan: int = MapgenDB.plan_by_id(String((plan_cells[i] as Dictionary)["mapgen"]))
		if plan >= 0 and MapgenDB.has_door(plan):
			out.append({"from": cell, "to": next})
	return out


func _front_water(place: Dictionary, footprint: Array, rot: int) -> bool:
	for pair: Dictionary in _door_fronts(place, footprint, rot):
		var kind: int = _world_map.cell_kind(pair["to"])
		if WorldMap.is_ocean(kind) or kind == WorldMap.Kind.LAKE_DEEP or kind == WorldMap.Kind.LAKE_SHALLOW:
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


# --- Pistes ---

static func _dir_bit(dir: Vector2i) -> int:
	var index: int = SettlementMap.DIRS.find(dir)
	return (1 << index) if index >= 0 else 0


## Piste de terre qui relie la porte du lieu à une route : {cellule: masque} (dictionnaire vide si la porte donne déjà sur une route),
## ou null s'il n'y a aucun chemin. Parcours en largeur dans la région, au plus `track_max_length` cellules, façade d'abord (tracé droit).
func _find_track(settlement: SettlementMap, place: Dictionary, footprint: Array[Vector2i], rot: int, region: Vector2i,
		taken: Dictionary, tracks: Dictionary) -> Variant:
	var pairs: Array = _door_fronts(place, footprint, rot)
	for pair: Dictionary in pairs:
		if settlement.cell_type(pair["to"], true, false) == SettlementMap.CellType.ROAD:
			return {}
	var blocked: Dictionary = {}
	for c in footprint:
		blocked[c] = true
	for pair: Dictionary in pairs:
		var result: Variant = _bfs_track(settlement, pair["from"], pair["to"], rot, int(place["track_max_length"]), region, taken, tracks, blocked)
		if result != null:
			return result
	return null


func _bfs_track(settlement: SettlementMap, from_cell: Vector2i, start: Vector2i, rot: int, max_length: int, region: Vector2i,
		taken: Dictionary, tracks: Dictionary, blocked: Dictionary) -> Variant:
	if not _track_cell_ok(settlement, start, region, taken, tracks, blocked):
		return null
	var front: Vector2i = SettlementMap.HOUSE_FRONTS[rot]
	var dirs: Array[Vector2i] = [front]
	for d in SettlementMap.DIRS:
		if d != front:
			dirs.append(d)
	var came: Dictionary = {start: start}
	var depth: Dictionary = {start: 1}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var node: Vector2i = queue[head]
		head += 1
		var road_dir: Vector2i = _road_neighbor_dir(settlement, node)
		if road_dir != Vector2i.ZERO:
			return _track_masks(came, start, node, from_cell, road_dir)
		if int(depth[node]) >= max_length:
			continue
		for d in dirs:
			var next: Vector2i = node + d
			if came.has(next) or not _track_cell_ok(settlement, next, region, taken, tracks, blocked):
				continue
			came[next] = node
			depth[next] = int(depth[node]) + 1
			queue.append(next)
	return null


## Direction d'une route voisine de la cellule (premier de DIRS), Vector2i.ZERO s'il n'y en a pas.
func _road_neighbor_dir(settlement: SettlementMap, cell: Vector2i) -> Vector2i:
	for d in SettlementMap.DIRS:
		if settlement.cell_type(cell + d, true, false) == SettlementMap.CellType.ROAD:
			return d
	return Vector2i.ZERO


func _track_cell_ok(settlement: SettlementMap, cell: Vector2i, region: Vector2i, taken: Dictionary, tracks: Dictionary,
		blocked: Dictionary) -> bool:
	if _region_of(cell) != region or blocked.has(cell) or taken.has(cell) or tracks.has(cell):
		return false
	if not settlement.town_at(cell).is_empty() or settlement.cell_type(cell, true, false) != SettlementMap.CellType.NONE:
		return false
	return not WorldMap.is_water(_world_map.cell_kind(cell))


## Masques de connexions du chemin (de la porte à la route) : chaque cellule relie la précédente et la suivante ; la première la
## cellule du lieu, la dernière la route.
func _track_masks(came: Dictionary, start: Vector2i, end: Vector2i, from_cell: Vector2i, road_dir: Vector2i) -> Dictionary:
	var path: Array[Vector2i] = [end]
	var current: Vector2i = end
	while current != start:
		current = came[current]
		path.append(current)
	path.reverse()
	var masks: Dictionary = {}
	for i in path.size():
		var previous: Vector2i = from_cell if i == 0 else path[i - 1]
		var mask: int = _dir_bit(previous - path[i])
		if i == path.size() - 1:
			mask |= _dir_bit(road_dir)
		else:
			mask |= _dir_bit(path[i + 1] - path[i])
		masks[path[i]] = mask
	return masks
