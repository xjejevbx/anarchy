class_name ChunkManager
extends RefCounted
## Chunks chargés autour du joueur (docs/WORLD_GEN.md §7). Génère à la demande (déterministe, voir ChunkGenerator),
## étale la génération des chunks lointains sur plusieurs frames et décharge ceux qui sont trop loin.
## La mémoire de la carte (cases vues) survit au déchargement.
## Jalon 6a (docs/MONSTER_SPAWN.md §2.3) : à son PREMIER chargement, un chunk reçoit ses monstres (SpawnGenerator, fonction pure) ;
## à son déchargement, ses monstres vivants sont mis en réserve (`_monster_store`, comme `_seen_store`) et rendus tels quels au
## rechargement. Un chunk déjà peuplé n'est jamais repeuplé : un monstre tué reste tué.
## Jalon 6d (docs/MONSTER_SPAWN.md §15, « rattrapage ») : un chunk absent depuis plus de CATCHUP_AFTER secondes de jeu voit sa faune AMBIANTE migrer à son
## retour : chaque monstre ambiant (hors uniques) part avec la probabilité CATCHUP_LOSS, et de nouveaux arrivent (autre tirage de l'écologie, `salt`).
## Les monstres de lieux ne migrent pas : ils sont chez eux.
## Axe vertical (jalon 6b) : le gestionnaire ne charge QU'UN étage (`level`, 0 = surface). Les requêtes par case (Vector2i) portent sur cet
## étage ; set_level() décharge tous les chunks de l'ancien étage (cases vues et monstres sont gardés par clé Vector3i, z compris).

# --- Réglages ---
const GEN_RADIUS: int = 3         # chunks maintenus autour du joueur (7 x 7)
const NEAR_RADIUS: int = 2        # chunks générés immédiatement (la vue de 20 cases tient dedans)
const KEEP_RADIUS: int = 4        # au-delà, le chunk est déchargé
const CHUNKS_PER_FRAME: int = 1   # génération étalée des chunks lointains (un chunk coûte quelques ms)
const CATCHUP_AFTER: float = 3600.0   # absence (secondes de jeu) au-delà de laquelle la faune ambiante migre
const CATCHUP_LOSS: float = 0.3       # part des monstres ambiants qui partent (et part de la faune fraîche qui arrive en plus)

var world_seed: int = 0
var arena: bool = false
var chunks: Dictionary = {}       # Vector3i -> Chunk
var world: World = null           # propriétaire des monstres (null : aucun monstre n'est créé ni mis en réserve)
var level: int = 0                # étage actif (z des chunks chargés)

var _root: Node2D                 # parent des chunks (le sol)
var _entities: Node2D             # parent des sprites d'arbres
var _seen_store: Dictionary = {}  # Vector3i -> PackedByteArray (cases vues des chunks déchargés)
var _populated: Dictionary = {}   # Vector3i -> true : chunks déjà peuplés (ne le sont plus jamais)
var _monster_store: Dictionary = {}  # Vector3i -> Array[Dictionary] (Monster.to_dict) des chunks déchargés
var _unloaded_at: Dictionary = {}    # Vector3i -> moment (points d'action) du déchargement d'un chunk peuplé
var _queue: Array[Vector3i] = []
# --- Deltas de sauvegarde (jalon 7) ---
var _modified: Dictionary = {}          # Vector3i -> true : chunk à écrire dans la sauvegarde
var _terrain_deltas: Dictionary = {}    # Vector3i -> Dictionary(index local -> index de terrain)
var _furniture_deltas: Dictionary = {}  # Vector3i -> Dictionary(index local -> index de mobilier)


func setup(seed_value: int, use_arena: bool, root: Node2D, entities: Node2D, owner_world: World = null) -> void:
	world_seed = seed_value
	arena = use_arena
	_root = root
	_entities = entities
	world = owner_world


