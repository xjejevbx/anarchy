class_name World
extends Node2D
## Le monde : chunks (via ChunkManager), objets au sol, monstres, file d'actions et champ de vision.
## La carte est INFINIE et générée par chunks de façon déterministe à partir de `world_seed`
## (voir docs/WORLD_GEN.md). Le terrain n'est jamais stocké ici : on interroge le ChunkManager.
##
## Rendu en couches (de bas en haut) :
##   1. `_terrain_layer` : les chunks (sol : herbe, murs)
##   2. `_items_layer`   : objets au sol
##   3. `entities`       : arbres, joueur, monstres, triés par Y (plus bas = plus devant)
##   3b. `fx`            : particules et ondes (poussière, éclaboussures), voir Fx
##   4. `fog`            : brouillard de guerre par-dessus
##   5. `_pick_overlay`  : touches de choix de la case où ramasser
##   6. `_target_overlay`: case ciblée par le déplacement automatique (carré + points du trajet)
## Les nœuds sont positionnés sur le coin haut-gauche de leur case ; UlticaTiles applique
## les décalages de chaque sprite (personnages 32x48, arbres 96x96...).

const TILE_SIZE: int = 128
const ALERT_REARM_POINTS: float = 5.0    # secondes hors de vue (dans le brouillard) avant qu'un monstre puisse être signalé à nouveau ; 0 = dès qu'il sort de vue
const VIEW_RADIUS: int = 20              # portée de vue en cases (plein jour pour l'instant)

# --- Case ciblée (déplacement automatique) ---
const TARGET_COLOR_IDLE: Color = Color(1, 1, 1, 0.95)          # case choisie, déplacement pas lancé
const TARGET_COLOR_TRAVEL: Color = Color(0.3, 1.0, 0.35, 0.95)  # déplacement automatique en cours
const TARGET_BORDER: float = 8.0
const TARGET_DOT_RADIUS: float = 12.0

var world_seed: int = 4444                  # à fixer AVANT add_child()
var use_arena: bool = false              # true : ancienne carte fermée 60x40 (debug), à fixer AVANT add_child()
var chunks: ChunkManager
var player: Player
var monsters: Array[Monster] = []
var entities: Node2D
var fx: Node2D                      # calque des effets visuels (particules), au-dessus des entités, sous le brouillard
var fog: FogLayer
var ground_items: Dictionary = {}   # Vector2i -> Array (d'Item posés au sol)
var pick_labels: Dictionary = {}    # Vector2i -> touche affichée (choix de la case où ramasser)
var visible_cells: Dictionary = {}  # cases actuellement visibles

var target_active: bool = false             # une case ciblée est affichée
var target_cell: Vector2i = Vector2i.ZERO
var target_path: Array[Vector2i] = []       # trajet complet (départ et arrivée inclus) ; vide = aucun chemin connu
var target_travelling: bool = false         # vrai : déplacement lancé (contour vert)

var _terrain_layer: Node2D
var _items_layer: Node2D
var _pick_overlay: Node2D
var _target_overlay: Node2D
var _hovered: Monster = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # sprites x4 réduits : lissage (NEAREST scintille)
	_terrain_layer = Node2D.new()
	add_child(_terrain_layer)
	_items_layer = Node2D.new()
	_items_layer.draw.connect(_draw_ground_items)
	add_child(_items_layer)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	fx = Node2D.new()
	fx.z_index = 5  # au-dessus des entités, sous le brouillard (z_index 10)
	add_child(fx)
	fog = FogLayer.new()
	fog.world = self
	fog.z_index = 10
	add_child(fog)
	_pick_overlay = Node2D.new()
	_pick_overlay.z_index = 11  # au-dessus du brouillard
	_pick_overlay.draw.connect(_draw_pick_overlay)
	add_child(_pick_overlay)
	_target_overlay = Node2D.new()
	_target_overlay.z_index = 11  # au-dessus du brouillard (ajouté après l'overlay de choix : dessiné par-dessus)
	_target_overlay.draw.connect(_draw_target_overlay)
	add_child(_target_overlay)
	chunks = ChunkManager.new()
	chunks.setup(world_seed, use_arena, _terrain_layer, entities)
	EventBus.time_advanced.connect(_on_time_advanced)


func add_entity(node: Node2D) -> void:
	entities.add_child(node)


## --- Objets au sol ---

## Affiche la touche (1-9) sur chaque case de `labels` (Vector2i -> String) ; {} pour effacer.
func show_pick_overlay(labels: Dictionary) -> void:
	pick_labels = labels
	_pick_overlay.queue_redraw()


