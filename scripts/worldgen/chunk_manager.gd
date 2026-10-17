class_name ChunkManager
extends RefCounted
## Chunks chargés autour du joueur (docs/WORLD_GEN.md §7). Génère à la demande (déterministe, voir ChunkGenerator),
## étale la génération des chunks lointains sur plusieurs frames et décharge ceux qui sont trop loin.
## La mémoire de la carte (cases vues) survit au déchargement.

# --- Réglages ---
const GEN_RADIUS: int = 3         # chunks maintenus autour du joueur (7 x 7)
const NEAR_RADIUS: int = 2        # chunks générés immédiatement (la vue de 20 cases tient dedans)
const KEEP_RADIUS: int = 4        # au-delà, le chunk est déchargé
const CHUNKS_PER_FRAME: int = 1   # génération étalée des chunks lointains (un chunk coûte quelques ms)

var world_seed: int = 0
var arena: bool = false
var chunks: Dictionary = {}       # Vector3i -> Chunk

var _root: Node2D                 # parent des chunks (le sol)
var _entities: Node2D             # parent des sprites d'arbres
var _seen_store: Dictionary = {}  # Vector3i -> PackedByteArray (cases vues des chunks déchargés)
var _queue: Array[Vector3i] = []


func setup(seed_value: int, use_arena: bool, root: Node2D, entities: Node2D) -> void:
	world_seed = seed_value
	arena = use_arena
	_root = root
	_entities = entities


static func key_of(cell: Vector2i, z: int = 0) -> Vector3i:
	return Vector3i(floori(float(cell.x) / Chunk.SIZE), floori(float(cell.y) / Chunk.SIZE), z)


static func index_of(cell: Vector2i) -> int:
	return posmod(cell.y, Chunk.SIZE) * Chunk.SIZE + posmod(cell.x, Chunk.SIZE)


## Charge les chunks proches de `cell` (tout de suite) et programme les plus lointains ; décharge les trop éloignés.
func update_around(cell: Vector2i) -> void:
	var center: Vector3i = key_of(cell)
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
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > KEEP_RADIUS:
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
	_root.add_child(chunk)
	chunks[key] = chunk
	if chunk.has_autotile:  # les murs des chunks voisins doivent se raccorder
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var other := chunks.get(Vector3i(key.x + dx, key.y + dy, key.z)) as Chunk
				if other != null and other != chunk and other.has_autotile:
					other.queue_redraw()


func _unload(key: Vector3i) -> void:
	var chunk := chunks[key] as Chunk
	_seen_store[key] = chunk.seen
	chunk.release()
	chunks.erase(key)


# --- Requêtes sur les cases (une case hors des chunks chargés est inconnue : ni praticable, opaque) ---

func chunk_at(cell: Vector2i) -> Chunk:
	return chunks.get(key_of(cell)) as Chunk


## Index de terrain de la case, -1 si son chunk n'est pas chargé.
func terrain_index(cell: Vector2i) -> int:
	var chunk: Chunk = chunk_at(cell)
	return -1 if chunk == null else chunk.terrain[index_of(cell)]


func has_terrain(cell: Vector2i) -> bool:
	return chunk_at(cell) != null


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
	if chunk != null:
		chunk.mark_seen(index_of(cell))


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
