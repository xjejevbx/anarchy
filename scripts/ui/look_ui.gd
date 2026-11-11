class_name LookUI
extends CanvasLayer
## Mode regard (touche x, ou Maj + pavé numérique / flèches depuis le monde) : la CAMÉRA se déplace, pas le joueur.
## Aucun temps ne passe (le jeu est en pause) et rien n'est révélé : le champ de vision et le brouillard restent ceux du joueur.
## Jalon 8 : le panneau lit l'ÉTAGE ACTIF (terrain, mobilier, objets, monstres) ; en sous-sol, les indications de biome et
## de lieu sont explicitement marquées « surface ».
## Un curseur (la case surlignée) désigne une case ; le panneau à droite donne ce qu'on sait d'elle :
##   - case VISIBLE : biome, lieu, terrain, mobilier, praticabilité, objets au sol, monstre (PV, coûts, probabilités de toucher
##     chaque partie du corps, comme l'infobulle de survol) ;
##   - case seulement VUE (mémoire) : terrain et mobilier (objets et monstres sont inconnus hors de vue) ;
##   - case JAMAIS VUE : rien (on n'apprend rien sur l'inconnu).
## Le trajet qu'emprunterait le déplacement automatique vers la case du curseur s'affiche (carré blanc + points, voir World.show_target).
## Pavé numérique / flèches (avec ou sans Maj) : déplacer le curseur ; 5 : recentrer sur le joueur ; * : quitter et aller à la case ciblée
## (déplacement automatique du double-clic : Player.travel_to) ; + / - : zoom ; x ou Échap : quitter
## (la caméra revient sur le joueur).

# --- Réglages ---
const MAX_RADIUS: int = 40         # distance maximale du curseur au joueur (cases)
const PANEL_WIDTH: float = 560.0
const PANEL_MARGIN: float = 16.0
const FONT_SIZE: int = 16
const LINE_HEIGHT: float = 22.0

const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.94)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_ACCENT: Color = Color(0.55, 0.8, 1.0)
const COLOR_WARN: Color = Color(1.0, 0.4, 0.35)

var player: Player

var _view: Control
var _is_open: bool = false
var _cursor: Vector2i = Vector2i.ZERO
var _lines: Array[Dictionary] = []   # {text, color}


func _ready() -> void:
	layer = 17
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.visible = false
	_view.draw.connect(_draw_view)
	add_child(_view)
	EventBus.look_requested.connect(_on_requested)


func _on_requested(direction: Vector2i) -> void:
	if player == null or player.dead or _is_open or player.input_blocked:
		return
	_is_open = true
	_cursor = player.grid_pos
	player.input_blocked = true
	_view.visible = true
	_move_cursor(direction)


func _close() -> void:
	_is_open = false
	player.camera.position = Vector2(World.TILE_SIZE, World.TILE_SIZE) / 2.0
	player.world.fog.look_offset = Vector2i.ZERO
	player.world.fog.queue_redraw()
	player.world.show_pick_overlay({})
	player.clear_target()   # l'aperçu du trajet disparaît (la touche * le réaffiche en lançant le déplacement)
	player.input_blocked = false
	_view.visible = false


func _move_cursor(direction: Vector2i) -> void:
	var target: Vector2i = _cursor + direction
	var offset: Vector2i = target - player.grid_pos
	if maxi(absi(offset.x), absi(offset.y)) <= MAX_RADIUS:
		_cursor = target
	_apply()


## Place la caméra sur le curseur (le brouillard s'étend d'autant) et reconstruit le panneau.
func _apply() -> void:
	var offset: Vector2i = _cursor - player.grid_pos
	player.camera.position = Vector2(World.TILE_SIZE, World.TILE_SIZE) / 2.0 + Vector2(offset * World.TILE_SIZE)
	player.world.fog.look_offset = offset
	player.world.fog.queue_redraw()
	player.world.show_pick_overlay({_cursor: ""})   # surligne la case (même calque que le choix de case du ramassage)
	player.set_target(_cursor)                      # carré + points du trajet qu'emprunterait « * » (rien si le curseur est sur le joueur)
	_build_lines()
	_view.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	get_viewport().set_input_as_handled()
	if not key_event.pressed:
		return
	var key: Key = key_event.physical_keycode
	if Player.MOVE_KEYS.has(key):   # la répétition de touche fait défiler le curseur
		_move_cursor(Player.MOVE_KEYS[key])
		return
	if key_event.echo:
		return
	if key == KEY_ESCAPE or KeyUtil.is_letter(key_event, "x"):
		_close()
	elif key == KEY_KP_5:
		_cursor = player.grid_pos
		_apply()
	elif key == KEY_KP_MULTIPLY or key_event.unicode == 42:  # « * » : aller à la case ciblée (comme un double-clic)
		var target: Vector2i = _cursor
		_close()
		player.travel_to(target)
	elif player.try_zoom(key_event):
		_view.queue_redraw()


# --- Contenu du panneau ---

func _add(text: String, color: Color = COLOR_TEXT) -> void:
	_lines.append({"text": text, "color": color})


