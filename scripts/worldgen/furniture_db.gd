class_name FurnitureDB
extends RefCounted
## Mobilier du monde, chargé depuis res://data/worldgen/furniture.json (voir le champ "_doc" du fichier).
## Les chunks stockent l'INDEX du mobilier (un octet par case) : 0 = rien, 1 = premier de la liste, etc.

const PATH: String = "res://data/worldgen/furniture.json"

static var _loaded: bool = false
static var _ids: Array[String] = []
static var _index: Dictionary = {}
static var _defs: Array[Dictionary] = []


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("FurnitureDB : %s introuvable." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("FurnitureDB : furniture.json invalide.")
		return
	var furniture: Dictionary = parsed.get("furniture", {})
	for id: String in furniture:
		_ids.append(id)
		_defs.append(furniture[id])
		_index[id] = _ids.size()   # 1-based
	if _ids.size() > 255:
		push_error("FurnitureDB : plus de 255 meubles (un chunk stocke un octet par case).")


static func has_id(id: String) -> bool:
	_ensure_loaded()
	return _index.has(id)


## Index (1..255) d'un meuble ; 0 (et une erreur) s'il est inconnu.
static func index_of(id: String) -> int:
	_ensure_loaded()
	if not _index.has(id):
		push_error("FurnitureDB : meuble inconnu « %s »." % id)
		return 0
	return _index[id]


static func count() -> int:
	_ensure_loaded()
	return _ids.size()


static func id_of(index: int) -> String:
	_ensure_loaded()
	return _ids[index - 1] if index >= 1 and index <= _ids.size() else ""


## Pas de meuble (0) : praticable. Sinon selon "walkable" (faux par défaut).
static func is_walkable(index: int) -> bool:
	_ensure_loaded()
	if index <= 0 or index > _defs.size():
		return true
	return bool(_defs[index - 1].get("walkable", false))


static func is_opaque(index: int) -> bool:
	_ensure_loaded()
	return index >= 1 and index <= _defs.size() and bool(_defs[index - 1].get("opaque", false))


static func tile_of(index: int) -> String:
	_ensure_loaded()
	return String(_defs[index - 1].get("tile", "")) if index >= 1 and index <= _defs.size() else ""


static func name_of(index: int) -> String:
	_ensure_loaded()
	return String(_defs[index - 1].get("name", "")) if index >= 1 and index <= _defs.size() else ""