static func key_of(cell: Vector2i, z: int = 0) -> Vector3i:
	return Vector3i(floori(float(cell.x) / Chunk.SIZE), floori(float(cell.y) / Chunk.SIZE), z)


static func index_of(cell: Vector2i) -> int:
	return posmod(cell.y, Chunk.SIZE) * Chunk.SIZE + posmod(cell.x, Chunk.SIZE)


## Change d'étage : l'ancien est déchargé en entier (monstres en réserve) ; le nouveau se charge au prochain update_around().
func set_level(new_level: int) -> void:
	if new_level == level:
		return
	level = new_level
	_queue.clear()
	for key: Vector3i in chunks.keys():
		if key.z != level:
			_unload(key)


## Charge les chunks proches de `cell` (tout de suite) et programme les plus lointains ; décharge les trop éloignés.
func update_around(cell: Vector2i) -> void:
	var center: Vector3i = key_of(cell, level)
	_queue.clear()
	for r in range(0, GEN_RADIUS + 1):  # du plus proche au plus lointain
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var key := Vector3i(center.x + dx, center.y + dy, center.z)
				if chunks.has(key):
					continue
				if r <= NEAR_RADIUS:
					_load(key)
				else:
					_queue.append(key)
	for key: Vector3i in chunks.keys():
		if key.z != level or maxi(absi(key.x - center.x), absi(key.y - center.y)) > KEEP_RADIUS:
			_unload(key)


## À appeler à chaque frame : génère quelques chunks lointains programmés.
func process_queue() -> void:
	var done: int = 0
	while done < CHUNKS_PER_FRAME and not _queue.is_empty():
		var key: Vector3i = _queue.pop_front()
		if not chunks.has(key):
			_load(key)
			done += 1


func _load(key: Vector3i) -> void:
	var seen: PackedByteArray = _seen_store.get(key, PackedByteArray())
	if seen.size() != Chunk.CELLS:
		seen = PackedByteArray()
		seen.resize(Chunk.CELLS)
	var chunk := Chunk.new()
	chunk.setup(key, ChunkGenerator.generate(world_seed, key, arena), seen, self, _entities)
	chunk.furniture = ChunkGenerator.generate_furniture(world_seed, key, arena)
	_apply_deltas(key, chunk)
	if not arena:
		chunk.build_roof()   # empreinte du toit (surface), après les deltas de portes / fenêtres
	_root.add_child(chunk)
	chunks[key] = chunk
	if chunk.has_autotile:  # les murs des chunks voisins doivent se raccorder
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var other := chunks.get(Vector3i(key.x + dx, key.y + dy, key.z)) as Chunk
				if other != null and other != chunk and other.has_autotile:
					other.queue_redraw()
	_populate(key, chunk)


## Applique les modifications de terrain / mobilier sauvegardées APRÈS la génération du chunk.
func _apply_deltas(key: Vector3i, chunk: Chunk) -> void:
	var terrain_data: Dictionary = _terrain_deltas.get(key, {})
	for index: int in terrain_data:
		chunk.set_terrain(index, int(terrain_data[index]))
	var furniture_data: Dictionary = _furniture_deltas.get(key, {})
	for index: int in furniture_data:
		chunk.set_furniture(index, int(furniture_data[index]))


func _unload(key: Vector3i) -> void:
	var chunk := chunks[key] as Chunk
	if _populated.has(key):
		_unloaded_at[key] = GameClock.elapsed_points
	_store_monsters(key)
	_seen_store[key] = chunk.seen
	chunk.release()
	chunks.erase(key)


# --- Monstres du chunk (jalon 6a) ---

