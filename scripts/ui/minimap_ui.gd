class_name MiniMapUI
extends CanvasLayer
## Mini-carte de DEBUG (touche m) : les biomes du monde autour du joueur, avec la seed, les coordonnées et le biome
## sous le curseur. Elle montre aussi ce qui n'est pas exploré : c'est un outil pour régler la génération
## (data/worldgen/biomes.json), pas la carte du joueur. Écran modal : le jeu est en pause tant qu'elle est ouverte.
## La souris sert uniquement à lire (biome sous le curseur).
##
## Zoom : chaque palier = nombre de cases du monde par échantillon (pixel de l'image). Sous 1, une case occupe plusieurs
## échantillons (jusqu'à 16 x 16 : on ne voit plus que 10 x 10 cases). À 1 case par échantillon ou moins, on dessine le TERRAIN réel
## (murs, routes, mobilier...) généré par ChunkGenerator, et non plus seulement la nature du biome.
##
## Performance :
##  - Grille ALIGNÉE sur le zoom : l'échantillon n représente la case floor(n x zoom), quel que soit le centre de la vue. La carte est
##    découpée en tuiles de TILE x TILE échantillons, mises en cache par (palier de zoom, x, y) dans des variables STATIQUES : se déplacer
##    ne calcule que les tuiles nouvelles, dézoomer puis rezoomer est instantané, et le cache survit à la fermeture de la carte
##    (vidé si la seed change).
##  - Rendu PROGRESSIF : les tuiles manquantes sont calculées par ordre de distance au centre, avec un budget de temps par frame
##    (BUDGET_US). En attendant, on affiche la tuile d'un zoom plus large étirée (aperçu), sinon un fond sombre.
##  - Un seul recalcul de la liste de tuiles par frame (drapeau _dirty), même si plusieurs touches arrivent ensemble.
##  - Tuiles remplies dans un PackedByteArray (Image.create_from_data) au lieu de set_pixel.
##  - Terrain réel : les chunks déjà chargés par le ChunkManager sont lus tels quels ; les autres sont générés une fois et gardés
##    (cache statique borné).
##  - Types de cellule (rue, parcelle...) mis en cache. Routes et lieux spéciaux (calcul très coûteux) seulement jusqu'à
##    ROUTES_MAX_ZOOM, villes jusqu'à SETTLEMENTS_MAX_ZOOM, biomes seuls au-delà.

# --- Réglages ---
const SAMPLES: int = 160                       # échantillons par côté de la zone affichée
const TILE: int = 16                           # échantillons par côté d'une tuile
const ZOOMS: Array[float] = [0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0, 256.0, 512.0, 1024.0, 2048.0, 4096.0]   # cases du monde par échantillon (chaque palier = x2 : l'aperçu en dépend)
const START_ZOOM_INDEX: int = 10               # 64 cases par échantillon (comme avant)
const TERRAIN_MAX_ZOOM: float = 1.0            # à ce zoom ou moins : terrain réel case par case
const ROUTES_MAX_ZOOM: float = 16.0            # routes entre villes et lieux spéciaux affichés jusqu'à ce zoom (au-delà : trop de régions à calculer)
const SETTLEMENTS_MAX_ZOOM: float = 256.0      # villes affichées jusqu'à ce zoom ; au-delà : biomes seuls
const BUDGET_US: int = 8000                    # temps de calcul de tuiles par frame (microsecondes)
const MAX_TILES: int = 4000                    # au-delà, le cache de tuiles est vidé
const MAX_TYPE_CACHE: int = 300000             # idem pour le cache des types de cellule
const MAX_CHUNK_CACHE: int = 300               # idem pour les chunks générés (terrain réel)
const PAN_SAMPLES: int = 20                    # déplacement de la vue, en échantillons
const FONT_SIZE: int = 16

const COLOR_DIM: Color = Color(0, 0, 0, 0.6)
const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.97)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_MARKER: Color = Color(1.0, 0.25, 0.2)
const COLOR_PENDING: Color = Color(0.14, 0.14, 0.17)

# Couleurs de repli du terrain réel pour les terrains SANS champ "color" dans terrain.json (les autres : la couleur de nature du biome).
const TERRAIN_COLORS: Dictionary = {
	"t_tree": Color("#1f4f1f"),
	"t_pavement": Color("#5b5f66"),
	"t_pavement_y": Color("#c8b84a"),
	"t_sidewalk": Color("#a8a8a8"),
	"t_bridge": Color("#8a6a45"),
	"t_wall_house": Color("#3a3a3a"),
	"t_wall_arena": Color("#3a3a3a"),
}

