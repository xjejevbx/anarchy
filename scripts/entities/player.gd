class_name Player
extends Node2D
## Joueur : déplacement, combat de base, stamina, charge portée (inventaire), coût des actions en temps.

# --- Santé ---
const HP_MAX: float = 100.0

# --- Stamina et pénalité de temps ---
const STAMINA_MAX: float = 100.0
const STAMINA_STEP: float = 30.0        # tous les 30 % de stamina perdue...
const PENALTY_PER_STEP: float = 0.10    # ...les actions durent +10 %
const MAX_PENALTY_STEPS: int = 3        # plafond : +30 %

# --- Charge portée (style CDDA) ---
# ratio = poids porté / capacité
#   ratio < 1 : marcher REGAGNE de la stamina, de moins en moins vite en se chargeant
#   ratio = 1 : marcher n'a aucun effet sur la stamina
#   ratio > 1 : marcher FAIT PERDRE de la stamina, de plus en plus vite (courbe quadratique)
const MOVE_REGEN_MAX: float = 0.6       # gain max par déplacement (à vide)
const WAIT_REGEN_MAX: float = 0.85      # gain max en attendant (à vide) : un peu mieux que marcher
const OVERLOAD_DRAIN_LINEAR: float = 2.0
const OVERLOAD_DRAIN_QUAD: float = 4.0
const CAPACITY_BASE: float = 20.0       # kg portables sans équipement (+ bonus d'équipement éventuels)

# --- Inventaire : coûts en points d'action (avant pénalité de stamina) ---
const PICKUP_BASE_COST: float = 1.0     # ramasser = base + poids réel de l'objet (kg) x coût/kg
const PICKUP_COST_PER_KG: float = 0.8
const HANDLE_BASE_COST: float = 1.0     # ranger / sortir / poser depuis un conteneur
const HANDLE_COST_PER_KG: float = 0.4
const EQUIP_BASE_COST: float = 3.0      # équiper / retirer un vêtement (+ poids x HANDLE_COST_PER_KG)
const INVENTORY_STAMINA_DELTA: float = 0.0
# Poser un objet « sur soi » au sol est gratuit (0 point).
const START_EQUIPMENT: Array[String] = ["undershirt", "jeans", "sneakers"]
const START_LOOSE: Array[String] = ["knife_butter"]

# --- Coûts des actions ---
const MOVE_BASE_COST: float = 1.0       # en points d'action (1 point = 1 s)
const WAIT_BASE_COST: float = 1.0       # attendre dure autant que se déplacer
const PUNCH_BASE_COST: float = 2.0
const PUNCH_STAMINA_DELTA: float = -2.0
const PUNCH_DAMAGE: float = 6.0

# --- Touche maintenue = appuis répétés ---
const REPEAT_DELAY: float = 0.25        # pause avant que la répétition démarre
const REPEAT_INTERVAL: float = 0.07     # délai entre deux répétitions

var world: World
var grid_pos: Vector2i = Vector2i(5, 5)
var hp: float = HP_MAX
var dead: bool = false
var stamina: float = STAMINA_MAX
var inventory := Inventory.new()
var pending_drops: Array[Dictionary] = []  # {item, cell} : posés au sol seulement à la validation de l'inventaire
var input_blocked: bool = false         # vrai quand une interface (inventaire) est ouverte

var _bg_sprite: String = ""
var _fg_sprite: String = ""
var _held_key: Key = KEY_NONE
var _repeat_timer: float = 0.0

const MOVE_KEYS: Dictionary = {
	KEY_KP_8: Vector2i.UP, KEY_KP_2: Vector2i.DOWN, KEY_KP_4: Vector2i.LEFT, KEY_KP_6: Vector2i.RIGHT,
	KEY_UP: Vector2i.UP, KEY_DOWN: Vector2i.DOWN, KEY_LEFT: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT,  # = 8 2 4 6
	KEY_KP_7: Vector2i(-1, -1), KEY_KP_9: Vector2i(1, -1),
	KEY_KP_1: Vector2i(-1, 1), KEY_KP_3: Vector2i(1, 1),
}
const WAIT_KEYS: Array = [KEY_SPACE, KEY_PERIOD, KEY_KP_5]


