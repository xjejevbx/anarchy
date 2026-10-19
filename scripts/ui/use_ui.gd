class_name UseUI
extends CanvasLayer
## Menu « Utiliser un objet » (touche u) : liste les objets consommables de l'inventaire (champ "use" de items.json),
## sur soi, équipés ou rangés dans un conteneur. 8 / 2 (ou flèches) : choisir, Entrée : utiliser, Échap ou u : fermer.
## Le jeu est en pause tant que le menu est ouvert ; l'utilisation passe du temps (champ "time" du « use », avant pénalité de stamina)
## et consomme UNE unité, sauf si l'objet n'a eu aucun effet (ex. antibiotiques sans infection : rien n'est consommé ni compté).
## Actions connues (« use.action ») : "antibiotic" (Infection.take_antibiotics). Pour en ajouter : un cas dans _use().

const FONT_SIZE: int = 16
const ROW_HEIGHT: float = 48.0
const BOX_WIDTH: float = 620.0

const COLOR_DIM: Color = Color(0, 0, 0, 0.45)
const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.97)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_SELECTED: Color = Color(0.25, 0.35, 0.55, 0.9)
const COLOR_WARN: Color = Color(1.0, 0.4, 0.35)

var player: Player

var _view: Control
var _is_open: bool = false
var _selected: int = 0
var _rows: Array[Dictionary] = []   # {item, use}


func _ready() -> void:
	layer = 22
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.visible = false
	_view.draw.connect(_draw_view)
	add_child(_view)


func _open() -> void:
	_rows.clear()
	for it: Item in player.inventory.loose:
		_scan(it)
	for slot: String in player.inventory.equipment:
		_scan(player.inventory.equipment[slot] as Item)
	if _rows.is_empty():
		EventBus.message_logged.emit("Vous n'avez rien à utiliser.")
		return
	_is_open = true
	_selected = 0
	player.input_blocked = true
	_view.visible = true
	_view.queue_redraw()


func _scan(item: Item) -> void:
	var use: Dictionary = item.def().get("use", {})
	if not use.is_empty():
		_rows.append({"item": item, "use": use})
	for c: Item in item.contents:
		_scan(c)


func _close() -> void:
	_is_open = false
	player.input_blocked = false
	_view.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or player == null:
		return
	if not _is_open:
		if key_event.pressed and not key_event.echo and not player.dead and not player.input_blocked \
				and KeyUtil.is_letter(key_event, "u"):
			get_viewport().set_input_as_handled()
			_open()
		return
	get_viewport().set_input_as_handled()
	if not key_event.pressed or key_event.echo:
		return
	var key: Key = key_event.physical_keycode
	if key == KEY_KP_8 or key == KEY_UP:
		_selected = posmod(_selected - 1, _rows.size())
	elif key == KEY_KP_2 or key == KEY_DOWN:
		_selected = (_selected + 1) % _rows.size()
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		var entry: Dictionary = _rows[_selected]
		_close()
		_use(entry)
		return
	elif key == KEY_ESCAPE or KeyUtil.is_letter(key_event, "u"):
		_close()
		return
	_view.queue_redraw()


## Applique l'objet ; s'il a servi, consomme une unité et fait passer son temps (les monstres agissent après l'effet).
func _use(entry: Dictionary) -> void:
	var item := entry["item"] as Item
	var use: Dictionary = entry["use"]
	var result: Dictionary = {"used": false, "text": "Rien ne se passe."}
	match String(use.get("action", "")):
		"antibiotic":
			result = Infection.take_antibiotics(player)
	EventBus.message_logged.emit(String(result["text"]))
	if not bool(result["used"]):
		return
	player.inventory.detach(item, 1)   # une unité consommée (l'objet disparaît s'il était seul)
	player.refresh_inventory()
	player.spend_inventory_time(float(use.get("time", 2.0)))


func _row_label(entry: Dictionary) -> String:
	var item := entry["item"] as Item
	var use: Dictionary = entry["use"]
	var text: String = "%s %s" % [String(use.get("label", "Utiliser")), item.display_name()]
	if item.count > 1:
		text += " ×%d" % item.count
	var holder: Item = player.inventory.find_holder(item)
	if holder != null:
		text += "  (dans %s)" % holder.display_name()
	return text


func _draw_view() -> void:
	var font: Font = _view.get_theme_default_font()
	var view_size: Vector2 = _view.size
	var status: String = StatusEffects.summary()
	var box := Rect2(Vector2.ZERO, Vector2(BOX_WIDTH, 84.0 + ROW_HEIGHT * _rows.size() + 40.0))
	box.position = (view_size - box.size) / 2.0
	_view.draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_DIM)
	_view.draw_rect(box, COLOR_PANEL)
	_view.draw_rect(box, COLOR_BORDER, false, 2.0)
	_view.draw_string(font, box.position + Vector2(16, 30), "UTILISER", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	if status != "":
		_view.draw_string(font, Vector2(box.position.x, box.position.y + 30), status, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 16.0, FONT_SIZE - 2, COLOR_WARN)
	for i in _rows.size():
		var row := Rect2(box.position + Vector2(12, 48.0 + i * ROW_HEIGHT), Vector2(BOX_WIDTH - 24.0, ROW_HEIGHT - 4.0))
		if i == _selected:
			_view.draw_rect(row, COLOR_SELECTED)
		var use: Dictionary = _rows[i]["use"]
		_view.draw_string(font, row.position + Vector2(10, 19), _row_label(_rows[i]), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 20.0, FONT_SIZE, COLOR_TEXT)
		_view.draw_string(font, row.position + Vector2(10, 38), "%s (%.0f s)" % [String(use.get("desc", "")), float(use.get("time", 2.0))],
			HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 20.0, FONT_SIZE - 3, COLOR_MUTED)
	_view.draw_string(font, box.position + Vector2(16, box.size.y - 12.0), "8 / 2 : choisir   Entrée : utiliser   Échap / u : fermer",
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 32.0, 14, COLOR_MUTED)
