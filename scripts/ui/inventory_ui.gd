class_name InventoryUI
extends CanvasLayer
## Interface d'inventaire (i), de ramassage (g : cases à portée, G : les 9 cases d'un coup).
## Le jeu est en pause tant qu'elle est ouverte. Clavier pour agir ; la souris sert uniquement à lire
## des infos (survol du diviseur de poids).
##
## Temps : les modifications sont immédiates mais le temps n'est décompté qu'à la fermeture, une seule fois,
## selon le coût NET des déplacements (InventoryLedger). Une popup propose « Validé » ou « Annulé »
## (Annulé rouvre l'inventaire pour continuer les modifications).
##
## Le ramassage (G) et l'inventaire (I) sont deux écrans séparés (pas de passage de l'un à l'autre).
## Ramassage : rien n'est modifié avant validation ; les objets choisis restent listés, grisés « déplacé vers
## l'inventaire », et peuvent être annulés (U). À la validation, ramassages et dépôts se font un par un, avec un
## petit délai et une bannière en haut de l'écran (STEP_DELAY). Chaque objet (chaque unité d'une pile) est sa
## propre étape : le temps de l'étape passe à ce moment-là (les monstres avancent entre deux étapes).
## Affichage des touches : minuscule = touche seule (u), MAJUSCULE = avec Maj (U). u annule l'objet sous le curseur,
## U annule tout (remise à zéro).
##
## Sélection multiple : 4 (ou +) ajoute l'objet sous le curseur à la sélection, ou +1 s'il y est déjà ;
## - retire 1. Curseur sur un conteneur : 6 = déplacer 1 unité de chaque objet sélectionné,
## Entrée = déplacer toute la sélection. 6 sur un objet sélectionné le retire de la sélection.

const PANEL_MARGIN: float = 48.0
const ROW_HEIGHT: float = 34.0
const ICON_SIZE: float = 30.0
const INDENT: float = 24.0
const FONT_SIZE: int = 16
const DETAIL_FONT_SIZE: int = 15
const LIST_WIDTH_RATIO: float = 0.58
const MAX_SELECTION_LINES: int = 6
const STEP_DELAY: float = 0.6   # secondes entre deux ramassages / dépôts à la validation (deviendra une option de jeu)

const COLOR_DIM: Color = Color(0, 0, 0, 0.55)
const COLOR_PANEL: Color = Color(0.09, 0.09, 0.11, 0.97)
const COLOR_BORDER: Color = Color(0.45, 0.45, 0.5)
const COLOR_SELECTED: Color = Color(0.25, 0.35, 0.55, 0.9)
const COLOR_HELD: Color = Color(0.2, 0.5, 0.4, 0.9)
const COLOR_TEXT: Color = Color(0.92, 0.92, 0.92)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.6)
const COLOR_HEADER: Color = Color(0.95, 0.8, 0.4)
const COLOR_ACCENT: Color = Color(0.55, 0.8, 1.0)
const COLOR_WARN: Color = Color(1.0, 0.4, 0.35)
const COLOR_OK: Color = Color(0.3, 0.7, 0.4)

# Pavé numérique -> chiffre (la disposition 7 8 9 / 4 5 6 / 1 2 3 reflète les 9 cases autour du joueur).
const DIGIT_KEYS: Dictionary = {
	KEY_KP_1: 1, KEY_KP_2: 2, KEY_KP_3: 3, KEY_KP_4: 4, KEY_KP_5: 5,
	KEY_KP_6: 6, KEY_KP_7: 7, KEY_KP_8: 8, KEY_KP_9: 9,
}
# Flèches = 8 / 2 / 4 / 6 (déplacement, navigation dans les listes, choix de case).
const ARROW_DIGITS: Dictionary = {KEY_UP: 8, KEY_DOWN: 2, KEY_LEFT: 4, KEY_RIGHT: 6}
const KEYS_ADD: Array = [KEY_KP_4, KEY_LEFT, KEY_KP_ADD, KEY_EQUAL]
const KEYS_REMOVE: Array = [KEY_KP_SUBTRACT, KEY_MINUS]
const KEYS_VALIDATE: Array = [KEY_KP_6, KEY_RIGHT]
const KEYS_CONFIRM: Array = [KEY_ENTER, KEY_KP_ENTER]
const KEYS_PICK: Array = [KEY_ENTER, KEY_KP_ENTER, KEY_G]
const DEST_NAMES: Dictionary = {"auto": "rangement auto", "hand": "en main", "equip": "équipé"}

enum Mode { NONE, INVENTORY, GROUND, PICK_CELL, CONFIRM, SEQUENCE }

var player: Player

var _mode: Mode = Mode.NONE
var _prev_mode: Mode = Mode.INVENTORY   # mode affiché derrière la popup de validation
var _view: Control
var _session: InventoryLedger
var _rows: Array[Dictionary] = []   # {item, state, depth, header, text, slot, cell}
var _selected: int = -1
var _scroll: int = 0
var _ground_cells: Array[Vector2i] = []
var _held: Array[Dictionary] = []   # sélection : {item, qty, state, cell}
var _confirm: Dictionary = {}       # {base, cost, moves}
var _staged: Array[Dictionary] = [] # ramassages préparés : {item, cell, qty, dest}
var _sequence: Array[Dictionary] = []  # étapes jouées à la validation : {text, run}
var _seq_timer: float = 0.0
var _seq_total: int = 0
var _status: String = ""
var _hover_zones: Array[Dictionary] = []  # {rect, tip}
var _hover_index: int = -1


func _ready() -> void:
	layer = 20
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.visible = false
	_view.draw.connect(_draw_view)
	add_child(_view)
	EventBus.inventory_requested.connect(func() -> void: _open(Mode.INVENTORY, false))
	EventBus.ground_requested.connect(func() -> void: _open(Mode.GROUND, false))
	EventBus.ground_all_requested.connect(func() -> void: _open(Mode.GROUND, true))


# --- Ouverture / fermeture (une « session » dure de l'ouverture à la validation) ---

func _open(mode: Mode, all_cells: bool) -> void:
	if player == null or player.dead or _mode != Mode.NONE:
		return
	_session = InventoryLedger.new()
	_session.begin(player)
	player.input_blocked = true
	_view.visible = true
	_status = ""
	if not _enter_mode(mode, all_cells):
		_finish()