func _ready() -> void:
	for item_id: String in START_EQUIPMENT:
		inventory.equip(Item.create(item_id))
	for item_id: String in START_LOOSE:
		inventory.add_loose(Item.create(item_id))
	position = Vector2(grid_pos * World.TILE_SIZE)
	_bg_sprite = UlticaTiles.pick_sprite("player_male", "bg", 0)
	_fg_sprite = UlticaTiles.pick_sprite("player_male", "fg", 0)
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(World.TILE_SIZE, World.TILE_SIZE) / 2.0
	EventBus.hostile_spotted.connect(func(_m: Node) -> void: _stop_repeat())
	_emit_stamina()
	_emit_load()
	EventBus.health_changed.emit(hp, HP_MAX)
	world.update_fov()  # vue initiale (sans ça, tout reste noir jusqu'au premier pas)


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if dead or key_event == null:
		return
	if input_blocked:
		_held_key = KEY_NONE
		return
	var key: Key = key_event.physical_keycode
	if not key_event.pressed:
		if key == _held_key:
			_held_key = KEY_NONE
		return
	if key_event.echo:
		return  # la répétition est gérée par _process (cadence fixe, indépendante de l'OS)
	if MOVE_KEYS.has(key) or WAIT_KEYS.has(key):
		_held_key = key  # avant l'action : elle peut interrompre la répétition
		_repeat_timer = REPEAT_DELAY
		_do_repeatable_action(key)
	elif KeyUtil.is_letter(key_event, "m"):  # lettre tapée (en AZERTY, le M n'est pas à la même place physique)
		EventBus.minimap_requested.emit()
	elif key == KEY_I:
		EventBus.inventory_requested.emit()
	elif key == KEY_G:
		if key_event.shift_pressed:
			EventBus.ground_all_requested.emit()
		else:
			EventBus.ground_requested.emit()


## Touche maintenue : chaque répétition est une action complète (temps, stamina, monstres...).
func _process(delta: float) -> void:
	if input_blocked:
		_held_key = KEY_NONE
	if dead or _held_key == KEY_NONE:
		return
	if not Input.is_physical_key_pressed(_held_key):
		_held_key = KEY_NONE
		return
	_repeat_timer -= delta
	if _repeat_timer <= 0.0:
		_repeat_timer = REPEAT_INTERVAL
		_do_repeatable_action(_held_key)


## Arrête la répétition (il faut relâcher puis réappuyer pour reprendre).
## Déclenché quand un ennemi apparaît ou quand on est blessé.
func _stop_repeat() -> void:
	_held_key = KEY_NONE


func _do_repeatable_action(key: Key) -> void:
	if MOVE_KEYS.has(key):
		var dir: Vector2i = MOVE_KEYS[key]
		if dir.x != 0 and dir.y != 0:
			_try_diagonal(dir)
		else:
			_try_move(dir)
	else:
		_wait()


## Pénalité de temps actuelle (0.0, 0.1, 0.2 ou 0.3).
func get_time_penalty() -> float:
	var lost: float = STAMINA_MAX - stamina
	var steps: int = mini(int(lost / STAMINA_STEP), MAX_PENALTY_STEPS)
	return steps * PENALTY_PER_STEP


## Poids porté (kg) : calculé depuis l'inventaire (réductions des conteneurs équipés comprises).
func get_carry_weight() -> float:
	return inventory.total_weight()


## Capacité (kg) : base du joueur + bonus de l'équipement.
func get_carry_capacity() -> float:
	return CAPACITY_BASE + inventory.capacity_bonus()


func get_load_ratio() -> float:
	return get_carry_weight() / maxf(get_carry_capacity(), 0.001)


## Variation de stamina pour UN déplacement, selon la charge.
## Positive = gain, négative = perte.
func get_move_stamina_delta() -> float:
	return _load_stamina_delta(MOVE_REGEN_MAX)


## Idem pour UNE attente : mêmes contraintes de charge, récupération un peu meilleure.
## Rester debout avec un sac trop lourd épuise autant que marcher avec.
func get_wait_stamina_delta() -> float:
	return _load_stamina_delta(WAIT_REGEN_MAX)


func _load_stamina_delta(regen_max: float) -> float:
	var ratio: float = get_load_ratio()
	if ratio <= 1.0:
		return regen_max * (1.0 - ratio)
	var over: float = ratio - 1.0
	return -(OVERLOAD_DRAIN_LINEAR * over + OVERLOAD_DRAIN_QUAD * over * over)


func take_damage(amount: float) -> void:
	if dead:
		return
	_stop_repeat()
	hp = maxf(hp - amount, 0.0)
	EventBus.health_changed.emit(hp, HP_MAX)
	if hp <= 0.0:
		dead = true
		EventBus.message_logged.emit("Vous êtes mort.")
		queue_redraw()


