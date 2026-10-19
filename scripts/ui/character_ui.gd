class_name CharacterUI
extends CanvasLayer
## Écran du personnage (touche c) : une barre d'onglets, 4 / 6 (ou flèches gauche / droite) pour en changer, c ou Échap pour fermer.
## Onglets : « Stats » (caractéristiques de data/stats.json et état du joueur) et « Corps » (une barre de vie par partie du corps,
## data/body_parts.json). Le jeu est en pause tant que l'écran est ouvert. Pour ajouter un onglet : l'ajouter à TAB_NAMES et à _draw_tab().

# --- Réglages ---
const PANEL_MARGIN: float = 64.0
const FONT_SIZE: int = 16
const TAB_NAMES: Array[String] = ["Stats", "Corps"]
const BODY_ROW_HEIGHT: float = 58.0
const BODY_NAME_WIDTH: float = 220.0
const BODY_BAR_HEIGHT: float = 22.0

const COLOR_DIM: Color = Color(0, 0, 0, 0.6)
const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.97)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_ACCENT: Color = Color(0.55, 0.8, 1.0)
const COLOR_WARN: Color = Color(1.0, 0.4, 0.35)
const COLOR_TAB: Color = Color(0.25, 0.35, 0.55, 0.9)
const COLOR_BAR_BACK: Color = Color(0.18, 0.18, 0.2)
const COLOR_BAR_GOOD: Color = Color(0.3, 0.7, 0.4)
const COLOR_BAR_MID: Color = Color(0.95, 0.75, 0.3)

var player: Player

var _view: Control
var _is_open: bool = false
var _tab: int = 0


func _ready() -> void:
	layer = 19
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.visible = false
	_view.draw.connect(_draw_view)
	add_child(_view)
	EventBus.character_requested.connect(_on_requested)


func _on_requested() -> void:
	if player == null or player.dead or _is_open or player.input_blocked:
		return
	_is_open = true
	_tab = 0
	player.input_blocked = true
	_view.visible = true
	_view.queue_redraw()


func _close() -> void:
	_is_open = false
	player.input_blocked = false
	_view.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	get_viewport().set_input_as_handled()  # le jeu est en pause : le joueur ne reçoit rien
	if not key_event.pressed or key_event.echo:
		return
	var key: Key = key_event.physical_keycode
	if key == KEY_ESCAPE or KeyUtil.is_letter(key_event, "c"):
		_close()
	elif key == KEY_KP_4 or key == KEY_LEFT:
		_tab = posmod(_tab - 1, TAB_NAMES.size())
		_view.queue_redraw()
	elif key == KEY_KP_6 or key == KEY_RIGHT:
		_tab = posmod(_tab + 1, TAB_NAMES.size())
		_view.queue_redraw()


