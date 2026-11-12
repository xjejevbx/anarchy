class_name Chunk
extends Node2D
## Un chunk de 24 x 24 cases : terrain (un octet par case), cases vues (mémoire de la carte) et sprites d'arbres.
## Le sol est dessiné une fois par le chunk lui-même (mis en cache par Godot, redessiné seulement si on le demande).
## Les arbres sont des sprites dans le calque `entities` (triés par Y avec joueur et monstres), cachés tant que la case n'a pas été vue.
## Les arbres balancent au vent (shader partagé, voir Fx.wind_material) et projettent une ombre dans le sol du chunk.

const SIZE: int = 24
const CELLS: int = SIZE * SIZE
const TREE_SHADOW_CENTER: Vector2 = Vector2(64.0, 108.0)   # pied du tronc dans la case (pixels)
const TREE_SHADOW_RADII: Vector2 = Vector2(52.0, 17.0)

# --- Toits (jalon 8) : empreinte du bâtiment du chunk, dérivée du terrain généré ---
const ROOF_NONE: int = 0       # hors du bâtiment
const ROOF_COVER: int = 1      # toit : intérieur et murs
const ROOF_OPENING: int = 2    # porte / fenêtre : reste visible sous le toit

var key: Vector3i = Vector3i.ZERO
var terrain: PackedByteArray = PackedByteArray()
var seen: PackedByteArray = PackedByteArray()
var furniture: PackedByteArray = PackedByteArray()   # mobilier : 0 = rien, sinon index FurnitureDB (rempli par ChunkManager)
var roof: PackedByteArray = PackedByteArray()        # ROOF_* par case (surface seulement), voir build_roof()
var roof_known: bool = false                          # au moins une case du toit a déjà été vue
var has_autotile: bool = false   # contient des murs (leur sprite dépend des chunks voisins)

var _manager: ChunkManager
var _entities: Node2D
var _tree_sprites: Dictionary = {}  # indice local -> Sprite2D


## Graine stable par case : la même case a toujours la même variante de sprite.
static func cell_seed(pos: Vector2i) -> int:
	return absi((pos.x * 73856093) ^ (pos.y * 19349663))


func setup(chunk_key: Vector3i, terrain_data: PackedByteArray, seen_data: PackedByteArray,
		manager: ChunkManager, entities: Node2D) -> void:
	key = chunk_key
	terrain = terrain_data
	seen = seen_data
	_manager = manager
	_entities = entities
	position = Vector2(key.x * SIZE * World.TILE_SIZE, key.y * SIZE * World.TILE_SIZE)
	for i in CELLS:
		var t: int = terrain[i]
		if TerrainDB.autotile_of(t) != "":
			has_autotile = true
		if TerrainDB.has_entity_sprite(t):
			_add_tree(i, entities)


## Calcule l'empreinte du bâtiment du chunk (surface seulement) à partir du terrain généré. Un bâtiment est une zone
## fermée par des murs, portes et fenêtres : les cases non atteignables depuis le bord du chunk sont couvertes, ainsi
## que les murs qui les bordent. Portes et fenêtres restent visibles (ROOF_OPENING) : elles percent le toit.
## Un plan sans intérieur fermé (ruines, parking, quai...) n'a pas de toit.
func build_roof() -> void:
	roof = PackedByteArray()
	roof_known = false
	if key.z != 0 or terrain.size() != CELLS:
		return
	var mask: PackedByteArray = roof_mask(terrain)
	var any: bool = false
	for i in CELLS:
		if mask[i] != ROOF_NONE:
			any = true
			break
	if not any:
		return
	roof = mask
	if seen.size() != CELLS:
		return
	for i in CELLS:
		if roof[i] != ROOF_NONE and seen[i] != 0:
			roof_known = true
			return


