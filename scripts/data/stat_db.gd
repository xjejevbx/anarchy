class_name StatDB
extends RefCounted
## Caractéristiques du joueur, chargées depuis res://data/stats.json (voir le champ "_doc" du fichier).

const PATH: String = "res://data/stats.json"

static var _loaded: bool = false
static var _ids: Array[String] = []
static var _defs: Dictionary = {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("StatDB : %s introuvable." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("StatDB : stats.json invalide.")
		return
	_defs = parsed.get("stats", {})
	for id: String in _defs:
		_ids.append(id)


## Ids des stats, dans l'ordre d'affichage.
static func ids() -> Array[String]:
	_ensure_loaded()
	return _ids


static func name_of(id: String) -> String:
	_ensure_loaded()
	return String((_defs.get(id, {}) as Dictionary).get("name", id))


static func base_of(id: String) -> int:
	_ensure_loaded()
	return int((_defs.get(id, {}) as Dictionary).get("base", 0))


static func description_of(id: String) -> String:
	_ensure_loaded()
	return String((_defs.get(id, {}) as Dictionary).get("description", ""))