## Premier chargement : les monstres initiaux (SpawnGenerator). Rechargement : les monstres mis en réserve, tels quels.
func _populate(key: Vector3i, chunk: Chunk) -> void:
	if world == null or arena:
		return
	var away: float = _away_time(key)
	if _monster_store.has(key):
		var saved: Array = _monster_store[key]
		_monster_store.erase(key)
		var gains: Array[Dictionary] = []
		if away >= CATCHUP_AFTER:
			saved = _migrate(key, chunk, saved, gains)
		for entry: Dictionary in saved:
			world.restore_monster(entry)
		for entry: Dictionary in gains:
			world.spawn_monster_at(entry)
		_modified[key] = true
		return
	if _populated.has(key):
		if away >= CATCHUP_AFTER:   # chunk vidé (ou sans monstre) : la faune ambiante peut revenir
			var gains: Array[Dictionary] = []
			_migrate(key, chunk, [], gains)
			for entry: Dictionary in gains:
				world.spawn_monster_at(entry)
			if not gains.is_empty():
				_modified[key] = true
		return
	if world.monsters.size() >= World.MAX_MONSTERS:
		return  # plafond global atteint : on retentera au prochain chargement
	_populated[key] = true
	_modified[key] = true  # même sans monstre, le chunk doit être sauvegardé (population figée)
	var entries: Array[Dictionary] = SpawnGenerator.generate(world_seed, key, chunk.terrain, chunk.furniture, world.population, world.safe_centers)
	for entry: Dictionary in entries:
		world.spawn_monster_at(entry)


## Secondes de jeu écoulées depuis le déchargement du chunk (0 s'il n'a jamais été déchargé) ; consomme l'horodatage.
func _away_time(key: Vector3i) -> float:
	if not _unloaded_at.has(key):
		return 0.0
	var away: float = GameClock.elapsed_points - float(_unloaded_at[key])
	_unloaded_at.erase(key)
	return away


## Migration de la faune d'un chunk resté absent : renvoie les monstres gardés (les uniques et ceux des lieux restent ; chaque monstre ambiant
## part avec CATCHUP_LOSS) ; `gains` reçoit les nouveaux arrivants (faune ambiante tirée avec un autre sel, autant que de partants plus une part
## du tirage frais). Pas de nouvel arrivant si le plafond de monstres est atteint.
func _migrate(key: Vector3i, chunk: Chunk, saved: Array, gains: Array[Dictionary]) -> Array:
	var bucket: int = maxi(int(GameClock.elapsed_points / CATCHUP_AFTER), 1)
	var rng: RandomNumberGenerator = WorldRng.rng_for(world_seed, WorldRng.LAYER_SPAWN, key.x, key.y, key.z, bucket + 1000003)
	var kept: Array = []
	var lost: int = 0
	for entry: Dictionary in saved:
		if bool(entry.get("ambient", false)) and not MonsterDB.tags_of(String(entry["id"])).has("unique") and rng.randf() < CATCHUP_LOSS:
			lost += 1
		else:
			kept.append(entry)
	if world.monsters.size() >= World.MAX_MONSTERS:
		return kept
	var fresh: Array[Dictionary] = SpawnGenerator.generate(world_seed, key, chunk.terrain, chunk.furniture, world.population, world.safe_centers,
		"", {}, bucket + 1, true)
	var count: int = mini(lost + ceili(CATCHUP_LOSS * float(fresh.size())), fresh.size())
	for i in count:
		gains.append(fresh[i])
	return kept


## Déchargement : les monstres qui se trouvent dans le chunk quittent le monde et sont mis en réserve.
func _store_monsters(key: Vector3i) -> void:
	if world == null:
		return
	var saved: Array[Dictionary] = []
	for m: Monster in world.monsters.duplicate():
		if m.z == key.z and key_of(m.grid_pos, key.z) == key:
			saved.append(m.to_dict())
			world.remove_monster(m)
	if not saved.is_empty():
		_monster_store[key] = saved
	_modified[key] = true


## Réinitialise tout l'état du gestionnaire (chargement d'une sauvegarde dans un monde neuf).
func reset_state() -> void:
	for key: Vector3i in chunks.keys():
		(chunks[key] as Chunk).release()
	chunks.clear()
	_queue.clear()
	_seen_store.clear()
	_populated.clear()
	_monster_store.clear()
	_unloaded_at.clear()
	reset_deltas()
	level = 0