## Une diagonale n'est PAS un déplacement spécial : c'est « vertical + horizontal »
## (ex. bas + gauche), deux pas orthogonaux avec chacun son temps, sa stamina, et pendant
## lesquels les monstres peuvent agir. On passe par une case intermédiaire libre ; si la case
## visée est occupée par un monstre, le second pas devient une attaque.
func _try_diagonal(dir: Vector2i) -> void:
	var target: Vector2i = grid_pos + dir
	if world.get_monster_at(target) == null and not world.is_walkable(target):
		return
	for first: Vector2i in [Vector2i(0, dir.y), Vector2i(dir.x, 0)]:  # vertical d'abord, puis horizontal
		var middle: Vector2i = grid_pos + first
		if world.is_walkable(middle) and world.get_monster_at(middle) == null:
			_try_move(first)
			if not dead:
				_try_move(dir - first)
			return


func _try_move(dir: Vector2i) -> void:
	var target: Vector2i = grid_pos + dir
	var monster: Monster = world.get_monster_at(target)
	if monster != null:
		_attack(monster)
		return
	if not world.is_walkable(target):
		return
	grid_pos = target
	position = Vector2(grid_pos * World.TILE_SIZE)
	world.update_fov()  # avant que le temps passe : les monstres réagissent à ce que tu viens de révéler
	_perform_action("Déplacement", MOVE_BASE_COST, get_move_stamina_delta())


func _attack(monster: Monster) -> void:
	var monster_name: String = monster.data.display_name
	var killed: bool = monster.take_damage(PUNCH_DAMAGE)
	EventBus.message_logged.emit("Vous frappez %s : -%d PV." % [monster_name, int(PUNCH_DAMAGE)])
	if killed:
		EventBus.message_logged.emit("%s est mort." % monster_name)
		world.remove_monster(monster)
	else:
		monster.alert(grid_pos)  # frappé : il sait où tu es, même s'il ne te voyait pas
	_perform_action("Attaque", PUNCH_BASE_COST, PUNCH_STAMINA_DELTA)


func _wait() -> void:
	_perform_action("Attendre", WAIT_BASE_COST, get_wait_stamina_delta())


# --- Inventaire ---
# Les modifications s'appliquent tout de suite mais ne coûtent AUCUN temps sur le moment : InventoryLedger calcule à la
# fermeture de l'inventaire le coût NET des déplacements, puis InventoryUI appelle spend_inventory_time() à chaque étape.

func real_cost(base_cost: float) -> float:
	return base_cost * (1.0 + get_time_penalty())


func pickup_cost_for_weight(weight: float) -> float:
	return PICKUP_BASE_COST + weight * PICKUP_COST_PER_KG


func handle_cost_for_weight(weight: float) -> float:
	return HANDLE_BASE_COST + weight * HANDLE_COST_PER_KG


func equip_cost_for_weight(weight: float) -> float:
	return EQUIP_BASE_COST + weight * HANDLE_COST_PER_KG


## Chaque objet est sa propre action : une pile de n objets = n actions (une par unité).
func unit_count(item: Item, qty: int) -> int:
	if item.count <= 1:
		return 1
	return item.count if qty < 0 else clampi(qty, 1, item.count)


## Poids d'une unité : un objet unique pèse avec son contenu, une pile pèse n x poids unitaire.
func unit_weight_of(item: Item) -> float:
	return item.real_weight() if item.count <= 1 else item.unit_weight()


# Coûts « d'un seul geste » (aperçu dans l'interface ; le coût réel est le coût net de la session, objet par objet).
func pickup_base_cost(item: Item, qty: int = -1) -> float:
	return unit_count(item, qty) * pickup_cost_for_weight(unit_weight_of(item))


func handle_base_cost(item: Item, qty: int = -1) -> float:
	return unit_count(item, qty) * handle_cost_for_weight(unit_weight_of(item))


func equip_base_cost(item: Item) -> float:
	return equip_cost_for_weight(item.real_weight())


## Poser : gratuit si l'objet est « sur soi », habillage si équipé, sinon manipulation (sorti d'un conteneur).
func drop_base_cost(item: Item, qty: int = -1) -> float:
	if inventory.slot_of(item) != "":
		return equip_base_cost(item)
	return 0.0 if inventory.is_loose(item) else handle_base_cost(item, qty)


## À portée de main : la case du joueur et les 8 cases autour (aucun coût supplémentaire).
func reach_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			out.append(grid_pos + Vector2i(dx, dy))
	return out


func reach_cells_with_items() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in reach_cells():
		if not world.get_ground_items(cell).is_empty():
			out.append(cell)
	return out