## Change d'écran (inventaire / sol / choix de case) sans terminer la session. false si impossible.
func _enter_mode(mode: Mode, all_cells: bool) -> bool:
	var labels: Dictionary = {}
	if mode == Mode.GROUND:
		var cells: Array[Vector2i] = player.reach_cells_with_items()
		if cells.is_empty():
			_status = "Il n'y a rien à portée de main."
			EventBus.message_logged.emit(_status)
			return false
		if all_cells or cells.size() == 1:
			_ground_cells = cells
		else:
			mode = Mode.PICK_CELL
			for cell: Vector2i in cells:
				labels[cell] = str(_digit_for_offset(cell - player.grid_pos))
	_held.clear()
	_selected = -1
	_scroll = 0
	_status = ""
	player.world.show_pick_overlay(labels)
	_mode = mode
	_rebuild()
	return true


## Fermeture demandée : s'il y a eu des déplacements, la popup de coût s'affiche avant de terminer.
func _request_close() -> void:
	var steps: Array[Dictionary] = _build_steps()
	if steps.is_empty():
		_finish()
		return
	var base: float = 0.0
	for step: Dictionary in steps:
		base += float(step["cost"])
	_prev_mode = _mode
	_confirm = {"base": base, "cost": player.real_cost(base), "moves": steps.size()}
	player.world.show_pick_overlay({})
	_mode = Mode.CONFIRM
	_view.queue_redraw()


## « Validé » : une étape par objet, jouées une à une (délai STEP_DELAY) ; le temps de chaque étape passe à ce moment.
func _validate() -> void:
	_sequence = _build_steps()
	_seq_total = _sequence.size()
	if _sequence.is_empty():
		_complete()
		return
	_mode = Mode.SEQUENCE
	_seq_timer = STEP_DELAY
	_view.queue_redraw()


## « Annulé » : on rouvre l'écran pour continuer les modifications (rien n'est défait).
func _cancel_confirm() -> void:
	_mode = _prev_mode
	_status = ""
	_rebuild()


func _finish() -> void:
	player.flush_pending_drops()  # sécurité : rien ne doit rester dans les limbes
	_mode = Mode.NONE
	_session = null
	_held.clear()
	_staged.clear()
	_sequence.clear()
	player.world.show_pick_overlay({})
	player.input_blocked = false
	_view.visible = false


func _complete() -> void:
	player.log_inventory_summary(int(_confirm["moves"]), float(_confirm["base"]))
	_finish()


func _advance_sequence() -> void:
	_run_next_step()
	if _mode != Mode.SEQUENCE:
		return
	if _sequence.is_empty():
		_complete()
	else:
		_seq_timer = STEP_DELAY


## Joue la prochaine étape : son effet sur le monde, puis son temps (les monstres agissent).
func _run_next_step() -> void:
	var step: Dictionary = _sequence.pop_front()
	var run: Callable = step["run"]
	if run.is_valid():
		run.call()
	player.spend_inventory_time(float(step["cost"]))
	if player.dead:
		_sequence.clear()
		_finish()


func _skip_sequence() -> void:
	while not _sequence.is_empty() and _mode == Mode.SEQUENCE:
		_run_next_step()
	if _mode == Mode.SEQUENCE:
		_complete()


## Toutes les étapes de la validation : une par objet déplacé, avec son texte, son coût de base et son effet.
func _build_steps() -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for e: Dictionary in _staged:
		steps.append_array(_pickup_steps(e))
	for s: Dictionary in _session.compute()["steps"]:
		var key: String = s["key"]
		var run: Callable = Callable()
		if String(s["to"]).begins_with("ground:"):
			run = func() -> void: _commit_drop_unit(key)
		steps.append({"text": s["text"], "cost": s["cost"], "run": run})
	return steps


func _pickup_steps(e: Dictionary) -> Array[Dictionary]:
	var item := e["item"] as Item
	var cell: Vector2i = e["cell"]
	var dest: String = e["dest"]
	var unit_cost: float = player.pickup_cost_for_weight(player.unit_weight_of(item))
	if dest == "equip":
		unit_cost += player.equip_cost_for_weight(item.real_weight())
	var how: String = {"hand": " en main", "equip": " et équipement"}.get(dest, "")
	var text: String = "Ramassage de %s%s (case %d)" % [item.display_name(), how, _digit_for_offset(cell - player.grid_pos)]
	var steps: Array[Dictionary] = []
	for i in player.unit_count(item, int(e["qty"])):
		steps.append({"text": text, "cost": unit_cost, "run": func() -> void: player.pickup_item(item, cell, 1, dest)})
	return steps


func _commit_drop_unit(key: String) -> void:
	for d: Dictionary in player.pending_drops:
		if _session.key_of(d["item"] as Item) == key:
			player.commit_pending_drop(d, 1)
			return


## U (Maj+u) : remise à zéro de tout ce qui a été décidé depuis l'ouverture.
func _reset_all() -> void:
	_held.clear()
	_staged.clear()
	if _session != null:
		_session.revert("")
	_status = "Tout est annulé."
	if _mode == Mode.INVENTORY or _mode == Mode.GROUND:
		_rebuild()


func _revert_key(key: String) -> void:
	_session.revert(key)
	_status = ""


## U (inventaire) : annule les déplacements de l'objet sous le curseur.
func _add_undo_action(item: Item, actions: Array[Dictionary]) -> void:
	if _mode != Mode.INVENTORY:
		return
	var key: String = _session.key_of(item)
	if _session.has_changes(key):
		actions.append(_action([KEY_U], "u", "Annuler les déplacements de %s" % item.display_name(), 0.0, "",
			func() -> void: _revert_key(key)))


func _ground_has_items() -> bool:
	for cell: Vector2i in _ground_cells:
		if not player.world.get_ground_items(cell).is_empty():
			return true
	return false


## 7 8 9 / 4 5 6 / 1 2 3 <-> décalage par rapport au joueur.
func _digit_for_offset(offset: Vector2i) -> int:
	return 5 + offset.x - 3 * offset.y


func _offset_for_digit(digit: int) -> Vector2i:
	return Vector2i((digit - 1) % 3 - 1, 1 - floori((digit - 1) / 3.0))


# --- Construction de la liste ---

func _rebuild() -> void:
	if player.dead:
		_finish()
		return
	var previous: Item = null
	if _selected >= 0 and _selected < _rows.size():
		previous = _rows[_selected].get("item") as Item
	var old_index: int = _selected
	_rows.clear()
	if _mode == Mode.INVENTORY:
		_build_inventory_rows()
	elif _mode == Mode.GROUND:
		_build_ground_rows()
		if _rows.is_empty():
			_request_close()  # plus rien à ramasser : l'écran se referme
			return
	_validate_held()
	_selected = -1
	if previous != null:
		for i in _rows.size():
			if _rows[i].get("item") == previous:
				_selected = i
	if _selected == -1:
		_select_near(maxi(old_index, 0))
	_view.queue_redraw()


