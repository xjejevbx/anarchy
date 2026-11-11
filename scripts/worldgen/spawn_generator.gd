class_name SpawnGenerator
extends RefCounted
## Monstres initiaux d'un chunk (docs/MONSTER_SPAWN.md §4). FONCTION PURE de (seed, clé de chunk, terrain, mobilier, réglages) :
## aucune lecture d'un chunk voisin, aucun tirage global, même résultat quel que soit l'ordre d'exploration.
##
## Deux couches, dans cet ordre (elles partagent le plafond du chunk, les cases prises et le budget de menace) :
##  1. LIEU (jalon 6b) : les règles de data/worldgen/place_spawns.json pour l'id du plan posé sur le chunk (maison, commerce, hôpital,
##     lieu spécial, lieu sur la route...). Modes : floor / paved / nature / any (densité par 100 cases candidates) et affinity (un monstre
##     par exemplaire d'un meuble ou d'un terrain, avec une probabilité : le dormeur dans son lit, le fidèle sur son banc).
##  2. AMBIANTE (jalon 6a) : ecology.json selon le contexte (rue, route, jardin, nature selon la nature de case ; l'eau est vide).
## Jalon 6c : CONTAMINATION (ContaminationMap : niveau et type du chunk). Chaque monstre tiré est remplacé par sa variante mutante avec la
## probabilité niveau x substitute_chance (ecology.json, substitutions ; règle `contaminate: false` : jamais) ; au-delà de ambient_switch_level,
## la couche ambiante tire dans eco_contaminated_<type>. Les monstres SWARM apparaissent en essaim (2 à 4 voisins de plus).
## Chaque monstre reçoit un ÉTAT (sleep / idle / guard : part « dormant » de la règle, ou état par défaut du monstre) et 0 à 2 AFFIXES
## (règle `affix`, affixes de climat d'ecology.json pour les cases extérieures, « alpha » dans un groupe de 4 et plus).
## Aucune apparition : à moins de `safe_radius` cases d'un point sûr (départ du joueur), sur une porte ou devant une porte.
## Jalon 6d : mode `water` (cases d'eau : monstres aquatiques ou nageurs), UNIQUES (règle `unique` : un monstre unique par lieu ou par chunk,
## tiré par mix(seed, LAYER_SPAWN, chunk, hash(id)), jamais repeuplé), `salt` (autre tirage de la faune ambiante : migration, voir ChunkManager) et
## `ambient_only` ; chaque entrée porte `ambient` (créée par la couche ambiante : elle migre, pas les monstres de lieu).
## Étages (z != 0) : aucun monstre pour l'instant (les règles `min_depth` des lieux à étages viendront avec le jalon 8).

const GROUPS_PATHS: Array[String] = ["res://data/worldgen/spawn_groups.json", "res://data/worldgen/spawn_groups_places.json",
	"res://data/worldgen/spawn_groups_contamination.json", "res://data/worldgen/spawn_groups_aquatic.json"]
