class_name Player
extends Node2D
## Joueur : déplacement, combat de base, santé par parties du corps, stamina, charge portée (inventaire), coût des actions en temps,
## posture (marche / sprint / accroupi), nage et noyade, zoom de la caméra, déplacements automatiques (touche maintenue, double-clic).

# --- Santé : une jauge de PV par partie du corps (data/body_parts.json, BodyPartDB) ---
# Mort : tête ou torse à 0 PV. Les membres à 0 PV n'ont pas encore d'effet.

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

# --- Nage (jalon 9b) : toute eau (peu profonde ou profonde) se traverse à la nage ---
# En nageant : la posture est ignorée ; chaque pas COÛTE de la stamina (plus en eau profonde) + la perte de surcharge habituelle.
# Attendre en eau peu profonde = faire la planche : même récupération qu'attendre à terre (une surcharge fait perdre de la stamina).
# Attendre en eau profonde = faire du surplace : coût fixe + surcharge, jamais de récupération.
# Stamina à 0 dans l'eau : noyade, dégâts (au torse) proportionnels à la durée de chaque action.
const SWIM_STAMINA_SHALLOW: float = 1.0       # perte par pas en eau peu profonde
const SWIM_STAMINA_DEEP: float = 2.5          # perte par pas en eau profonde
const SWIM_TREAD_STAMINA_DEEP: float = 1.0    # perte par attente (ou geste d'inventaire) en eau profonde
const DROWN_DAMAGE_PER_SECOND: float = 2.0    # PV perdus par seconde d'action quand on se noie
const SWIM_REPEAT_MIN_STAMINA: float = 20.0   # touche maintenue : la nage automatique s'arrête sous ce niveau de stamina

# --- Posture (touche |) : indices de Posture ---
enum Posture { WALK, SPRINT, CROUCH }
const POSTURE_NAMES: Array[String] = ["Marche", "Sprint", "Accroupi"]
const POSTURE_TIME_FACTOR: Array[float] = [1.0, 0.7, 1.5]     # multiplie la durée d'un déplacement
const POSTURE_MOVE_STAMINA: Array[float] = [0.0, -1.0, 0.3]   # ajouté à la variation de stamina de chaque déplacement
const POSTURE_DETECT_FACTOR: Array[float] = [1.0, 1.5, 0.5]   # multiplie la portée de détection des monstres

# --- Zoom de la caméra (touches + et -) ---
# 1 case = 128 px (sprites x4) : 0.25 = l'ancien zoom 1.0 (cases de 32 px).
const ZOOM_LEVELS: Array[float] = [0.125, 0.25, 0.375, 0.5, 0.75]
const ZOOM_START_INDEX: int = 1

# --- Déplacements automatiques ---
const AUTO_LOOKAHEAD: int = 12          # touche maintenue : on vise la case la plus lointaine connue dans cette direction
const AUTO_CLEAR_RANGE: int = 4         # tant que ces cases devant sont libres, on avance tout droit
const TRAVEL_MAX_RADIUS: int = 45       # double-clic : le chemin reste dans ce carré autour du joueur

# --- Esquive automatique du décor (option du menu |) ---
# Un appui sur une direction (orthogonale) bloquée par le décor (arbre, mur, meuble...) contourne l'obstacle : petit détour de
# quelques pas qui se termine une case plus loin dans la direction demandée. Sert aussi à la touche maintenue. Utilise le terrain
# RÉEL des cases (pas besoin d'avoir la vue derrière l'arbre) et ne s'engage jamais dans l'eau si on n'y est pas déjà.
const DODGE_RADIUS: int = 3             # écart latéral maximal du détour (cases)
const DODGE_MAX_STEPS: int = 6          # longueur maximale du détour (pas)

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
var body: Dictionary = {} # id de partie du corps (data/body_parts.json) -> PV
var dead: bool = false
var stamina: float = STAMINA_MAX
var inventory := Inventory.new()
var pending_drops: Array[Dictionary] = []  # {item, cell} : posés au sol seulement à la validation de l'inventaire
var input_blocked: bool = false         # vrai quand une interface (inventaire, écran personnage...) est ouverte
var camera: Camera2D
var zoom_index: int = ZOOM_START_INDEX
var posture: int = Posture.WALK
var stats: Dictionary = {}              # id de stat (data/stats.json) -> valeur
var avoid_scenery: bool = true          # option « esquive automatique du décor » (menu |)