func _build_inventory_rows() -> void:
	_rows.append({"header": true, "text": "ÉQUIPEMENT"})
	for slot: String in ItemDB.SLOTS:
		var it := player.inventory.equipment.get(slot) as Item
		if it == null:
			_rows.append({"dim": true, "text": "%s : —" % ItemDB.SLOT_NAMES[slot]})
			continue
		_rows.append({"item": it, "state": "equipped", "slot": slot, "depth": 0,
			"prefix": "%s : " % ItemDB.SLOT_NAMES[slot]})
		_add_content_rows(it)
	_rows.append({"header": true, "text": "SUR SOI"})
	if player.inventory.loose.is_empty():
		_rows.append({"dim": true, "text": "(rien)"})
	for it: Item in player.inventory.loose:
		_rows.append({"item": it, "state": "loose", "depth": 0})
		_add_content_rows(it)
	if not player.pending_drops.is_empty():
		_rows.append({"header": true, "text": "À POSER AU SOL (à la validation)"})
		for d: Dictionary in player.pending_drops:
			_rows.append({"item": d["item"], "state": "pending_drop", "depth": 0, "cell": d["cell"]})


func _add_content_rows(container: Item, state: String = "contained") -> void:
	for c: Item in container.contents:
		_rows.append({"item": c, "state": state, "depth": 1})


func _build_ground_rows() -> void:
	for cell: Vector2i in _ground_cells:
		for it: Item in player.world.get_ground_items(cell):
			_rows.append({"item": it, "state": "ground", "depth": 0, "cell": cell})
			_add_content_rows(it, "ground_content")  # affiché, non sélectable


func _is_selectable(index: int) -> bool:
	return index >= 0 and index < _rows.size() and _rows[index].get("item") != null \
		and _rows[index].get("state") != "ground_content"


func _select_near(index: int) -> void:
	index = clampi(index, 0, maxi(_rows.size() - 1, 0))
	for i in range(index, _rows.size()):
		if _is_selectable(i):
			_selected = i
			return
	for i in range(index, -1, -1):
		if _is_selectable(i):
			_selected = i
			return
	_selected = -1


func _move_selection(step: int) -> void:
	var i: int = _selected + step
	while i >= 0 and i < _rows.size():
		if _is_selectable(i):
			_selected = i
			_view.queue_redraw()
			return
		i += step


# --- Sélection multiple ---

func _entry_of(item: Item) -> Dictionary:
	for e: Dictionary in _held:
		if e["item"] == item:
			return e
	return {}


## Les entrées disparaissent si l'objet n'existe plus ; leur quantité suit celle de la pile.
func _validate_held() -> void:
	var valid: Array[Dictionary] = []
	for e: Dictionary in _held:
		var item := e["item"] as Item
		for row: Dictionary in _rows:
			if row.get("item") == item and String(row.get("state")) != "ground_content":
				e["qty"] = mini(int(e["qty"]), item.count)
				e["state"] = row["state"]
				e["cell"] = row.get("cell", Vector2i.ZERO)
				if int(e["qty"]) >= 1:
					valid.append(e)
				break
	_held = valid


## 4 / + : ajoute l'objet sous le curseur à la sélection (+1 s'il y est déjà).
func _hold_add() -> void:
	if _selected < 0:
		return
	var row: Dictionary = _rows[_selected]
	var item := row["item"] as Item
	var state: String = row["state"]
	if state == "pending_drop":
		_status = "%s est déjà à poser (u : annuler)." % item.display_name()
		return
	var entry: Dictionary = _entry_of(item)
	if entry.is_empty():
		_held.append({"item": item, "qty": 1, "state": row["state"], "cell": row.get("cell", Vector2i.ZERO)})
	else:
		entry["qty"] = mini(int(entry["qty"]) + 1, item.count)
	_status = ""
	_view.queue_redraw()


## - : retire 1 unité de l'objet sous le curseur dans la sélection.
func _hold_decrease() -> void:
	if _selected < 0:
		return
	var entry: Dictionary = _entry_of(_rows[_selected]["item"] as Item)
	if entry.is_empty():
		return
	entry["qty"] = int(entry["qty"]) - 1
	if int(entry["qty"]) <= 0:
		_held.erase(entry)
	_view.queue_redraw()


func _hold_remove(item: Item) -> void:
	_held.erase(_entry_of(item))


func _held_summary() -> String:
	if _held.size() == 1:
		return _label(_held[0]["item"] as Item, int(_held[0]["qty"]))
	var units: int = 0
	for e: Dictionary in _held:
		units += int(e["qty"])
	return "%d objets, %d unités" % [_held.size(), units]


## Applique `fn(entry)` aux entrées de l'état donné ("" = toutes) puis les retire de la sélection.
func _held_apply(only_state: String, fn: Callable) -> void:
	var remaining: Array[Dictionary] = []
	for e: Dictionary in _held:
		if only_state != "" and String(e["state"]) != only_state:
			remaining.append(e)
		else:
			fn.call(e)
	_held = remaining


func _held_cost(only_state: String, kind: String) -> float:
	var total: float = 0.0
	for e: Dictionary in _held:
		if only_state != "" and String(e["state"]) != only_state:
			continue
		var item := e["item"] as Item
		var qty: int = e["qty"]
		match kind:
			"pickup": total += player.pickup_base_cost(item, qty)
			"drop": total += player.drop_base_cost(item, qty)
			_: total += player.handle_base_cost(item, qty)
	return total


func _held_count(only_state: String) -> int:
	var n: int = 0
	for e: Dictionary in _held:
		if only_state == "" or String(e["state"]) == only_state:
			n += 1
	return n


func _staged_entry(item: Item) -> Dictionary:
	for e: Dictionary in _staged:
		if e["item"] == item:
			return e
	return {}


func _staged_cost() -> float:
	var total: float = 0.0
	for e: Dictionary in _staged:
		for step: Dictionary in _pickup_steps(e):
			total += float(step["cost"])
	return total


func _total_base_cost() -> float:
	return float(_session.compute()["cost"]) + _staged_cost()


