class_name SaveMenuUI
extends CanvasLayer
## Écran des sauvegardes (jalon 7), utilisé comme MENU PRINCIPAL au lancement et en jeu (F5).
##
## Menu principal : partie rapide (seed aléatoire), arène de test, sauvegardes (charger / supprimer),
## nouvelle partie (seed + scénario). En jeu : choisir un emplacement pour sauvegarder (écrasement confirmé),
## charger une autre partie, supprimer, partie rapide, arène de test, ou créer une nouvelle partie
## (la partie en cours est perdue). Touches : 8 / 2 (ou flèches), Entrée, Échap ; N = seed aléatoire,
## T = arène de test, L = charger, Suppr = supprimer, C = copier la seed affichée. La saisie de la seed se fait
## au clavier (Ctrl+V colle), vide = seed aléatoire affichée dans le journal une fois la partie créée.

enum Screen { LIST, NEW_GAME, CONFIRM }

const FONT_SIZE: int = 16
const ROW_HEIGHT: float = 64.0
const BOX_WIDTH: float = 800.0
const NEW_GAME_ROW_HEIGHT: float = 54.0
const MAX_VISIBLE_ROWS: int = 7

const COLOR_DIM: Color = Color(0, 0, 0, 0.58)
const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.98)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_SELECTED: Color = Color(0.25, 0.35, 0.55, 0.9)
const COLOR_WARN: Color = Color(1.0, 0.4, 0.35)
const COLOR_ON: Color = Color(0.4, 0.85, 0.5)
const MAX_SEED_LENGTH: int = 64

const SCENARIOS: Array[String] = ["default", "island"]
const SCENARIO_LABELS: Array[String] = ["Lisière de ville / pleine nature", "Île perdue (si une île existe près de l'origine)"]

var player: Player
var main_mode: bool = false
var notice: String = ""

var _view: Control
var _is_open: bool = false
var _screen: int = Screen.LIST
var _rows: Array[Dictionary] = []
var _selected: int = 0
var _scroll: int = 0

var _seed_input: String = ""
var _scenario_index: int = 0
var _new_game_selected: int = 0

var _confirm_action: String = ""
var _confirm_slot: String = ""
var _confirm_return: int = Screen.LIST
var _message: String = ""


func _ready() -> void:
	layer = 30 if main_mode else 24
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.visible = false
	_view.draw.connect(_draw_view)
	add_child(_view)
	if main_mode:
		_open()


func _open() -> void:
	if _is_open:
		return
	_is_open = true
	if player != null:
		player.input_blocked = true
	_screen = Screen.LIST
	_message = notice
	notice = ""
	_refresh_slots()
	_view.visible = true
	_view.queue_redraw()


func _close() -> void:
	_is_open = false
	if player != null:
		player.input_blocked = false
	_view.visible = false


func _refresh_slots() -> void:
	var previous: Dictionary = {}
	if _selected >= 0 and _selected < _rows.size():
		previous = _rows[_selected]
	_rows.clear()
	# Accès direct demandé par le menu principal : partie rapide et arène de test, avant les sauvegardes.
	_rows.append({"kind": "quick_game"})
	_rows.append({"kind": "arena"})
	for entry: Dictionary in SaveGame.list_slots():
		_rows.append({"kind": "slot", "slot": entry["slot"], "meta": entry["meta"]})
	if not main_mode:
		_rows.append({"kind": "new_save", "slot": SaveGame.next_slot_name()})
	_rows.append({"kind": "new_game"})
	_rows.append({"kind": "resume"} if not main_mode else {"kind": "quit"})
	_selected = 0
	if not previous.is_empty():
		for i in _rows.size():
			if _rows[i].get("kind", "") == previous.get("kind", "") and _rows[i].get("slot", "") == previous.get("slot", ""):
				_selected = i
				break
	_selected = clampi(_selected, 0, maxi(_rows.size() - 1, 0))
	_keep_selected_visible()


# --- Entrées ---

func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null:
		return
	if not _is_open:
		if not main_mode and key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_F5 \
				and player != null and not player.dead and not player.input_blocked:
			get_viewport().set_input_as_handled()
			_open()
		return
	get_viewport().set_input_as_handled()
	if not key_event.pressed or key_event.echo:
		return
	match _screen:
		Screen.LIST:
			_handle_list_key(key_event)
		Screen.NEW_GAME:
			_handle_new_game_key(key_event)
		Screen.CONFIRM:
			_handle_confirm_key(key_event)
	_view.queue_redraw()