func _draw_view() -> void:
	var font: Font = _view.get_theme_default_font()
	var view_size: Vector2 = _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_DIM)
	var panel := Rect2(Vector2.ONE * PANEL_MARGIN, view_size - Vector2.ONE * PANEL_MARGIN * 2.0)
	_view.draw_rect(panel, COLOR_PANEL)
	_view.draw_rect(panel, COLOR_BORDER, false, 2.0)
	_view.draw_string(font, panel.position + Vector2(16, 28), "PERSONNAGE", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	# Onglets
	var x: float = panel.position.x + 16.0
	for i in TAB_NAMES.size():
		var width: float = font.get_string_size(TAB_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 28.0
		var tab := Rect2(Vector2(x, panel.position.y + 44.0), Vector2(width, 30.0))
		if i == _tab:
			_view.draw_rect(tab, COLOR_TAB)
		_view.draw_rect(tab, COLOR_BORDER if i != _tab else COLOR_ACCENT, false, 1.5)
		_view.draw_string(font, tab.position + Vector2(14, 21), TAB_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
			COLOR_TEXT if i == _tab else COLOR_MUTED)
		x += width + 8.0
	_view.draw_line(Vector2(panel.position.x + 8, panel.position.y + 78), Vector2(panel.end.x - 8, panel.position.y + 78), COLOR_BORDER, 1.0)
	_draw_tab(font, _tab, Rect2(panel.position + Vector2(16, 90), panel.size - Vector2(32, 150)))
	_view.draw_string(font, Vector2(panel.position.x + 16, panel.end.y - 14), "4 / 6 (ou flèches) : changer d'onglet   c / Échap : fermer",
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, 14, COLOR_MUTED)


func _draw_tab(font: Font, tab: int, area: Rect2) -> void:
	match TAB_NAMES[tab]:
		"Stats":
			_draw_stats(font, area)
		"Corps":
			_draw_body(font, area)


## Colonne de gauche : les caractéristiques ; colonne de droite : l'état du joueur.
func _draw_stats(font: Font, area: Rect2) -> void:
	var left_width: float = area.size.x * 0.55
	var y: float = area.position.y + 14.0
	_view.draw_string(font, Vector2(area.position.x, y), "CARACTÉRISTIQUES", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_HEADER)
	for id in StatDB.ids():
		y += 30.0
		_view.draw_string(font, Vector2(area.position.x + 8, y), StatDB.name_of(id), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_TEXT)
		_view.draw_string(font, Vector2(area.position.x, y), str(player.stats.get(id, 0)), HORIZONTAL_ALIGNMENT_RIGHT, 180.0, FONT_SIZE, COLOR_ACCENT)
		y += 20.0
		_view.draw_string(font, Vector2(area.position.x + 8, y), StatDB.description_of(id), HORIZONTAL_ALIGNMENT_LEFT, left_width - 16.0, FONT_SIZE - 3, COLOR_MUTED)
	var rx: float = area.position.x + left_width + 24.0
	_view.draw_line(Vector2(rx - 12, area.position.y), Vector2(rx - 12, area.end.y), COLOR_BORDER, 1.0)
	var ratio: float = player.get_load_ratio()
	var lines: Array[Array] = [
		["Heure", GameClock.get_time_string(), COLOR_TEXT],
		["PV (total, voir l'onglet Corps)", "%d / %d" % [ceili(player.total_hp()), int(BodyPartDB.total_max_hp())], COLOR_TEXT],
		["Stamina", "%d %%" % roundi(player.stamina / Player.STAMINA_MAX * 100.0), COLOR_TEXT],
		["Pénalité de temps", "+%d %%" % roundi(player.get_time_penalty() * 100.0), COLOR_TEXT],
		["Charge", "%.1f / %.1f kg (%d %%)" % [player.get_carry_weight(), player.get_carry_capacity(), roundi(ratio * 100.0)],
			COLOR_WARN if ratio > 1.0 else COLOR_TEXT],
		["Posture", player.posture_name(), COLOR_TEXT],
		["  durée d'un pas", "× %s" % String.num(Player.POSTURE_TIME_FACTOR[player.posture]), COLOR_MUTED],
		["  détection par les monstres", "× %s" % String.num(Player.POSTURE_DETECT_FACTOR[player.posture]), COLOR_MUTED],
	]
	y = area.position.y + 14.0
	_view.draw_string(font, Vector2(rx, y), "ÉTAT", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_HEADER)
	for line in lines:
		y += 28.0
		_view.draw_string(font, Vector2(rx, y), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_MUTED if String(line[0]).begins_with("  ") else COLOR_TEXT)
		_view.draw_string(font, Vector2(rx, y), String(line[1]), HORIZONTAL_ALIGNMENT_RIGHT, area.end.x - rx - 8.0, FONT_SIZE, line[2])


## Une barre de vie par partie du corps (comme CDDA). Tête et torse : la mort survient à 0 PV.
func _draw_body(font: Font, area: Rect2) -> void:
	var y: float = area.position.y + 14.0
	_view.draw_string(font, Vector2(area.position.x, y), "ÉTAT DU CORPS", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_HEADER)
	var bar_x: float = area.position.x + BODY_NAME_WIDTH
	var bar_width: float = minf(area.size.x - BODY_NAME_WIDTH - 140.0, 520.0)
	for id in BodyPartDB.ids():
		y += BODY_ROW_HEIGHT
		var hp: float = player.part_hp(id)
		var max_hp: float = BodyPartDB.max_hp_of(id)
		var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		var color: Color = COLOR_BAR_GOOD if ratio > 0.6 else (COLOR_BAR_MID if ratio > 0.3 else COLOR_WARN)
		_view.draw_string(font, Vector2(area.position.x + 8, y), BodyPartDB.name_of(id), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_TEXT)
		if BodyPartDB.is_vital(id):
			_view.draw_string(font, Vector2(area.position.x + 8, y + 18), "vital : mort à 0 PV", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 4, COLOR_MUTED)
		var bar := Rect2(Vector2(bar_x, y - BODY_BAR_HEIGHT + 4.0), Vector2(bar_width, BODY_BAR_HEIGHT))
		_view.draw_rect(bar, COLOR_BAR_BACK)
		_view.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), color)
		_view.draw_rect(bar, COLOR_BORDER, false, 1.5)
		var value_text: String = "%d / %d" % [ceili(hp), int(max_hp)]
		if hp <= 0.0:
			value_text += "  HORS D'USAGE" if not BodyPartDB.is_vital(id) else "  DÉTRUIT"
		_view.draw_string(font, Vector2(bar.end.x + 12.0, y), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_WARN if hp <= 0.0 else COLOR_TEXT)
	y += BODY_ROW_HEIGHT
	_view.draw_string(font, Vector2(area.position.x, y), "Les membres à 0 PV n'ont pas encore d'effet (à venir : bras = dégâts, jambes = vitesse).",
		HORIZONTAL_ALIGNMENT_LEFT, area.size.x, FONT_SIZE - 3, COLOR_MUTED)
	y += 22.0
	_view.draw_string(font, Vector2(area.position.x, y), "Les probabilités de toucher chaque partie s'affichent en observant un monstre (survol ou touche x).",
		HORIZONTAL_ALIGNMENT_LEFT, area.size.x, FONT_SIZE - 3, COLOR_MUTED)