## Empreinte de toit d'un terrain de chunk : ROOF_NONE / ROOF_COVER / ROOF_OPENING par case.
static func roof_mask(terrain_data: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(CELLS)
	if terrain_data.size() != CELLS:
		return result
	var blocked: Array[int] = []
	blocked.resize(CELLS)
	var openings: Array[int] = []
	openings.resize(CELLS)
	for i in CELLS:
		var t: int = terrain_data[i]
		var wall: bool = TerrainDB.autotile_of(t) == "wall"
		var links: bool = TerrainDB.links_wall(t)
		if wall or links:
			blocked[i] = 1
		if links:
			openings[i] = 1
	# Extérieur : propagation depuis les quatre bords à travers tout ce qui n'est ni mur ni ouverture.
	var outside: Array[int] = []
	outside.resize(CELLS)
	var stack: Array[int] = []
	for n in SIZE:
		_roof_visit(n, outside, blocked, stack)                       # bord nord
		_roof_visit((SIZE - 1) * SIZE + n, outside, blocked, stack)   # bord sud
		_roof_visit(n * SIZE, outside, blocked, stack)                # bord ouest
		_roof_visit(n * SIZE + SIZE - 1, outside, blocked, stack)     # bord est
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x: int = i % SIZE
		if x > 0:
			_roof_visit(i - 1, outside, blocked, stack)
		if x < SIZE - 1:
			_roof_visit(i + 1, outside, blocked, stack)
		if i >= SIZE:
			_roof_visit(i - SIZE, outside, blocked, stack)
		if i < CELLS - SIZE:
			_roof_visit(i + SIZE, outside, blocked, stack)
	# Intérieur fermé : cases non atteignables depuis l'extérieur.
	var interior: int = 0
	for i in CELLS:
		if blocked[i] == 0 and outside[i] == 0:
			result[i] = ROOF_COVER
			interior += 1
	if interior == 0:
		return result
	# Murs qui bordent l'intérieur (une seule couronne : les murs de clôture isolés ne sont pas couverts).
	var mask: Array[int] = []
	mask.resize(CELLS)
	for i in CELLS:
		mask[i] = result[i]
	var walls: Array[int] = []
	walls.resize(CELLS)
	for i in CELLS:
		if blocked[i] != 0 and openings[i] == 0 and mask[i] == ROOF_NONE:
			if _has_cover_neighbor(mask, i % SIZE, floori(float(i) / SIZE)):
				walls[i] = 1
	for i in CELLS:
		if walls[i] != 0:
			mask[i] = ROOF_COVER
			result[i] = ROOF_COVER
	# Portes et fenêtres adjacentes au bâtiment : trous dans le toit.
	for i in CELLS:
		if openings[i] != 0 and _has_cover_neighbor(mask, i % SIZE, floori(float(i) / SIZE)):
			result[i] = ROOF_OPENING
	return result


static func _roof_visit(index: int, outside: Array[int], blocked: Array[int], stack: Array[int]) -> void:
	if index < 0 or index >= CELLS or outside[index] != 0 or blocked[index] != 0:
		return
	outside[index] = 1
	stack.append(index)


## Une case voisine (8 directions) est-elle couverte par le toit ?
static func _has_cover_neighbor(mask: Array[int], x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < SIZE and ny >= 0 and ny < SIZE and mask[ny * SIZE + nx] == ROOF_COVER:
				return true
	return false


## Applique une modification de terrain (delta de sauvegarde) et met à jour l'arbre éventuel.
func set_terrain(index: int, value: int) -> void:
	var old: int = terrain[index]
	if old == value:
		return
	terrain[index] = value
	if TerrainDB.autotile_of(value) != "":
		has_autotile = true
	if TerrainDB.has_entity_sprite(old) or TerrainDB.has_entity_sprite(value):
		_remove_tree(index)
		if TerrainDB.has_entity_sprite(value):
			_add_tree(index, _entities)
	queue_redraw()


## Applique une modification de mobilier (delta de sauvegarde).
func set_furniture(index: int, value: int) -> void:
	if furniture.size() != CELLS:
		return
	furniture[index] = value
	queue_redraw()


## Case du monde correspondant à un indice local.
func cell_of(index: int) -> Vector2i:
	return Vector2i(key.x * SIZE + index % SIZE, key.y * SIZE + floori(float(index) / SIZE))


func _add_tree(index: int, entities: Node2D) -> void:
	var cell: Vector2i = cell_of(index)
	var sprite_name: String = UlticaTiles.pick_sprite(TerrainDB.tile_of(terrain[index]), "fg", cell_seed(cell))
	var sprite := Sprite2D.new()
	sprite.texture = UlticaTiles.get_texture(sprite_name)
	sprite.centered = false
	sprite.offset = UlticaTiles.get_offset(sprite_name)
	sprite.position = Vector2(cell * World.TILE_SIZE)
	sprite.visible = seen[index] != 0
	sprite.material = Fx.wind_material()  # null si le vent est désactivé
	entities.add_child(sprite)
	_tree_sprites[index] = sprite


func _remove_tree(index: int) -> void:
	var sprite := _tree_sprites.get(index) as Sprite2D
	if sprite != null:
		sprite.queue_free()
	_tree_sprites.erase(index)


## Marque une case comme vue (et révèle son arbre s'il y en a un). Renvoie true si la case était nouvelle.
func mark_seen(index: int) -> bool:
	if seen[index] != 0:
		return false
	seen[index] = 1
	if roof.size() == CELLS and roof[index] != ROOF_NONE:
		roof_known = true
	if _tree_sprites.has(index):
		(_tree_sprites[index] as Sprite2D).visible = true
	return true


## Libère le chunk et ses sprites (la mémoire des cases vues est gardée par le ChunkManager).
func release() -> void:
	for sprite: Sprite2D in _tree_sprites.values():
		sprite.queue_free()
	_tree_sprites.clear()
	queue_free()


func _draw() -> void:
	for i in CELLS:
		var t: int = terrain[i]
		var cell: Vector2i = cell_of(i)
		var sprite_name: String
		var local := Vector2(i % SIZE, floori(float(i) / SIZE)) * World.TILE_SIZE
		if TerrainDB.autotile_of(t) == "wall":
			sprite_name = _manager.wall_sprite(cell)
		else:
			# Certaines tuiles de terrain ont un fond (tombe sur l'herbe, machine sur le béton) : voir tiles.json.
			var ground_tile: String = TerrainDB.ground_tile_of(t)
			UlticaTiles.draw_sprite(self, UlticaTiles.pick_sprite(ground_tile, "bg", cell_seed(cell)), local)
			sprite_name = UlticaTiles.pick_sprite(ground_tile, "fg", cell_seed(cell))
		UlticaTiles.draw_sprite(self, sprite_name, local)
		if sprite_name == "" or UlticaTiles.get_texture(sprite_name) == null:  # repli : carré coloré du terrain
			draw_rect(Rect2(local, Vector2(World.TILE_SIZE, World.TILE_SIZE)), TerrainDB.color_of(t))
		if furniture.size() == CELLS and furniture[i] != 0:
			var furniture_tile: String = FurnitureDB.tile_of(furniture[i])
			UlticaTiles.draw_sprite(self, UlticaTiles.pick_sprite(furniture_tile, "bg", 0), local)
			var furniture_sprite: String = UlticaTiles.pick_sprite(furniture_tile, "fg", cell_seed(cell))
			UlticaTiles.draw_sprite(self, furniture_sprite, local)
			if furniture_sprite == "" or UlticaTiles.get_texture(furniture_sprite) == null:  # repli : petit carré coloré
				draw_rect(Rect2(local + Vector2(24, 24), Vector2(80, 80)), FurnitureDB.color_of(furniture[i]))
	if Fx.SHADOWS:  # ombres des arbres : seconde passe, pour qu'une case voisine ne les recouvre pas
		for i: int in _tree_sprites:
			var origin := Vector2(i % SIZE, floori(float(i) / SIZE)) * World.TILE_SIZE
			draw_colored_polygon(Fx.ellipse_points(origin + TREE_SHADOW_CENTER, TREE_SHADOW_RADII), Fx.SHADOW_COLOR)