# --- Deltas de sauvegarde (jalon 7) ---

## Marque le chunk de `cell` (étage z) comme modifié : il sera écrit dans la sauvegarde.
func mark_modified_at(cell: Vector2i, z: int = 0) -> void:
	_modified[key_of(cell, z)] = true


## Modifie le terrain d'une case (delta) : la valeur de base est régénérée au chargement.
func set_terrain(cell: Vector2i, value: int) -> void:
	var key: Vector3i = key_of(cell, level)
	var index: int = index_of(cell)
	if not _terrain_deltas.has(key):
		_terrain_deltas[key] = {}
	(_terrain_deltas[key] as Dictionary)[index] = value
	_modified[key] = true
	var chunk := chunks.get(key) as Chunk
	if chunk != null:
		chunk.set_terrain(index, value)
		_redraw_wall_neighbors(key)


## Modifie le mobilier d'une case (delta).
func set_furniture(cell: Vector2i, value: int) -> void:
	var key: Vector3i = key_of(cell, level)
	var index: int = index_of(cell)
	if not _furniture_deltas.has(key):
		_furniture_deltas[key] = {}
	(_furniture_deltas[key] as Dictionary)[index] = value
	_modified[key] = true
	var chunk := chunks.get(key) as Chunk
	if chunk != null:
		chunk.set_furniture(index, value)
		if FurnitureDB.is_opaque(value):
			_redraw_wall_neighbors(key)