func _handle_list_key(event: InputEventKey) -> void:
	var key: Key = event.physical_keycode
	if key == KEY_KP_8 or key == KEY_UP:
		_selected = posmod(_selected - 1, _rows.size())
		_keep_selected_visible()
	elif key == KEY_KP_2 or key == KEY_DOWN:
		_selected = (_selected + 1) % _rows.size()
		_keep_selected_visible()
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		_activate_row()
	elif key == KEY_DELETE or key == KEY_BACKSPACE:
		var row: Dictionary = _rows[_selected]
		if row.get("kind", "") == "slot":
			_ask_confirm("delete", String(row["slot"]), Screen.LIST)
	elif KeyUtil.is_letter(event, "l") and not main_mode:
		var row: Dictionary = _rows[_selected]
		if row.get("kind", "") == "slot":
			_ask_confirm("load", String(row["slot"]), Screen.LIST)
	elif KeyUtil.is_letter(event, "n"):
		_activate_quick_game()
	elif KeyUtil.is_letter(event, "t"):
		_activate_arena()
	elif KeyUtil.is_letter(event, "c"):
		var row: Dictionary = _rows[_selected]
		if row.get("kind", "") == "slot":
			_copy_seed(String((row["meta"] as Dictionary).get("seed_text", "")))
	elif key == KEY_ESCAPE:
		if main_mode:
			get_tree().quit()
		else:
			_close()


func _activate_row() -> void:
	var row: Dictionary = _rows[_selected]
	match String(row.get("kind", "")):
		"quick_game":
			_activate_quick_game()
		"arena":
			_activate_arena()
		"slot":
			var slot: String = String(row["slot"])
			if main_mode:
				var reason: String = SaveGame.compatibility_error(row["meta"] as Dictionary)
				if reason != "":
					_message = reason
				else:
					_load_game(slot)
			else:
				_ask_confirm("overwrite", slot, Screen.LIST)
		"new_save":
			_save_to(String(row["slot"]))
		"new_game":
			_screen = Screen.NEW_GAME
			_new_game_selected = 0
			_seed_input = ""
			_scenario_index = 0
			_message = ""
		"resume":
			_close()
		"quit":
			get_tree().quit()


func _handle_new_game_key(event: InputEventKey) -> void:
	var key: Key = event.physical_keycode
	if key == KEY_ESCAPE:
		_screen = Screen.LIST
		_message = ""
		return
	if key == KEY_KP_8 or key == KEY_UP:
		_new_game_selected = posmod(_new_game_selected - 1, 4)
		return
	if key == KEY_KP_2 or key == KEY_DOWN:
		_new_game_selected = (_new_game_selected + 1) % 4
		return
	match _new_game_selected:
		0:
			if key == KEY_ENTER or key == KEY_KP_ENTER:
				_start_new_game()
			else:
				_edit_seed(event)
		1:
			if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_KP_4 or key == KEY_LEFT \
					or key == KEY_KP_6 or key == KEY_RIGHT:
				_scenario_index = (_scenario_index + 1) % SCENARIOS.size()
		2:
			if key == KEY_ENTER or key == KEY_KP_ENTER:
				_start_new_game()
		3:
			if key == KEY_ENTER or key == KEY_KP_ENTER:
				_screen = Screen.LIST