## `dest` : "auto" (meilleur conteneur, sinon sur soi), "hand" (sur soi, en main) ou "equip" (équipé directement).
func pickup_item(item: Item, cell: Vector2i, qty: int = -1, dest: String = "auto") -> void:
	if not reach_cells().has(cell) or not world.get_ground_items(cell).has(item):
		return
	var n: int = item.count if qty < 0 else clampi(qty, 1, item.count)
	var taken: Item = item
	if n < item.count:
		taken = item.split(n)
		world.refresh_items()
	else:
		world.remove_ground_item(cell, item)
	match dest:
		"hand":
			inventory.add_loose(taken)
		"equip":
			if inventory.equip(taken) != "":
				inventory.auto_add(taken)
		_:
			inventory.auto_add(taken)
	_after_inventory_change()


## Poser au sol : l'objet quitte l'inventaire tout de suite mais n'apparaît au sol qu'à la validation (commit_pending_drop).
func drop_item(item: Item, qty: int = -1) -> void:
	pending_drops.append({"item": inventory.detach(item, qty), "cell": grid_pos})
	_after_inventory_change()


func cancel_pending_drop(item: Item) -> void:
	for d: Dictionary in pending_drops:
		if d["item"] == item:
			pending_drops.erase(d)
			inventory.add_loose(item)
			_after_inventory_change()
			return


## Pose réellement au sol `qty` unités (tout si qty < 0) d'un objet « à poser ».
func commit_pending_drop(entry: Dictionary, qty: int = -1) -> void:
	var item := entry["item"] as Item
	var unit: Item = item
	if qty > 0 and qty < item.count:
		unit = item.split(qty)
	else:
		pending_drops.erase(entry)
	world.add_ground_item(entry["cell"], unit)


func flush_pending_drops() -> void:
	for d: Dictionary in pending_drops.duplicate():
		commit_pending_drop(d)


## Renvoie "" si le rangement a eu lieu, sinon la raison du refus.
func store_item(item: Item, container: Item, qty: int = -1) -> String:
	var reason: String = inventory.store(item, container, qty)
	if reason == "":
		_after_inventory_change()
	return reason


func take_out_item(item: Item, qty: int = -1) -> void:
	inventory.take_out(item, qty)
	_after_inventory_change()


## Renvoie "" ou la raison du refus.
func equip_item(item: Item) -> String:
	var reason: String = inventory.equip(item)
	if reason == "":
		_after_inventory_change()
	return reason


func unequip_slot(slot: String) -> void:
	inventory.unequip(slot)
	_after_inventory_change()


## Chaque étape de la validation fait passer son propre temps (les monstres agissent entre deux étapes).
func spend_inventory_time(base_cost: float) -> void:
	if base_cost > 0.0:
		_perform_action("Inventaire", base_cost, INVENTORY_STAMINA_DELTA)


func log_inventory_summary(action_count: int, base_total: float) -> void:
	EventBus.message_logged.emit("Inventaire : %d action(s), %.1f s." % [action_count, real_cost(base_total)])


## À appeler après une modification directe de l'inventaire (poids affiché, vêtements visibles).
func refresh_inventory() -> void:
	_after_inventory_change()


func _after_inventory_change() -> void:
	_emit_load()
	queue_redraw()  # vêtements visibles sur le sprite


## Coût réel en temps = coût de base * (1 + pénalité de stamina).
## stamina_delta : positif = gain, négatif = perte.
func _perform_action(action_name: String, base_cost: float, stamina_delta: float) -> void:
	var cost: float = base_cost * (1.0 + get_time_penalty())
	stamina = clampf(stamina + stamina_delta, 0.0, STAMINA_MAX)
	EventBus.action_performed.emit(action_name, cost, stamina_delta)
	GameClock.advance(cost)  # les monstres agissent pendant ce temps (voir World)
	_emit_stamina()


func _emit_stamina() -> void:
	EventBus.stamina_changed.emit(stamina, STAMINA_MAX, get_time_penalty())


func _emit_load() -> void:
	EventBus.load_changed.emit(get_carry_weight(), get_carry_capacity())


func _draw() -> void:
	var tint: Color = Color(0.45, 0.45, 0.45) if dead else Color.WHITE
	UlticaTiles.draw_sprite(self, _bg_sprite, Vector2.ZERO, tint)
	UlticaTiles.draw_sprite(self, _fg_sprite, Vector2.ZERO, tint)
	for slot: String in ItemDB.WORN_DRAW_ORDER:  # vêtements portés, par-dessus le mannequin
		var worn := inventory.equipment.get(slot) as Item
		if worn != null:
			UlticaTiles.draw_sprite(self, UlticaTiles.pick_sprite(worn.worn_tile(), "fg", 0), Vector2.ZERO, tint)