func _draw_pick_overlay() -> void:
	var font: Font = ThemeDB.fallback_font
	for pos: Vector2i in pick_labels:
		var cell := Rect2(Vector2(pos * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))
		_pick_overlay.draw_rect(cell, Color(0.3, 0.6, 1.0, 0.35))
		_pick_overlay.draw_rect(cell, Color(0.55, 0.8, 1.0, 0.95), false, 8.0)
		_pick_overlay.draw_string(font, cell.position + Vector2(0, 92), String(pick_labels[pos]),
			HORIZONTAL_ALIGNMENT_CENTER, TILE_SIZE, 80, Color.WHITE)


# --- Case ciblée du déplacement automatique ---

## Affiche le carré autour de `cell` et les points du trajet `path` (départ et arrivée inclus, peut être vide).
## `travelling` : le déplacement est lancé (contour vert au lieu de blanc).
func show_target(cell: Vector2i, path: Array[Vector2i], travelling: bool) -> void:
	target_active = true
	target_cell = cell
	target_path = path
	target_travelling = travelling
	_target_overlay.queue_redraw()


func clear_target() -> void:
	if not target_active:
		return
	target_active = false
	target_path = []
	target_travelling = false
	_target_overlay.queue_redraw()


func _draw_target_overlay() -> void:
	if not target_active:
		return
	var color: Color = TARGET_COLOR_TRAVEL if target_travelling else TARGET_COLOR_IDLE
	var half := Vector2(TILE_SIZE, TILE_SIZE) / 2.0
	# Points sur les cases INTERMÉDIAIRES (ni le joueur ni la case ciblée).
	for i in range(1, target_path.size() - 1):
		_target_overlay.draw_circle(Vector2(target_path[i] * TILE_SIZE) + half, TARGET_DOT_RADIUS, color)
	var inset: float = TARGET_BORDER / 2.0 + 2.0
	var square := Rect2(Vector2(target_cell * TILE_SIZE) + Vector2(inset, inset), Vector2(TILE_SIZE, TILE_SIZE) - Vector2(inset, inset) * 2.0)
	_target_overlay.draw_rect(square, color, false, TARGET_BORDER)


func get_ground_items(pos: Vector2i) -> Array:
	return ground_items.get(pos, [])


func add_ground_item(pos: Vector2i, item: Item) -> void:
	var list: Array = ground_items.get(pos, [])
	var merged: bool = false
	for it: Item in list:
		if it.can_merge(item):
			it.count += item.count
			merged = true
			break
	if not merged:
		list.append(item)
	ground_items[pos] = list
	refresh_items()


func remove_ground_item(pos: Vector2i, item: Item) -> void:
	var list: Array = ground_items.get(pos, [])
	list.erase(item)
	if list.is_empty():
		ground_items.erase(pos)
	refresh_items()


## À appeler après toute modification d'un tas d'objets au sol.
func refresh_items() -> void:
	_items_layer.queue_redraw()


# --- Terrain (délégué aux chunks) ---

## Une case hors des chunks chargés est inconnue : ni praticable, opaque.
## « Praticable » = À PIED (monstres, marche automatique) : l'eau profonde ne l'est pas, le joueur y nage (can_player_enter).
func is_walkable(pos: Vector2i) -> bool:
	return chunks.is_walkable(pos)


## Profondeur de nage de la case (TerrainDB.SWIM_NONE / SWIM_SHALLOW / SWIM_DEEP) ; SWIM_NONE si le chunk n'est pas chargé.
func swim_depth(pos: Vector2i) -> int:
	var chunk: Chunk = chunks.chunk_at(pos)
	if chunk == null:
		return TerrainDB.SWIM_NONE
	return TerrainDB.swim_depth(chunk.terrain[ChunkManager.index_of(pos)])


func is_deep_water(pos: Vector2i) -> bool:
	return swim_depth(pos) == TerrainDB.SWIM_DEEP


## Case où le JOUEUR peut entrer : praticable à pied, ou eau profonde (il nage).
func can_player_enter(pos: Vector2i) -> bool:
	return is_walkable(pos) or is_deep_water(pos)


## Eau profonde visible ou déjà vue : la marche automatique ne s'y engage que si le joueur nage déjà.
func is_known_deep_water(pos: Vector2i) -> bool:
	return is_deep_water(pos) and (visible_cells.has(pos) or is_seen(pos))


## Murs et arbres bloquent la vue.
func is_opaque(pos: Vector2i) -> bool:
	return chunks.is_opaque(pos)


func has_terrain(pos: Vector2i) -> bool:
	return chunks.has_terrain(pos)


## Portée de mêlée : cases voisines en orthogonal uniquement (cohérent avec les déplacements).
static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func is_occupied(pos: Vector2i) -> bool:
	return (player != null and player.grid_pos == pos) or get_monster_at(pos) != null


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return PathFinder.find(self, from, to)


# --- Champ de vision ---

func is_visible_cell(pos: Vector2i) -> bool:
	return visible_cells.has(pos)


## Case praticable ET connue du joueur (visible ou déjà vue) : sert aux déplacements automatiques, qui ne « devinent » pas l'inconnu.
func is_known_walkable(pos: Vector2i) -> bool:
	return is_walkable(pos) and (visible_cells.has(pos) or is_seen(pos))