var _bg_sprite: String = ""
var _fg_sprite: String = ""
var _held_key: Key = KEY_NONE
var _repeat_timer: float = 0.0
var _travel_path: Array[Vector2i] = []  # déplacement automatique en cours (double-clic) : cases restant à parcourir
var _travel_timer: float = 0.0
var _has_target: bool = false           # une case ciblée est affichée (carré + trajet), voir World.show_target
var _target_cell: Vector2i = Vector2i.ZERO
var _target_from: Vector2i = Vector2i.ZERO   # position du joueur lors du dernier calcul du trajet affiché
var _target_travelling: bool = false         # état « déplacement lancé » lors du dernier affichage
var _dodge_side: int = 1                # côté préféré du dernier détour (+1 / -1) : évite de zigzaguer d'un côté à l'autre
var _hostile_seen: bool = false         # un monstre est apparu pendant un détour (le détour s'arrête)
var _shift_released_msec: int = -1000
var _announced_swim: int = TerrainDB.SWIM_NONE  # dernière profondeur annoncée dans le journal (évite de répéter le message)
var _anim_time: float = 0.0             # animation purement visuelle (voir Fx)
var _hop: float = 0.0                   # rebond pendant un pas (pixels)
var _breath: float = 0.0                # respiration à l'arrêt (étirement vertical)

const MOVE_KEYS: Dictionary = {
	KEY_KP_8: Vector2i.UP, KEY_KP_2: Vector2i.DOWN, KEY_KP_4: Vector2i.LEFT, KEY_KP_6: Vector2i.RIGHT,
	KEY_UP: Vector2i.UP, KEY_DOWN: Vector2i.DOWN, KEY_LEFT: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT,  # = 8 2 4 6
	KEY_KP_7: Vector2i(-1, -1), KEY_KP_9: Vector2i(1, -1),
	KEY_KP_1: Vector2i(-1, 1), KEY_KP_3: Vector2i(1, 1),
}
const WAIT_KEYS: Array = [KEY_SPACE, KEY_PERIOD, KEY_KP_5]
# Maj + pavé numérique (VerrNum actif) : Windows peut envoyer la touche de navigation correspondante (Début, Fin...) au lieu du pavé.
const LOOK_NAV_KEYS: Dictionary = {
	KEY_HOME: Vector2i(-1, -1), KEY_PAGEUP: Vector2i(1, -1), KEY_END: Vector2i(-1, 1), KEY_PAGEDOWN: Vector2i(1, 1),
	KEY_CLEAR: Vector2i.ZERO,
}
# Windows simule un « Maj relâché » juste avant une touche du pavé tapée avec Maj : on considère Maj enfoncé s'il vient d'être relâché.
const SHIFT_GRACE_MSEC: int = 80

func _ready() -> void:
	for stat_id: String in StatDB.ids():
		stats[stat_id] = StatDB.base_of(stat_id)
	for part_id: String in BodyPartDB.ids():
		body[part_id] = BodyPartDB.max_hp_of(part_id)
	for item_id: String in START_EQUIPMENT:
		inventory.equip(Item.create(item_id))
	for item_id: String in START_LOOSE:
		inventory.add_loose(Item.create(item_id))
	position = Vector2(grid_pos * World.TILE_SIZE)
	_bg_sprite = UlticaTiles.pick_sprite("player_male", "bg", 0)
	_fg_sprite = UlticaTiles.pick_sprite("player_male", "fg", 0)
	camera = Camera2D.new()
	add_child(camera)
	camera.position = Vector2(World.TILE_SIZE, World.TILE_SIZE) / 2.0
	camera.zoom = Vector2.ONE * ZOOM_LEVELS[zoom_index]
	EventBus.hostile_spotted.connect(_on_hostile_spotted)
	_emit_stamina()
	_emit_load()
	_emit_health()
	EventBus.posture_changed.emit(posture_name())
	world.update_fov()  # vue initiale (sans ça, tout reste noir jusqu'au premier pas)


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	if key_event.physical_keycode == KEY_SHIFT and not key_event.pressed:
		_shift_released_msec = Time.get_ticks_msec()
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
	_travel_path.clear()  # toute touche interrompt un déplacement automatique
	# Mode regard (LookUI) : x, ou Maj + pavé numérique / flèches. Déplace la caméra, pas le joueur ; ne coûte aucun temps.
	if KeyUtil.is_letter(key_event, "x"):
		EventBus.look_requested.emit(Vector2i.ZERO)
		return
	var nav_key: Key = key if LOOK_NAV_KEYS.has(key) else key_event.keycode
	if _shift_held(key_event) and (MOVE_KEYS.has(key) or key == KEY_KP_5 or LOOK_NAV_KEYS.has(nav_key)):
		var look_direction: Vector2i = MOVE_KEYS.get(key, LOOK_NAV_KEYS.get(nav_key, Vector2i.ZERO))
		EventBus.look_requested.emit(look_direction)
		return
	var zoom_step: int = _zoom_direction(key_event)
	if zoom_step != 0:
		_change_zoom(zoom_step)
	elif MOVE_KEYS.has(key) or WAIT_KEYS.has(key):
		_held_key = key  # avant l'action : elle peut interrompre la répétition
		_repeat_timer = REPEAT_DELAY
		_do_repeatable_action(key)
	elif KeyUtil.is_letter(key_event, "m"):  # lettre tapée (en AZERTY, le M n'est pas à la même place physique)
		EventBus.minimap_requested.emit()
	elif KeyUtil.is_letter(key_event, "c"):
		EventBus.character_requested.emit()
	elif key_event.unicode == 124:  # « | » (AltGr + 6 en AZERTY) : détecté par le caractère tapé
		EventBus.posture_requested.emit()
	elif key == KEY_I:
		EventBus.inventory_requested.emit()
	elif key == KEY_G:
		if key_event.shift_pressed:
			EventBus.ground_all_requested.emit()
		else:
			EventBus.ground_requested.emit()