func _edit_seed(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		if KeyUtil.is_letter(event, "v"):
			var pasted: String = DisplayServer.clipboard_get().strip_edges()
			_seed_input = ( _seed_input + pasted).substr(0, MAX_SEED_LENGTH)
		return
	if event.physical_keycode == KEY_BACKSPACE:
		_seed_input = _seed_input.substr(0, maxi(_seed_input.length() - 1, 0))
		return
	if event.unicode >= 32 and event.unicode != 127:
		var typed: String = String.chr(event.unicode)
		if _seed_input.length() < MAX_SEED_LENGTH:
			_seed_input += typed


func _handle_confirm_key(event: InputEventKey) -> void:
	var key: Key = event.physical_keycode
	if key == KEY_ESCAPE:
		_screen = _confirm_return
		_message = ""
		return
	if key != KEY_ENTER and key != KEY_KP_ENTER:
		return
	match _confirm_action:
		"delete":
			if SaveGame.delete_slot(_confirm_slot):
				_message = "Sauvegarde « %s » supprimée." % _confirm_slot
			else:
				_message = "Impossible de supprimer « %s »." % _confirm_slot
			_screen = Screen.LIST
			_refresh_slots()
		"overwrite":
			_screen = Screen.LIST
			_save_to(_confirm_slot)
		"load":
			_load_game(_confirm_slot)
		"new_game":
			_launch_new_game()
		"quick_game":
			_launch_quick_game()
		"arena":
			_launch_arena()


func _ask_confirm(action: String, slot: String, return_screen: int) -> void:
	_confirm_action = action
	_confirm_slot = slot
	_confirm_return = return_screen
	_message = ""
	_screen = Screen.CONFIRM


# --- Actions ---

func _save_to(slot: String) -> void:
	if player == null or player.world == null:
		_message = "Aucune partie en cours à sauvegarder."
		return
	var result: Dictionary = SaveGame.save(player.world, player, slot)
	if bool(result.get("ok", false)):
		EventBus.message_logged.emit("Partie sauvegardée dans « %s » (seed « %s »)." % [slot, player.world.seed_text])
		_close()
	else:
		_message = String(result.get("error", "échec de la sauvegarde"))


func _load_game(slot: String) -> void:
	var meta: Dictionary = SaveGame.read_meta(slot)
	var reason: String = SaveGame.compatibility_error(meta)
	if reason != "":
		_message = reason
		_screen = Screen.LIST
		return
	GameSession.request_load(slot)
	get_tree().reload_current_scene()


func _start_new_game() -> void:
	if not main_mode:
		_ask_confirm("new_game", "", Screen.NEW_GAME)
		return
	_launch_new_game()


func _launch_new_game() -> void:
	var seed_value: String = _seed_input.strip_edges()
	if seed_value == "":
		seed_value = _random_seed_text()
	GameSession.request_new_game(seed_value, SCENARIOS[_scenario_index])
	get_tree().reload_current_scene()


## Partie rapide : seed aléatoire, scénario par défaut (aucune saisie).
func _activate_quick_game() -> void:
	if main_mode:
		_launch_quick_game()
	else:
		_ask_confirm("quick_game", "", Screen.LIST)


func _launch_quick_game() -> void:
	GameSession.request_new_game(_random_seed_text(), "default")
	get_tree().reload_current_scene()


## Arène de test : seed fixe, contenu de démonstration (voir TestArena et ArenaGuideUI).
func _activate_arena() -> void:
	if main_mode:
		_launch_arena()
	else:
		_ask_confirm("arena", "", Screen.LIST)


func _launch_arena() -> void:
	GameSession.request_arena()
	get_tree().reload_current_scene()


func _copy_seed(text: String) -> void:
	if text.strip_edges() == "":
		return
	DisplayServer.clipboard_set(text)
	_message = "Seed copiée dans le presse-papiers : « %s »." % text


static func _random_seed_text() -> String:
	var value: int = (randi() << 32) ^ randi()
	return str(value)


## Maintient la ligne sélectionnée dans la fenêtre visible (liste longue).
func _keep_selected_visible() -> void:
	_scroll = clampi(_scroll, 0, maxi(_rows.size() - MAX_VISIBLE_ROWS, 0))
	if _selected < _scroll:
		_scroll = _selected
	elif _selected >= _scroll + MAX_VISIBLE_ROWS:
		_scroll = _selected - MAX_VISIBLE_ROWS + 1
	_scroll = clampi(_scroll, 0, maxi(_rows.size() - MAX_VISIBLE_ROWS, 0))


# --- Rendu ---

func _draw_view() -> void:
	var font: Font = _view.get_theme_default_font()
	var view_size: Vector2 = _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_DIM)
	match _screen:
		Screen.NEW_GAME:
			_draw_new_game(font, view_size)
		Screen.CONFIRM:
			_draw_confirm(font, view_size)
		_:
			_draw_list(font, view_size)