# Caches STATIQUES : ils survivent à la fermeture de la carte (la seed ne change pas pendant la partie).
static var _tiles: Dictionary = {}           # Vector3i (indice de zoom, tx, ty) -> ImageTexture
static var _type_towns: Dictionary = {}      # Vector2i (cellule macro) -> type, sans routes ni lieux
static var _type_full: Dictionary = {}       # idem avec routes et lieux spéciaux
static var _chunk_data: Dictionary = {}      # Vector3i (chunk) -> {terrain, furniture} (chunks générés pour le terrain réel)
static var _fixed_colors: Dictionary = {}    # index de terrain -> Color fixe, ou null s'il faut la couleur du biome
static var _cache_seed: int = 0
static var _cache_ready: bool = false
static var _kind_colors: Array[Color] = []
static var _kind_rgb: PackedByteArray = PackedByteArray()      # 3 octets par nature de case
static var _overlay_rgb: PackedByteArray = PackedByteArray()   # 3 octets par SettlementMap.CellType

var player: Player
var seed_text: String = ""

var _view: Control
var _is_open: bool = false
var _zoom_index: int = START_ZOOM_INDEX
var _center: Vector2i = Vector2i.ZERO
var _map_rect: Rect2 = Rect2()
var _hover_cell: Vector2i = Vector2i.ZERO
var _hovering: bool = false
var _dirty: bool = false                     # la liste des tuiles à calculer doit être refaite (un seul passage par frame)
var _pending: Array[Vector3i] = []           # tuiles à calculer, les plus proches du centre d'abord


func _ready() -> void:
	layer = 18
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.visible = false
	_view.draw.connect(_draw_view)
	add_child(_view)
	EventBus.minimap_requested.connect(_on_requested)


func _on_requested() -> void:
	if player == null or player.dead or _is_open or player.input_blocked:
		return
	if player.world.use_arena:
		EventBus.message_logged.emit("Pas de carte du monde dans l'arène de test.")
		return
	_prepare_caches(player.world.world_seed)
	_is_open = true
	_zoom_index = START_ZOOM_INDEX
	_center = player.grid_pos
	player.input_blocked = true
	_view.visible = true
	_dirty = true
	_view.queue_redraw()


func _close() -> void:
	_is_open = false
	_pending.clear()
	player.input_blocked = false
	_view.visible = false


## Vide les caches si la seed a changé ; prépare les palettes une seule fois.
static func _prepare_caches(world_seed: int) -> void:
	if not _cache_ready or _cache_seed != world_seed:
		_tiles.clear()
		_type_towns.clear()
		_type_full.clear()
		_chunk_data.clear()
		_cache_seed = world_seed
		_cache_ready = true
	if _kind_colors.is_empty():
		for kind in WorldMap.kind_count():
			var c: Color = WorldMap.kind_color(kind)
			_kind_colors.append(c)
			_kind_rgb.append(c.r8)
			_kind_rgb.append(c.g8)
			_kind_rgb.append(c.b8)
		for cell_type in 5:  # NONE, ROAD, LOT, YARD, SPECIAL
			var o: Color = SettlementMap.overlay_color(cell_type)
			_overlay_rgb.append(o.r8)
			_overlay_rgb.append(o.g8)
			_overlay_rgb.append(o.b8)


# --- Grille alignée et tuiles ---

## Case du monde représentée par l'échantillon n (sur un axe) : floor(n x zoom). Exact : les zooms sont des puissances de 2.
static func _cell_of_index(n: int, zoom: float) -> int:
	return floori(n * zoom)


## Indice d'échantillon (grille alignée) de l'angle haut-gauche de la zone affichée.
func _view_origin() -> Vector2i:
	var zoom: float = ZOOMS[_zoom_index]
	return Vector2i(floori(_center.x / zoom), floori(_center.y / zoom)) - Vector2i(SAMPLES / 2, SAMPLES / 2)


## 0 = biomes seuls, 1 = villes, 2 = villes + routes + lieux spéciaux.
static func _overlay_mode(zoom: float) -> int:
	if zoom <= ROUTES_MAX_ZOOM:
		return 2
	if zoom <= SETTLEMENTS_MAX_ZOOM:
		return 1
	return 0


