class_name ContaminationMap
extends RefCounted
## Contamination du monde (docs/MONSTER_SPAWN.md §5, jalon 6c). FONCTION PURE de (seed, cellule macro = chunk) : le niveau (0 à 1) et le type
## (radiation, toxic, experiment, fire, cursed, oil) viennent des SOURCES voisines, jamais d'un état partagé ni de l'ordre d'exploration.
##
## Sources = lieux spéciaux listés dans data/worldgen/ecology.json (section « contamination », champ `sources` : id de lieu -> force, rayon, type) :
## centrale nucléaire, laboratoire, silo, bunker, usine, station d'épuration, plateforme pétrolière, volcan, station de recherche, ruines.
## Niveau d'un chunk, pour une source : force x (1 - d / rayon) ^ falloff, où d = distance (en cellules) à la cellule la plus proche de
## l'EMPREINTE du lieu (donc `force` partout sous le lieu) ; 0 au-delà du rayon. Niveau final = le plus fort des niveaux ; à égalité, la source
## rencontrée la première (ordre fixe : régions de haut en bas puis de gauche à droite, lieux dans l'ordre de SpecialMap.region_places).
##
## Une empreinte ne franchit jamais la frontière de sa région (32 x 32 cellules) : pour un chunk il suffit de lire sa région et, s'il est à moins
## de `rayon maximal` cellules d'un bord, la région voisine de ce côté (au plus 4 régions). Les lieux d'une région sont mis en cache par
## instance de SettlementMap (ils sont de toute façon calculés quand on s'y promène).

const PATH: String = "res://data/worldgen/ecology.json"
const NONE: Dictionary = {"level": 0.0, "type": ""}

static var _loaded: bool = false
static var _defs: Dictionary = {}       # id de lieu -> {force, radius, type}
static var _falloff: float = 1.0
static var _reach: int = 0              # plus grand rayon des sources (cellules, arrondi au-dessus)
static var _errors: Array[String] = []
static var _cache: Dictionary = {}      # « id d'instance/seed » de SettlementMap -> {Vector2i (région) -> Array de sources}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		_fail("%s introuvable." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("ecology.json invalide.")
		return
	var config: Dictionary = (parsed as Dictionary).get("contamination", {})
	_falloff = maxf(float(config.get("falloff", 1.0)), 0.01)
	var sources: Dictionary = config.get("sources", {})
	for id: String in sources:
		var def: Dictionary = sources[id]
		if float(def.get("force", 0.0)) <= 0.0 or float(def.get("force", 0.0)) > 1.0 or float(def.get("radius", 0.0)) <= 0.0:
			_fail("source %s : force (0 à 1] ou rayon > 0 invalide." % id)
			continue
		if String(def.get("type", "")) == "":
			_fail("source %s : type manquant." % id)
			continue
		_defs[id] = def
		_reach = maxi(_reach, ceili(float(def["radius"])))


static func _fail(message: String) -> void:
	_errors.append(message)
	push_error("ContaminationMap : " + message)


# --- Requêtes ---

static func errors() -> Array[String]:
	_ensure_loaded()
	return _errors


## Ids des lieux qui contaminent.
static func source_ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for id: String in _defs:
		out.append(id)
	return out


static func source_def(id: String) -> Dictionary:
	_ensure_loaded()
	return _defs.get(id, {})


## Plus grand rayon d'une source (cellules).
static func max_reach() -> int:
	_ensure_loaded()
	return _reach


## {level: float [0, 1], type: String} de la cellule macro `coord` ; {level: 0, type: ""} s'il n'y a pas de contamination.
static func sample(world_seed: int, coord: Vector2i) -> Dictionary:
	return sample_with(SettlementMap.for_seed(world_seed), coord)


## Idem avec une instance donnée de SettlementMap (tests : instance neuve, caches vides).
static func sample_with(settlement: SettlementMap, coord: Vector2i) -> Dictionary:
	_ensure_loaded()
	if _defs.is_empty():
		return NONE
	var size: int = SettlementMap.region_size_cells()
	var region := Vector2i(floori(float(coord.x) / size), floori(float(coord.y) / size))
	var local: Vector2i = coord - region * size
	var first_dx: int = -1 if local.x < _reach else 0
	var last_dx: int = 1 if local.x > size - 1 - _reach else 0
	var first_dy: int = -1 if local.y < _reach else 0
	var last_dy: int = 1 if local.y > size - 1 - _reach else 0
	var best_level: float = 0.0
	var best_type: String = ""
	for dy in range(first_dy, last_dy + 1):
		for dx in range(first_dx, last_dx + 1):
			for source: Dictionary in _region_sources(settlement, region + Vector2i(dx, dy)):
				var level: float = _level_from(source, coord)
				if level > best_level:
					best_level = level
					best_type = String(source["type"])
	if best_level <= 0.0:
		return NONE
	return {"level": best_level, "type": best_type}


static func level_at(world_seed: int, coord: Vector2i) -> float:
	return float(sample(world_seed, coord)["level"])


## Niveau d'une source en `coord` (0 hors du rayon).
static func _level_from(source: Dictionary, coord: Vector2i) -> float:
	var nearest: float = INF
	for cell: Vector2i in source["cells"]:
		nearest = minf(nearest, Vector2(coord).distance_to(Vector2(cell)))
	var radius: float = source["radius"]
	if nearest >= radius:
		return 0.0
	return float(source["force"]) * pow(1.0 - nearest / radius, _falloff)


## Sources d'une région : [{id, cells (empreinte), force, radius, type}] (mis en cache).
static func _region_sources(settlement: SettlementMap, region: Vector2i) -> Array:
	var key: String = "%d/%d" % [settlement.get_instance_id(), settlement.world_seed]   # la seed protège d'un id d'instance réutilisé
	if not _cache.has(key):
		_cache[key] = {}
	var by_region: Dictionary = _cache[key]
	if by_region.has(region):
		return by_region[region]
	var list: Array = []
	for place: Dictionary in settlement.specials().region_places(region):
		var id: String = place["id"]
		if _defs.has(id):
			var def: Dictionary = _defs[id]
			list.append({"id": id, "cells": place["cells"], "force": float(def["force"]), "radius": float(def["radius"]), "type": String(def["type"])})
	by_region[region] = list
	return list


## Mesure (µs) : contamination de `count x count` chunks autour de `center`, caches de la région vides ou non. Pour régler les rayons des sources.
static func benchmark(settlement: SettlementMap, center: Vector2i, count: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var contaminated: int = 0
	for dy in count:
		for dx in count:
			if float(sample_with(settlement, center + Vector2i(dx - count / 2, dy - count / 2))["level"]) > 0.0:
				contaminated += 1
	return {"us": Time.get_ticks_usec() - started, "chunks": count * count, "contaminated": contaminated}