## Case déjà vue au moins une fois (mémoire de la carte).
func is_seen(pos: Vector2i) -> bool:
	return chunks.is_seen(pos)


## À appeler quand le joueur change de case (et au démarrage) : charge les chunks proches, puis calcule la vue.
func update_fov() -> void:
	if player == null:
		return
	chunks.update_around(player.grid_pos)
	visible_cells = FieldOfView.compute(self, player.grid_pos, VIEW_RADIUS)
	for cell: Vector2i in visible_cells:
		chunks.mark_seen(cell)
	fog.queue_redraw()
	_refresh_monster_visibility()


## Cache les monstres hors de vue ; signale ceux qui viennent d'apparaître.
func _refresh_monster_visibility() -> void:
	for m in monsters:
		var now_visible: bool = visible_cells.has(m.grid_pos)
		if now_visible and not m.visible:
			# Le message n'apparaît qu'une fois par monstre ; il revient seulement si le monstre est resté hors de vue
			# (dans le brouillard) au moins ALERT_REARM_POINTS : un monstre qui clignote en bord de vue ne spamme pas.
			if not m.spotted or GameClock.elapsed_points - m.hidden_since >= ALERT_REARM_POINTS:
				EventBus.message_logged.emit("Vous apercevez %s." % m.data.display_name)
				m.spotted = true
			EventBus.hostile_spotted.emit(m)  # arrête toujours la marche automatique
		elif not now_visible and m.visible:
			m.hidden_since = GameClock.elapsed_points
		m.visible = now_visible


# --- Monstres ---

func get_monster_at(pos: Vector2i) -> Monster:
	for m in monsters:
		if m.grid_pos == pos:
			return m
	return null


func find_free_cell_near(origin: Vector2i) -> Vector2i:
	for r in range(0, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var p: Vector2i = origin + Vector2i(dx, dy)
				if is_walkable(p) and not is_occupied(p):
					return p
	return origin


func spawn_monster(data: MonsterData, near: Vector2i) -> Monster:
	var m := Monster.new()
	m.data = data
	m.world = self
	m.hp = data.max_hp
	m.grid_pos = find_free_cell_near(near)
	m.next_action_time = GameClock.elapsed_points
	m.hidden_since = GameClock.elapsed_points
	m.visible = false  # update_fov() décidera
	entities.add_child(m)
	monsters.append(m)
	_refresh_monster_visibility()
	return m


func remove_monster(m: Monster) -> void:
	monsters.erase(m)
	if _hovered == m:
		_hovered = null
		EventBus.monster_hovered.emit(null)
	m.queue_free()


## Fait agir tous les monstres dont le moment d'action est arrivé, dans l'ordre chronologique.
func _on_time_advanced(_points: float) -> void:
	if player == null:
		return
	var guard: int = 0
	while guard < 500 and not player.dead:
		var next_monster: Monster = null
		for m in monsters:
			if m.next_action_time <= GameClock.elapsed_points:
				if next_monster == null or m.next_action_time < next_monster.next_action_time:
					next_monster = m
		if next_monster == null:
			break
		var cost: float = next_monster.take_turn()
		next_monster.next_action_time += maxf(cost, 0.1)
		guard += 1
	_refresh_monster_visibility()


func _process(_delta: float) -> void:
	chunks.process_queue()  # génération étalée des chunks lointains
	var cell := Vector2i((get_global_mouse_position() / TILE_SIZE).floor())
	var under_mouse: Monster = get_monster_at(cell)
	if under_mouse != null and not under_mouse.visible:
		under_mouse = null  # on n'infobulle pas ce qu'on ne voit pas
	if under_mouse != _hovered:
		_hovered = under_mouse
		EventBus.monster_hovered.emit(under_mouse)


# --- Rendu des objets au sol ---

## Objets au sol : sprite du dernier objet posé ; petit repère blanc s'il y en a plusieurs.
func _draw_ground_items() -> void:
	for pos: Vector2i in ground_items:
		var list: Array = ground_items[pos]
		if list.is_empty():
			continue
		var origin := Vector2(pos * TILE_SIZE)
		var top := list[list.size() - 1] as Item
		var sprite: String = UlticaTiles.pick_sprite(top.tile_id(), "fg", 0)
		var box := Rect2(origin, Vector2(TILE_SIZE, TILE_SIZE))
		if not UlticaTiles.draw_icon(_items_layer, sprite, box):
			_items_layer.draw_rect(Rect2(origin + Vector2(40, 40), Vector2(48, 48)), Color(0.85, 0.7, 0.3))  # repli
		if list.size() > 1:
			_items_layer.draw_rect(Rect2(origin + Vector2(TILE_SIZE - 28, TILE_SIZE - 28), Vector2(20, 20)), Color.WHITE)
