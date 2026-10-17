class_name PostureUI
extends CanvasLayer
## Petit menu de posture (touche |) : Marche / Sprint / Accroupi. À l'ouverture, la posture SUIVANTE est présélectionnée :
## « | » puis Entrée fait donc passer marche -> sprint -> accroupi -> marche. | de nouveau, ou 8 / 2 (flèches), change la sélection ;
## Entrée valide, Échap ferme sans rien changer. Le jeu est en pause tant que le menu est ouvert ; changer de posture est gratuit.

# --- Réglages ---
const FONT_SIZE: int = 16
const ROW_HEIGHT: float = 44.0
const BOX_WIDTH: float = 520.0

const COLOR_DIM: Color = Color(0, 0, 0, 0.45)
const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.97)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_SELECTED: Color = Color(0.25, 0.35, 0.55, 0.9)

var player: Player

var _view: Control
var _is_open: bool = false
var _selected: int = 0


func _ready() -> void:
	layer = 21
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.visible = false
	_view.draw.connect(_draw_view)
	add_child(_view)
	EventBus.posture_requested.connect(_on_requested)


func _on_requested() -> void:
	if player == null or player.dead or _is_open or player.input_blocked:
		return
	_is_open = true
	_selected = (player.posture + 1) % Player.POSTURE_NAMES.size()
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
	get_viewport().set_input_as_handled()
	if not key_event.pressed or key_event.echo:
		return
	var key: Key = key_event.physical_keycode
	var count: int = Player.POSTURE_NAMES.size()
	if key_event.unicode == 124:  # « | »
		_selected = (_selected + 1) % count
	elif key == KEY_KP_8 or key == KEY_UP:
		_selected = posmod(_selected - 1, count)
	elif key == KEY_KP_2 or key == KEY_DOWN:
		_selected = (_selected + 1) % count
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		var chosen: int = _selected
		_close()
		player.set_posture(chosen)
		return
	elif key == KEY_ESCAPE:
		_close()
		return
	_view.queue_redraw()


func _effect_text(index: int) -> String:
	return "durée × %s   détection × %s   stamina %+.1f / pas" % [String.num(Player.POSTURE_TIME_FACTOR[index]),
		String.num(Player.POSTURE_DETECT_FACTOR[index]), Player.POSTURE_MOVE_STAMINA[index]]


func _draw_view() -> void:
	var font: Font = _view.get_theme_default_font()
	var view_size: Vector2 = _view.size
	var count: int = Player.POSTURE_NAMES.size()
	_view.draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_DIM)
	var box := Rect2(Vector2.ZERO, Vector2(BOX_WIDTH, 80.0 + ROW_HEIGHT * count + 40.0))
	box.position = (view_size - box.size) / 2.0
	_view.draw_rect(box, COLOR_PANEL)
	_view.draw_rect(box, COLOR_BORDER, false, 2.0)
	_view.draw_string(font, box.position + Vector2(16, 30), "POSTURE", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	for i in count:
		var row := Rect2(box.position + Vector2(12, 48.0 + i * ROW_HEIGHT), Vector2(BOX_WIDTH - 24.0, ROW_HEIGHT - 4.0))
		if i == _selected:
			_view.draw_rect(row, COLOR_SELECTED)
		var label: String = Player.POSTURE_NAMES[i] + ("  (actuelle)" if i == player.posture else "")
		_view.draw_string(font, row.position + Vector2(10, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_TEXT)
		_view.draw_string(font, row.position + Vector2(10, 35), _effect_text(i), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 20.0, FONT_SIZE - 3, COLOR_MUTED)
	_view.draw_string(font, box.position + Vector2(16, box.size.y - 12.0), "| ou 8 / 2 : choisir   Entrée : valider   Échap : fermer",
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 32.0, 14, COLOR_MUTED)
