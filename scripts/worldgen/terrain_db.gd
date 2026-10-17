class_name TerrainDB
extends RefCounted
## Terrains du monde, chargés depuis res://data/worldgen/terrain.json (voir le champ "_doc" du fichier).
## Les chunks stockent l'INDEX du terrain (un octet par case) ; cette classe donne les propriétés d'un index.

const PATH: String = "res://data/worldgen/terrain.json"

static var _loaded: bool = false
static var _ids: Array[String] = []
static var _index: Dictionary = {}
static var _defs: Array[Dictionary] = []
static var _walkable: PackedByteArray = PackedByteArray()
static var _opaque: PackedByteArray = PackedByteArray()
static var _entity: PackedByteArray = PackedByteArray()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("TerrainDB : %s introuvable." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TerrainDB : terrain.json invalide.")
		return
	var terrains: Dictionary = parsed.get("terrains", {})
	for id: String in terrains:
		var def: Dictionary = terrains[id]
		_index[id] = _ids.size()
		_ids.append(id)
		_defs.append(def)
		_walkable.append(1 if bool(def.get("walkable", true)) else 0)
		_opaque.append(1 if bool(def.get("opaque", false)) else 0)
		_entity.append(1 if bool(def.get("entity_sprite", false)) else 0)
	if _ids.size() > 255:
		push_error("TerrainDB : plus de 255 terrains (un chunk stocke un octet par case).")


static func index_of(id: String) -> int:
	_ensure_loaded()
	if not _index.has(id):
		push_error("TerrainDB : terrain inconnu « %s »." % id)
		return 0
	return _index[id]


static func id_of(index: int) -> String:
	_ensure_loaded()
	return _ids[index] if index >= 0 and index < _ids.size() else ""


static func is_walkable(index: int) -> bool:
	_ensure_loaded()
	return index >= 0 and index < _walkable.size() and _walkable[index] != 0


static func is_opaque(index: int) -> bool:
	_ensure_loaded()
	return index < 0 or index >= _opaque.size() or _opaque[index] != 0


## Dessiné comme un sprite trié par Y (arbres) plutôt que dans le sol du chunk.
static func has_entity_sprite(index: int) -> bool:
	_ensure_loaded()
	return index >= 0 and index < _entity.size() and _entity[index] != 0


static func tile_of(index: int) -> String:
	_ensure_loaded()
	return String(_defs[index].get("tile", "")) if index >= 0 and index < _defs.size() else ""


## Tuile dessinée dans le sol du chunk (la « base » pour un arbre : de l'herbe dessous).
static func ground_tile_of(index: int) -> String:
	_ensure_loaded()
	if index < 0 or index >= _defs.size():
		return ""
	var def: Dictionary = _defs[index]
	return String(def.get("base", def.get("tile", "")))


static func autotile_of(index: int) -> String:
	_ensure_loaded()
	return String(_defs[index].get("autotile", "")) if index >= 0 and index < _defs.size() else ""


## Les murs voisins se raccordent à ce terrain (porte, fenêtre) : champ "wall_link" de terrain.json.
static func links_wall(index: int) -> bool:
	_ensure_loaded()
	return index >= 0 and index < _defs.size() and bool(_defs[index].get("wall_link", false))


static func has_id(id: String) -> bool:
	_ensure_loaded()
	return _index.has(id)