## Un monstre apparaît : le déplacement automatique (double-clic, *) s'arrête, mais la touche MAINTENUE continue
## (elle ne s'arrête que si le joueur est blessé : voir take_damage).
func _on_hostile_spotted(_monster: Node) -> void:
	_travel_path.clear()
	_hostile_seen = true

## Maj enfoncé ? Tient compte du faux « Maj relâché » que Windows envoie juste avant une touche du pavé numérique tapée avec Maj.
func _shift_held(event: InputEventKey) -> bool:
	return event.shift_pressed or Input.is_physical_key_pressed(KEY_SHIFT) \
		or Time.get_ticks_msec() - _shift_released_msec < SHIFT_GRACE_MSEC

## +1 (zoomer), -1 (dézoomer), 0 sinon. Détecté par le caractère tapé (en AZERTY, « - » est sur la touche 6) ou le pavé numérique.
func _zoom_direction(event: InputEventKey) -> int:
	if event.physical_keycode == KEY_KP_ADD or event.unicode == 43 or event.unicode == 61:
		return 1
	if event.physical_keycode == KEY_KP_SUBTRACT or event.unicode == 45:
		return -1
	return 0

## Applique le zoom demandé par la touche (utilisé aussi par le mode regard). Renvoie true si la touche était une touche de zoom.
func try_zoom(event: InputEventKey) -> bool:
	var step: int = _zoom_direction(event)
	if step == 0:
		return false
	_change_zoom(step)
	return true

## Le champ de vision ne change pas : en dézoomant, le brouillard (FogLayer) couvre simplement plus de cases.
func _change_zoom(step: int) -> void:
	var index: int = clampi(zoom_index + step, 0, ZOOM_LEVELS.size() - 1)
	if index == zoom_index:
		return
	zoom_index = index
	camera.zoom = Vector2.ONE * ZOOM_LEVELS[zoom_index]
	world.fog.queue_redraw()


## Clic gauche sur une case : elle devient la case ciblée (carré blanc + points du trajet). Double-clic : déplacement automatique.
func _on_mouse_button(button: InputEventMouseButton) -> void:
	if input_blocked or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := Vector2i((world.get_global_mouse_position() / World.TILE_SIZE).floor())
	if button.double_click:
		_start_travel(cell)
	else:
		set_target(cell)

## Déplacement automatique vers une case (même système que le double-clic) : utilisé par le mode regard (touche *).
func travel_to(cell: Vector2i) -> void:
	_start_travel(cell)

func _start_travel(cell: Vector2i) -> void:
	if cell == grid_pos:
		return
	set_target(cell)
	if not world.is_visible_cell(cell):
		EventBus.message_logged.emit("Vous ne voyez pas cette case.")
		return
	if not world.is_walkable(cell) or world.get_monster_at(cell) != null:
		EventBus.message_logged.emit("Impossible de s'y rendre.")  # y compris l'eau profonde : on s'y jette case par case
		return
	var path: Array[Vector2i] = AutoPath.find(world, grid_pos, cell, TRAVEL_MAX_RADIUS)
	if path.size() < 2:
		EventBus.message_logged.emit("Aucun chemin connu vers cette case.")
		return
	_stop_repeat()
	path.remove_at(0)
	_travel_path = path
	_travel_timer = 0.0
	_update_target()  # le contour passe au vert tout de suite