func _draw_list(font: Font, view_size: Vector2) -> void:
	var has_message: bool = _message != ""
	var visible_count: int = mini(_rows.size(), MAX_VISIBLE_ROWS)
	var box_height: float = 92.0 + visible_count * ROW_HEIGHT + (28.0 if has_message else 0.0) + 38.0
	var box := Rect2(Vector2.ZERO, Vector2(BOX_WIDTH, box_height))
	box.position = (view_size - box.size) / 2.0
	_view.draw_rect(box, COLOR_PANEL)
	_view.draw_rect(box, COLOR_BORDER, false, 2.0)
	var title: String = "ANARCHY — MENU PRINCIPAL" if main_mode else "SAUVEGARDES"
	_view.draw_string(font, box.position + Vector2(18, 32), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	var subtitle: String = "Partie rapide, arène de test, sauvegardes ou nouvelle partie au choix."
	if not main_mode and player != null and player.world != null:
		subtitle = "Partie en cours : seed « %s » • %s" % [player.world.seed_text, GameClock.get_time_string()]
	_view.draw_string(font, box.position + Vector2(18, 54), subtitle, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 36.0, FONT_SIZE - 2, COLOR_MUTED)
	var y: float = box.position.y + 72.0
	var last: int = mini(_scroll + visible_count, _rows.size())
	for i in range(_scroll, last):
		var row := Rect2(Vector2(box.position.x + 12.0, y), Vector2(box.size.x - 24.0, ROW_HEIGHT - 4.0))
		if i == _selected:
			_view.draw_rect(row, COLOR_SELECTED)
		_draw_list_row(font, row, _rows[i])
		y += ROW_HEIGHT
	if _scroll > 0:
		_view.draw_string(font, box.position + Vector2(box.size.x - 34.0, 68.0), "▲", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_MUTED)
	if last < _rows.size():
		_view.draw_string(font, Vector2(box.position.x + box.size.x - 34.0, y - 4.0), "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_MUTED)
	if has_message:
		_view.draw_string(font, Vector2(box.position.x + 18.0, y + 18.0), _message,
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 36.0, FONT_SIZE - 2, COLOR_WARN)
		y += 28.0
	var hint: String
	if main_mode:
		hint = "8 / 2 : choisir   Entrée : valider   N : seed aléatoire   T : arène   C : copier   Échap : quitter"
	else:
		hint = "8 / 2 : choisir   Entrée : valider   N : seed aléatoire   T : arène   L : charger   Échap : reprendre"
	_view.draw_string(font, Vector2(box.position.x + 18.0, box.position.y + box.size.y - 14.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 36.0, 12, COLOR_MUTED)


func _draw_list_row(font: Font, row: Rect2, data: Dictionary) -> void:
	var kind: String = String(data.get("kind", ""))
	match kind:
		"slot":
			var slot: String = String(data["slot"])
			var meta: Dictionary = data["meta"]
			var seed_text: String = String(meta.get("seed_text", meta.get("seed", "")))
			var reason: String = SaveGame.compatibility_error(meta)
			var label: String = "« %s »   seed « %s »" % [slot, seed_text]
			if not main_mode:
				label += "   (Entrée : sauvegarder ici)"
			_view.draw_string(font, row.position + Vector2(12, 24), label,
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_TEXT)
			var detail: String = "%s   •   %s   •   %d chunk(s)" % [
				String(meta.get("clock_text", "?")), String(meta.get("saved_at", "?")), int(meta.get("chunk_count", 0))]
			if reason != "":
				detail = "INCOMPATIBLE — " + reason
			_view.draw_string(font, row.position + Vector2(12, 46), detail,
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE - 3,
				COLOR_WARN if reason != "" else COLOR_MUTED)
		"new_save":
			_view.draw_string(font, row.position + Vector2(12, 34), "＋ Nouvelle sauvegarde (emplacement « %s »)" % String(data["slot"]),
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_ON)
		"quick_game":
			_view.draw_string(font, row.position + Vector2(12, 24), "▶ Nouvelle partie (seed aléatoire)",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_ON)
			_view.draw_string(font, row.position + Vector2(12, 46), "Lancement immédiat, scénario par défaut (lisière de ville / nature).",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE - 4, COLOR_MUTED)
		"arena":
			_view.draw_string(font, row.position + Vector2(12, 24), "▶ Arène de test (toutes les fonctionnalités)",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_ON)
			_view.draw_string(font, row.position + Vector2(12, 46), "Carte fixe multi-zones et multi-étages, guide pas à pas en haut (F1).",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE - 4, COLOR_MUTED)
		"new_game":
			_view.draw_string(font, row.position + Vector2(12, 34), "＋ Nouvelle partie (seed et scénario au choix)",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_ON)
		"resume":
			_view.draw_string(font, row.position + Vector2(12, 34), "Reprendre la partie",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_TEXT)
		"quit":
			_view.draw_string(font, row.position + Vector2(12, 34), "Quitter le jeu",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_TEXT)


func _draw_new_game(font: Font, view_size: Vector2) -> void:
	var box := Rect2(Vector2.ZERO, Vector2(760.0, 96.0 + 4.0 * NEW_GAME_ROW_HEIGHT + 42.0))
	box.position = (view_size - box.size) / 2.0
	_view.draw_rect(box, COLOR_PANEL)
	_view.draw_rect(box, COLOR_BORDER, false, 2.0)
	_view.draw_string(font, box.position + Vector2(18, 32), "NOUVELLE PARTIE", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	_view.draw_string(font, box.position + Vector2(18, 54), "Seed vide = aléatoire (la seed tirée est affichée dans le journal et copiable avec F2).",
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 36.0, FONT_SIZE - 2, COLOR_MUTED)
	var labels: Array[String] = ["Seed", "Scénario de départ", "Créer la partie", "Retour"]
	var values: Array[String] = [
		_seed_input if _seed_input != "" else "vide = aléatoire",
		SCENARIO_LABELS[_scenario_index],
		"", "",
	]
	for i in 4:
		var row := Rect2(Vector2(box.position.x + 12.0, box.position.y + 72.0 + i * NEW_GAME_ROW_HEIGHT),
			Vector2(box.size.x - 24.0, NEW_GAME_ROW_HEIGHT - 4.0))
		if i == _new_game_selected:
			_view.draw_rect(row, COLOR_SELECTED)
		_view.draw_string(font, row.position + Vector2(12, 23), labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_MUTED)
		if i == 0:
			var shown: String = "vide = aléatoire"
			if not _seed_input.is_empty():
				shown = _seed_input + ("_" if i == _new_game_selected else "")
			elif i == _new_game_selected:
				shown += "_"
			_view.draw_string(font, row.position + Vector2(240, 23), shown,
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 252.0, FONT_SIZE, COLOR_TEXT if _seed_input != "" else COLOR_MUTED)
			_view.draw_string(font, row.position + Vector2(12, 43), "Tapez la seed (Ctrl+V colle) ; Entrée crée la partie.",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE - 4, COLOR_MUTED)
		elif i == 1:
			_view.draw_string(font, row.position + Vector2(240, 23), String(values[1]) + ("   (Entrée / 4 / 6 : changer)" if i == _new_game_selected else ""),
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 252.0, FONT_SIZE, COLOR_TEXT)
			_view.draw_string(font, row.position + Vector2(12, 43), "« default » part en lisière de la ville la plus proche ; « island » cherche une petite île.",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE - 4, COLOR_MUTED)
		elif i == 2:
			var create: String = "Créer la partie"
			if not main_mode:
				create += "  (la partie en cours sera perdue)"
			_view.draw_string(font, row.position + Vector2(12, 32), create,
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_ON)
		else:
			_view.draw_string(font, row.position + Vector2(12, 32), "Retour aux sauvegardes",
				HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24.0, FONT_SIZE, COLOR_TEXT)
	_view.draw_string(font, Vector2(box.position.x + 18.0, box.position.y + box.size.y - 14.0),
		"8 / 2 : choisir la ligne   Gauche / droite : scénario   Entrée : créer / revenir   Échap : annuler",
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 36.0, 14, COLOR_MUTED)


func _draw_confirm(font: Font, view_size: Vector2) -> void:
	var box := Rect2(Vector2.ZERO, Vector2(680.0, 260.0))
	box.position = (view_size - box.size) / 2.0
	_view.draw_rect(box, COLOR_PANEL)
	_view.draw_rect(box, COLOR_BORDER, false, 2.0)
	_view.draw_string(font, box.position + Vector2(18, 32), "CONFIRMATION", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	var text: String = ""
	match _confirm_action:
		"delete":
			text = "Supprimer définitivement la sauvegarde « %s » ?" % _confirm_slot
		"overwrite":
			text = "Écraser la sauvegarde « %s » ?\nLa progression déjà enregistrée dans cet emplacement sera remplacée." % _confirm_slot
		"load":
			text = "Charger la sauvegarde « %s » ?\nLa progression en cours non sauvegardée sera perdue." % _confirm_slot
		"new_game":
			text = "Créer une nouvelle partie ?\nLa progression en cours non sauvegardée sera perdue."
		"quick_game":
			text = "Créer une nouvelle partie avec une seed aléatoire ?\nLa progression en cours non sauvegardée sera perdue."
		"arena":
			text = "Lancer l'arène de test ?\nLa progression en cours non sauvegardée sera perdue."
	_view.draw_multiline_string(font, box.position + Vector2(18, 78), text, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 36.0,
		FONT_SIZE, -1, COLOR_TEXT)
	_view.draw_string(font, box.position + Vector2(18, box.size.y - 54), "Entrée : oui, confirmer",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_WARN)
	_view.draw_string(font, box.position + Vector2(18, box.size.y - 26), "Échap : non, retour",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_MUTED)
