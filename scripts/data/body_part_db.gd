class_name BodyPartDB
extends RefCounted
## Parties du corps du joueur, chargées depuis res://data/body_parts.json (voir le champ "_doc" du fichier).
## Sert aussi aux monstres : choix de la partie touchée par une attaque (pick) et affichage des probabilités (zone_lines).

const PATH: String = "res://data/body_parts.json"
const FALLBACK_PART: String = "torso"

static var _loaded: bool = false
static var _ids: Array[String] = []
static var _defs: Dictionary = {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("BodyPartDB : %s introuvable." % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BodyPartDB : body_parts.json invalide.")
		return
	_defs = parsed.get("parts", {})
	for id: String in _defs:
		_ids.append(id)


## Ids des parties, dans l'ordre d'affichage.
static func ids() -> Array[String]:
	_ensure_loaded()
	return _ids


static func has_id(id: String) -> bool:
	_ensure_loaded()
	return _defs.has(id)


static func name_of(id: String) -> String:
	_ensure_loaded()
	return String((_defs.get(id, {}) as Dictionary).get("name", id))


static func short_of(id: String) -> String:
	_ensure_loaded()
	return String((_defs.get(id, {}) as Dictionary).get("short", name_of(id)))


static func max_hp_of(id: String) -> float:
	_ensure_loaded()
	return float((_defs.get(id, {}) as Dictionary).get("max_hp", 1.0))


## Vital : la mort survient quand cette partie tombe à 0 PV.
static func is_vital(id: String) -> bool:
	_ensure_loaded()
	return bool((_defs.get(id, {}) as Dictionary).get("vital", false))


static func total_max_hp() -> float:
	_ensure_loaded()
	var total: float = 0.0
	for id: String in _ids:
		total += max_hp_of(id)
	return total


## Partie touchée : tirage pondéré dans `zones` ({id: poids}) avec `roll` dans [0, 1). Zones vides : le torse.
static func pick(zones: Dictionary, roll: float) -> String:
	var total: float = 0.0
	for id: String in zones:
		total += float(zones[id])
	if total <= 0.0:
		return FALLBACK_PART
	var target: float = roll * total
	var acc: float = 0.0
	var last: String = FALLBACK_PART
	for id: String in zones:
		acc += float(zones[id])
		last = id
		if target < acc:
			return id
	return last


## Probabilités affichables : « Tête 10% · Torse 36% · Bras g. 20% », réparties en lignes de `per_line` zones.
static func zone_lines(zones: Dictionary, per_line: int = 3) -> Array[String]:
	var lines: Array[String] = []
	var total: float = 0.0
	for id: String in zones:
		total += float(zones[id])
	if total <= 0.0:
		return lines
	var parts: Array[String] = []
	for id: String in zones:
		parts.append("%s %d%%" % [short_of(id), roundi(100.0 * float(zones[id]) / total)])
	var i: int = 0
	while i < parts.size():
		lines.append(" · ".join(parts.slice(i, i + per_line)))
		i += per_line
	return lines