## Un pas du déplacement automatique. Les pas diagonaux (cases voisines en diagonale dans le chemin) déplacent directement le
## joueur sur la case en diagonale, sans passer par une case intermédiaire, mais comptent pour DEUX déplacements (temps, stamina).
func _travel_step() -> void:
	var next: Vector2i = _travel_path[0]
	var step: Vector2i = next - grid_pos
	if maxi(absi(step.x), absi(step.y)) != 1 or not world.is_walkable(next) or world.get_monster_at(next) != null:
		_travel_path.clear()  # chemin bloqué
		return
	if step.x != 0 and step.y != 0:
		if not _diagonal_passable(step):
			_travel_path.clear()
			return
		_travel_path.remove_at(0)
		_move_diagonal_direct(step)
		return
	_travel_path.remove_at(0)
	_try_move(step)


## Une diagonale est permise si l'une des deux cases « de l'angle » est libre (même règle que _try_diagonal, pour les touches 7 9 1 3).
func _diagonal_passable(dir: Vector2i) -> bool:
	for first: Vector2i in [Vector2i(0, dir.y), Vector2i(dir.x, 0)]:
		var middle: Vector2i = grid_pos + first
		if world.can_player_enter(middle) and world.get_monster_at(middle) == null:
			return true
	return false


## Déplacement diagonal direct (déplacement automatique) : le joueur arrive tout de suite sur la case en diagonale, puis le temps
## de DEUX déplacements passe, un par un (les monstres peuvent agir entre les deux).
func _move_diagonal_direct(dir: Vector2i) -> void:
	var from_cell: Vector2i = grid_pos
	var was_swimming: bool = is_swimming()
	grid_pos += dir
	position = Vector2(grid_pos * World.TILE_SIZE)
	world.update_fov()  # avant que le temps passe : les monstres réagissent à ce que tu viens de révéler
	_announce_swim()
	var swimming: bool = is_swimming()
	Fx.footstep(world, from_cell, grid_pos, posture == Posture.SPRINT, posture == Posture.CROUCH, was_swimming, swimming)
	var time_factor: float = 1.0 if swimming else POSTURE_TIME_FACTOR[posture]
	for i in 2:
		if dead:
			return
		_perform_action("Nage" if swimming else "Déplacement", MOVE_BASE_COST * time_factor, get_move_stamina_delta())


# --- Case ciblée (carré + trajet affichés par World) ---

## Désigne une case : carré blanc autour d'elle et points sur le trajet qu'emprunterait le déplacement automatique.
func set_target(cell: Vector2i) -> void:
	if cell == grid_pos:
		clear_target()
		return
	_travel_path.clear()  # choisir une autre case interrompt un déplacement en cours
	_has_target = true
	_target_cell = cell
	_target_from = grid_pos
	_target_travelling = not _travel_path.is_empty()
	_refresh_target()


func clear_target() -> void:
	_has_target = false
	world.clear_target()


## Appelé à chaque image : suit les déplacements du joueur (trajet raccourci / recalculé), passe le contour au vert pendant le
## déplacement automatique, efface la case une fois atteinte.
func _update_target() -> void:
	if not _has_target:
		return
	if grid_pos == _target_cell:
		clear_target()
		return
	var travelling: bool = not _travel_path.is_empty()
	if grid_pos != _target_from or travelling != _target_travelling:
		_target_from = grid_pos
		_target_travelling = travelling
		_refresh_target()


func _refresh_target() -> void:
	var path: Array[Vector2i] = []
	if not _travel_path.is_empty():
		path.append(grid_pos)       # déplacement lancé : on montre ce qui reste du chemin réellement suivi
		path.append_array(_travel_path)
	else:
		path = AutoPath.find(world, grid_pos, _target_cell, TRAVEL_MAX_RADIUS)
	world.show_target(_target_cell, path, not _travel_path.is_empty())


## Touche maintenue : chaque répétition est une action complète (temps, stamina, monstres...).
func _process(delta: float) -> void:
	_update_visual(delta)
	_update_target()
	if input_blocked:
		_held_key = KEY_NONE
		_travel_path.clear()
	if dead:
		return
	if not _travel_path.is_empty():
		_travel_timer -= delta
		if _travel_timer <= 0.0:
			_travel_timer = REPEAT_INTERVAL
			_travel_step()
		return
	if _held_key == KEY_NONE:
		return
	if not Input.is_physical_key_pressed(_held_key):
		_held_key = KEY_NONE
		return
	_repeat_timer -= delta
	if _repeat_timer <= 0.0:
		_repeat_timer = REPEAT_INTERVAL
		_repeat_action(_held_key)