## Refait la liste des tuiles visibles qui ne sont pas encore en cache, les plus proches du centre d'abord.
func _plan() -> void:
	if _tiles.size() > MAX_TILES:
		_tiles.clear()
	if _type_towns.size() > MAX_TYPE_CACHE:
		_type_towns.clear()
	if _type_full.size() > MAX_TYPE_CACHE:
		_type_full.clear()
	if _chunk_data.size() > MAX_CHUNK_CACHE:
		_chunk_data.clear()
	var s0: Vector2i = _view_origin()
	var middle := Vector2(s0) + Vector2(SAMPLES, SAMPLES) / 2.0
	var wanted: Array[Vector3i] = []
	for ty in range(floori(float(s0.y) / TILE), floori(float(s0.y + SAMPLES - 1) / TILE) + 1):
		for tx in range(floori(float(s0.x) / TILE), floori(float(s0.x + SAMPLES - 1) / TILE) + 1):
			var key := Vector3i(_zoom_index, tx, ty)
			if not _tiles.has(key):
				wanted.append(key)
	wanted.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var da: Vector2 = Vector2(a.y + 0.5, a.z + 0.5) * TILE - middle
		var db: Vector2 = Vector2(b.y + 0.5, b.z + 0.5) * TILE - middle
		return da.length_squared() < db.length_squared())
	_pending = wanted


## Calcule des tuiles pendant BUDGET_US au plus (au moins une par frame).
func _work() -> void:
	var started: int = Time.get_ticks_usec()
	while not _pending.is_empty():
		var key: Vector3i = _pending.pop_front()
		if not _tiles.has(key):
			_tiles[key] = _compute_tile(key)
		if Time.get_ticks_usec() - started >= BUDGET_US:
			break
	_view.queue_redraw()


static func _cell_type(settlement: SettlementMap, coord: Vector2i, full: bool) -> int:
	var cache: Dictionary = _type_full if full else _type_towns
	if cache.has(coord):
		return cache[coord]
	var type: int = settlement.cell_type(coord, full)
	cache[coord] = type
	return type


## Terrain et mobilier d'un chunk : chunk déjà chargé par le jeu, sinon généré une fois et gardé.
func _chunk_arrays(key: Vector3i) -> Dictionary:
	var loaded := player.world.chunks.chunks.get(key) as Chunk
	if loaded != null:
		return {"terrain": loaded.terrain, "furniture": loaded.furniture}
	if not _chunk_data.has(key):
		_chunk_data[key] = {
			"terrain": ChunkGenerator.generate(_cache_seed, key),
			"furniture": ChunkGenerator.generate_furniture(_cache_seed, key),
		}
	return _chunk_data[key]


## Couleur fixe d'un terrain (champ "color" de terrain.json ou repli TERRAIN_COLORS), null s'il faut prendre la couleur du biome.
static func _fixed_color(terrain: int) -> Variant:
	if _fixed_colors.has(terrain):
		return _fixed_colors[terrain]
	var result: Variant = null
	if TerrainDB.has_color(terrain):
		result = TerrainDB.color_of(terrain)
	else:
		var terrain_id: String = TerrainDB.id_of(terrain)
		if TERRAIN_COLORS.has(terrain_id):
			result = TERRAIN_COLORS[terrain_id]
	_fixed_colors[terrain] = result
	return result


