class_name TerrainDB
extends RefCounted
## Terrains du monde, chargés depuis res://data/worldgen/terrain.json puis terrain_vertical.json (voir le champ "_doc" des fichiers).
## Les chunks stockent l'INDEX du terrain (un octet par case) ; cette classe donne les propriétés d'un index.
## Jalon 6b (axe vertical) : terrain_vertical.json ajoute roche, vide et escaliers ; `connects_z` (+1 / -1) = liaison vers l'étage voisin.
## Jalon 8 (portes et fenêtres) : `open_into` / `close_into` donnent l'état ouvert ou fermé d'une case actionnable
## (t_door <-> t_door_o, t_window <-> t_window_open), avec `open_cost` / `open_noise` et `close_cost` / `close_noise`.

const PATHS: Array[String] = ["res://data/worldgen/terrain.json", "res://data/worldgen/terrain_vertical.json"]

# Profondeur de nage (champ "swim" de terrain.json) : le joueur nage dans l'eau, qu'elle soit « praticable à pied » ou non.
const SWIM_NONE: int = 0
const SWIM_SHALLOW: int = 1
const SWIM_DEEP: int = 2

static var _loaded: bool = false
static var _ids: Array[String] = []
static var _index: Dictionary = {}
static var _defs: Array[Dictionary] = []
static var _walkable: PackedByteArray = PackedByteArray()
static var _opaque: PackedByteArray = PackedByteArray()
static var _entity: PackedByteArray = PackedByteArray()
static var _swim: PackedByteArray = PackedByteArray()
static var _z_link: PackedInt32Array = PackedInt32Array()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in PATHS:
		_load_file(path)
	if _ids.size() > 255:
		push_error("TerrainDB : plus de 255 terrains (un chunk stocke un octet par case).")


static func _load_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("TerrainDB : %s introuvable." % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TerrainDB : %s invalide." % path)
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
		_swim.append(_swim_value(id, def))
		_z_link.append(clampi(int(def.get("connects_z", 0)), -1, 1))


static func _swim_value(id: String, def: Dictionary) -> int:
	match String(def.get("swim", "")):
		"":
			return SWIM_NONE
		"shallow":
			return SWIM_SHALLOW
		"deep":
			return SWIM_DEEP
	push_error("TerrainDB : %s : valeur « swim » inconnue (attendu shallow ou deep)." % id)
	return SWIM_NONE


static func index_of(id: String) -> int:
	_ensure_loaded()
	if not _index.has(id):
		push_error("TerrainDB : terrain inconnu « %s »." % id)
		return 0
	return _index[id]


static func id_of(index: int) -> String:
	_ensure_loaded()
	return _ids[index] if index >= 0 and index < _ids.size() else ""


## Nom affiché (champ "name" de terrain.json), l'id à défaut ; "" si l'index est invalide. Utilisé par le mode regard.
static func name_of(index: int) -> String:
	_ensure_loaded()
	if index < 0 or index >= _defs.size():
		return ""
	return String(_defs[index].get("name", _ids[index]))


## Praticable À PIED (monstres, marche automatique). L'eau profonde ne l'est pas : le joueur y nage (voir swim_depth).
static func is_walkable(index: int) -> bool:
	_ensure_loaded()
	return index >= 0 and index < _walkable.size() and _walkable[index] != 0


## SWIM_NONE (sol), SWIM_SHALLOW (eau peu profonde, de marais...) ou SWIM_DEEP (eau profonde). Le joueur y nage.
static func swim_depth(index: int) -> int:
	_ensure_loaded()
	return _swim[index] if index >= 0 and index < _swim.size() else SWIM_NONE


## Liaison verticale : +1 (monte à l'étage du dessus), -1 (descend), 0 (aucune). Escaliers, échelles, trappes.
static func z_link(index: int) -> int:
	_ensure_loaded()
	return _z_link[index] if index >= 0 and index < _z_link.size() else 0


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


## Porte (fermée ou ouverte) : champ "door" de terrain.json. Les fenêtres, elles, n'en ont pas.
static func is_door(index: int) -> bool:
	_ensure_loaded()
	return index >= 0 and index < _defs.size() and bool(_defs[index].get("door", false))


## État ouvert d'un terrain fermé actionnable (porte, fenêtre), -1 s'il ne s'ouvre pas.
static func open_into(index: int) -> int:
	return _linked(index, "open_into")


## État fermé d'un terrain ouvert actionnable (porte, fenêtre), -1 s'il ne se ferme pas.
static func close_into(index: int) -> int:
	return _linked(index, "close_into")


## Coût en points d'action pour ouvrir / fermer (0 si le terrain ne l'est pas).
static func open_cost(index: int) -> float:
	return _def_float(index, "open_cost")


static func close_cost(index: int) -> float:
	return _def_float(index, "close_cost")


## Bruit (rayon en cases) fait en ouvrant / fermant.
static func open_noise(index: int) -> int:
	return roundi(_def_float(index, "open_noise"))


static func close_noise(index: int) -> int:
	return roundi(_def_float(index, "close_noise"))


static func _linked(index: int, field: String) -> int:
	_ensure_loaded()
	if index < 0 or index >= _defs.size():
		return -1
	var target: String = String(_defs[index].get(field, ""))
	return int(_index.get(target, -1))


static func _def_float(index: int, field: String) -> float:
	_ensure_loaded()
	if index < 0 or index >= _defs.size():
		return 0.0
	return float(_defs[index].get(field, 0.0))


static func has_id(id: String) -> bool:
	_ensure_loaded()
	return _index.has(id)


## Le terrain a-t-il un champ "color" dans terrain.json ? (sinon color_of renvoie le magenta de repli)
static func has_color(index: int) -> bool:
	_ensure_loaded()
	return index >= 0 and index < _defs.size() and _defs[index].has("color")


## Couleur de repli (champ "color" de terrain.json), dessinée quand la tuile n'a pas de sprite dans le pack.
static func color_of(index: int) -> Color:
	_ensure_loaded()
	if index >= 0 and index < _defs.size() and _defs[index].has("color"):
		return Color.html(String(_defs[index]["color"]))
	return Color(0.8, 0.2, 0.8)
