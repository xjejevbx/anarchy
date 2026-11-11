class_name SaveGame
extends RefCounted
## Sauvegarde / chargement d'une partie (docs/WORLD_GEN.md §7, jalon 7).
##
## Dossier : user://saves/<slot>/meta.json + chunks/<cx>_<cy>_<z>.json.
## Le TERRAIN n'est jamais sauvegardé : on garde la seed, la version du générateur et les DELTAS des chunks explorés
## (cases vues, population, terrain/mobilier modifiés, objets au sol, monstres vivants). Au chargement, le monde est
## régénéré puis ces deltas sont appliqués ; un chunk marqué `populated` n'est jamais repeuplé (les monstres absents
## sont donc morts, uniques compris).
##
## Le seed est écrit en CHAÎNE pour ne pas perdre les entiers 64 bits dans JSON.

const VERSION: int = 1
const SAVE_DIR: String = "user://saves"
const CHUNK_DIR: String = "chunks"
const SLOT_PREFIX: String = "partie"


static func slot_dir(slot: String) -> String:
	return SAVE_DIR.path_join(slot)


static func meta_path(slot: String) -> String:
	return slot_dir(slot).path_join("meta.json")


static func chunks_dir(slot: String) -> String:
	return slot_dir(slot).path_join(CHUNK_DIR)


static func chunk_path(slot: String, key: Vector3i) -> String:
	return chunks_dir(slot).path_join("%d_%d_%d.json" % [key.x, key.y, key.z])


static func valid_slot(slot: String) -> bool:
	return slot != "" and not slot.begins_with(".") and slot.is_valid_filename()


# --- Liste des sauvegardes ---

## Toutes les sauvegardes valides (métadonnées + dossier), les plus récentes d'abord.
static func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for slot: String in dir.get_directories():
		var meta: Dictionary = read_meta(slot)
		if meta.is_empty():
			continue
		out.append({"slot": slot, "meta": meta})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var time_a: float = float((a["meta"] as Dictionary).get("saved_unix", 0.0))
		var time_b: float = float((b["meta"] as Dictionary).get("saved_unix", 0.0))
		if time_a != time_b:
			return time_a > time_b
		return String(a["slot"]) < String(b["slot"]))
	return out


static func read_meta(slot: String) -> Dictionary:
	if not valid_slot(slot):
		return {}
	var path := meta_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


static func exists(slot: String) -> bool:
	return not read_meta(slot).is_empty()


## Nom libre suivant : partie-1, partie-2...
static func next_slot_name() -> String:
	var used: Dictionary = {}
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for slot: String in dir.get_directories():
			used[slot] = true
	var index: int = 1
	while used.has("%s-%d" % [SLOT_PREFIX, index]):
		index += 1
	return "%s-%d" % [SLOT_PREFIX, index]


## Raison du refus de charger une sauvegarde ("", si compatible).
static func compatibility_error(meta: Dictionary) -> String:
	if meta.is_empty():
		return "sauvegarde illisible"
	var version: int = int(meta.get("version", 0))
	if version != VERSION:
		return "format de sauvegarde incompatible (version %d, attendu %d)" % [version, VERSION]
	var generator: int = int(meta.get("generator_version", 0))
	if generator != WorldRng.GENERATOR_VERSION:
		return "monde généré par une autre version (générateur %d, attendu %d) : cette sauvegarde ne peut pas être rechargée" % [
			generator, WorldRng.GENERATOR_VERSION]
	return ""


# --- Sauvegarde ---