## Image d'une tuile : une couleur par échantillon, écrite dans un buffer d'octets.
func _compute_tile(key: Vector3i) -> ImageTexture:
	var zoom: float = ZOOMS[key.x]
	var world_seed: int = _cache_seed
	var world_map: WorldMap = WorldMap.for_seed(world_seed)
	var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
	var case_level: bool = zoom <= TERRAIN_MAX_ZOOM
	var mode: int = _overlay_mode(zoom)
	var data := PackedByteArray()
	data.resize(TILE * TILE * 3)
	var index: int = 0
	var last_chunk := Vector3i(1 << 30, 0, 0)
	var terrain := PackedByteArray()
	var furniture := PackedByteArray()
	for j in TILE:
		var wy: int = _cell_of_index(key.z * TILE + j, zoom)
		for i in TILE:
			var cell := Vector2i(_cell_of_index(key.y * TILE + i, zoom), wy)
			if case_level:  # terrain réel : mobilier, puis terrain, puis couleur du biome
				var chunk_key: Vector3i = ChunkManager.key_of(cell)
				if chunk_key != last_chunk:
					last_chunk = chunk_key
					var arrays: Dictionary = _chunk_arrays(chunk_key)
					terrain = arrays["terrain"]
					furniture = arrays["furniture"]
				var cell_index: int = ChunkManager.index_of(cell)
				var color: Color
				var furniture_index: int = furniture[cell_index] if furniture.size() == Chunk.CELLS else 0
				if furniture_index != 0:
					color = FurnitureDB.color_of(furniture_index)
				else:
					var fixed: Variant = _fixed_color(terrain[cell_index])
					color = fixed if fixed != null else _kind_colors[world_map.kind_at(cell)]
				data[index] = color.r8
				data[index + 1] = color.g8
				data[index + 2] = color.b8
			else:
				var palette: PackedByteArray = _kind_rgb
				var offset: int = world_map.kind_at(cell) * 3
				if mode != 0:  # les villes se dessinent par-dessus les biomes
					var coord := Vector2i(floori(float(cell.x) / Chunk.SIZE), floori(float(cell.y) / Chunk.SIZE))
					var cell_type: int = _cell_type(settlement, coord, mode == 2)
					if cell_type != SettlementMap.CellType.NONE:
						palette = _overlay_rgb
						offset = cell_type * 3
				data[index] = palette[offset]
				data[index + 1] = palette[offset + 1]
				data[index + 2] = palette[offset + 2]
			index += 3
	return ImageTexture.create_from_image(Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data))


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	get_viewport().set_input_as_handled()
	if not key_event.pressed or key_event.echo:
		return
	var key: Key = key_event.physical_keycode
	if key == KEY_ESCAPE or KeyUtil.is_letter(key_event, "m"):
		_close()
		return
	var step: int = maxi(roundi(PAN_SAMPLES * ZOOMS[_zoom_index]), 1)
	if key == KEY_KP_ADD or key == KEY_EQUAL:
		_zoom_index = maxi(_zoom_index - 1, 0)
	elif key == KEY_KP_SUBTRACT or key == KEY_MINUS:
		_zoom_index = mini(_zoom_index + 1, ZOOMS.size() - 1)
	elif key == KEY_KP_8 or key == KEY_UP:
		_center.y -= step
	elif key == KEY_KP_2 or key == KEY_DOWN:
		_center.y += step
	elif key == KEY_KP_4 or key == KEY_LEFT:
		_center.x -= step
	elif key == KEY_KP_6 or key == KEY_RIGHT:
		_center.x += step
	elif key == KEY_KP_7:
		_center += Vector2i(-step, -step)
	elif key == KEY_KP_9:
		_center += Vector2i(step, -step)
	elif key == KEY_KP_1:
		_center += Vector2i(-step, step)
	elif key == KEY_KP_3:
		_center += Vector2i(step, step)
	elif key == KEY_KP_5:
		_center = player.grid_pos
	else:
		return
	_dirty = true  # la liste de tuiles est refaite une seule fois, dans _process
	_view.queue_redraw()


func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _dirty:
		_dirty = false
		_plan()
	if not _pending.is_empty():
		_work()
	var mouse: Vector2 = _view.get_local_mouse_position()
	var inside: bool = _map_rect.has_point(mouse)
	var cell: Vector2i = _hover_cell
	if inside:
		var sample: Vector2 = (mouse - _map_rect.position) / _map_rect.size * SAMPLES
		var n: Vector2i = Vector2i(clampi(floori(sample.x), 0, SAMPLES - 1), clampi(floori(sample.y), 0, SAMPLES - 1)) + _view_origin()
		var zoom: float = ZOOMS[_zoom_index]
		cell = Vector2i(_cell_of_index(n.x, zoom), _cell_of_index(n.y, zoom))
	if inside != _hovering or (inside and cell != _hover_cell):
		_hovering = inside
		_hover_cell = cell
		_view.queue_redraw()