## Purement visuel : le sprite (et la caméra, qui en est l'enfant) glisse vers la case logique, déjà atteinte, avec un petit
## rebond ; à l'arrêt, une légère respiration. Ne retarde jamais une action (voir Fx).
func _update_visual(delta: float) -> void:
	var left: float = Fx.glide(self, Vector2(grid_pos * World.TILE_SIZE), delta)
	_anim_time += delta
	_hop = 0.0 if is_swimming() else Fx.hop_of(left)
	_breath = 0.0 if (left > 0.0 or dead) else sin(_anim_time * 2.2) * Fx.BREATH
	if Fx.SMOOTH_MOVE:
		queue_redraw()


## Arrête la répétition et tout déplacement automatique (il faut relâcher puis réappuyer pour reprendre).
## Déclenché quand un ennemi apparaît ou quand on est blessé.
func _stop_repeat() -> void:
	_held_key = KEY_NONE
	_travel_path.clear()


func _do_repeatable_action(key: Key) -> void:
	if MOVE_KEYS.has(key):
		var dir: Vector2i = MOVE_KEYS[key]
		if dir.x != 0 and dir.y != 0:
			_try_diagonal(dir)
		else:
			_move_with_dodge(dir)
	else:
		_wait()


## Répétition d'une touche maintenue : tout droit tant que c'est libre, sinon un chemin qui contourne les obstacles connus.
## Dans l'eau, la répétition continue de nager (tout droit) tant que la stamina reste au-dessus de SWIM_REPEAT_MIN_STAMINA.
func _repeat_action(key: Key) -> void:
	if not MOVE_KEYS.has(key):
		_wait()
		return
	if is_swimming() and stamina < SWIM_REPEAT_MIN_STAMINA:
		_stop_repeat()  # à bout de souffle : c'est au joueur de décider (flotter, rejoindre la rive...)
		return
	var dir: Vector2i = MOVE_KEYS[key]
	if _ray_clear(dir):
		_do_repeatable_action(key)
		return
	if avoid_scenery and (dir.x == 0 or dir.y == 0):
		# Esquive du décor : on avance tant que la case devant est libre (même inconnue), on contourne l'obstacle sinon.
		var ahead: Vector2i = grid_pos + dir
		if world.get_monster_at(ahead) == null:
			if world.is_walkable(ahead) or (is_swimming() and world.can_player_enter(ahead)):
				_do_repeatable_action(key)
				return
			if not world.can_player_enter(ahead) and _dodge(dir):
				return
		_stop_repeat()  # monstre devant, eau profonde depuis la rive ou détour impossible
		return
	var target: Vector2i = _lookahead_target(dir)
	if target != grid_pos:
		var path: Array[Vector2i] = AutoPath.find(world, grid_pos, target, AUTO_LOOKAHEAD + 6, dir)
		if path.size() >= 2 and world.get_monster_at(path[1]) == null:
			_try_move(path[1] - grid_pos)
			return
	_stop_repeat()  # rien de praticable devant


# --- Esquive automatique du décor ---

func set_avoid_scenery(value: bool) -> void:
	avoid_scenery = value
	EventBus.message_logged.emit("Esquive automatique du décor : %s." % ("OUI" if value else "NON"))


## Pas orthogonal dans la direction `dir` ; si le décor bloque la case devant (et qu'aucun monstre ne s'y trouve) et que l'option est
## active, on contourne l'obstacle. Sans détour possible, rien ne se passe (comme avant).
func _move_with_dodge(dir: Vector2i) -> void:
	var target: Vector2i = grid_pos + dir
	if avoid_scenery and world.get_monster_at(target) == null and not world.can_player_enter(target) and _dodge(dir):
		return
	_try_move(dir)


## Joue le détour (un vrai déplacement par pas : temps, stamina, monstres). false s'il n'y a pas de détour.
## Il s'interrompt si un monstre apparaît, si on est blessé ou si la route est prise.
func _dodge(dir: Vector2i) -> bool:
	var path: Array[Vector2i] = _dodge_path(dir)
	if path.is_empty():
		return false
	_hostile_seen = false
	var hp_before: float = total_hp()
	for cell: Vector2i in path:
		if dead or _hostile_seen or total_hp() < hp_before or world.get_monster_at(cell) != null:
			break
		var step: Vector2i = cell - grid_pos
		if absi(step.x) + absi(step.y) != 1:
			break
		_try_move(step)
	return true


