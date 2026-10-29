class_name MonsterDB
extends RefCounted
## Bestiaire, chargé depuis res://data/monsters.json puis monsters_places.json (voir le champ "_doc" des fichiers et docs/MONSTER_SPAWN.md).
## Jalon 6b : create(id, affixes) applique des affixes (data/monster_affixes.json : nom accordé, PV, vitesse, dégâts, armure).
## create(id) fabrique un MonsterData neuf. Les erreurs de données sont listées par errors() (un monstre invalide est tout de même
## chargé : le jeu continue, le test tests/test_spawn.gd les signale).

const PATHS: Array[String] = ["res://data/monsters.json", "res://data/monsters_places.json"]
const AFFIX_PATH: String = "res://data/monster_affixes.json"

## Capacités connues (MONSTER_SPAWN.md section 7). En 6a, seule ARMOR(n) agit ; les autres sont lues et ignorées.
const ABILITIES: Array[String] = ["ARMOR", "DORMANT", "GUARD", "AMBUSH", "ERRATIC", "EXPLODE", "AURA_RAD", "COLD_AURA", "FIRE_AURA",
	"REGEN", "LEAP", "CHARGE", "GRAB", "CONSTRICT", "SPLIT", "SWARM", "THROW", "BURST", "SUMMON", "RAISE", "STEALTH", "BLIND_HEARING",
	"SWIM", "AQUATIC", "FLY", "SPORE", "LOOT_CARRIER"]
const BEHAVIORS: Array[String] = ["hostile", "passive", "territorial"]
const STATES: Array[String] = ["sleep", "idle", "guard", "patrol", "wander"]
const MAX_THREAT: int = 10

static var _loaded: bool = false
static var _ids: Array[String] = []
static var _defs: Dictionary = {}
static var _errors: Array[String] = []
static var _affixes: Dictionary = {}
static var _affix_ids: Array[String] = []


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in PATHS:
		_load_file(path)
	_load_affixes()