func _redraw_wall_neighbors(key: Vector3i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var other := chunks.get(Vector3i(key.x + dx, key.y + dy, key.z)) as Chunk
			if other != null and other.has_autotile:
				other.queue_redraw()


## Clés des chunks à sauvegarder (explorés, peuplés ou modifiés depuis la création).
func modified_keys() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for key: Vector3i in _modified:
		out.append(key)
	out.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z < b.z
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	return out


func is_populated_key(key: Vector3i) -> bool:
	return _populated.has(key)


func terrain_delta(key: Vector3i) -> Dictionary:
	return _terrain_deltas.get(key, {})


func furniture_delta(key: Vector3i) -> Dictionary:
	return _furniture_deltas.get(key, {})


## Cases vues d'un chunk (chargé ou en réserve), toujours de la taille d'un chunk.
func seen_of(key: Vector3i) -> PackedByteArray:
	var seen := PackedByteArray()
	var chunk := chunks.get(key) as Chunk
	if chunk != null:
		seen = chunk.seen
	elif _seen_store.has(key):
		seen = _seen_store[key]
	if seen.size() != Chunk.CELLS:
		seen = PackedByteArray()
		seen.resize(Chunk.CELLS)
	return seen


## Contenu d'un chunk pour un fichier de sauvegarde (terrain régénérable non inclus).
func snapshot_saved_chunk(key: Vector3i) -> Dictionary:
	var chunk := chunks.get(key) as Chunk
	var monsters: Array = []
	if world != null:
		if chunk != null:
			for m: Monster in world.monsters:
				if m.z == key.z and key_of(m.grid_pos, key.z) == key:
					monsters.append(m.to_dict())
		elif _monster_store.has(key):
			monsters = (_monster_store[key] as Array).duplicate(true)
	var items: Array = []
	if world != null:
		var ground: Dictionary = world.ground_items_of_level(key.z)
		for cell: Vector2i in ground:
			if key_of(cell, key.z) != key:
				continue
			var list: Array = ground[cell]
			if list.is_empty():
				continue
			var encoded: Array = []
			for item: Item in list:
				encoded.append(item.to_dict())
			items.append([index_of(cell), encoded])
	items.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var terrain_source: Dictionary = _terrain_deltas.get(key, {})
	var furniture_source: Dictionary = _furniture_deltas.get(key, {})
	var terrain_data: Array = []
	for index: int in _delta_indexes(terrain_source):
		terrain_data.append([index, int(terrain_source[index])])
	var furniture_data: Array = []
	for index: int in _delta_indexes(furniture_source):
		furniture_data.append([index, int(furniture_source[index])])
	return {
		"key": [key.x, key.y, key.z],
		"populated": _populated.has(key),
		"seen": Marshalls.raw_to_base64(seen_of(key)),
		"terrain": terrain_data,
		"furniture": furniture_data,
		"items": items,
		"monsters": monsters,
	}


func _delta_indexes(data: Dictionary) -> Array:
	var indexes: Array = data.keys()
	indexes.sort()
	return indexes


## Recharge un chunk sauvegardé : mémoire des cases vues, population, deltas et objets au sol.
## À appeler AVANT qu'un joueur ne charge les chunks (sinon le chunk déjà chargé garde son état régénéré).
func restore_saved_chunk(data: Dictionary) -> bool:
	var raw_key: Variant = data.get("key", [])
	if not (raw_key is Array):
		return false
	var key_array: Array = raw_key
	if key_array.size() < 3:
		return false
	var key := Vector3i(int(key_array[0]), int(key_array[1]), int(key_array[2]))
	var seen: PackedByteArray = Marshalls.base64_to_raw(String(data.get("seen", "")))
	if seen.size() != Chunk.CELLS:
		seen = PackedByteArray()
		seen.resize(Chunk.CELLS)
	_seen_store[key] = seen
	if bool(data.get("populated", false)):
		_populated[key] = true
	else:
		_populated.erase(key)
	for pair: Variant in data.get("terrain", []):
		if pair is Array:
			var pair_array: Array = pair
			if pair_array.size() >= 2:
				if not _terrain_deltas.has(key):
					_terrain_deltas[key] = {}
				(_terrain_deltas[key] as Dictionary)[int(pair_array[0])] = int(pair_array[1])
	for pair: Variant in data.get("furniture", []):
		if pair is Array:
			var pair_array: Array = pair
			if pair_array.size() >= 2:
				if not _furniture_deltas.has(key):
					_furniture_deltas[key] = {}
				(_furniture_deltas[key] as Dictionary)[int(pair_array[0])] = int(pair_array[1])
	var saved_monsters: Array = data.get("monsters", [])
	if _populated.has(key) or not saved_monsters.is_empty():
		_monster_store[key] = saved_monsters
	else:
		_monster_store.erase(key)
	if world != null:
		for entry: Variant in data.get("items", []):
			if not (entry is Array):
				continue
			var entry_array: Array = entry
			if entry_array.size() < 2:
				continue
			var local: int = int(entry_array[0])
			var cell := Vector2i(key.x * Chunk.SIZE + local % Chunk.SIZE, key.y * Chunk.SIZE + floori(float(local) / Chunk.SIZE))
			var items: Array = []
			for item_data: Variant in entry_array[1]:
				if item_data is Dictionary:
					items.append(Item.from_dict(item_data))
			world.set_ground_items_at(key.z, cell, items)
	_modified[key] = true
	return true


## Vide l'état de sauvegarde en mémoire (tests / nouvelle partie).
func reset_deltas() -> void:
	_modified.clear()
	_terrain_deltas.clear()
	_furniture_deltas.clear()


## Le chunk a-t-il déjà été peuplé ? (tests)
func is_populated(key: Vector3i) -> bool:
	return _populated.has(key)


## Nombre de monstres en réserve (chunks déchargés). (tests)
func stored_monster_count() -> int:
	var total: int = 0
	for key: Vector3i in _monster_store:
		total += (_monster_store[key] as Array).size()
	return total


# --- Requêtes sur les cases (une case hors des chunks chargés est inconnue : ni praticable, opaque) ---

func chunk_at(cell: Vector2i) -> Chunk:
	return chunks.get(key_of(cell, level)) as Chunk


## Index de terrain de la case, -1 si son chunk n'est pas chargé.
func terrain_index(cell: Vector2i) -> int:
	var chunk: Chunk = chunk_at(cell)
	return -1 if chunk == null else chunk.terrain[index_of(cell)]


## Terrain d'une case à un étage donné, MÊME si cet étage n'est pas chargé : lit le delta sauvegardé s'il existe,
## sinon régénère le chunk (fonction pure). Sert à valider une arrivée par escalier avant de changer d'étage.
func terrain_at_level(cell: Vector2i, z: int) -> int:
	var key: Vector3i = key_of(cell, z)
	var index: int = index_of(cell)
	if z == level:
		var chunk := chunks.get(key) as Chunk
		if chunk != null:
			return chunk.terrain[index]
	var delta: Dictionary = _terrain_deltas.get(key, {})
	if delta.has(index):
		return int(delta[index])
	return ChunkGenerator.generate(world_seed, key, arena)[index]


## Mobilier d'une case à un étage donné, chargé ou non (même principe que terrain_at_level).
func furniture_at_level(cell: Vector2i, z: int) -> int:
	var key: Vector3i = key_of(cell, z)
	var index: int = index_of(cell)
	if z == level:
		var chunk := chunks.get(key) as Chunk
		if chunk != null:
			return chunk.furniture[index]
	var delta: Dictionary = _furniture_deltas.get(key, {})
	if delta.has(index):
		return int(delta[index])
	return ChunkGenerator.generate_furniture(world_seed, key, arena)[index]


func has_terrain(cell: Vector2i) -> bool:
	return chunk_at(cell) != null


## Type de toit de la case à l'étage actif : Chunk.ROOF_NONE / ROOF_COVER / ROOF_OPENING.
func roof_at(cell: Vector2i) -> int:
	var chunk: Chunk = chunk_at(cell)
	if chunk == null or chunk.roof.size() != Chunk.CELLS:
		return Chunk.ROOF_NONE
	return chunk.roof[index_of(cell)]


## Le toit du chunk de la case a-t-il déjà été aperçu (au moins une de ses cases vue) ?
func roof_known_at(cell: Vector2i) -> bool:
	var chunk: Chunk = chunk_at(cell)
	return chunk != null and chunk.roof_known


func is_walkable(cell: Vector2i) -> bool:
	var chunk: Chunk = chunk_at(cell)
	if chunk == null:
		return false
	var i: int = index_of(cell)
	return TerrainDB.is_walkable(chunk.terrain[i]) and FurnitureDB.is_walkable(chunk.furniture[i])


func is_opaque(cell: Vector2i) -> bool:
	var chunk: Chunk = chunk_at(cell)
	if chunk == null:
		return true
	var i: int = index_of(cell)
	return TerrainDB.is_opaque(chunk.terrain[i]) or FurnitureDB.is_opaque(chunk.furniture[i])


func is_seen(cell: Vector2i) -> bool:
	var chunk: Chunk = chunk_at(cell)
	return chunk != null and chunk.seen[index_of(cell)] != 0


func mark_seen(cell: Vector2i) -> void:
	var chunk: Chunk = chunk_at(cell)
	if chunk != null and chunk.mark_seen(index_of(cell)):
		_modified[chunk.key] = true


# --- Murs : choix du sprite selon les murs voisins ---

func _is_wall(cell: Vector2i) -> bool:
	var index: int = terrain_index(cell)
	return TerrainDB.autotile_of(index) == "wall" or TerrainDB.links_wall(index)  # portes et fenêtres se raccordent aux murs


## Convention UltiCa/CDDA : « corner_nw » est le coin nord-ouest d'une structure (il relie l'est et le sud).
## À FAIRE : jonctions en T et extrémités (t_connection_*, end_piece_*) quand on aura des bâtiments.
func wall_sprite(cell: Vector2i) -> String:
	var n: bool = _is_wall(cell + Vector2i.UP)
	var e: bool = _is_wall(cell + Vector2i.RIGHT)
	var s: bool = _is_wall(cell + Vector2i.DOWN)
	var w: bool = _is_wall(cell + Vector2i.LEFT)
	if n and s and not e and not w:
		return "t_wall_edge_ns"
	if e and w and not n and not s:
		return "t_wall_edge_ew"
	if e and s and not n and not w:
		return "t_wall_corner_nw"
	if w and s and not n and not e:
		return "t_wall_corner_ne"
	if w and n and not e and not s:
		return "t_wall_corner_se"
	if e and n and not w and not s:
		return "t_wall_corner_sw"
	var links: int = int(n) + int(e) + int(s) + int(w)
	if links == 3:  # jonction en T : le nom du sprite est le côté SANS mur (convention à vérifier à l'œil ; inverser ici si besoin)
		if not n:
			return "t_wall_t_connection_n"
		if not e:
			return "t_wall_t_connection_e"
		if not s:
			return "t_wall_t_connection_s"
		return "t_wall_t_connection_w"
	if links == 1:  # extrémité : le nom du sprite est le côté libre (opposé au mur relié)
		if s:
			return "t_wall_end_piece_n"
		if n:
			return "t_wall_end_piece_s"
		if w:
			return "t_wall_end_piece_e"
		return "t_wall_end_piece_w"
	if n and s:
		return "t_wall_edge_ns"
	if e and w:
		return "t_wall_edge_ew"
	return "t_wall_unconnected"


# --- Toits : même convention de raccord que les murs, pièces « t_shingle_flat_roof_* » ---

func _is_roof_cover(cell: Vector2i) -> bool:
	return roof_at(cell) == Chunk.ROOF_COVER


## Sprite du toit de la case selon les cases de toit voisines (aucun raccord avec l'extérieur du bâtiment).
func roof_sprite(cell: Vector2i) -> String:
	var n: bool = _is_roof_cover(cell + Vector2i.UP)
	var e: bool = _is_roof_cover(cell + Vector2i.RIGHT)
	var s: bool = _is_roof_cover(cell + Vector2i.DOWN)
	var w: bool = _is_roof_cover(cell + Vector2i.LEFT)
	var links: int = int(n) + int(e) + int(s) + int(w)
	if links == 4:
		return "t_shingle_flat_roof_center"
	if links == 3:  # jonction en T : le nom du sprite est le côté SANS toit
		if not n:
			return "t_shingle_flat_roof_t_connection_n"
		if not e:
			return "t_shingle_flat_roof_t_connection_e"
		if not s:
			return "t_shingle_flat_roof_t_connection_s"
		return "t_shingle_flat_roof_t_connection_w"
	if links == 1:  # extrémité : le nom du sprite est le côté libre
		if s:
			return "t_shingle_flat_roof_end_piece_n"
		if n:
			return "t_shingle_flat_roof_end_piece_s"
		if w:
			return "t_shingle_flat_roof_end_piece_e"
		return "t_shingle_flat_roof_end_piece_w"
	if n and s and not e and not w:
		return "t_shingle_flat_roof_edge_ns"
	if e and w and not n and not s:
		return "t_shingle_flat_roof_edge_ew"
	if e and s and not n and not w:
		return "t_shingle_flat_roof_corner_nw"
	if w and s and not n and not e:
		return "t_shingle_flat_roof_corner_ne"
	if w and n and not e and not s:
		return "t_shingle_flat_roof_corner_se"
	if e and n and not w and not s:
		return "t_shingle_flat_roof_corner_sw"
	if n and s:
		return "t_shingle_flat_roof_edge_ns"
	if e and w:
		return "t_shingle_flat_roof_edge_ew"
	return "t_shingle_flat_roof_unconnected"