## Écrit la sauvegarde ; renvoie {ok: bool, error: String, slot: String}.
static func save(world: World, player: Player, slot: String) -> Dictionary:
	if not valid_slot(slot):
		return {"ok": false, "error": "nom de sauvegarde invalide", "slot": slot}
	if world == null or player == null or world.chunks == null:
		return {"ok": false, "error": "partie non initialisée", "slot": slot}
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(chunks_dir(slot)))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "impossible de créer le dossier de sauvegarde (%d)" % dir_error, "slot": slot}
	var chunks: ChunkManager = world.chunks
	# Les fichiers de chunks d'une ancienne sauvegarde du même emplacement ne doivent pas survivre.
	_clear_dir(chunks_dir(slot))
	var saved_chunks: int = 0
	for key: Vector3i in chunks.modified_keys():
		var data: Dictionary = chunks.snapshot_saved_chunk(key)
		var error: String = _write_json(chunk_path(slot, key), data, false)
		if error != "":
			return {"ok": false, "error": error, "slot": slot}
		saved_chunks += 1
	var meta: Dictionary = {
		"version": VERSION,
		"generator_version": WorldRng.GENERATOR_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"saved_unix": Time.get_unix_time_from_system(),
		"seed": str(world.world_seed),
		"seed_text": world.seed_text if world.seed_text != "" else str(world.world_seed),
		"scenario": world.scenario,
		"use_arena": world.use_arena,
		"population": world.population,
		"level": world.chunks.level,
		"clock": GameClock.elapsed_points,
		"clock_text": GameClock.get_time_string(),
		"safe_centers": _cells_to_arrays(world.safe_centers),
		"player": player_to_dict(player),
		"chunk_count": saved_chunks,
	}
	var error: String = _write_json(meta_path(slot), meta, true)
	if error != "":
		return {"ok": false, "error": error, "slot": slot}
	return {"ok": true, "error": "", "slot": slot}


## Prépare un monde NEUF avec une sauvegarde : seed, horloge, deltas des chunks et objets au sol.
## À appeler après add_child(world) mais AVANT de créer le joueur (sinon les chunks se chargent régénérés).
## Renvoie {ok, error, meta}.
static func load_world(world: World, slot: String) -> Dictionary:
	var meta: Dictionary = read_meta(slot)
	var reason: String = compatibility_error(meta)
	if reason != "":
		return {"ok": false, "error": reason, "meta": {}}
	var seed_value: int = String(meta.get("seed", "0")).to_int()
	world.clear_ground_items()
	world.world_seed = seed_value
	world.seed_text = String(meta.get("seed_text", meta.get("seed", "")))
	world.scenario = String(meta.get("scenario", "default"))
	world.use_arena = bool(meta.get("use_arena", false))
	world.population = float(meta.get("population", 1.0))
	world.safe_centers.clear()
	for cell_data: Variant in meta.get("safe_centers", []):
		world.safe_centers.append(World.cell_from_data(cell_data))
	GameClock.elapsed_points = float(meta.get("clock", 0.0))
	StatusEffects.reset()
	Infection.reset()
	world.chunks.reset_state()
	world.chunks.world_seed = seed_value
	world.chunks.arena = world.use_arena
	world.chunks.level = int(meta.get("level", 0))
	var dir := DirAccess.open(chunks_dir(slot))
	if dir != null:
		for file: String in dir.get_files():
			if not file.ends_with(".json"):
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(chunks_dir(slot).path_join(file)))
			if parsed is Dictionary:
				world.chunks.restore_saved_chunk(parsed)
	return {"ok": true, "error": "", "meta": meta}


## Case de départ du joueur sauvegardé (repli : case 0, 0).
static func saved_spawn(meta: Dictionary) -> Vector2i:
	var player_data: Dictionary = meta.get("player", {})
	return World.cell_from_data(player_data.get("cell", []), Vector2i.ZERO)


# --- Joueur ---

static func player_to_dict(player: Player) -> Dictionary:
	var pending: Array = []
	for entry: Dictionary in player.pending_drops:
		pending.append({
			"item": (entry.get("item") as Item).to_dict(),
			"cell": _cell_to_array(entry.get("cell", Vector2i.ZERO)),
		})
	return {
		"cell": _cell_to_array(player.grid_pos),
		"body": player.body.duplicate(true),
		"dead": player.dead,
		"stamina": player.stamina,
		"posture": player.posture,
		"zoom_index": player.zoom_index,
		"stats": player.stats.duplicate(true),
		"avoid_scenery": player.avoid_scenery,
		"inventory": player.inventory.to_dict(),
		"pending_drops": pending,
		"map_markers": _markers_to_arrays(player.map_markers),
		"status_effects": StatusEffects.snapshot(),
		"infection": Infection.snapshot(),
	}


