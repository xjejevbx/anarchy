class_name MissingSpritesUI
extends CanvasLayer
## Écran de contrôle des sprites, affiché au lancement du jeu (réglage SHOW_MISSING_SPRITES de main.gd) : liste, par famille (terrains,
## murs, mobilier, objets, vêtements, monstres, joueur), les tuiles demandées par les données qui ne peuvent pas être chargées depuis
## assets/tiles.json (tuile absente, sprite absent, png introuvable). Sert à voir ce qu'il reste à ajouter ou à renommer.
## Rien ne s'affiche si tout est chargé. Le jeu est en pause tant que l'écran est ouvert. La liste est aussi écrite dans la console Godot.
## 8 / 2 (ou flèches) : défiler, PageHaut / PageBas : page, Début / Fin ; Entrée, Espace ou Échap : fermer. Données : SpriteAudit.

const PANEL_MARGIN: float = 48.0
const FONT_SIZE: int = 16
const LINE_HEIGHT: float = 22.0
const TILE_COLUMN: float = 360.0
const HEADER_HEIGHT: float = 84.0
const FOOTER_HEIGHT: float = 40.0
const MAX_USERS_SHOWN: int = 3

const COLOR_DIM: Color = Color(0, 0, 0, 0.7)
const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.97)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_WARN: Color = Color(1.0, 0.4, 0.35)
const COLOR_OK: Color = Color(0.3, 0.7, 0.4)

var player: Player

var _view: Control
var _is_open: bool = false
var _lines: Array[Dictionary] = []   # {kind: "header" / "entry" / "ok", text, detail, color}
var _scroll: int = 0
var _missing: int = 0


func _ready() -> void:
	layer = 30
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.visible = false
	_view.draw.connect(_draw_view)
	add_child(_view)


## Lance l'audit et ouvre l'écran s'il y a des sprites manquants (sinon, un simple message dans le journal).
func show_report() -> void:
	var report: Array[Dictionary] = SpriteAudit.run()
	_missing = SpriteAudit.missing_count(report)
	_lines.clear()
	for category: Dictionary in report:
		var entries: Array = category["entries"]
		var header: String = "%s : %d manquant(s) sur %d" % [category["name"], entries.size(), category["total"]]
		if entries.is_empty():
			_lines.append({"kind": "header", "text": header, "color": COLOR_OK})
			continue
		_lines.append({"kind": "header", "text": header, "color": COLOR_HEADER})
		if String(category["note"]) != "":
			_lines.append({"kind": "note", "text": "   " + String(category["note"]), "color": COLOR_MUTED})
		for entry: Dictionary in entries:
			_lines.append({"kind": "entry", "text": String(entry["tile"]), "detail": _detail(entry), "color": COLOR_WARN})
	_print_report()
	if _missing == 0:
		EventBus.message_logged.emit("Sprites : toutes les tuiles demandées par les données sont chargées.")
		return
	EventBus.message_logged.emit("Sprites : %d tuile(s) manquante(s) ou mal nommée(s) (liste affichée au lancement)." % _missing)
	_scroll = 0
	_is_open = true
	player.input_blocked = true
	_view.visible = true
	_view.queue_redraw()


func _detail(entry: Dictionary) -> String:
	var users: Array = entry["users"]
	var shown: Array[String] = []
	for i in mini(users.size(), MAX_USERS_SHOWN):
		shown.append(String(users[i]))
	var text: String = ", ".join(shown)
	if users.size() > MAX_USERS_SHOWN:
		text += " (+%d)" % (users.size() - MAX_USERS_SHOWN)
	return "%s   [%s]" % [text, entry["reason"]]


func _print_report() -> void:
	print("SpriteAudit : %d tuile(s) manquante(s) ou mal nommée(s)" % _missing)
	for line: Dictionary in _lines:
		match String(line["kind"]):
			"header":
				print("  == ", line["text"])
			"entry":
				print("     %s  <-  %s" % [line["text"], line["detail"]])


func _close() -> void:
	_is_open = false
	player.input_blocked = false
	_view.visible = false


func _visible_rows() -> int:
	return maxi(int((_view.size.y - PANEL_MARGIN * 2.0 - HEADER_HEIGHT - FOOTER_HEIGHT) / LINE_HEIGHT), 1)