## Plus court détour (parcours en largeur, 4 directions) vers une case située UNE case plus loin dans la direction `dir`, sans jamais
## reculer, à au plus DODGE_RADIUS cases de côté et DODGE_MAX_STEPS pas. Le côté du dernier détour est essayé en premier.
func _dodge_path(dir: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var origin: Vector2i = grid_pos
	var base_perp := Vector2i(-dir.y, dir.x)
	var perp: Vector2i = base_perp * _dodge_side
	var dirs: Array[Vector2i] = [dir, perp, -perp]
	var swimmer: bool = is_swimming()
	var came: Dictionary = {origin: origin}
	var depth: Dictionary = {origin: 0}
	var queue: Array[Vector2i] = [origin]
	var head: int = 0
	while head < queue.size():
		var node: Vector2i = queue[head]
		head += 1
		var d: int = int(depth[node])
		if d >= DODGE_MAX_STEPS:
			continue
		for step in dirs:
			var next: Vector2i = node + step
			if came.has(next):
				continue
			var off: Vector2i = next - origin
			var along: int = off.x * dir.x + off.y * dir.y
			var lateral: int = off.x * base_perp.x + off.y * base_perp.y
			if along < 0 or along > 1 or absi(lateral) > DODGE_RADIUS:
				continue
			if not _dodge_cell_ok(next, swimmer):
				continue
			came[next] = node
			depth[next] = d + 1
			if along == 1:
				if lateral != 0:
					_dodge_side = signi(lateral)
				var path: Array[Vector2i] = [next]
				var current: Vector2i = next
				while came[current] != origin:
					current = came[current]
					path.append(current)
				path.reverse()
				return path
			queue.append(next)
	return empty


## Case utilisable pour un détour : libre de monstre, praticable à pied et hors de l'eau (sauf si on nage déjà).
func _dodge_cell_ok(cell: Vector2i, swimmer: bool) -> bool:
	if world.get_monster_at(cell) != null:
		return false
	if swimmer:
		return world.can_player_enter(cell)
	return world.is_walkable(cell) and world.swim_depth(cell) == TerrainDB.SWIM_NONE


## Cases devant libres : praticables à pied et connues ; en nageant, l'eau profonde connue compte aussi (jamais depuis la rive).
func _ray_clear(dir: Vector2i) -> bool:
	var in_water: bool = is_swimming()
	for k in range(1, AUTO_CLEAR_RANGE + 1):
		var cell: Vector2i = grid_pos + dir * k
		if not (world.is_known_walkable(cell) or (in_water and world.is_known_deep_water(cell))):
			return false
	return true


## Case connue et praticable la plus lointaine dans la direction (jusqu'à AUTO_LOOKAHEAD), grid_pos s'il n'y en a aucune.
func _lookahead_target(dir: Vector2i) -> Vector2i:
	for k in range(AUTO_LOOKAHEAD, 0, -1):
		var cell: Vector2i = grid_pos + dir * k
		if world.is_known_walkable(cell):
			return cell
	return grid_pos


# --- Posture ---

func posture_name() -> String:
	return POSTURE_NAMES[posture]


## Facteur appliqué à la portée de détection des monstres (sprint : ils entendent de plus loin ; accroupi : de moins loin).
func get_detect_factor() -> float:
	return POSTURE_DETECT_FACTOR[posture]


## Changer de posture est gratuit (aucun temps), mais interrompt un déplacement automatique.
func set_posture(new_posture: int) -> void:
	new_posture = clampi(new_posture, 0, POSTURE_NAMES.size() - 1)
	if new_posture == posture:
		return
	posture = new_posture
	_stop_repeat()
	EventBus.posture_changed.emit(posture_name())
	EventBus.message_logged.emit("Posture : %s." % posture_name())


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

# --- Santé par parties du corps ---

## PV actuels d'une partie du corps (id de data/body_parts.json).
func part_hp(part_id: String) -> float:
	return float(body.get(part_id, 0.0))


## PV totaux (somme des parties) : affichage du HUD.
func total_hp() -> float:
	var total: float = 0.0
	for part_id: String in body:
		total += float(body[part_id])
	return total


# --- Nage ---

## Profondeur de nage de la case du joueur (TerrainDB.SWIM_NONE / SWIM_SHALLOW / SWIM_DEEP).
func swim_depth() -> int:
	return world.swim_depth(grid_pos) if world != null else TerrainDB.SWIM_NONE


func is_swimming() -> bool:
	return swim_depth() != TerrainDB.SWIM_NONE


## Perte de stamina due à la surcharge (0 si ratio <= 1) : courbe quadratique, commune à la marche et à la nage.
static func overload_drain(ratio: float) -> float:
	var over: float = ratio - 1.0
	if over <= 0.0:
		return 0.0
	return OVERLOAD_DRAIN_LINEAR * over + OVERLOAD_DRAIN_QUAD * over * over


## Variation de stamina à terre selon la charge : gain jusqu'à regen_max à vide, nul à ratio 1, perte au-delà.
static func load_stamina_delta(ratio: float, regen_max: float) -> float:
	if ratio <= 1.0:
		return regen_max * (1.0 - ratio)
	return -overload_drain(ratio)


## Variation de stamina pour UN pas à la nage (toujours négative).
static func swim_move_stamina_delta(depth: int, ratio: float) -> float:
	var base: float = SWIM_STAMINA_DEEP if depth >= TerrainDB.SWIM_DEEP else SWIM_STAMINA_SHALLOW
	return -base - overload_drain(ratio)


## Variation de stamina pour UNE attente (ou un geste) dans l'eau : planche en eau peu profonde, surplace en eau profonde.
static func swim_wait_stamina_delta(depth: int, ratio: float) -> float:
	if depth >= TerrainDB.SWIM_DEEP:
		return -SWIM_TREAD_STAMINA_DEEP - overload_drain(ratio)
	return load_stamina_delta(ratio, WAIT_REGEN_MAX)


## PV perdus pour une action de `action_cost` secondes quand on se noie.
static func drown_damage(action_cost: float) -> float:
	return DROWN_DAMAGE_PER_SECOND * action_cost


## Variation de stamina pour UN déplacement, selon la charge et la posture (ou la nage : la posture est alors ignorée).
## Positive = gain, négative = perte.
func get_move_stamina_delta() -> float:
	var depth: int = swim_depth()
	if depth != TerrainDB.SWIM_NONE:
		return swim_move_stamina_delta(depth, get_load_ratio())
	return load_stamina_delta(get_load_ratio(), MOVE_REGEN_MAX) + POSTURE_MOVE_STAMINA[posture]


## Idem pour UNE attente : mêmes contraintes de charge, récupération un peu meilleure.
## Rester debout avec un sac trop lourd épuise autant que marcher avec. Dans l'eau : voir swim_wait_stamina_delta.
func get_wait_stamina_delta() -> float:
	var depth: int = swim_depth()
	if depth != TerrainDB.SWIM_NONE:
		return swim_wait_stamina_delta(depth, get_load_ratio())
	return load_stamina_delta(get_load_ratio(), WAIT_REGEN_MAX)


## Message du journal quand on entre dans l'eau, qu'on change de profondeur ou qu'on reprend pied.
func _announce_swim() -> void:
	var depth: int = swim_depth()
	if depth == _announced_swim:
		return
	_announced_swim = depth
	match depth:
		TerrainDB.SWIM_NONE:
			EventBus.message_logged.emit("Vous reprenez pied.")
		TerrainDB.SWIM_SHALLOW:
			EventBus.message_logged.emit("Vous nagez (eau peu profonde) : attendre permet de flotter et de récupérer.")
		_:
			EventBus.message_logged.emit("Eau profonde : la nage vous épuise plus vite et il n'y a aucun repos possible.")
	queue_redraw()  # teinte du sprite

## Stamina à 0 dans l'eau : le joueur se noie à chaque action qui fait avancer le temps (dégâts au torse).
func _check_drowning(action_cost: float) -> void:
	if dead or stamina > 0.0 or not is_swimming():
		return
	var damage: float = drown_damage(action_cost)
	EventBus.message_logged.emit("Vous vous noyez : -%d PV." % roundi(damage))
	take_damage(damage, "torso")


## Dégâts à UNE partie du corps (id de data/body_parts.json ; id inconnu : le torse). Les PV d'une partie ne descendent pas sous 0
## et l'excédent est perdu. La mort survient quand une partie vitale (tête, torse) tombe à 0. L'appelant écrit le message du journal.
func take_damage(amount: float, part_id: String = "torso") -> void:
	if dead:
		return
	_stop_repeat()
	if not body.has(part_id):
		part_id = "torso"
	var before: float = float(body[part_id])
	body[part_id] = maxf(before - amount, 0.0)
	_emit_health()
	if before > 0.0 and float(body[part_id]) <= 0.0:
		if BodyPartDB.is_vital(part_id):
			dead = true
			EventBus.message_logged.emit("%s : 0 PV. Vous êtes mort." % BodyPartDB.name_of(part_id))
			queue_redraw()
		else:
			EventBus.message_logged.emit("%s : 0 PV (hors d'usage)." % BodyPartDB.name_of(part_id))

## Une diagonale au clavier (7 9 1 3) n'est PAS un déplacement spécial : c'est « vertical + horizontal »
## (ex. bas + gauche), deux pas orthogonaux avec chacun son temps, sa stamina, et pendant
## lesquels les monstres peuvent agir. On passe par une case intermédiaire libre ; si la case
## visée est occupée par un monstre, le second pas devient une attaque.
## (Le déplacement automatique, lui, saute directement sur la case en diagonale : voir _move_diagonal_direct.)
func _try_diagonal(dir: Vector2i) -> void:
	var target: Vector2i = grid_pos + dir
	if world.get_monster_at(target) == null and not world.can_player_enter(target):
		return
	for first: Vector2i in [Vector2i(0, dir.y), Vector2i(dir.x, 0)]:  # vertical d'abord, puis horizontal
		var middle: Vector2i = grid_pos + first
		if world.can_player_enter(middle) and world.get_monster_at(middle) == null:
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
	if not world.can_player_enter(target):
		return
	grid_pos = target
	position = Vector2(grid_pos * World.TILE_SIZE)
	var from_cell: Vector2i = grid_pos
	var was_swimming: bool = is_swimming()
	grid_pos = target  # la position affichée suit en glissant (voir _update_visual)
	world.update_fov()  # avant que le temps passe : les monstres réagissent à ce que tu viens de révéler
	_announce_swim()
	var swimming: bool = is_swimming()
	Fx.footstep(world, from_cell, grid_pos, posture == Posture.SPRINT, posture == Posture.CROUCH, was_swimming, swimming)
	var time_factor: float = 1.0 if swimming else POSTURE_TIME_FACTOR[posture]  # on nage à la même vitesse quelle que soit la posture
	_perform_action("Nage" if swimming else "Déplacement", MOVE_BASE_COST * time_factor, get_move_stamina_delta())


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
	var action_name: String = "Attendre"
	match swim_depth():
		TerrainDB.SWIM_SHALLOW:
			action_name = "Flotter"
		TerrainDB.SWIM_DEEP:
			action_name = "Surplace"
	_perform_action(action_name, WAIT_BASE_COST, get_wait_stamina_delta())


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
## En eau profonde, chaque étape coûte de la stamina (surplace) ; ailleurs, INVENTORY_STAMINA_DELTA.
func spend_inventory_time(base_cost: float) -> void:
	if base_cost > 0.0:
		var delta: float = INVENTORY_STAMINA_DELTA
		var depth: int = swim_depth()
		if depth == TerrainDB.SWIM_DEEP:
			delta = swim_wait_stamina_delta(depth, get_load_ratio())
		_perform_action("Inventaire", base_cost, delta)


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
## Toute action passe par ici : c'est aussi là qu'on se noie (stamina à 0 dans l'eau, une fois le temps écoulé).
func _perform_action(action_name: String, base_cost: float, stamina_delta: float) -> void:
	var cost: float = base_cost * (1.0 + get_time_penalty())
	stamina = clampf(stamina + stamina_delta, 0.0, STAMINA_MAX)
	EventBus.action_performed.emit(action_name, cost, stamina_delta)
	GameClock.advance(cost)  # les monstres agissent pendant ce temps (voir World)
	_emit_stamina()
	_check_drowning(cost)


func _emit_stamina() -> void:
	EventBus.stamina_changed.emit(stamina, STAMINA_MAX, get_time_penalty())


func _emit_load() -> void:
	EventBus.load_changed.emit(get_carry_weight(), get_carry_capacity())

func _emit_health() -> void:
	EventBus.health_changed.emit(total_hp(), BodyPartDB.total_max_hp())

func _draw() -> void:
	var tint: Color = Color.WHITE
	var swimming: bool = is_swimming()
	if dead:
		tint = Color(0.45, 0.45, 0.45)
	elif swimming:
		tint = Color(0.7, 0.85, 1.0)  # le joueur nage : teinte bleutée
	var pivot := Vector2(World.TILE_SIZE / 2.0, World.TILE_SIZE - 10.0)  # bas et centre de la case : rebond et respiration s'y ancrent
	if Fx.SHADOWS and not swimming:
		var squeeze: float = 1.0 - _hop / 60.0  # l'ombre rétrécit quand le personnage rebondit
		draw_colored_polygon(Fx.ellipse_points(pivot + Vector2(0, 2), Vector2(34.0, 11.0) * squeeze), Fx.SHADOW_COLOR)
	draw_set_transform(pivot + Vector2(0, -_hop), 0.0, Vector2(1.0 - _breath * 0.5, 1.0 + _breath))
	UlticaTiles.draw_sprite(self, _bg_sprite, -pivot, tint)
	UlticaTiles.draw_sprite(self, _fg_sprite, -pivot, tint)
	for slot: String in ItemDB.WORN_DRAW_ORDER:  # vêtements portés, par-dessus le mannequin
		var worn := inventory.equipment.get(slot) as Item
		if worn != null:
			UlticaTiles.draw_sprite_anchored(self, UlticaTiles.pick_sprite(worn.worn_tile(), "fg", 0), -pivot, World.TILE_SIZE, tint)