static func _load_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		_fail("%s introuvable." % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("%s invalide." % path)
		return
	var monsters: Dictionary = (parsed as Dictionary).get("monsters", {})
	for id: String in monsters:
		if _defs.has(id):
			_fail("%s : monstre « %s » défini deux fois." % [path, id])
			continue
		_ids.append(id)
		_defs[id] = monsters[id]
		_validate(id, monsters[id])


static func _load_affixes() -> void:
	if not FileAccess.file_exists(AFFIX_PATH):
		_fail("%s introuvable." % AFFIX_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AFFIX_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("monster_affixes.json invalide.")
		return
	_affixes = (parsed as Dictionary).get("affixes", {})
	for id: String in _affixes:
		_affix_ids.append(id)
		var def: Dictionary = _affixes[id]
		if String(def.get("adj_m", "")) == "" or String(def.get("adj_f", "")) == "":
			_fail("affixe %s : adjectifs adj_m / adj_f manquants." % id)
		if float(def.get("hp", 1.0)) <= 0.0 or float(def.get("speed", 1.0)) <= 0.0 or float(def.get("dmg", 1.0)) <= 0.0:
			_fail("affixe %s : multiplicateur nul ou négatif." % id)


static func _fail(message: String) -> void:
	_errors.append(message)
	push_error("MonsterDB : " + message)


static func _validate(id: String, def: Dictionary) -> void:
	if String(def.get("name", "")) == "":
		_fail("%s : nom manquant." % id)
	if float(def.get("hp", 20.0)) <= 0.0 or float(def.get("move_cost", 1.2)) <= 0.0:
		_fail("%s : PV ou coût de déplacement invalide." % id)
	if not BEHAVIORS.has(String(def.get("behavior", "hostile"))):
		_fail("%s : comportement inconnu." % id)
	if not STATES.has(String(def.get("default_state", "idle"))):
		_fail("%s : état par défaut inconnu." % id)
	if not ["m", "f"].has(String(def.get("gender", "m"))):
		_fail("%s : genre inconnu (m ou f)." % id)
	for ability: String in def.get("abilities", []):
		if not ABILITIES.has(_ability_base(ability)):
			_fail("%s : capacité inconnue « %s »." % [id, ability])
	for part: String in ["attack", "special", "ranged"]:
		var block: Dictionary = def.get(part, {})
		var zones: Variant = block.get("zones", null)
		if typeof(zones) == TYPE_STRING and not MonsterData.ZONE_TABLES.has(String(zones)):
			_fail("%s : table de zones inconnue « %s »." % [id, zones])


## "ARMOR(2)" -> "ARMOR".
static func _ability_base(ability: String) -> String:
	var open: int = ability.find("(")
	return ability if open < 0 else ability.substr(0, open)


## "ARMOR(2)" -> 2 ; 0 s'il n'y a pas d'argument.
static func _ability_arg(ability: String) -> int:
	var open: int = ability.find("(")
	if open < 0:
		return 0
	return int(ability.substr(open + 1, ability.length() - open - 2))


# --- Requêtes ---

## Ids des monstres, dans l'ordre du fichier.
static func ids() -> Array[String]:
	_ensure_loaded()
	return _ids


static func has_id(id: String) -> bool:
	_ensure_loaded()
	return _defs.has(id)


static func errors() -> Array[String]:
	_ensure_loaded()
	return _errors


static func def_of(id: String) -> Dictionary:
	_ensure_loaded()
	return _defs.get(id, {})


static func tags_of(id: String) -> Array:
	return def_of(id).get("tags", [])


## Menace (1 à 10) : champ "threat", sinon PV / 25 arrondi.
static func threat_of(id: String) -> int:
	var def: Dictionary = def_of(id)
	var fallback: int = clampi(roundi(float(def.get("hp", 20.0)) / 25.0), 1, MAX_THREAT)
	return clampi(int(def.get("threat", fallback)), 1, MAX_THREAT)


## Fabrique un MonsterData neuf, avec des affixes éventuels (ids de monster_affixes.json ; ceux qui ne conviennent pas sont ignorés).
## Id inconnu : erreur et zombie.
static func create(monster_id: String, affix_ids: Array = []) -> MonsterData:
	_ensure_loaded()
	if not _defs.has(monster_id):
		push_error("MonsterDB : monstre inconnu « %s »." % monster_id)
		if monster_id != "zombie" and _defs.has("zombie"):
			return create("zombie", affix_ids)
		return MonsterData.new()
	var d: Dictionary = _defs[monster_id]
	var m := MonsterData.new()
	m.id = monster_id
	m.display_name = String(d.get("name", monster_id))
	m.gender = String(d.get("gender", "m"))
	m.tile_id = String(d.get("tile", "mon_" + monster_id))
	m.max_hp = float(d.get("hp", 20.0))
	m.move_cost = float(d.get("move_cost", 1.2))
	m.detect_range = int(d.get("detect_range", 14))
	m.pack_radius = int(d.get("pack_radius", 0))
	m.behavior = String(d.get("behavior", "hostile"))
	m.default_state = String(d.get("default_state", "idle"))
	m.wake_range = int(d.get("wake_range", 6))
	m.threat = threat_of(monster_id)
	m.tags.assign(d.get("tags", []))
	m.abilities.assign(d.get("abilities", []))
	for ability: String in m.abilities:
		if _ability_base(ability) == "ARMOR":
			m.armor = _ability_arg(ability)
	m.fallback_tile = String(d.get("fallback_tile", "mon_wolf" if m.tags.has("animal") else "mon_zombie"))
	if d.has("tint"):
		m.tint = Color.html(String(d["tint"]))
	else:
		m.tint = Color.from_hsv(float(absi(monster_id.hash()) % 360) / 360.0, 0.4, 1.0)

	var attack: Dictionary = d.get("attack", {})
	m.attack_name = String(attack.get("name", "Griffure"))
	m.attack_cost = float(attack.get("cost", 1.4))
	m.attack_damage = float(attack.get("damage", 4.0))
	m.attack_zones = _zones(attack.get("zones", "humanoid"))
	m.attack_effect = _effect(attack.get("effect", {}))
	m.attack_infection = float(attack.get("infection", 0.0))

	var special: Dictionary = d.get("special", {})
	if not special.is_empty():
		m.special_name = String(special.get("name", "Attaque spéciale"))
		m.special_cost = float(special.get("cost", 3.0))
		m.special_damage = float(special.get("damage", 8.0))
		m.special_chance = float(special.get("chance", 0.25))
		m.special_zones = _zones(special.get("zones", "bite"))
		m.special_effect = _effect(special.get("effect", {}))
		m.special_infection = float(special.get("infection", 0.0))

	var ranged: Dictionary = d.get("ranged", {})
	if not ranged.is_empty():
		m.ranged_name = String(ranged.get("name", "Tir"))
		m.ranged_range = int(ranged.get("range", 6))
		m.ranged_cost = float(ranged.get("cost", 2.0))
		m.ranged_damage = float(ranged.get("damage", 4.0))
		m.ranged_cooldown = float(ranged.get("cooldown", 8.0))
		m.ranged_zones = _zones(ranged.get("zones", "humanoid"))
		m.ranged_effect = _effect(ranged.get("effect", {}))

	var scream: Dictionary = d.get("scream", {})
	if not scream.is_empty():
		m.scream_name = String(scream.get("name", "Hurlement"))
		m.scream_radius = int(scream.get("radius", 20))
		m.scream_cost = float(scream.get("cost", 3.0))
		m.scream_cooldown = float(scream.get("cooldown", 25.0))
	_apply_affixes(m, affix_ids)
	return m


## Applique les affixes (au plus 2, ceux que le monstre accepte) : nom accordé au genre, PV, durée du pas, dégâts, armure, menace.
static func _apply_affixes(m: MonsterData, affix_ids: Array) -> void:
	for raw: Variant in affix_ids:
		var affix_id: String = String(raw)
		if m.affixes.size() >= 2 or m.affixes.has(affix_id) or not affix_ok(m.id, affix_id):
			continue
		var a: Dictionary = _affixes[affix_id]
		m.affixes.append(affix_id)
		m.max_hp *= float(a.get("hp", 1.0))
		m.move_cost *= float(a.get("speed", 1.0))
		var dmg: float = float(a.get("dmg", 1.0))
		m.attack_damage *= dmg
		m.special_damage *= dmg
		m.ranged_damage *= dmg
		m.armor += int(a.get("armor", 0))
		m.threat = clampi(m.threat + int(a.get("threat", 0)), 1, MAX_THREAT)
		if bool(a.get("never_sleeps", false)):
			m.never_sleeps = true
		m.display_name += " " + String(a.get("adj_f" if m.gender == "f" else "adj_m", ""))


## Ids des affixes, dans l'ordre du fichier.
static func affix_ids() -> Array[String]:
	_ensure_loaded()
	return _affix_ids


## Le monstre accepte-t-il cet affixe ? (au moins un tag de allowed_tags, aucun de forbidden_tags)
static func affix_ok(monster_id: String, affix_id: String) -> bool:
	_ensure_loaded()
	if not _affixes.has(affix_id) or not _defs.has(monster_id):
		return false
	var a: Dictionary = _affixes[affix_id]
	var tags: Array = tags_of(monster_id)
	for tag: Variant in a.get("forbidden_tags", []):
		if tags.has(tag):
			return false
	var allowed: Array = a.get("allowed_tags", [])
	if allowed.is_empty():
		return true
	for tag: Variant in allowed:
		if tags.has(tag):
			return true
	return false


## État de départ d'un monstre créé par un chunk : "guard" (GUARD), "sleep" (DORMANT ou AMBUSH), sinon la valeur de default_state.
static func default_state_of(monster_id: String) -> String:
	var def: Dictionary = def_of(monster_id)
	var abilities: Array = def.get("abilities", [])
	if abilities.has("GUARD"):
		return "guard"
	if abilities.has("DORMANT") or abilities.has("AMBUSH"):
		return "sleep"
	return String(def.get("default_state", "idle"))


## Table de zones : nom d'une table de MonsterData.ZONE_TABLES, ou dictionnaire {partie: poids} (copié).
static func _zones(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_STRING:
		return (MonsterData.ZONE_TABLES.get(String(value), {}) as Dictionary).duplicate()
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate()
	return {}


## Effet d'état au format de MonsterData.effect() ; dictionnaire vide si absent.
static func _effect(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).is_empty():
		return {}
	var e: Dictionary = value
	return MonsterData.effect(String(e.get("id", "")), float(e.get("chance", 1.0)), float(e.get("duration", 0.0)),
		float(e.get("dps", 0.0)), float(e.get("stamina", 0.0)), String(e.get("part", "")))
