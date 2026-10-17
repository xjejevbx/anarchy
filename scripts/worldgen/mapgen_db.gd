class_name MapgenDB
extends RefCounted
## Plans de maisons (docs/WORLD_GEN.md §5.5, jalon 3c), chargés depuis res://data/worldgen/mapgen/houses.json.
## Chaque plan (24 x 24 caractères, façade au SUD) est compilé une fois : un octet de terrain (index TerrainDB, ou NATURE =
## « garder le terrain naturel ») et un octet de mobilier (index FurnitureDB) par case. Les erreurs de plan sont listées par
## errors() et affichées au chargement : un plan invalide est ignoré, le jeu continue.

const PATH: String = "res://data/worldgen/mapgen/houses.json"
const NATURE: int = 255
const SIZE: int = 24

static var _loaded: bool = false
static var _plans: Array[Dictionary] = []   # {id, weight, terrain, furniture}
static var _total_weight: float = 0.0
static var _errors: Array[String] = []


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		_fail("%s introuvable." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("houses.json invalide.")
		return
	var palette: Dictionary = parsed.get("palette", {})
	for plan: Dictionary in parsed.get("plans", []):
		_compile(plan, palette)


static func _fail(message: String) -> void:
	_errors.append(message)
	push_error("MapgenDB : " + message)


static func _compile(plan: Dictionary, palette: Dictionary) -> void:
	var id: String = String(plan.get("id", "?"))
	var rows: Array = plan.get("rows", [])
	if rows.size() != SIZE:
		_fail("%s : %d lignes (attendu %d)." % [id, rows.size(), SIZE])
		return
	var terrain := PackedByteArray()
	terrain.resize(SIZE * SIZE)
	var furniture := PackedByteArray()
	furniture.resize(SIZE * SIZE)
	for y in SIZE:
		var row: String = String(rows[y])
		if row.length() != SIZE:
			_fail("%s : ligne %d de %d caractères (attendu %d)." % [id, y, row.length(), SIZE])
			return
		for x in SIZE:
			var symbol: String = row[x]
			if not palette.has(symbol):
				_fail("%s (%d, %d) : caractère « %s » absent de la palette." % [id, x, y, symbol])
				return
			var entry: Dictionary = palette[symbol]
			var t: int = NATURE
			if entry.has("terrain"):
				var terrain_id: String = String(entry["terrain"])
				if not TerrainDB.has_id(terrain_id):
					_fail("%s : terrain inconnu « %s »." % [id, terrain_id])
					return
				t = TerrainDB.index_of(terrain_id)
			var f: int = 0
			if entry.has("furniture"):
				var furniture_id: String = String(entry["furniture"])
				if not FurnitureDB.has_id(furniture_id):
					_fail("%s : meuble inconnu « %s »." % [id, furniture_id])
					return
				f = FurnitureDB.index_of(furniture_id)
			terrain[y * SIZE + x] = t
			furniture[y * SIZE + x] = f
	var weight: float = maxf(float(plan.get("weight", 1.0)), 0.0)
	_plans.append({"id": id, "weight": weight, "terrain": terrain, "furniture": furniture})
	_total_weight += weight


static func errors() -> Array[String]:
	_ensure_loaded()
	return _errors


static func plan_count() -> int:
	_ensure_loaded()
	return _plans.size()


static func plan_id(plan: int) -> String:
	_ensure_loaded()
	return String(_plans[plan]["id"])


## Plan tiré par `roll` (réel dans [0, 1)), pondéré par "weight". -1 s'il n'y a aucun plan valide.
static func pick(roll: float) -> int:
	_ensure_loaded()
	if _plans.is_empty() or _total_weight <= 0.0:
		return -1
	var target: float = roll * _total_weight
	var acc: float = 0.0
	for i in _plans.size():
		acc += float(_plans[i]["weight"])
		if target < acc:
			return i
	return _plans.size() - 1


## Terrain (index TerrainDB, ou NATURE) à l'indice de plan `plan_index` (y * 24 + x, plan non tourné).
static func terrain_at(plan: int, plan_index: int) -> int:
	_ensure_loaded()
	return (_plans[plan]["terrain"] as PackedByteArray)[plan_index]


static func furniture_at(plan: int, plan_index: int) -> int:
	_ensure_loaded()
	return (_plans[plan]["furniture"] as PackedByteArray)[plan_index]


## Indice (dans le plan non tourné) de la case locale (lx, ly) du chunk. rot : quarts de tour horaires appliqués au plan
## (0 : façade au sud, 1 : ouest, 2 : nord, 3 : est).
static func plan_index(lx: int, ly: int, rot: int) -> int:
	var last: int = SIZE - 1
	match rot:
		1:
			return (last - lx) * SIZE + ly
		2:
			return (last - ly) * SIZE + (last - lx)
		3:
			return lx * SIZE + (last - ly)
		_:
			return ly * SIZE + lx