const CONTAMINATION_TYPES: Array[String] = ["radiation", "toxic", "experiment", "fire", "cursed", "oil"]
const SWARM_EXTRA_MIN: int = 2
const SWARM_EXTRA_MAX: int = 4
const PLACES_PATH: String = "res://data/worldgen/place_spawns.json"
const ECOLOGY_PATH: String = "res://data/worldgen/ecology.json"
const MAX_GROUP_DEPTH: int = 3
const SPACING_ATTEMPTS: int = 6
const ALPHA_MIN_GROUP: int = 4      # un groupe d'au moins N monstres (une règle) peut avoir un alpha
const ALPHA_CHANCE: float = 0.08
const MODES: Array[String] = ["floor", "paved", "nature", "any", "affinity", "water"]
const RING: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static var _loaded: bool = false
static var _groups: Dictionary = {}
static var _places: Dictionary = {}      # id de plan -> Array de règles
static var _ambient: Dictionary = {}
static var _limits: Dictionary = {}
static var _climate_affixes: Array = []
static var _substitutions: Dictionary = {}   # monstre -> {type de contamination: monstre mutant ou "affix:<id>"}
static var _substitute_chance: float = 0.8
static var _switch_level: float = 0.6
static var _errors: Array[String] = []
static var _paved: Dictionary = {}       # index de terrain -> true (asphalte, trottoir, béton)
static var _indoor: Dictionary = {}      # index de terrain -> true (plancher, porte)
static var _t_door: int = -1
static var _t_floor: int = -1


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("%s introuvable." % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("%s invalide." % path)
		return {}
	return parsed


static func _fail(message: String) -> void:
	_errors.append(message)
	push_error("SpawnGenerator : " + message)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in GROUPS_PATHS:
		var groups: Dictionary = _read(path).get("groups", {})
		for id: String in groups:
			if _groups.has(id):
				_fail("%s : groupe « %s » défini deux fois." % [path, id])
			_groups[id] = groups[id]
	var raw_places: Dictionary = _read(PLACES_PATH).get("plans", {})
	for plan_id: String in raw_places:
		_places[plan_id] = raw_places[plan_id]
	for plan_id: String in _places.keys():   # {"copy": autre plan} : mêmes règles
		var value: Variant = _places[plan_id]
		if typeof(value) == TYPE_DICTIONARY:
			var source: String = String((value as Dictionary).get("copy", ""))
			if not raw_places.has(source) or typeof(raw_places[source]) != TYPE_ARRAY:
				_fail("place_spawns.json %s : copy « %s » introuvable (ou copie d'une copie)." % [plan_id, source])
				_places[plan_id] = []
			else:
				_places[plan_id] = raw_places[source]
	var ecology: Dictionary = _read(ECOLOGY_PATH)
	_ambient = ecology.get("ambient", {})
	_limits = ecology.get("limits", {})
	_climate_affixes = ecology.get("climate_affixes", [])
	var contamination: Dictionary = ecology.get("contamination", {})
	_substitutions = contamination.get("substitutions", {})
	_substitute_chance = float(contamination.get("substitute_chance", 0.8))
	_switch_level = float(contamination.get("ambient_switch_level", 0.6))
	for id: String in ["t_pavement", "t_pavement_y", "t_sidewalk", "t_concrete"]:
		if TerrainDB.has_id(id):
			_paved[TerrainDB.index_of(id)] = true
	for id: String in ["t_floor", "t_door"]:
		if TerrainDB.has_id(id):
			_indoor[TerrainDB.index_of(id)] = true
	if TerrainDB.has_id("t_door"):
		_t_door = TerrainDB.index_of("t_door")
	if TerrainDB.has_id("t_floor"):
		_t_floor = TerrainDB.index_of("t_floor")
	_validate()


## Vérifie les données : monstres et groupes cités, cycles, contextes d'écologie, plans et règles des lieux, affixes de climat.
static func _validate() -> void:
	for group_id: String in _groups:
		var entries: Array = (_groups[group_id] as Dictionary).get("entries", [])
		if entries.is_empty():
			_fail("groupe %s : aucune entrée." % group_id)
		for entry: Dictionary in entries:
			if float(entry.get("weight", 0.0)) <= 0.0:
				_fail("groupe %s : poids nul ou négatif." % group_id)
			if entry.has("monster"):
				if not MonsterDB.has_id(String(entry["monster"])):
					_fail("groupe %s : monstre inconnu « %s »." % [group_id, entry["monster"]])
			elif entry.has("group"):
				if not _groups.has(String(entry["group"])):
					_fail("groupe %s : groupe inclus inconnu « %s »." % [group_id, entry["group"]])
			else:
				_fail("groupe %s : entrée sans monster ni group." % group_id)
		if not _depth_ok(group_id, 0):
			_fail("groupe %s : cycle ou profondeur > %d." % [group_id, MAX_GROUP_DEPTH])
	for context: String in ["street", "yard", "road"]:
		_validate_context(context, _ambient.get(context, {}))
	var kinds: Dictionary = _ambient.get("kinds", {})
	for kind_id: String in kinds:
		if not RouteMap.KIND_IDS.has(kind_id):
			_fail("ecology.json : nature de case inconnue « %s »." % kind_id)
		_validate_context("kinds/" + kind_id, kinds[kind_id])
	for plan_id: String in _places:
		if MapgenDB.plan_by_id(plan_id) < 0:
			_fail("place_spawns.json : plan « %s » inconnu." % plan_id)
		for rule: Dictionary in _places[plan_id]:
			_validate_rule(plan_id, rule)
	_validate_contamination()
	for ca: Dictionary in _climate_affixes:
		if not MonsterDB.affix_ids().has(String(ca.get("affix", ""))):
			_fail("ecology.json climate_affixes : affixe inconnu « %s »." % ca.get("affix", ""))
		if ca.has("climate") and not WorldMap.CLIMATE_IDS.has(String(ca["climate"])):
			_fail("ecology.json climate_affixes : climat inconnu « %s »." % ca["climate"])
		for kind_id: Variant in ca.get("kinds", []):
			if not RouteMap.KIND_IDS.has(String(kind_id)):
				_fail("ecology.json climate_affixes : nature de case inconnue « %s »." % kind_id)


## Substitutions de contamination : monstres connus, types connus, affixes connus.
static func _validate_contamination() -> void:
	for base_id: String in _substitutions:
		if not MonsterDB.has_id(base_id):
			_fail("ecology.json substitutions : monstre inconnu « %s »." % base_id)
		var table: Dictionary = _substitutions[base_id]
		for type_id: String in table:
			if not CONTAMINATION_TYPES.has(type_id):
				_fail("ecology.json substitutions %s : type de contamination inconnu « %s »." % [base_id, type_id])
			var target: String = String(table[type_id])
			if target.begins_with("affix:"):
				if not MonsterDB.affix_ids().has(target.substr(6)):
					_fail("ecology.json substitutions %s : affixe inconnu « %s »." % [base_id, target])
			elif not MonsterDB.has_id(target):
				_fail("ecology.json substitutions %s : monstre inconnu « %s »." % [base_id, target])
	for type_id: String in CONTAMINATION_TYPES:
		if _groups.has("eco_contaminated_" + type_id) and (_groups["eco_contaminated_" + type_id] as Dictionary).get("entries", []).is_empty():
			_fail("groupe eco_contaminated_%s vide." % type_id)
	for source_id: String in ContaminationMap.source_ids():
		if not CONTAMINATION_TYPES.has(String(ContaminationMap.source_def(source_id)["type"])):
			_fail("ecology.json contamination.sources %s : type inconnu." % source_id)


static func _validate_rule(plan_id: String, rule: Dictionary) -> void:
	var label: String = "place_spawns.json %s" % plan_id
	if not _groups.has(String(rule.get("group", ""))):
		_fail("%s : groupe inconnu « %s »." % [label, rule.get("group", "")])
	var mode: String = String(rule.get("mode", ""))
	if not MODES.has(mode):
		_fail("%s : mode inconnu « %s »." % [label, mode])
	if mode == "affinity":
		var has_furniture: bool = rule.has("furniture") and FurnitureDB.has_id(String(rule["furniture"]))
		var has_terrain: bool = rule.has("terrain") and TerrainDB.has_id(String(rule["terrain"]))
		if not has_furniture and not has_terrain:
			_fail("%s : affinité sans meuble ni terrain connu." % label)
		if float(rule.get("chance", 0.0)) <= 0.0:
			_fail("%s : affinité sans chance." % label)
	elif float(rule.get("density", -1.0)) < 0.0:
		_fail("%s : densité manquante ou négative." % label)
	for field: String in ["dormant", "rare"]:
		var value: float = float(rule.get(field, 0.0))
		if value < 0.0 or value > 1.0:
			_fail("%s : %s hors de [0, 1]." % [label, field])
	var unique: Dictionary = rule.get("unique", {})
	if not unique.is_empty() and not MonsterDB.has_id(String(unique.get("monster", ""))):
		_fail("%s : unique inconnu « %s »." % [label, unique.get("monster", "")])
	var affix: Dictionary = rule.get("affix", {})
	if not affix.is_empty() and not MonsterDB.affix_ids().has(String(affix.get("id", ""))):
		_fail("%s : affixe inconnu « %s »." % [label, affix.get("id", "")])


static func _validate_context(label: String, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	if not _groups.has(String(entry.get("group", ""))):
		_fail("ecology.json %s : groupe inconnu « %s »." % [label, entry.get("group", "")])
	if float(entry.get("density", 0.0)) < 0.0:
		_fail("ecology.json %s : densité négative." % label)
	if entry.has("mode") and not MODES.has(String(entry["mode"])):
		_fail("ecology.json %s : mode inconnu « %s »." % [label, entry["mode"]])
	var unique: Dictionary = entry.get("unique", {})
	if not unique.is_empty() and not MonsterDB.has_id(String(unique.get("monster", ""))):
		_fail("ecology.json %s : unique inconnu « %s »." % [label, unique.get("monster", "")])


static func _depth_ok(group_id: String, depth: int) -> bool:
	if depth > MAX_GROUP_DEPTH:
		return false
	var entries: Array = (_groups.get(group_id, {}) as Dictionary).get("entries", [])
	for entry: Dictionary in entries:
		if entry.has("group") and not _depth_ok(String(entry["group"]), depth + 1):
			return false
	return true


# --- Requêtes (tests) ---

static func errors() -> Array[String]:
	_ensure_loaded()
	return _errors


static func group_ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for id: String in _groups:
		out.append(id)
	return out


## Ids des plans qui ont une population (place_spawns.json).
static func place_plan_ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for id: String in _places:
		out.append(id)
	return out


static func place_rules(plan_id: String) -> Array:
	_ensure_loaded()
	return _places.get(plan_id, [])


## Tous les monstres que peut donner un groupe (groupes inclus compris), sans doublon.
static func group_monsters(group_id: String) -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	_collect_monsters(group_id, out, 0)
	return out


static func _collect_monsters(group_id: String, out: Array[String], depth: int) -> void:
	if depth > MAX_GROUP_DEPTH:
		return
	for entry: Dictionary in (_groups.get(group_id, {}) as Dictionary).get("entries", []):
		if entry.has("group"):
			_collect_monsters(String(entry["group"]), out, depth + 1)
		elif not out.has(String(entry.get("monster", ""))):
			out.append(String(entry.get("monster", "")))


## Groupe ambiant d'un chunk contaminé : eco_contaminated_<type> si le niveau dépasse ambient_switch_level (et que le groupe existe), sinon `base_group`.
static func contaminated_group(base_group: String, contamination: Dictionary) -> String:
	_ensure_loaded()
	var group_id: String = "eco_contaminated_" + String(contamination.get("type", ""))
	if float(contamination.get("level", 0.0)) > _switch_level and _groups.has(group_id):
		return group_id
	return base_group


static func limit(name: String, fallback: int) -> int:
	_ensure_loaded()
	return int(_limits.get(name, fallback))


# --- Génération ---

## Monstres initiaux du chunk : [{monster, cell, facing, state, affixes}], dans l'ordre de tirage.
## `population` multiplie les densités et les chances (0 : aucun monstre) ; `safe_centers` : cases (en plus du départ par défaut de la
## seed) autour desquelles aucun monstre n'apparaît ; `plan_override` (tests) : id d'un plan dont on applique les règles à ce terrain,
## sans couche ambiante ; `contamination_override` (tests) : {level, type} imposé au lieu de ContaminationMap ; `salt` != 0 : autre tirage
## (migration de la faune) ; `ambient_only` : seulement la couche ambiante (pas de règles de lieu ni d'uniques).
static func generate(world_seed: int, key: Vector3i, terrain: PackedByteArray, furniture: PackedByteArray,
		population: float = 1.0, safe_centers: Array[Vector2i] = [], plan_override: String = "",
		contamination_override: Dictionary = {}, salt: int = 0, ambient_only: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if key.z != 0 or population <= 0.0 or terrain.size() != Chunk.CELLS:
		return out
	_ensure_loaded()
	var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
	var world_map: WorldMap = WorldMap.for_seed(world_seed)
	var coord := Vector2i(key.x, key.y)
	var plan_id: String = plan_override
	var ambient: Dictionary = {}
	var contamination: Dictionary = contamination_override
	if contamination.is_empty():
		contamination = ContaminationMap.sample_with(settlement, coord) if plan_override == "" else ContaminationMap.NONE
	if plan_override == "":
		var info: Dictionary = settlement.cell_plan(coord)
		if not info.is_empty():
			plan_id = MapgenDB.plan_id(int(info["plan"]))
		ambient = _ambient_context(world_map, settlement, coord)
		if not ambient.is_empty():
			ambient["group"] = contaminated_group(String(ambient["group"]), contamination)
	var rules: Array = _places.get(plan_id, []) if plan_id != "" and not ambient_only else []
	if rules.is_empty() and ambient.is_empty():
		return out
	var ctx: Dictionary = {"kind": world_map.cell_kind(coord), "climate": world_map.cell_climate(coord), "contamination": contamination}
	var safes: Array[Vector2i] = []
	safes.append_array(safe_centers)
	safes.append(settlement.spawn_cell())
	var ok: PackedByteArray = _base_cells(key, terrain, furniture, safes)
	var is_place: bool = not rules.is_empty()
	var st: Dictionary = {
		"taken": {}, "threat": 0, "count": 0,
		"seed": world_seed, "water": _water_cells(key, terrain, safes), "ambient_only": ambient_only,
		"cap": limit("place_max_per_chunk", 20) if is_place else limit("max_per_chunk", 12),
		"budget": limit("place_threat_budget", 60) if is_place else limit("threat_budget", 30),
	}
	var rng: RandomNumberGenerator = WorldRng.rng_for(world_seed, WorldRng.LAYER_SPAWN, key.x, key.y, key.z, salt)
	for rule: Dictionary in rules:
		_apply_rule(rule, key, terrain, furniture, ok, rng, ctx, st, population, out)
	if not ambient.is_empty():
		var first_ambient: int = out.size()
		_apply_rule(ambient, key, terrain, furniture, ok, rng, ctx, st, population, out)
		for i in range(first_ambient, out.size()):
			out[i]["ambient"] = true
	return out


## Empreinte (FNV-1a 64 bits) des monstres initiaux d'un chunk : test de déterminisme.
static func fingerprint(world_seed: int, key: Vector3i, population: float = 1.0) -> int:
	var terrain: PackedByteArray = ChunkGenerator.generate(world_seed, key)
	var furniture: PackedByteArray = ChunkGenerator.generate_furniture(world_seed, key)
	var h: int = -3750763034362895579
	for entry: Dictionary in generate(world_seed, key, terrain, furniture, population):
		var cell: Vector2i = entry["cell"]
		var facing: Vector2i = entry["facing"]
		h = (h ^ String(entry["monster"]).hash()) * 1099511628211
		h = (h ^ cell.x) * 1099511628211
		h = (h ^ cell.y) * 1099511628211
		h = (h ^ (facing.x + 2 * facing.y + 3)) * 1099511628211
		h = (h ^ String(entry["state"]).hash()) * 1099511628211
		h = (h ^ ",".join(PackedStringArray(entry["affixes"])).hash()) * 1099511628211
	return h


# --- Contexte ambiant ---

## Règle ambiante du chunk (même forme qu'une règle de lieu : group, mode, density, dormant) ou {} s'il n'en a pas.
static func _ambient_context(world_map: WorldMap, settlement: SettlementMap, coord: Vector2i) -> Dictionary:
	match settlement.cell_type(coord):
		SettlementMap.CellType.ROAD:
			return _ambient_entry("road" if settlement.is_wild_road(coord) else "street", "paved")
		SettlementMap.CellType.LOT, SettlementMap.CellType.YARD:
			return _ambient_entry("yard", "nature")
		SettlementMap.CellType.SPECIAL:
			return {}   # lieux spéciaux : leur population vient de place_spawns.json
	var kinds: Dictionary = _ambient.get("kinds", {})
	var entry: Dictionary = kinds.get(RouteMap.KIND_IDS[world_map.cell_kind(coord)], {})
	return _entry_rule(entry, "nature")


static func _ambient_entry(name: String, mode: String) -> Dictionary:
	return _entry_rule(_ambient.get(name, {}), mode)


static func _entry_rule(entry: Dictionary, mode: String) -> Dictionary:
	if entry.is_empty() or float(entry.get("density", 0.0)) <= 0.0:
		return {}
	var rule: Dictionary = entry.duplicate()
	rule["mode"] = String(entry.get("mode", mode))   # une entrée d'écologie peut imposer son mode (eau)
	return rule


# --- Cases candidates ---

## 1 si un monstre peut se tenir sur la case : praticable à pied, hors eau, sans meuble bloquant, ni sur ni devant une porte, hors zone sûre.
static func _base_cells(key: Vector3i, terrain: PackedByteArray, furniture: PackedByteArray, safes: Array[Vector2i]) -> PackedByteArray:
	var ok := PackedByteArray()
	ok.resize(Chunk.CELLS)
	var safe_radius: float = float(limit("safe_radius", 12))
	var has_furniture: bool = furniture.size() == Chunk.CELLS
	for i in Chunk.CELLS:
		var t: int = terrain[i]
		if not TerrainDB.is_walkable(t) or TerrainDB.swim_depth(t) != TerrainDB.SWIM_NONE:
			continue
		if has_furniture and furniture[i] != 0 and not FurnitureDB.is_walkable(furniture[i]):
			continue
		if _near_door(terrain, i):
			continue
		var cell: Vector2i = _cell_of(key, i)
		var safe: bool = false
		for center: Vector2i in safes:
			if Vector2(cell).distance_to(Vector2(center)) <= safe_radius:
				safe = true
				break
		if not safe:
			ok[i] = 1
	return ok


## 1 si la case est de l'eau (nageable) et hors zone sûre : cases des monstres aquatiques ou nageurs (mode `water`).
static func _water_cells(key: Vector3i, terrain: PackedByteArray, safes: Array[Vector2i]) -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize(Chunk.CELLS)
	var safe_radius: float = float(limit("safe_radius", 12))
	for i in Chunk.CELLS:
		if TerrainDB.swim_depth(terrain[i]) == TerrainDB.SWIM_NONE:
			continue
		var cell: Vector2i = _cell_of(key, i)
		var safe: bool = false
		for center: Vector2i in safes:
			if Vector2(cell).distance_to(Vector2(center)) <= safe_radius:
				safe = true
				break
		if not safe:
			flags[i] = 1
	return flags


## Indices libres (non pris) qui conviennent au mode : floor (t_floor), paved (chaussée), nature (ni chaussée, ni plancher, ni porte), any.
## Les cases avec un meuble sont exclues (sauf par le mode affinity, qui les traite à part).
static func _mode_cells(mode: String, terrain: PackedByteArray, furniture: PackedByteArray, ok: PackedByteArray, taken: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var has_furniture: bool = furniture.size() == Chunk.CELLS
	for i in Chunk.CELLS:
		if ok[i] == 0 or taken.has(i) or (has_furniture and furniture[i] != 0):
			continue
		var t: int = terrain[i]
		var fits: bool = false
		match mode:
			"floor":
				fits = t == _t_floor
			"paved":
				fits = _paved.has(t)
			"nature":
				fits = not _paved.has(t) and not _indoor.has(t)
			"any":
				fits = true
			"water":
				fits = TerrainDB.swim_depth(t) != TerrainDB.SWIM_NONE
		if fits:
			out.append(i)
	return out


## La case (indice local) est-elle une porte ou touche-t-elle une porte (4 directions, dans le chunk) ?
static func _near_door(terrain: PackedByteArray, index: int) -> bool:
	if _t_door < 0:
		return false
	if terrain[index] == _t_door:
		return true
	var lx: int = index % Chunk.SIZE
	var ly: int = floori(float(index) / Chunk.SIZE)
	for dir: Vector2i in RING:
		var nx: int = lx + dir.x
		var ny: int = ly + dir.y
		if nx < 0 or ny < 0 or nx >= Chunk.SIZE or ny >= Chunk.SIZE:
			continue
		if terrain[ny * Chunk.SIZE + nx] == _t_door:
			return true
	return false


static func _cell_of(key: Vector3i, index: int) -> Vector2i:
	return Vector2i(key.x * Chunk.SIZE + index % Chunk.SIZE, key.y * Chunk.SIZE + floori(float(index) / Chunk.SIZE))


static func _spaced(cell: Vector2i, placed: Array[Vector2i], spacing: int) -> bool:
	for other: Vector2i in placed:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) < spacing:
			return false
	return true


# --- Règles ---

static func _apply_rule(rule: Dictionary, key: Vector3i, terrain: PackedByteArray, furniture: PackedByteArray, ok: PackedByteArray,
		rng: RandomNumberGenerator, ctx: Dictionary, st: Dictionary, population: float, out: Array[Dictionary]) -> void:
	var rare: float = float(rule.get("rare", 0.0))
	if rare > 0.0 and rng.randf() >= rare:
		return
	var mode: String = String(rule.get("mode", "nature"))
	if mode == "affinity":
		_apply_affinity(rule, key, terrain, furniture, ok, rng, ctx, st, population, out)
		return
	var taken: Dictionary = st["taken"]
	var flags: PackedByteArray = st["water"] if mode == "water" else ok   # cases utilisables : eau ou terre ferme
	if rule.has("unique") and not bool(st["ambient_only"]):
		_apply_unique(rule, mode, key, terrain, furniture, flags, rng, ctx, st, out)
	var candidates: PackedInt32Array = _mode_cells(mode, terrain, furniture, flags, taken)
	var expected: float = float(rule.get("density", 0.0)) * float(candidates.size()) / 100.0 * population
	var count: int = floori(expected)
	if rng.randf() < expected - float(count):
		count += 1
	var group: String = String(rule["group"])
	var spacing: int = limit("min_spacing", 2)
	var outdoor: bool = mode == "paved" or mode == "nature"
	var placed: Array[Vector2i] = []
	var made: Array[Dictionary] = []
	for n in count:
		if candidates.is_empty() or int(st["count"]) >= int(st["cap"]):
			break
		var monster_id: String = _pick_monster(group, rng, 0)
		if monster_id == "":
			continue
		var forced_affix: String = ""
		var substitute: Array = _substitute(monster_id, rule, ctx, rng)
		monster_id = String(substitute[0])
		forced_affix = String(substitute[1])
		var threat: int = MonsterDB.threat_of(monster_id)
		if int(st["threat"]) + threat > int(st["budget"]):
			continue
		var slot: int = -1
		for attempt in SPACING_ATTEMPTS:
			var k: int = rng.randi_range(0, candidates.size() - 1)
			if _spaced(_cell_of(key, candidates[k]), placed, spacing):
				slot = k
				break
		if slot < 0:
			continue
		var index: int = candidates[slot]
		candidates.remove_at(slot)
		var cell: Vector2i = _cell_of(key, index)
		placed.append(cell)
		taken[index] = true
		st["threat"] = int(st["threat"]) + threat
		st["count"] = int(st["count"]) + 1
		var entry: Dictionary = _make_entry(monster_id, cell, rng, rule, ctx, outdoor, forced_affix)
		out.append(entry)
		made.append(entry)
		if MonsterDB.has_ability(monster_id, "SWARM"):
			_add_swarm(monster_id, index, key, flags, rng, rule, ctx, outdoor, st, out)
	if made.size() >= ALPHA_MIN_GROUP and rng.randf() < ALPHA_CHANCE:
		var affixes: Array = made[0]["affixes"]
		if affixes.size() < 2 and not affixes.has("alpha") and MonsterDB.affix_ok(String(made[0]["monster"]), "alpha"):
			affixes.append("alpha")


## Unique (règle `unique` : {monster, chance}) : tirage pur de (seed, chunk, id) ; s'il passe, une case du mode reçoit le monstre (état et
## affixes par défaut), sans tenir compte du budget de menace. Un unique tué ne revient jamais (le chunk n'est plus repeuplé).
static func _apply_unique(rule: Dictionary, mode: String, key: Vector3i, terrain: PackedByteArray, furniture: PackedByteArray, flags: PackedByteArray,
		rng: RandomNumberGenerator, ctx: Dictionary, st: Dictionary, out: Array[Dictionary]) -> void:
	var unique: Dictionary = rule["unique"]
	var unique_id: String = String(unique.get("monster", ""))
	var roll: float = WorldRng.unit(WorldRng.mix(int(st["seed"]), WorldRng.LAYER_SPAWN, key.x, key.y, WorldRng.seed_from_text(unique_id)))
	if unique_id == "" or roll >= float(unique.get("chance", 0.1)) or int(st["count"]) >= int(st["cap"]):
		return
	var taken: Dictionary = st["taken"]
	var candidates: PackedInt32Array = _mode_cells(mode, terrain, furniture, flags, taken)
	if candidates.is_empty():
		return
	var index: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	taken[index] = true
	st["threat"] = int(st["threat"]) + MonsterDB.threat_of(unique_id)
	st["count"] = int(st["count"]) + 1
	out.append(_make_entry(unique_id, _cell_of(key, index), rng, {}, ctx, false))


## Affinité : chaque meuble (ou terrain) correspondant tire sa chance ; le monstre prend la case du meuble s'il est praticable (chaise,
## banc), sinon la première case voisine libre (lit, comptoir, tombe...).
static func _apply_affinity(rule: Dictionary, key: Vector3i, terrain: PackedByteArray, furniture: PackedByteArray, ok: PackedByteArray,
		rng: RandomNumberGenerator, ctx: Dictionary, st: Dictionary, population: float, out: Array[Dictionary]) -> void:
	var furniture_index: int = 0
	if rule.has("furniture") and FurnitureDB.has_id(String(rule["furniture"])):
		furniture_index = FurnitureDB.index_of(String(rule["furniture"]))
	var terrain_index: int = -1
	if rule.has("terrain") and TerrainDB.has_id(String(rule["terrain"])):
		terrain_index = TerrainDB.index_of(String(rule["terrain"]))
	var chance: float = float(rule.get("chance", 0.5)) * population
	var group: String = String(rule["group"])
	var taken: Dictionary = st["taken"]
	var has_furniture: bool = furniture.size() == Chunk.CELLS
	for i in Chunk.CELLS:
		var matches: bool = (furniture_index > 0 and has_furniture and furniture[i] == furniture_index) \
			or (terrain_index >= 0 and terrain[i] == terrain_index)
		if not matches or rng.randf() >= chance:
			continue
		if int(st["count"]) >= int(st["cap"]):
			break
		var target: int = _affinity_cell(i, ok, taken)
		if target < 0:
			continue
		var monster_id: String = _pick_monster(group, rng, 0)
		if monster_id == "":
			continue
		var substitute: Array = _substitute(monster_id, rule, ctx, rng)
		monster_id = String(substitute[0])
		var threat: int = MonsterDB.threat_of(monster_id)
		if int(st["threat"]) + threat > int(st["budget"]):
			continue
		taken[target] = true
		st["threat"] = int(st["threat"]) + threat
		st["count"] = int(st["count"]) + 1
		out.append(_make_entry(monster_id, _cell_of(key, target), rng, rule, ctx, false, String(substitute[1])))
		if MonsterDB.has_ability(monster_id, "SWARM"):
			_add_swarm(monster_id, target, key, ok, rng, rule, ctx, false, st, out)


## Case où se tient le monstre d'un meuble : le meuble lui-même s'il est praticable, sinon la première voisine libre (dans l'ordre de RING). -1 si aucune.
static func _affinity_cell(index: int, ok: PackedByteArray, taken: Dictionary) -> int:
	if ok[index] != 0 and not taken.has(index):
		return index
	var lx: int = index % Chunk.SIZE
	var ly: int = floori(float(index) / Chunk.SIZE)
	for dir: Vector2i in RING:
		var nx: int = lx + dir.x
		var ny: int = ly + dir.y
		if nx < 0 or ny < 0 or nx >= Chunk.SIZE or ny >= Chunk.SIZE:
			continue
		var neighbor: int = ny * Chunk.SIZE + nx
		if ok[neighbor] != 0 and not taken.has(neighbor):
			return neighbor
	return -1


## Entrée finale : orientation, affixes (règle, puis climat pour les cases extérieures) et état de départ.
static func _make_entry(monster_id: String, cell: Vector2i, rng: RandomNumberGenerator, rule: Dictionary, ctx: Dictionary, outdoor: bool,
		forced_affix: String = "") -> Dictionary:
	var facing: Vector2i = RING[rng.randi_range(0, RING.size() - 1)]
	var affixes: Array[String] = []
	if forced_affix != "" and MonsterDB.affix_ok(monster_id, forced_affix):
		affixes.append(forced_affix)
	var rule_affix: Dictionary = rule.get("affix", {})
	if not rule_affix.is_empty():
		var affix_id: String = String(rule_affix.get("id", ""))
		if MonsterDB.affix_ok(monster_id, affix_id) and rng.randf() < float(rule_affix.get("chance", 0.1)):
			affixes.append(affix_id)
	if outdoor:
		for ca: Dictionary in _climate_affixes:
			var affix_id: String = String(ca.get("affix", ""))
			if affixes.size() >= 2 or affixes.has(affix_id) or not _climate_match(ca, ctx, monster_id) or not MonsterDB.affix_ok(monster_id, affix_id):
				continue
			if rng.randf() < float(ca.get("chance", 0.1)):
				affixes.append(affix_id)
	var state: String = MonsterDB.default_state_of(monster_id)
	var dormant: float = float(rule.get("dormant", 0.0))
	if dormant > 0.0 and rng.randf() < dormant and state != "guard":
		state = "sleep"
	if state == "sleep" and affixes.has("feral"):
		state = "idle"
	return {"monster": monster_id, "cell": cell, "facing": facing, "state": state, "affixes": affixes, "ambient": false}


## Substitution de contamination : [monstre, affixe imposé ("" si aucun)]. Un tirage seulement quand le monstre a une variante pour ce type.
static func _substitute(monster_id: String, rule: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> Array:
	var same: Array = [monster_id, ""]
	if not bool(rule.get("contaminate", true)):
		return same
	var contamination: Dictionary = ctx["contamination"]
	var level: float = float(contamination.get("level", 0.0))
	if level <= 0.0 or not _substitutions.has(monster_id):
		return same
	var target: String = String((_substitutions[monster_id] as Dictionary).get(String(contamination.get("type", "")), ""))
	if target == "" or rng.randf() >= level * _substitute_chance:
		return same
	if target.begins_with("affix:"):
		return [monster_id, target.substr(6)]
	return [target, ""]


## Essaim : SWARM_EXTRA_MIN à SWARM_EXTRA_MAX monstres du même type sur les cases libres voisines (rayon 2), dans la limite du plafond et du budget.
static func _add_swarm(monster_id: String, origin_index: int, key: Vector3i, ok: PackedByteArray, rng: RandomNumberGenerator,
		rule: Dictionary, ctx: Dictionary, outdoor: bool, st: Dictionary, out: Array[Dictionary]) -> void:
	var wanted: int = rng.randi_range(SWARM_EXTRA_MIN, SWARM_EXTRA_MAX)
	var taken: Dictionary = st["taken"]
	var threat: int = MonsterDB.threat_of(monster_id)
	var ox: int = origin_index % Chunk.SIZE
	var oy: int = floori(float(origin_index) / Chunk.SIZE)
	for radius in range(1, 3):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if wanted <= 0:
					return
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var nx: int = ox + dx
				var ny: int = oy + dy
				if nx < 0 or ny < 0 or nx >= Chunk.SIZE or ny >= Chunk.SIZE:
					continue
				var index: int = ny * Chunk.SIZE + nx
				if ok[index] == 0 or taken.has(index):
					continue
				if int(st["count"]) >= int(st["cap"]) or int(st["threat"]) + threat > int(st["budget"]):
					return
				taken[index] = true
				st["threat"] = int(st["threat"]) + threat
				st["count"] = int(st["count"]) + 1
				out.append(_make_entry(monster_id, _cell_of(key, index), rng, rule, ctx, outdoor))
				wanted -= 1


static func _climate_match(ca: Dictionary, ctx: Dictionary, monster_id: String) -> bool:
	if ca.has("climate") and WorldMap.CLIMATE_IDS.find(String(ca["climate"])) != int(ctx["climate"]):
		return false
	if ca.has("kinds") and not (ca["kinds"] as Array).has(RouteMap.KIND_IDS[int(ctx["kind"])]):
		return false
	if ca.has("tag") and not MonsterDB.tags_of(monster_id).has(String(ca["tag"])):
		return false
	return true


## Monstre tiré dans un groupe pondéré (les groupes inclus sont tirés récursivement). "" si le groupe est vide.
static func _pick_monster(group_id: String, rng: RandomNumberGenerator, depth: int) -> String:
	var entries: Array = (_groups.get(group_id, {}) as Dictionary).get("entries", [])
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += float(entry.get("weight", 0.0))
	if total <= 0.0:
		return ""
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	var chosen: Dictionary = entries[entries.size() - 1]
	for entry: Dictionary in entries:
		acc += float(entry.get("weight", 0.0))
		if roll < acc:
			chosen = entry
			break
	if chosen.has("group"):
		return "" if depth >= MAX_GROUP_DEPTH else _pick_monster(String(chosen["group"]), rng, depth + 1)
	return String(chosen.get("monster", ""))
