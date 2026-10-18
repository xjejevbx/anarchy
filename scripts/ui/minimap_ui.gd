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

# --- Réglages ---
const SAMPLES: int = 160                       # échantillons par côté (160 x 160 = 25 600 calculs par rafraîchissement)
const ZOOMS: Array[float] = [0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0, 256.0, 512.0, 1024.0, 2048.0, 4096.0]   # cases du monde par échantillon
const START_ZOOM_INDEX: int = 10               # 64 cases par échantillon (comme avant)
const TERRAIN_MAX_ZOOM: float = 1.0            # à ce zoom ou moins : terrain réel case par case
const ROUTES_MAX_ZOOM: float = 16.0            # routes entre villes affichées jusqu'à ce zoom (au-delà : trop de régions à calculer)
const SETTLEMENTS_MAX_ZOOM: float = 256.0
const PAN_SAMPLES: int = 20                    # déplacement de la vue, en échantillons
const FONT_SIZE: int = 16

const COLOR_DIM: Color = Color(0, 0, 0, 0.6)
const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.97)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_MARKER: Color = Color(1.0, 0.25, 0.2)

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

var player: Player
var seed_text: String = ""

var _view: Control
var _is_open: bool = false
var _zoom_index: int = START_ZOOM_INDEX
var _center: Vector2i = Vector2i.ZERO
var _texture: ImageTexture
var _map_rect: Rect2 = Rect2()
var _hover_cell: Vector2i = Vector2i.ZERO
var _hovering: bool = false


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
	_is_open = true
	_zoom_index = START_ZOOM_INDEX
	_center = player.grid_pos
	player.input_blocked = true
	_view.visible = true
	_rebuild()


func _close() -> void:
	_is_open = false
	player.input_blocked = false
	_view.visible = false


## Case du monde sous l'échantillon (i, j) (entiers, 0..SAMPLES-1). Sous 1 case par échantillon, plusieurs échantillons voisins
## tombent sur la même case (floori).
func _cell_of_sample(i: int, j: int) -> Vector2i:
	var zoom: float = ZOOMS[_zoom_index]
	var half: int = SAMPLES / 2
	return _center + Vector2i(floori((i - half) * zoom), floori((j - half) * zoom))


## Couleur du terrain réel d'une case (chunk généré et mis en cache pour la durée du rafraîchissement).
func _case_color(cell: Vector2i, world_seed: int, world_map: WorldMap, kind_colors: Array[Color], chunk_cache: Dictionary) -> Color:
	var key: Vector3i = ChunkManager.key_of(cell)
	if not chunk_cache.has(key):
		chunk_cache[key] = {
			"terrain": ChunkGenerator.generate(world_seed, key),
			"furniture": ChunkGenerator.generate_furniture(world_seed, key),
		}
	var data: Dictionary = chunk_cache[key]
	var index: int = ChunkManager.index_of(cell)
	var furniture: int = (data["furniture"] as PackedByteArray)[index]
	if furniture != 0:
		return FurnitureDB.color_of(furniture)
	var terrain: int = (data["terrain"] as PackedByteArray)[index]
	if TerrainDB.has_color(terrain):
		return TerrainDB.color_of(terrain)
	var terrain_id: String = TerrainDB.id_of(terrain)
	if TERRAIN_COLORS.has(terrain_id):
		return TERRAIN_COLORS[terrain_id]
	return kind_colors[world_map.kind_at(cell)]


## Recalcule l'image : une couleur par échantillon, selon la nature de la case au centre de l'échantillon.
func _rebuild() -> void:
	var world_seed: int = player.world.world_seed
	var world_map: WorldMap = WorldMap.for_seed(world_seed)
	var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
	var colors: Array[Color] = []
	for kind in WorldMap.kind_count():
		colors.append(WorldMap.kind_color(kind))
	var zoom: float = ZOOMS[_zoom_index]
	var case_level: bool = zoom <= TERRAIN_MAX_ZOOM
	var type_cache: Dictionary = {}  # cellule macro -> type (rue, parcelle, jardin)
	var chunk_cache: Dictionary = {} # clé de chunk -> {terrain, furniture} (zoom case par case)
	var image := Image.create(SAMPLES, SAMPLES, false, Image.FORMAT_RGB8)
	for j in SAMPLES:
		for i in SAMPLES:
			var cell: Vector2i = _cell_of_sample(i, j)
			var color: Color
			if case_level:
				color = _case_color(cell, world_seed, world_map, colors, chunk_cache)
			else:
				color = colors[world_map.kind_at(cell)]
				var coord := Vector2i(floori(float(cell.x) / Chunk.SIZE), floori(float(cell.y) / Chunk.SIZE))
				if not type_cache.has(coord):
					type_cache[coord] = settlement.cell_type(coord, zoom <= SETTLEMENTS_MAX_ZOOM)
				var cell_type: int = type_cache[coord]
				if cell_type != SettlementMap.CellType.NONE:
					color = SettlementMap.overlay_color(cell_type)  # les villes se dessinent par-dessus les biomes
			image.set_pixel(i, j, color)
	_texture = ImageTexture.create_from_image(image)
	_view.queue_redraw()


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
	elif key == KEY_KP_5:
		_center = player.grid_pos
	else:
		return
	_rebuild()


func _process(_delta: float) -> void:
	if not _is_open:
		return
	var mouse: Vector2 = _view.get_local_mouse_position()
	var inside: bool = _map_rect.has_point(mouse)
	var cell: Vector2i = _hover_cell
	if inside:
		var sample: Vector2 = (mouse - _map_rect.position) / _map_rect.size * SAMPLES
		cell = _cell_of_sample(clampi(floori(sample.x), 0, SAMPLES - 1), clampi(floori(sample.y), 0, SAMPLES - 1))
	if inside != _hovering or (inside and cell != _hover_cell):
		_hovering = inside
		_hover_cell = cell
		_view.queue_redraw()


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

	# Carte
	_map_rect = Rect2(panel.position + Vector2(16, 90), map_size)
	_view.draw_texture_rect(_texture, _map_rect, false)
	_view.draw_rect(_map_rect, COLOR_BORDER, false, 1.0)
	# Position du joueur : centre de sa case (une case = 1 / zoom échantillons de large).
	var marker_sample: Vector2 = Vector2(SAMPLES, SAMPLES) / 2.0 + (Vector2(here - _center) + Vector2(0.5, 0.5)) / zoom
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
		var hover_sample: Vector2 = Vector2(SAMPLES, SAMPLES) / 2.0 + Vector2(_hover_cell - _center) / zoom
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
		"+/− : zoom (jusqu'à ~10 cases)   8/2/4/6 (ou flèches) : déplacer la vue   5 : recentrer   m / Échap : fermer",
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, 14, COLOR_MUTED)
