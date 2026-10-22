class_name SpawnGenerator
extends RefCounted
## Monstres initiaux d'un chunk (docs/MONSTER_SPAWN.md §4). FONCTION PURE de (seed, clé de chunk, terrain, mobilier, réglages) :
## aucune lecture d'un chunk voisin, aucun tirage global, même résultat quel que soit l'ordre d'exploration.
## Jalon 6a : couche AMBIANTE seulement (data/worldgen/ecology.json + spawn_groups.json). Les lieux spéciaux n'ont pas encore de
## population (jalon 6b) et les plans de bâtiments ne reçoivent rien : seules les cases hors bâtiment comptent (rues, routes, jardins, nature).
##
## Contexte du chunk (type de cellule macro, comme ChunkGenerator) :
##   rue de ville -> « street » (cases asphalte / trottoir / béton) ; route entre villes -> « road » (idem) ;
##   parcelle ou jardin -> « yard » (cases de terrain naturel) ; lieu spécial -> rien ;
##   sinon -> la nature de case de la cellule (« kinds » d'ecology.json ; l'eau n'a pas de monstre en 6a) (cases de terrain naturel).
## Déroulement : nombre attendu = densité x cases candidates / 100 x population (partie entière + tirage sur le reste), plafonné ;
## pour chaque monstre : tirage dans le groupe pondéré, case candidate tirée (espacement minimal), budget de menace respecté.
## Aucune apparition : à moins de `safe_radius` cases d'un point sûr (départ du joueur), sur une porte ou devant une porte.

const GROUPS_PATH: String = "res://data/worldgen/spawn_groups.json"
const ECOLOGY_PATH: String = "res://data/worldgen/ecology.json"
const MAX_GROUP_DEPTH: int = 3
const SPACING_ATTEMPTS: int = 6
const RING: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static var _loaded: bool = false
static var _groups: Dictionary = {}
static var _ambient: Dictionary = {}
static var _limits: Dictionary = {}
static var _errors: Array[String] = []
static var _paved: Dictionary = {}    # index de terrain -> true (asphalte, trottoir, béton)
static var _indoor: Dictionary = {}   # index de terrain -> true (plancher, porte)
static var _t_door: int = -1


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
	_groups = _read(GROUPS_PATH).get("groups", {})
	var ecology: Dictionary = _read(ECOLOGY_PATH)
	_ambient = ecology.get("ambient", {})
	_limits = ecology.get("limits", {})
	for id: String in ["t_pavement", "t_pavement_y", "t_sidewalk", "t_concrete"]:
		if TerrainDB.has_id(id):
			_paved[TerrainDB.index_of(id)] = true
	for id: String in ["t_floor", "t_door"]:
		if TerrainDB.has_id(id):
			_indoor[TerrainDB.index_of(id)] = true
	if TerrainDB.has_id("t_door"):
		_t_door = TerrainDB.index_of("t_door")
	_validate()


## Vérifie les données : monstres et groupes cités, cycles, contextes d'écologie, natures de case.
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