## Dessine les tuiles visibles (rognées à la zone affichée). Tuile absente : aperçu d'une tuile d'un zoom plus large, sinon fond sombre.
func _draw_tiles(pixel_scale: int, s0: Vector2i) -> void:
	var view_rect := Rect2(Vector2(s0), Vector2(SAMPLES, SAMPLES))
	for ty in range(floori(float(s0.y) / TILE), floori(float(s0.y + SAMPLES - 1) / TILE) + 1):
		for tx in range(floori(float(s0.x) / TILE), floori(float(s0.x + SAMPLES - 1) / TILE) + 1):
			var tile_rect := Rect2(Vector2(tx, ty) * TILE, Vector2(TILE, TILE))
			var part: Rect2 = tile_rect.intersection(view_rect)
			if part.size.x <= 0.0 or part.size.y <= 0.0:
				continue
			var tex := _tiles.get(Vector3i(_zoom_index, tx, ty)) as ImageTexture
			var origin: Vector2 = tile_rect.position   # angle de la texture, en échantillons de ce zoom
			var extent: float = float(TILE)            # largeur de la texture, en échantillons de ce zoom
			if tex == null:
				for k in range(1, 4):
					if _zoom_index + k >= ZOOMS.size():
						break
					var factor: int = 1 << k
					var coarse_x: int = floori(float(tx) / factor)
					var coarse_y: int = floori(float(ty) / factor)
					tex = _tiles.get(Vector3i(_zoom_index + k, coarse_x, coarse_y)) as ImageTexture
					if tex != null:
						origin = Vector2(coarse_x, coarse_y) * float(TILE * factor)
						extent = float(TILE * factor)
						break
			var dst := Rect2(_map_rect.position + (part.position - Vector2(s0)) * pixel_scale, part.size * pixel_scale)
			if tex == null:
				_view.draw_rect(dst, COLOR_PENDING)
			else:
				var src := Rect2((part.position - origin) / extent * TILE, part.size / extent * TILE)
				_view.draw_texture_rect_region(tex, dst, src)