## Prépare le ramassage de `qty` unités (rien n'est modifié avant la validation).
func _stage(item: Item, cell: Vector2i, qty: int, dest: String) -> void:
	var entry: Dictionary = _staged_entry(item)
	var already: int = int(entry.get("qty", 0))
	var n: int = mini(qty, item.count - already)
	if n <= 0:
		_status = "Déjà déplacé vers l'inventaire."
		return
	if dest == "equip" and item.slot() == "":
		_status = "%s ne se porte pas." % item.display_name()
		return
	if entry.is_empty():
		_staged.append({"item": item, "cell": cell, "qty": n, "dest": dest})
	else:
		entry["qty"] = already + n
		entry["dest"] = dest


func _unstage(item: Item) -> void:
	_staged.erase(_staged_entry(item))


func _stage_held(dest: String) -> void:
	for e: Dictionary in _held:
		_stage(e["item"] as Item, e["cell"], int(e["qty"]), dest)
	_held.clear()


func _ground_actions(item: Item, cell: Vector2i, actions: Array[Dictionary]) -> void:
	var staged: Dictionary = _staged_entry(item)
	var staged_qty: int = int(staged.get("qty", 0))
	var remaining: int = item.count - staged_qty
	var blocked: String = "déjà déplacé vers l'inventaire" if remaining <= 0 else ""
	var cost: float = player.pickup_base_cost(item, remaining) if remaining > 0 else 0.0
	actions.append(_action(KEYS_PICK, "Entrée", "Ramasser → %s" % _pickup_destination(item), cost, blocked,
		func() -> void: _stage(item, cell, remaining, "auto")))
	var hand: Dictionary = _action([KEY_W], "w", "Prendre en main (sur soi)", cost, blocked,
		func() -> void: _stage(item, cell, remaining, "hand"))
	hand["shift"] = false
	actions.append(hand)
	var equip_blocked: String = blocked if blocked != "" else ("ne se porte pas" if item.slot() == "" else "")
	var equip: Dictionary = _action([KEY_W], "W", "Équiper directement", cost + player.equip_base_cost(item), equip_blocked,
		func() -> void: _stage(item, cell, remaining, "equip"))
	equip["shift"] = true
	actions.append(equip)
	if not staged.is_empty():
		actions.append(_action([KEY_U], "u", "Annuler le déplacement (%d)" % staged_qty, 0.0, "",
			func() -> void: _unstage(item)))


# --- Actions possibles sur la ligne sélectionnée ---

## Chaque action : {keys, hint, label, cost (secondes, aperçu d'un geste isolé), blocked (raison ou ""), run, info}.
func _actions_for(row: Dictionary) -> Array[Dictionary]:
	var state: String = row["state"]
	if not _held.is_empty() and state != "pending_drop":
		return _held_actions(row)
	var item := row["item"] as Item
	var inv: Inventory = player.inventory
	var cell: Vector2i = row.get("cell", Vector2i.ZERO)
	var actions: Array[Dictionary] = []
	match state:
		"equipped":
			var slot: String = row["slot"]
			actions.append(_action([KEY_E], "e", "Retirer", player.equip_base_cost(item), "",
				func() -> void: player.unequip_slot(slot)))
			actions.append(_action([KEY_G], "g", "Poser au sol", player.drop_base_cost(item), "",
				func() -> void: player.drop_item(item)))
		"loose":
			if item.slot() != "":
				var old := inv.equipment.get(item.slot()) as Item
				var label: String = "Équiper" + (" (remplace %s)" % old.display_name() if old != null else "")
				actions.append(_action([KEY_E], "e", label, player.equip_base_cost(item), "",
					func() -> void: _equip_checked(item)))
			actions.append(_auto_store_action(item))
			actions.append(_action([KEY_G], "g", "Poser au sol", player.drop_base_cost(item), "",
				func() -> void: player.drop_item(item)))
		"contained":
			actions.append(_action([KEY_T], "t", "Sortir (sur soi)", player.handle_base_cost(item), "",
				func() -> void: player.take_out_item(item)))
			actions.append(_action([KEY_G], "g", "Poser au sol", player.drop_base_cost(item), "",
				func() -> void: player.drop_item(item)))
		"pending_drop":
			pass  # seule action : U (annuler), ajoutée plus bas
		"ground":
			_ground_actions(item, cell, actions)
	_add_undo_action(item, actions)
	if state != "pending_drop":
		actions.append(_add_info_action(row))
	return actions


func _add_info_action(_row: Dictionary) -> Dictionary:
	return {"keys": [], "hint": "4 ou +", "label": "Sélectionner (ajouter à la sélection)", "cost": 0.0,
		"blocked": "", "run": Callable(), "info": true}


func _equip_checked(item: Item) -> void:
	var reason: String = player.equip_item(item)
	if reason != "":
		_status = "Impossible : %s." % reason


func _store_checked(item: Item, container: Item, qty: int) -> bool:
	var reason: String = player.store_item(item, container, qty)
	if reason != "":
		_status = "Impossible : %s (%s)." % [reason, item.display_name()]
		return false
	return true


func _auto_store_action(item: Item) -> Dictionary:
	var target: Item = player.inventory.find_container_for(item)
	if target == null:
		var why: String = "les conteneurs se rangent à la main (4 puis 6)" if item.is_container() \
			else player.inventory.why_no_container(item)
		return _action([KEY_R], "r", "Ranger", 0.0, why, Callable())
	return _action([KEY_R], "r", "Ranger dans %s" % target.display_name(), player.handle_base_cost(item), "",
		func() -> void: _store_checked(item, target, -1))