static func _validate_context(label: String, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	if not _groups.has(String(entry.get("group", ""))):
		_fail("ecology.json %s : groupe inconnu « %s »." % [label, entry.get("group", "")])
	if float(entry.get("density", 0.0)) < 0.0:
		_fail("ecology.json %s : densité négative." % label)


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


static func limit(name: String, fallback: int) -> int:
	_ensure_loaded()
	return int(_limits.get(name, fallback))


# --- Génération ---

## Monstres initiaux du chunk : [{monster: id, cell: Vector2i, facing: Vector2i}], dans l'ordre de tirage.
## `population` multiplie les densités (0 : aucun monstre) ; `safe_centers` : cases (en plus du départ par défaut de la seed)
## autour desquelles aucun monstre n'apparaît.
static func generate(world_seed: int, key: Vector3i, terrain: PackedByteArray, furniture: PackedByteArray,
		population: float = 1.0, safe_centers: Array[Vector2i] = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if key.z != 0 or population <= 0.0 or terrain.size() != Chunk.CELLS:
		return out
	_ensure_loaded()
	var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
	var context: Dictionary = _context(world_seed, settlement, Vector2i(key.x, key.y))
	if context.is_empty():
		return out
	var safes: Array[Vector2i] = []
	safes.append_array(safe_centers)
	safes.append(settlement.spawn_cell())
	var candidates: PackedInt32Array = _candidates(key, terrain, furniture, bool(context["paved"]), safes)
	var expected: float = float(context["density"]) * float(candidates.size()) / 100.0 * population
	var rng: RandomNumberGenerator = WorldRng.rng_for(world_seed, WorldRng.LAYER_SPAWN, key.x, key.y, key.z)
	var count: int = floori(expected)
	if rng.randf() < expected - float(count):
		count += 1
	count = mini(count, limit("max_per_chunk", 12))
	var budget: int = limit("threat_budget", 30)
	var spacing: int = limit("min_spacing", 2)
	var group: String = context["group"]
	var placed: Array[Vector2i] = []
	var threat_total: int = 0
	for n in count:
		if candidates.is_empty():
			break
		var monster_id: String = _pick_monster(group, rng, 0)
		if monster_id == "":
			continue
		var threat: int = MonsterDB.threat_of(monster_id)
		if threat_total + threat > budget:
			continue
		var slot: int = -1
		for attempt in SPACING_ATTEMPTS:
			var k: int = rng.randi_range(0, candidates.size() - 1)
			if _spaced(_cell_of(key, candidates[k]), placed, spacing):
				slot = k
				break
		if slot < 0:
			continue
		var cell: Vector2i = _cell_of(key, candidates[slot])
		candidates.remove_at(slot)
		placed.append(cell)
		threat_total += threat
		out.append({"monster": monster_id, "cell": cell, "facing": RING[rng.randi_range(0, RING.size() - 1)]})
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
	return h


# --- Contexte et candidats ---

## {group, density, paved} du chunk, ou {} s'il ne reçoit aucun monstre.
static func _context(world_seed: int, settlement: SettlementMap, coord: Vector2i) -> Dictionary:
	match settlement.cell_type(coord):
		SettlementMap.CellType.ROAD:
			return _ambient_entry("road" if settlement.is_wild_road(coord) else "street", true)
		SettlementMap.CellType.LOT, SettlementMap.CellType.YARD:
			return _ambient_entry("yard", false)
		SettlementMap.CellType.SPECIAL:
			return {}   # lieux spéciaux : jalon 6b
	var kind: int = WorldMap.for_seed(world_seed).cell_kind(coord)
	var kinds: Dictionary = _ambient.get("kinds", {})
	var entry: Dictionary = kinds.get(RouteMap.KIND_IDS[kind], {})
	if entry.is_empty() or float(entry.get("density", 0.0)) <= 0.0:
		return {}
	return {"group": String(entry["group"]), "density": float(entry["density"]), "paved": false}


static func _ambient_entry(name: String, paved: bool) -> Dictionary:
	var entry: Dictionary = _ambient.get(name, {})
	if entry.is_empty() or float(entry.get("density", 0.0)) <= 0.0:
		return {}
	return {"group": String(entry["group"]), "density": float(entry["density"]), "paved": paved}


## Indices locaux des cases où un monstre peut apparaître : praticables à pied, hors eau, sans meuble bloquant, du bon type
## (chaussée si `paved`, terrain naturel sinon : ni plancher ni porte), hors zone sûre, ni sur ni devant une porte.
static func _candidates(key: Vector3i, terrain: PackedByteArray, furniture: PackedByteArray, paved: bool,
		safes: Array[Vector2i]) -> PackedInt32Array:
	var out := PackedInt32Array()
	var safe_radius: float = float(limit("safe_radius", 12))
	var has_furniture: bool = furniture.size() == Chunk.CELLS
	for i in Chunk.CELLS:
		var t: int = terrain[i]
		if not TerrainDB.is_walkable(t) or TerrainDB.swim_depth(t) != TerrainDB.SWIM_NONE:
			continue
		if has_furniture and furniture[i] != 0 and not FurnitureDB.is_walkable(furniture[i]):
			continue
		if _paved.has(t) != paved:
			continue
		if not paved and _indoor.has(t):
			continue
		if _near_door(terrain, i):
			continue
		var cell: Vector2i = _cell_of(key, i)
		var safe: bool = false
		for center: Vector2i in safes:
			if Vector2(cell).distance_to(Vector2(center)) <= safe_radius:
				safe = true
				break
		if safe:
			continue
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