func _draw_view() -> void:
	var font: Font = _view.get_theme_default_font()
	var view_size: Vector2 = _view.size
	var world_map: WorldMap = WorldMap.for_seed(player.world.world_seed)
	var pixel_scale: int = maxi(floori((view_size.y - 170.0) / SAMPLES), 2)
	var map_size := Vector2(SAMPLES * pixel_scale, SAMPLES * pixel_scale)
	var legend_width: float = 300.0
	var panel_size := Vector2(map_size.x + legend_width + 48.0, map_size.y + 150.0)
	var panel := Rect2((view_size - panel_size) / 2.0, panel_size)
	_view.draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_DIM)
	_view.draw_rect(panel, COLOR_PANEL)
	_view.draw_rect(panel, COLOR_BORDER, false, 2.0)

	# En-tête : seed, échelle, joueur
	var zoom: float = ZOOMS[_zoom_index]
	var span: int = maxi(roundi(SAMPLES * zoom), 1)
	var scale_text: String = "1 pixel = %d cases" % roundi(zoom) if zoom >= 1.0 else "1 case = %d x %d pixels" % [roundi(1.0 / zoom), roundi(1.0 / zoom)]
	_view.draw_string(font, panel.position + Vector2(16, 28), "CARTE DU MONDE (debug)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	if not _pending.is_empty() or _dirty:
		_view.draw_string(font, Vector2(panel.position.x, panel.position.y + 28), "Calcul : %d tuile(s) restante(s)…" % _pending.size(),
			HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 16.0, FONT_SIZE - 2, COLOR_MUTED)
	_view.draw_string(font, panel.position + Vector2(16, 52), "Seed : « %s » (%d)   —   %s, la carte couvre %d × %d cases (%.1f chunks de côté)%s" % \
		[seed_text, player.world.world_seed, scale_text, span, span, float(span) / Chunk.SIZE,
		"   —   terrain réel" if zoom <= TERRAIN_MAX_ZOOM else ""],
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, FONT_SIZE - 2, COLOR_TEXT)
	var here: Vector2i = player.grid_pos
	var here_chunk: Vector3i = ChunkManager.key_of(here)
	var settlement: SettlementMap = SettlementMap.for_seed(player.world.world_seed)
	var here_town: Dictionary = settlement.town_at(Vector2i(here_chunk.x, here_chunk.y))
	_view.draw_string(font, panel.position + Vector2(16, 74), "Joueur : (%d, %d)   chunk (%d, %d)   %s%s" % \
		[here.x, here.y, here_chunk.x, here_chunk.y, WorldMap.kind_name(world_map.kind_at(here)),
		("   —   " + String(here_town["name"])) if not here_town.is_empty() else ""],
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, FONT_SIZE - 2, COLOR_TEXT)

	# Carte (tuiles en cache, grille alignée sur le zoom)
	_map_rect = Rect2(panel.position + Vector2(16, 90), map_size)
	var s0: Vector2i = _view_origin()
	_draw_tiles(pixel_scale, s0)
	_view.draw_rect(_map_rect, COLOR_BORDER, false, 1.0)
	# Position du joueur : centre de sa case (une case = 1 / zoom échantillons de large).
	var marker_sample: Vector2 = (Vector2(here) + Vector2(0.5, 0.5)) / zoom - Vector2(s0)
	var marker: Vector2 = _map_rect.position + marker_sample * pixel_scale
	if _map_rect.grow(2).has_point(marker):
		if zoom < 1.0:  # case agrandie : on l'entoure au lieu de la couvrir
			var case_px: float = pixel_scale / zoom
			_view.draw_rect(Rect2(marker - Vector2(case_px, case_px) / 2.0, Vector2(case_px, case_px)), COLOR_MARKER, false, 3.0)
		else:
			_view.draw_circle(marker, 5.0, COLOR_MARKER)
			_view.draw_circle(marker, 5.0, Color.WHITE, false, 1.5)
	# Case sous le curseur (zoom fort) : contour blanc.
	if _hovering and zoom < 1.0:
		var hover_sample: Vector2 = Vector2(_hover_cell) / zoom - Vector2(s0)
		var hover_pos: Vector2 = _map_rect.position + hover_sample * pixel_scale
		var hover_px: float = pixel_scale / zoom
		if _map_rect.encloses(Rect2(hover_pos, Vector2(hover_px, hover_px))):
			_view.draw_rect(Rect2(hover_pos, Vector2(hover_px, hover_px)), Color.WHITE, false, 2.0)

	# Légende
	var legend_x: float = _map_rect.end.x + 24.0
	var y: float = _map_rect.position.y + 4.0
	_view.draw_string(font, Vector2(legend_x, y + 14), "LÉGENDE", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, COLOR_HEADER)
	y += 30.0
	for kind in WorldMap.kind_count():
		_view.draw_rect(Rect2(legend_x, y, 16, 16), WorldMap.kind_color(kind))
		_view.draw_string(font, Vector2(legend_x + 26, y + 14), WorldMap.kind_name(kind), HORIZONTAL_ALIGNMENT_LEFT, legend_width - 30.0, FONT_SIZE - 2, COLOR_TEXT)
		y += 24.0
	for entry in [[SettlementMap.CellType.ROAD, "Rue / route"], [SettlementMap.CellType.LOT, "Parcelle (maison)"], [SettlementMap.CellType.YARD, "Jardin"], [SettlementMap.CellType.SPECIAL, "Lieu spécial"]]:
		_view.draw_rect(Rect2(legend_x, y, 16, 16), SettlementMap.overlay_color(entry[0]))
		_view.draw_string(font, Vector2(legend_x + 26, y + 14), String(entry[1]), HORIZONTAL_ALIGNMENT_LEFT, legend_width - 30.0, FONT_SIZE - 2, COLOR_TEXT)
		y += 24.0
	y += 14.0
	if _hovering:
		_view.draw_string(font, Vector2(legend_x, y + 14), "Curseur : (%d, %d)" % [_hover_cell.x, _hover_cell.y], HORIZONTAL_ALIGNMENT_LEFT, legend_width, FONT_SIZE - 2, COLOR_TEXT)
		_view.draw_string(font, Vector2(legend_x, y + 36), WorldMap.kind_name(world_map.kind_at(_hover_cell)), HORIZONTAL_ALIGNMENT_LEFT, legend_width, FONT_SIZE - 2, COLOR_HEADER)
		var hover_coord := Vector2i(floori(float(_hover_cell.x) / Chunk.SIZE), floori(float(_hover_cell.y) / Chunk.SIZE))
		var hover_town: Dictionary = settlement.town_at(hover_coord)
		if not hover_town.is_empty():
			_view.draw_string(font, Vector2(legend_x, y + 58), "%s (rayon %d cellules)" % [hover_town["name"], hover_town["radius"]], HORIZONTAL_ALIGNMENT_LEFT, legend_width, FONT_SIZE - 2, COLOR_HEADER)
		var hover_special: Dictionary = settlement.specials().special_cell(hover_coord)
		if not hover_special.is_empty():
			_view.draw_string(font, Vector2(legend_x, y + 80), settlement.specials().place_name(String(hover_special["place"])), HORIZONTAL_ALIGNMENT_LEFT, legend_width, FONT_SIZE - 2, COLOR_HEADER)
	_view.draw_string(font, Vector2(panel.position.x + 16, panel.end.y - 14),
		"+/− : zoom (jusqu'à ~10 cases)   8/2/4/6 (ou flèches), 7/9/1/3 : déplacer la vue   5 : recentrer   m / Échap : fermer",
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, 14, COLOR_MUTED)