func _build_lines() -> void:
	_lines.clear()
	var world: World = player.world
	var cell: Vector2i = _cursor
	var offset: Vector2i = cell - player.grid_pos
	var level: int = world.get_level()
	_add("REGARD   case (%d, %d)   —   %s" % [cell.x, cell.y, "surface" if level == 0 else "étage %d" % level], COLOR_HEADER)
	if offset == Vector2i.ZERO:
		_add("Vous êtes ici.", COLOR_ACCENT)
	else:
		_add("Distance : %d pas (%+d, %+d)" % [absi(offset.x) + absi(offset.y), offset.x, offset.y], COLOR_MUTED)
	var is_visible: bool = world.is_visible_cell(cell)
	if not is_visible and not world.is_seen(cell):
		_add("Case jamais vue : rien à signaler.", COLOR_MUTED)
		return
	_add("Visible" if is_visible else "Hors de vue (mémoire de la carte)", COLOR_ACCENT if is_visible else COLOR_MUTED)

	_add_place_lines(world, cell)
	var terrain: int = world.chunks.terrain_index(cell)
	if terrain < 0:
		_add("Terrain : zone non chargée.", COLOR_MUTED)
		return
	_add("Terrain : %s" % TerrainDB.name_of(terrain))
	var chunk: Chunk = world.chunks.chunk_at(cell)
	var furniture: int = 0
	if chunk != null and chunk.furniture.size() == Chunk.CELLS:
		furniture = chunk.furniture[ChunkManager.index_of(cell)]
	if furniture != 0:
		_add("Mobilier : %s" % FurnitureDB.name_of(furniture))
	var props: Array[String] = []
	props.append("praticable à pied" if world.is_walkable(cell) else "non praticable à pied")
	match TerrainDB.swim_depth(terrain):
		TerrainDB.SWIM_SHALLOW:
			props.append("à la nage (eau peu profonde)")
		TerrainDB.SWIM_DEEP:
			props.append("à la nage (eau profonde)")
	if TerrainDB.is_opaque(terrain) or FurnitureDB.is_opaque(furniture):
		props.append("bloque la vue")
	_add("   " + ", ".join(props), COLOR_MUTED)

	if not is_visible:
		_add("Objets et monstres : inconnus hors de vue.", COLOR_MUTED)
		return
	var items: Array = world.get_ground_items(cell)
	if not items.is_empty():
		_add("OBJETS AU SOL (%d)" % items.size(), COLOR_HEADER)
		for item: Item in items:
			var label: String = item.display_name() + (" ×%d" % item.count if item.count > 1 else "")
			_add("   • %s   %.2f kg" % [label, item.real_weight()])
	var monster: Monster = world.get_monster_at(cell)
	if monster != null and monster.visible:
		_add("MONSTRE", COLOR_HEADER)
		var info: Array[String] = monster.get_tooltip_lines()
		for i in info.size():
			_add(info[i], COLOR_WARN if i == 0 else COLOR_TEXT)
	elif items.is_empty() and offset != Vector2i.ZERO:
		_add("Rien de particulier ici.", COLOR_MUTED)


## Biome, ville et lieu spécial de la case (pas dans l'arène de test). Sous terre, ces informations décrivent la
## SURFACE au-dessus du joueur : on les préfixe pour ne pas les confondre avec le plan de l'étage.
func _add_place_lines(world: World, cell: Vector2i) -> void:
	if world.use_arena:
		return
	var under: bool = world.get_level() != 0
	var kind: int = WorldMap.for_seed(world.world_seed).kind_at(cell)
	_add(("Biome (surface) : %s" if under else "Biome : %s") % WorldMap.kind_name(kind))
	var key: Vector3i = ChunkManager.key_of(cell)
	var coord := Vector2i(key.x, key.y)
	var settlement: SettlementMap = SettlementMap.for_seed(world.world_seed)
	var town: Dictionary = settlement.town_at(coord)
	if not town.is_empty():
		_add(("Lieu (surface) : %s" if under else "Lieu : %s") % String(town["name"]))
	var special: Dictionary = settlement.specials().special_cell(coord)
	if not special.is_empty():
		_add(("Lieu (surface) : %s" if under else "Lieu : %s") % settlement.specials().place_name(String(special["place"])))


# --- Dessin ---

func _draw_view() -> void:
	var font: Font = _view.get_theme_default_font()
	var view_size: Vector2 = _view.size
	var height: float = 28.0 + _lines.size() * LINE_HEIGHT + 34.0
	var panel := Rect2(Vector2(view_size.x - PANEL_WIDTH - PANEL_MARGIN, PANEL_MARGIN), Vector2(PANEL_WIDTH, height))
	_view.draw_rect(panel, COLOR_PANEL)
	_view.draw_rect(panel, COLOR_BORDER, false, 2.0)
	var y: float = panel.position.y + 28.0
	for line: Dictionary in _lines:
		_view.draw_string(font, Vector2(panel.position.x + 16.0, y), String(line["text"]), HORIZONTAL_ALIGNMENT_LEFT,
			PANEL_WIDTH - 32.0, FONT_SIZE, line["color"])
		y += LINE_HEIGHT
	_view.draw_string(font, Vector2(panel.position.x + 16.0, panel.end.y - 12.0),
		"pavé / flèches : curseur   5 : recentrer   * : y aller   + / - : zoom   x / Échap : quitter",
		HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH - 32.0, 14, COLOR_MUTED)