## Actions quand la sélection n'est pas vide.
func _held_actions(row: Dictionary) -> Array[Dictionary]:
	var cursor := row["item"] as Item
	var cursor_state: String = row["state"]
	var cursor_selected: bool = not _entry_of(cursor).is_empty()
	var actions: Array[Dictionary] = []
	if _mode == Mode.GROUND:
		var cost: float = _held_cost("", "pickup")
		actions.append(_action(KEYS_PICK, "Entrée", "Ramasser la sélection (%s)" % _held_summary(), cost, "",
			func() -> void: _stage_held("auto")))
		var hand: Dictionary = _action([KEY_W], "w", "Prendre la sélection en main", cost, "",
			func() -> void: _stage_held("hand"))
		hand["shift"] = false
		actions.append(hand)
		var equip: Dictionary = _action([KEY_W], "W", "Équiper la sélection (si possible)", cost, "",
			func() -> void: _stage_held("equip"))
		equip["shift"] = true
		actions.append(equip)
		if not _staged_entry(cursor).is_empty():
			actions.append(_action([KEY_U], "u", "Annuler le déplacement de %s" % cursor.display_name(), 0.0, "",
				func() -> void: _unstage(cursor)))
	else:
		if not cursor_selected and cursor.is_container() and (cursor_state == "equipped" or cursor_state == "loose"):
			actions.append(_move_action(KEYS_VALIDATE, "6", cursor, true))
			actions.append(_move_action(KEYS_CONFIRM, "Entrée", cursor, false))
		var wearable: int = _held_wearable_count()
		if wearable > 0:
			actions.append(_action([KEY_E], "e", "Équiper / retirer la sélection (%d)" % wearable, _held_wear_cost(), "",
				func() -> void: _equip_selection()))
		if _held_count("contained") > 0:
			actions.append(_action([KEY_T], "t", "Sortir la sélection (sur soi)", _held_cost("contained", "handle"), "",
				func() -> void: _held_apply("contained", func(e: Dictionary) -> void: player.take_out_item(e["item"], e["qty"]))))
		if _held_count("loose") > 0:
			actions.append(_action([KEY_R], "r", "Ranger la sélection (auto)", _held_cost("loose", "handle"), "",
				func() -> void: _held_apply("loose", func(e: Dictionary) -> void: _auto_store_entry(e))))
		actions.append(_action([KEY_G], "g", "Poser la sélection au sol", _held_cost("", "drop"), "",
			func() -> void: _held_apply("", func(e: Dictionary) -> void: player.drop_item(e["item"], e["qty"]))))
		_add_undo_action(cursor, actions)
	if cursor_selected:
		actions.append(_action(KEYS_VALIDATE, "6", "Retirer de la sélection", 0.0, "", func() -> void: _hold_remove(cursor)))
	actions.append(_add_info_action(row))
	return actions


## Entrées de la sélection qu'on peut équiper (sur soi / rangées) ou retirer (déjà équipées).
func _held_wearable_count() -> int:
	var n: int = 0
	for e: Dictionary in _held:
		if String(e["state"]) == "equipped" or (e["item"] as Item).slot() != "":
			n += 1
	return n


func _held_wear_cost() -> float:
	var total: float = 0.0
	for e: Dictionary in _held:
		var item := e["item"] as Item
		if String(e["state"]) == "equipped" or item.slot() != "":
			total += player.equip_base_cost(item)
	return total


## E avec une sélection : équipe ce qui peut l'être (ex. un jean et un sac à dos en même temps), retire ce qui est équipé.
func _equip_selection() -> void:
	var used: Dictionary = {}
	var remaining: Array[Dictionary] = []
	for e: Dictionary in _held:
		var item := e["item"] as Item
		if String(e["state"]) == "equipped":
			player.unequip_slot(player.inventory.slot_of(item))
		elif item.slot() == "":
			remaining.append(e)
		elif used.has(item.slot()):
			_status = "Deux objets pour l'emplacement « %s »." % ItemDB.SLOT_NAMES.get(item.slot(), item.slot())
			remaining.append(e)
		else:
			used[item.slot()] = true
			_equip_checked(item)
	_held = remaining


func _auto_store_entry(e: Dictionary) -> void:
	var item := e["item"] as Item
	var target: Item = player.inventory.find_container_for(item)
	if target == null:
		_status = "Impossible : %s (%s)." % [player.inventory.why_no_container(item), item.display_name()]
		return
	_store_checked(item, target, int(e["qty"]))


## `one_each` : 1 unité de chaque objet sélectionné ; sinon toute la sélection.
func _move_action(keys: Array, hint: String, container: Item, one_each: bool) -> Dictionary:
	var cost: float = 0.0
	var reason: String = ""
	var all_blocked: bool = true
	for e: Dictionary in _held:
		var item := e["item"] as Item
		var n: int = 1 if one_each else int(e["qty"])
		cost += player.handle_base_cost(item, n)
		var why: String = player.inventory.can_store(item, n, container)
		if why == "":
			all_blocked = false
		elif reason == "":
			reason = why
	var label: String
	if one_each:
		label = "Déplacer 1 %s dans %s" % [(_held[0]["item"] as Item).display_name(), container.display_name()] if _held.size() == 1 \
			else "Déplacer 1 de chaque dans %s" % container.display_name()
	else:
		label = "Déplacer la sélection (%s) dans %s" % [_held_summary(), container.display_name()]
	return _action(keys, hint, label, cost, reason if all_blocked else "",
		func() -> void: _held_move(container, one_each))


## Déplace vers `container` ; ce qui ne rentre pas reste sélectionné (raison dans la ligne d'état).
func _held_move(container: Item, one_each: bool) -> void:
	var remaining: Array[Dictionary] = []
	for e: Dictionary in _held:
		var item := e["item"] as Item
		var n: int = 1 if one_each else int(e["qty"])
		if _store_checked(item, container, n):
			e["qty"] = int(e["qty"]) - n
		if int(e["qty"]) > 0:
			remaining.append(e)
	_held = remaining


func _action(keys: Array, hint: String, label: String, base_cost: float, blocked: String, run: Callable) -> Dictionary:
	return {"keys": keys, "hint": hint, "label": label, "cost": player.real_cost(base_cost),
		"blocked": blocked, "run": run, "info": false}


func _label(item: Item, qty: int) -> String:
	return item.display_name() + (" ×%d" % qty if qty > 1 else "")


func _pickup_destination(item: Item) -> String:
	var holder: Item = player.inventory.find_container_for(item)
	return holder.display_name() if holder != null else "sur soi"


func _cost_text(cost: float) -> String:
	return "gratuit" if cost <= 0.0 else "%.1f s" % cost


# --- Entrées ---