## Réapplique l'état du joueur APRÈS son _ready() (inventaire de départ remplacé, signaux rafraîchis par l'appelant).
static func apply_player(player: Player, data: Dictionary) -> void:
	var cell: Vector2i = World.cell_from_data(data.get("cell", []), player.grid_pos)
	player.grid_pos = cell
	player.position = Vector2(cell * World.TILE_SIZE)
	player.body.clear()
	var body_data: Dictionary = data.get("body", {})
	for part_id: Variant in body_data:
		player.body[String(part_id)] = float(body_data[part_id])
	for part_id: String in BodyPartDB.ids():  # une partie ajoutée depuis la sauvegarde repart au maximum
		if not player.body.has(part_id):
			player.body[part_id] = BodyPartDB.max_hp_of(part_id)
	player.dead = bool(data.get("dead", false))
	player.stamina = clampf(float(data.get("stamina", Player.STAMINA_MAX)), 0.0, Player.STAMINA_MAX)
	player.posture = clampi(int(data.get("posture", Player.Posture.WALK)), 0, Player.POSTURE_NAMES.size() - 1)
	player.zoom_index = clampi(int(data.get("zoom_index", Player.ZOOM_START_INDEX)), 0, Player.ZOOM_LEVELS.size() - 1)
	if player.camera != null:
		player.camera.zoom = Vector2.ONE * Player.ZOOM_LEVELS[player.zoom_index]
	player.stats.clear()
	var stats_data: Dictionary = data.get("stats", {})
	for stat_id: Variant in stats_data:
		player.stats[String(stat_id)] = float(stats_data[stat_id])
	for stat_id: String in StatDB.ids():
		if not player.stats.has(stat_id):
			player.stats[stat_id] = StatDB.base_of(stat_id)
	player.avoid_scenery = bool(data.get("avoid_scenery", true))
	player.inventory.apply_dict(data.get("inventory", {}))
	player.pending_drops.clear()
	for entry: Variant in data.get("pending_drops", []):
		if not (entry is Dictionary):
			continue
		var item_data: Variant = entry.get("item", null)
		if item_data is Dictionary:
			player.pending_drops.append({
				"item": Item.from_dict(item_data),
				"cell": World.cell_from_data(entry.get("cell", []), cell),
			})
	# Champ ajouté au jalon 8 : les anciennes sauvegardes n'en ont pas (liste vide).
	player.map_markers.clear()
	for entry: Variant in data.get("map_markers", []):
		if entry is Array and (entry as Array).size() >= 3:
			var marker: Array = entry
			player.map_markers[Vector3i(int(marker[0]), int(marker[1]), int(marker[2]))] = true
	StatusEffects.restore(player, data.get("status_effects", {}))
	Infection.restore(player, data.get("infection", {}))
	player.clear_target()
	player.refresh_inventory()
	if player.world != null:
		player.world.update_fov()


# --- Suppression ---

static func delete_slot(slot: String) -> bool:
	if not valid_slot(slot) or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot_dir(slot))):
		return false
	_remove_tree(slot_dir(slot))
	return not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot_dir(slot)))


# --- Internes ---

static func _markers_to_arrays(markers: Dictionary) -> Array:
	var out: Array = []
	var keys: Array = markers.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z < b.z
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	for key: Vector3i in keys:
		out.append([key.x, key.y, key.z])
	return out


static func _cells_to_arrays(cells: Array[Vector2i]) -> Array:
	var out: Array = []
	for cell: Vector2i in cells:
		out.append(_cell_to_array(cell))
	return out


static func _cell_to_array(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


static func _write_json(path: String, data: Dictionary, pretty: bool) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "impossible d'écrire %s (erreur %d)" % [path, FileAccess.get_open_error()]
	file.store_string(JSON.stringify(data, "\t" if pretty else ""))
	file.close()
	return ""


static func _clear_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for sub: String in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