func _max_scroll() -> int:
	return maxi(_lines.size() - _visible_rows(), 0)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	get_viewport().set_input_as_handled()   # le jeu est en pause : le joueur ne reçoit rien
	if not key_event.pressed:
		return
	var key: Key = key_event.physical_keycode
	var page: int = _visible_rows()
	if key == KEY_KP_8 or key == KEY_UP:
		_scroll -= 1
	elif key == KEY_KP_2 or key == KEY_DOWN:
		_scroll += 1
	elif key == KEY_PAGEUP:
		_scroll -= page
	elif key == KEY_PAGEDOWN:
		_scroll += page
	elif key == KEY_HOME:
		_scroll = 0
	elif key == KEY_END:
		_scroll = _max_scroll()
	elif not key_event.echo and (key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE):
		_close()
		return
	_scroll = clampi(_scroll, 0, _max_scroll())
	_view.queue_redraw()


func _draw_view() -> void:
	var font: Font = _view.get_theme_default_font()
	var view_size: Vector2 = _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_DIM)
	var panel := Rect2(Vector2.ONE * PANEL_MARGIN, view_size - Vector2.ONE * PANEL_MARGIN * 2.0)
	_view.draw_rect(panel, COLOR_PANEL)
	_view.draw_rect(panel, COLOR_BORDER, false, 2.0)
	_view.draw_string(font, panel.position + Vector2(16, 28), "SPRITES MANQUANTS", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	_view.draw_string(font, panel.position + Vector2(16, 54), "%d tuile(s) demandée(s) par les données mais absente(s) de assets/tiles.json (ou png introuvable)." % _missing,
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, FONT_SIZE - 2, COLOR_TEXT)
	_view.draw_string(font, panel.position + Vector2(16, 74), "À ajouter dans tiles.json / tools/build_ultica_pack.py (IDS), ou à renommer dans les données.",
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, FONT_SIZE - 3, COLOR_MUTED)
	var rows: int = _visible_rows()
	_scroll = clampi(_scroll, 0, _max_scroll())
	var y: float = panel.position.y + HEADER_HEIGHT + 14.0
	for i in range(_scroll, mini(_lines.size(), _scroll + rows)):
		var line: Dictionary = _lines[i]
		var x: float = panel.position.x + 16.0
		match String(line["kind"]):
			"entry":
				_view.draw_string(font, Vector2(x + 12.0, y), String(line["text"]), HORIZONTAL_ALIGNMENT_LEFT, TILE_COLUMN - 12.0, FONT_SIZE, line["color"])
				_view.draw_string(font, Vector2(x + TILE_COLUMN, y), String(line["detail"]), HORIZONTAL_ALIGNMENT_LEFT,
					panel.size.x - TILE_COLUMN - 40.0, FONT_SIZE - 2, COLOR_MUTED)
			"note":
				_view.draw_string(font, Vector2(x, y), String(line["text"]), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40.0, FONT_SIZE - 3, line["color"])
			_:
				_view.draw_string(font, Vector2(x, y), String(line["text"]), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40.0, FONT_SIZE, line["color"])
		y += LINE_HEIGHT
	if _max_scroll() > 0:   # petite barre de défilement
		var track := Rect2(panel.end.x - 12.0, panel.position.y + HEADER_HEIGHT, 6.0, rows * LINE_HEIGHT + 14.0)
		var thumb_h: float = maxf(track.size.y * float(rows) / float(_lines.size()), 20.0)
		var thumb_y: float = track.position.y + (track.size.y - thumb_h) * float(_scroll) / float(_max_scroll())
		_view.draw_rect(track, Color(1, 1, 1, 0.08))
		_view.draw_rect(Rect2(track.position.x, thumb_y, track.size.x, thumb_h), COLOR_MUTED)
	_view.draw_string(font, Vector2(panel.position.x + 16, panel.end.y - 14),
		"8 / 2 (ou flèches) : défiler   PgHaut / PgBas : page   Début / Fin   Entrée / Espace / Échap : fermer   (liste aussi dans la console)",
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, 14, COLOR_MUTED)