func _unhandled_input(event: InputEvent) -> void:
	if _mode == Mode.NONE:
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	get_viewport().set_input_as_handled()  # le jeu est en pause : le joueur ne reçoit rien
	if not key_event.pressed:
		return
	var key: Key = key_event.physical_keycode
	# W : on se fie à l'étiquette de la touche (en AZERTY, le W n'est pas à la même place physique qu'en QWERTY)
	if KeyUtil.is_letter(key_event, "w"):
		key = KEY_W
	elif key == KEY_W:
		key = KEY_NONE
	if _mode == Mode.SEQUENCE:
		if not key_event.echo:
			_skip_sequence()  # une touche = passer l'animation
		return
	if _mode == Mode.CONFIRM:
		if key_event.echo:
			return
		if KEYS_CONFIRM.has(key):
			_validate()
		elif key == KEY_ESCAPE:
			_cancel_confirm()
		elif key == KEY_U and key_event.shift_pressed:
			_reset_all()  # tout annuler (Maj+u seulement : u seul ne fait rien) : on referme sans avoir perdu une seconde
			_finish()
		return
	if _mode != Mode.PICK_CELL:
		if key == KEY_KP_8 or key == KEY_UP:
			_move_selection(-1)
			return
		if key == KEY_KP_2 or key == KEY_DOWN:
			_move_selection(1)
			return
		if KEYS_ADD.has(key):
			_hold_add()
			return
		if KEYS_REMOVE.has(key):
			_hold_decrease()
			return
	if key_event.echo:
		return
	_status = ""
	if key == KEY_U and key_event.shift_pressed:
		_reset_all()
	elif key == KEY_ESCAPE:
		_request_close()
	elif key == KEY_I:
		if _mode == Mode.INVENTORY:
			_request_close()
		else:
			_status = "Terminez le ramassage avant d'ouvrir l'inventaire."
	elif key == KEY_G and _mode == Mode.PICK_CELL:
		_request_close()
	elif key == KEY_G and key_event.shift_pressed and _mode == Mode.GROUND:
		_enter_mode(Mode.GROUND, true)  # toutes les cases à portée dans une seule liste
	elif _mode == Mode.PICK_CELL:
		_pick_cell_with_key(key)
	elif _selected >= 0:
		_run_action_for_key(key, key_event.shift_pressed)


func _pick_cell_with_key(key: Key) -> void:
	var digit: int = int(DIGIT_KEYS.get(key, ARROW_DIGITS.get(key, 0)))
	if digit == 0:
		return
	var cell: Vector2i = player.grid_pos + _offset_for_digit(digit)
	if player.world.get_ground_items(cell).is_empty() or not player.reach_cells().has(cell):
		return
	_ground_cells.clear()
	_ground_cells.append(cell)
	player.world.show_pick_overlay({})
	_mode = Mode.GROUND
	_selected = -1
	_rebuild()


func _run_action_for_key(key: Key, shift: bool) -> void:
	for a: Dictionary in _actions_for(_rows[_selected]):
		if not (a["keys"] as Array).has(key):
			continue
		if a.has("shift") and bool(a["shift"]) != shift:
			continue
		if String(a["blocked"]) != "":
			_status = "Impossible : %s." % a["blocked"]
		else:
			(a["run"] as Callable).call()
			_rebuild()
		_view.queue_redraw()
		return


func _process(delta: float) -> void:
	if _mode == Mode.NONE:
		return
	if _mode == Mode.SEQUENCE:
		_seq_timer -= delta
		_view.queue_redraw()  # le petit icône de chargement tourne
		if _seq_timer <= 0.0:
			_advance_sequence()
		return
	var mouse: Vector2 = _view.get_local_mouse_position()
	var index: int = -1
	for i in _hover_zones.size():
		if (_hover_zones[i]["rect"] as Rect2).has_point(mouse):
			index = i
			break
	if index != _hover_index:
		_hover_index = index
		_view.queue_redraw()


# --- Dessin ---

func _kg(value: float) -> String:
	return "%.2f kg" % value


func _item_text(row: Dictionary) -> String:
	var item := row["item"] as Item
	var text: String = String(row.get("prefix", "")) + item.display_name()
	if item.count > 1:
		text += " ×%d" % item.count
	if item.is_container():
		text += "  [%.1f/%.0f kg]" % [item.contents_real_weight(), item.weight_limit()]
	var entry: Dictionary = _entry_of(item)
	if not entry.is_empty():
		text += "   [sélection : %d]" % int(entry["qty"])
	return text


func _dest_text(item: Item, entry: Dictionary) -> String:
	var qty: int = entry["qty"]
	var dest: String = DEST_NAMES.get(String(entry["dest"]), "")
	if qty >= item.count:
		return "déplacé vers l'inventaire (%s)" % dest
	return "%d/%d déplacés vers l'inventaire (%s)" % [qty, item.count, dest]


func _item_right_text(row: Dictionary) -> String:
	var item := row["item"] as Item
	match String(row["state"]):
		"ground":
			var staged: Dictionary = _staged_entry(item)
			if not staged.is_empty():
				return _dest_text(item, staged)
			return "%s · %s" % [_kg(item.real_weight()), _cost_text(player.real_cost(player.pickup_base_cost(item)))]
		"pending_drop":
			return "posé au sol à la validation"
		"contained":
			return _kg(item.real_weight() / player.inventory.effective_ratio(item))
	return _kg(item.carried_weight())


func _draw_view() -> void:
	_hover_zones.clear()
	var font: Font = _view.get_theme_default_font()
	var view_size: Vector2 = _view.size
	if _mode == Mode.PICK_CELL:
		_draw_pick_banner(font, view_size)
		return
	if _mode == Mode.SEQUENCE:
		_draw_sequence_banner(font, view_size)
		return
	_draw_main(font, view_size, _prev_mode if _mode == Mode.CONFIRM else _mode)
	if _mode == Mode.CONFIRM:
		_draw_confirm(font, view_size)
	else:
		_draw_tooltip(font, view_size)


func _draw_pick_banner(font: Font, view_size: Vector2) -> void:
	var text: String = "Choisissez la case (touches affichées au sol) — Échap : fermer"
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 32.0
	var bar := Rect2(Vector2((view_size.x - width) / 2.0, 20), Vector2(width, 36))
	_view.draw_rect(bar, COLOR_PANEL)
	_view.draw_rect(bar, COLOR_BORDER, false, 2.0)
	_view.draw_string(font, bar.position + Vector2(16, 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_TEXT)


## Bannière centrée en haut de l'écran pendant les ramassages / dépôts : texte de l'étape + icône de chargement.
func _draw_sequence_banner(font: Font, view_size: Vector2) -> void:
	var text: String = ""
	if not _sequence.is_empty():
		text = "%s  (%d/%d)" % [_sequence[0]["text"], _seq_total - _sequence.size() + 1, _seq_total]
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 76.0
	var bar := Rect2(Vector2((view_size.x - width) / 2.0, 20), Vector2(width, 40))
	_view.draw_rect(bar, COLOR_PANEL)
	_view.draw_rect(bar, COLOR_BORDER, false, 2.0)
	var angle: float = float(Time.get_ticks_msec()) / 1000.0 * TAU
	_view.draw_arc(bar.position + Vector2(26, 20), 9.0, angle, angle + PI * 1.5, 20, COLOR_ACCENT, 3.0)
	_view.draw_string(font, bar.position + Vector2(48, 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_TEXT)


func _draw_main(font: Font, view_size: Vector2, shown: Mode) -> void:
	_view.draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_DIM)
	var panel := Rect2(Vector2.ONE * PANEL_MARGIN, view_size - Vector2.ONE * PANEL_MARGIN * 2.0)
	_view.draw_rect(panel, COLOR_PANEL)
	_view.draw_rect(panel, COLOR_BORDER, false, 2.0)

	var title: String = "INVENTAIRE"
	if shown == Mode.GROUND:
		title = "AU SOL (case %d)" % _digit_for_offset(_ground_cells[0] - player.grid_pos) if _ground_cells.size() == 1 \
			else "AU SOL (toutes les cases à portée)"
	_view.draw_string(font, panel.position + Vector2(16, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 4, COLOR_HEADER)
	var ratio: float = player.get_load_ratio()
	var load_text: String = "Charge : %.1f / %.1f kg (%d%%)%s" % [player.get_carry_weight(), player.get_carry_capacity(),
		roundi(ratio * 100.0), "  SURCHARGE !" if ratio > 1.0 else ""]
	_view.draw_string(font, panel.position + Vector2(16, 52), load_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		COLOR_WARN if ratio > 1.0 else COLOR_TEXT)
	_view.draw_string(font, Vector2(panel.position.x, panel.position.y + 28), "Temps cumulé (compté à la fermeture) : %s" % \
		_cost_text(player.real_cost(_total_base_cost())), HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 16, FONT_SIZE, COLOR_ACCENT)

	var list_rect := Rect2(panel.position + Vector2(12, 66), Vector2(panel.size.x * LIST_WIDTH_RATIO, panel.size.y - 66 - 56))
	var visible_rows: int = maxi(int(list_rect.size.y / ROW_HEIGHT), 1)
	if _selected >= 0:
		_scroll = clampi(_scroll, maxi(_selected - visible_rows + 1, 0), _selected)
	for i in range(_scroll, mini(_rows.size(), _scroll + visible_rows)):
		_draw_row(font, _rows[i], i == _selected, Rect2(list_rect.position + Vector2(0, (i - _scroll) * ROW_HEIGHT),
			Vector2(list_rect.size.x, ROW_HEIGHT)))

	var detail_pos := Vector2(list_rect.end.x + 24, list_rect.position.y)
	_view.draw_line(Vector2(detail_pos.x - 12, detail_pos.y), Vector2(detail_pos.x - 12, list_rect.end.y), COLOR_BORDER, 1.0)
	if _selected >= 0:
		_draw_details(font, _rows[_selected], detail_pos, panel.end.x - detail_pos.x - 16)

	if _status != "":
		_view.draw_string(font, Vector2(panel.position.x + 16, panel.end.y - 36), _status, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_WARN)
	var hint: String = "8/2 (ou flèches) : naviguer   4/+ : sélectionner   e : équiper   r : ranger   t : sortir   g : poser   u : annuler   U : tout annuler   Échap : fermer"
	if shown == Mode.GROUND:
		hint = "8/2 (ou flèches) : naviguer   4/+ : sélectionner   Entrée/g : ramasser   w : en main   W : équiper   u : annuler   U : tout annuler   G : tout   Échap : fermer"
	elif not _held.is_empty():
		hint = "4/+ : ajouter   − : retirer 1   6 : 1 de chaque   Entrée : tout   e : équiper   g : poser   U : tout annuler   Échap : fermer"
	_view.draw_string(font, Vector2(panel.position.x + 16, panel.end.y - 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_MUTED)


func _draw_row(font: Font, row: Dictionary, selected: bool, rect: Rect2) -> void:
	var baseline: float = rect.position.y + ROW_HEIGHT * 0.5 + FONT_SIZE * 0.35
	if row.get("header", false):
		_view.draw_string(font, Vector2(rect.position.x + 4, baseline), String(row["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_HEADER)
		return
	if row.get("item") == null:
		_view.draw_string(font, Vector2(rect.position.x + 12, baseline), String(row["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_MUTED)
		return
	var item := row["item"] as Item
	var state: String = row["state"]
	var staged: Dictionary = _staged_entry(item) if state == "ground" else {}
	var ghost: bool = state == "pending_drop" or (not staged.is_empty() and int(staged["qty"]) >= item.count)
	if not _entry_of(item).is_empty():
		_view.draw_rect(rect, COLOR_HELD)
	if selected:
		_view.draw_rect(rect, Color(COLOR_SELECTED, 0.5))
		_view.draw_rect(rect, COLOR_SELECTED, false, 2.0)
	var indent: float = float(row.get("depth", 0)) * INDENT
	var icon_box := Rect2(rect.position + Vector2(8 + indent, (ROW_HEIGHT - ICON_SIZE) / 2.0), Vector2(ICON_SIZE, ICON_SIZE))
	var tint: Color = Color(1, 1, 1, 0.4) if ghost else Color.WHITE
	if not UlticaTiles.draw_icon(_view, UlticaTiles.pick_sprite(item.tile_id(), "fg", 0), icon_box, tint):
		_view.draw_rect(icon_box.grow(-8), Color(0.85, 0.7, 0.3, tint.a))  # repli sans sprite
	_view.draw_string(font, Vector2(icon_box.end.x + 8, baseline), _item_text(row), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		COLOR_MUTED if ghost else COLOR_TEXT)
	var right_color: Color = COLOR_ACCENT if (ghost or not staged.is_empty()) else COLOR_MUTED
	_view.draw_string(font, Vector2(rect.position.x, baseline), _item_right_text(row), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, FONT_SIZE, right_color)


func _draw_details(font: Font, row: Dictionary, pos: Vector2, width: float) -> void:
	var item := row["item"] as Item
	var y: float = pos.y + 18
	_view.draw_string(font, Vector2(pos.x, y), item.display_name(), HORIZONTAL_ALIGNMENT_LEFT, width, FONT_SIZE + 2, COLOR_HEADER)
	y += 30
	_draw_weight_line(font, item, Vector2(pos.x, y))
	var lines: Array[String] = []
	var dims: Vector2 = item.size_dims()
	lines.append("Taille : %d × %d cm" % [dims.x, dims.y])
	if item.slot() != "":
		lines.append("Se porte : %s" % ItemDB.SLOT_NAMES.get(item.slot(), item.slot()))
	if item.is_container():
		var cd: Dictionary = item.container_def()
		lines.append("Conteneur : max %d × %d cm, limite %.0f kg" % [cd.get("max_length", 0), cd.get("max_width", 0), item.weight_limit()])
		var real: float = item.contents_real_weight()
		lines.append("Contenu : %.1f kg réels ÷ %s = %.1f kg portés" % [real, String.num(item.weight_ratio()), real / item.weight_ratio()])
	var staged_entry: Dictionary = _staged_entry(item) if String(row["state"]) == "ground" else {}
	if not staged_entry.is_empty():
		lines.append("Ramassage préparé : %s" % _dest_text(item, staged_entry))
	for line: String in lines:
		y += 22
		_view.draw_string(font, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, width, DETAIL_FONT_SIZE, COLOR_TEXT)
	if not _held.is_empty():
		y += 34
		_view.draw_string(font, Vector2(pos.x, y), "SÉLECTION (%s)" % _held_summary(), HORIZONTAL_ALIGNMENT_LEFT, width, DETAIL_FONT_SIZE, COLOR_ACCENT)
		for i in mini(_held.size(), MAX_SELECTION_LINES):
			y += 20
			_view.draw_string(font, Vector2(pos.x + 8, y), "• " + _label(_held[i]["item"] as Item, int(_held[i]["qty"])),
				HORIZONTAL_ALIGNMENT_LEFT, width, DETAIL_FONT_SIZE - 1, COLOR_TEXT)
		if _held.size() > MAX_SELECTION_LINES:
			y += 20
			_view.draw_string(font, Vector2(pos.x + 8, y), "… +%d" % (_held.size() - MAX_SELECTION_LINES),
				HORIZONTAL_ALIGNMENT_LEFT, width, DETAIL_FONT_SIZE - 1, COLOR_MUTED)
	y += 36
	_view.draw_string(font, Vector2(pos.x, y), "ACTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_FONT_SIZE, COLOR_HEADER)
	for a: Dictionary in _actions_for(row):
		y += 24
		var blocked: String = a["blocked"]
		var text: String
		if a["info"]:
			text = "[%s] %s" % [a["hint"], a["label"]] + (" : %s" % blocked if blocked != "" else "")
		else:
			text = "[%s] %s : %s" % [a["hint"], a["label"], blocked if blocked != "" else _cost_text(a["cost"])]
		_view.draw_string(font, Vector2(pos.x, y), text, HORIZONTAL_ALIGNMENT_LEFT, width, DETAIL_FONT_SIZE,
			COLOR_MUTED if blocked != "" else COLOR_TEXT)


## « Poids : 0.40 kg ÷ 2 × 4 = 0.80 kg » ; le diviseur (surligné) a une infobulle au survol de la souris.
func _draw_weight_line(font: Font, item: Item, pos: Vector2) -> void:
	var ratio: float = player.inventory.effective_ratio(item)
	var has_ratio: bool = not is_equal_approx(ratio, 1.0)
	var parts: Array[Dictionary] = [{"text": "Poids : %s" % _kg(item.unit_weight())}]
	if has_ratio:
		var holder: Item = player.inventory.find_holder(item)
		parts.append({"text": " ÷ "})
		parts.append({"text": String.num(ratio), "tip": "%s : poids ÷ %s" % [holder.display_name(), String.num(ratio)]})
	if item.count > 1:
		parts.append({"text": " × %d" % item.count})
	if has_ratio or item.count > 1:
		parts.append({"text": " = %s" % _kg(item.own_weight() / ratio)})
	var x: float = pos.x
	for part: Dictionary in parts:
		var text: String = part["text"]
		var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_FONT_SIZE)
		var tip: String = part.get("tip", "")
		var color: Color = COLOR_TEXT
		if tip != "":
			color = COLOR_ACCENT
			_view.draw_line(Vector2(x, pos.y + 3), Vector2(x + size.x, pos.y + 3), COLOR_ACCENT, 1.0)
			_hover_zones.append({"rect": Rect2(x - 3, pos.y - size.y, size.x + 6, size.y + 6), "tip": tip})
		_view.draw_string(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_FONT_SIZE, color)
		x += size.x


func _draw_tooltip(font: Font, view_size: Vector2) -> void:
	if _hover_index < 0 or _hover_index >= _hover_zones.size():
		return
	var text: String = _hover_zones[_hover_index]["tip"]
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_FONT_SIZE) + Vector2(20, 14)
	var pos: Vector2 = _view.get_local_mouse_position() + Vector2(14, 18)
	pos.x = minf(pos.x, view_size.x - size.x - 8)
	pos.y = minf(pos.y, view_size.y - size.y - 8)
	var box := Rect2(pos, size)
	_view.draw_rect(box, Color(0.05, 0.05, 0.07, 0.98))
	_view.draw_rect(box, COLOR_ACCENT, false, 1.0)
	_view.draw_string(font, pos + Vector2(10, size.y - 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_FONT_SIZE, COLOR_TEXT)


## Popup de fin de session : coût total en temps ; Validé (Entrée), Annulé (Échap : on continue) ou Tout annuler (U).
func _draw_confirm(font: Font, view_size: Vector2) -> void:
	_view.draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_DIM)
	var box := Rect2(view_size / 2.0 - Vector2(300, 95), Vector2(600, 190))
	_view.draw_rect(box, COLOR_PANEL)
	_view.draw_rect(box, COLOR_BORDER, false, 2.0)
	var cost: float = _confirm["cost"]
	var title: String = "Coût en temps : gratuit" if cost <= 0.0 else "Coût en temps : %.1f secondes" % cost
	_view.draw_string(font, box.position + Vector2(0, 40), title, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, FONT_SIZE + 4, COLOR_HEADER)
	_view.draw_string(font, box.position + Vector2(0, 64), "%d action(s)" % int(_confirm["moves"]),
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, DETAIL_FONT_SIZE, COLOR_MUTED)
	var labels: Array[String] = ["Validé  [Entrée]", "Annulé  [Échap]", "Tout annuler  [U]"]
	var colors: Array[Color] = [COLOR_OK, COLOR_ACCENT, COLOR_WARN]
	for i in 3:
		var button := Rect2(box.position + Vector2(16 + i * 192, 84), Vector2(184, 44))
		_view.draw_rect(button, Color(colors[i], 0.28))
		_view.draw_rect(button, colors[i], false, 2.0)
		_view.draw_string(font, button.position + Vector2(0, 28), labels[i], HORIZONTAL_ALIGNMENT_CENTER, button.size.x, FONT_SIZE, COLOR_TEXT)
	_view.draw_string(font, box.position + Vector2(0, 156), "Annulé : on continue de modifier.  Tout annuler : rien ne change, aucune seconde perdue.",
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 13, COLOR_MUTED)
