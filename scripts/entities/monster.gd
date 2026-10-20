class_name Monster
extends Node2D
## Monstre : joue quand son "prochain moment d'action" est atteint.
## take_turn() fait UNE action et renvoie son coût en points d'action.
## Compétences (voir MonsterData) : attaque spéciale, effets d'état, tir à distance, hurlement, meute.
##
## Mêlée : orthogonale OU diagonale (règle de l'angle : une des deux cases « de l'angle » doit être franchissable, comme pour
## les diagonales du joueur ; voir _can_melee). Le joueur, lui, frappe toujours en orthogonal.
##
## ORIENTATION : le monstre regarde dans une des 4 directions (`facing` : haut, droite, bas, gauche ; flèche rouge à ses pieds).
## Il ne frappe en mêlée que la case devant lui et ses deux diagonales avant (voir in_front_arc). Si le joueur est à portée de mêlée
## mais hors de cette zone, il PIVOTE vers lui : TURN_STEPS_PER_ACTION quarts de tour (90°) par action, pour TURN_COST_FACTOR x le
## temps d'un pas et la même variation de stamina qu'un pas. Se déplacer l'oriente dans le sens du pas (gratuit).
## DÉPLACEMENT : A* à 8 directions (PathFinder). Un pas diagonal (règle de l'angle) déplace le monstre tout de suite sur la case en
## diagonale mais lui coûte le temps et la stamina de DEUX pas, exactement comme le déplacement automatique du joueur.
## ORDRE DES TOURS : le joueur agit toujours d'abord (il change de case, la vue est recalculée), PUIS le temps passe et les monstres dont
## le moment d'action est arrivé jouent (World._on_time_advanced) : un monstre prêt à frapper ne frappe pas un joueur qui s'est éloigné.
##
## Stamina : les monstres ont la même stamina que le joueur (Player.STAMINA_MAX) et les mêmes règles de ralentissement :
## chaque tranche de 30 % perdue ajoute +10 % à la durée de leurs actions (max +30 %). Se déplacer à terre regagne de la stamina,
## nager (eau peu profonde ; ils ne vont pas en eau profonde) en coûte, attendre régénère, attaquer fatigue.
## Mêmes fonctions statiques que le joueur (Player.load_stamina_delta, swim_move_stamina_delta, swim_wait_stamina_delta), charge nulle.

const IDLE_COST: float = 5.0   # rien à faire : on revient voir plus tard
const BLOCKED_COST: float = 1.0 # chemin bloqué : on attend un peu
const ATTACK_STAMINA_PER_SECOND: float = 1.0  # fatigue d'une attaque ou d'un tir : -1 par seconde d'action (le joueur : -2 pour 2 s)

# --- Orientation ---
const TURN_STEPS_PER_ACTION: int = 1   # quarts de tour (90°) par pivotement (1 = un quart par action ; 2 = demi-tour en une action)
const TURN_COST_FACTOR: float = 1.0    # durée d'un pivotement = move_cost x ce facteur (1.0 = autant qu'un pas ; 1.5 = plus lent à se retourner)
const SHOW_FACING_ARROW: bool = true
const ARROW_COLOR: Color = Color(0.9, 0.1, 0.1, 0.55)           # le monstre regarde par là (rien à portée de sa zone d'attaque)
const ARROW_THREAT_COLOR: Color = Color(1.0, 0.1, 0.1, 0.95)    # le joueur est dans sa zone : il frappera à sa prochaine action
const ARROW_OUTLINE: Color = Color(0.15, 0.0, 0.0, 0.9)
const ARROW_CENTER: Vector2 = Vector2(64.0, 96.0)               # milieu de la flèche dans la case (pixels, case de 128 px)
const ARROW_RADII: Vector2 = Vector2(62.0, 44.0)                # portée de la pointe (aplatie en Y comme l'ombre : perspective)
const ARROW_HALF_WIDTH: Vector2 = Vector2(24.0, 17.0)
const ARROW_THREAT_SCALE: float = 1.15
# Les 4 directions dans l'ordre horaire (haut, droite, bas, gauche) : tourner d'un quart = passer à la suivante.
const RING: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var data: MonsterData
var world: World
var grid_pos: Vector2i = Vector2i.ZERO
var hp: float = 1.0
var stamina: float = Player.STAMINA_MAX
var next_action_time: float = 0.0
var has_target: bool = false            # sait où est (ou était) le joueur
var target_cell: Vector2i = Vector2i.ZERO
var spotted: bool = false               # déjà signalé au joueur (message « Vous apercevez... »)
var hidden_since: float = 0.0           # moment (points d'action) où il est sorti du champ de vision
var facing: Vector2i = Vector2i(0, 1)   # direction du regard (une des 4 de RING)

var _rng := RandomNumberGenerator.new()
var _fg_sprite: String = ""
var _ranged_ready_at: float = 0.0       # moment (points d'action) où le prochain tir est possible
var _scream_ready_at: float = 0.0       # idem pour le hurlement
var _anim_time: float = 0.0
var _anim_phase: float = 0.0            # déphase la respiration d'un monstre à l'autre (purement visuel)
var _hop: float = 0.0
var _breath: float = 0.0
var _threat: bool = false               # le joueur est dans sa zone d'attaque (flèche vive)


func _ready() -> void:
	position = Vector2(grid_pos * World.TILE_SIZE)
	facing = RING[_rng.randi() % RING.size()]   # orientation de départ au hasard
	# Chaque monstre garde la variante de sprite tirée à sa création.
	var variant_seed: int = randi()
	_anim_phase = float(variant_seed % 628) / 100.0
	_fg_sprite = UlticaTiles.pick_sprite(data.tile_id, "fg", variant_seed)  # la couche "bg" d'UltiCa (ombre) n'est plus dessinée : voir Fx


## Purement visuel : l'affichage glisse vers la case logique (déjà atteinte) avec un petit rebond.
func _process(delta: float) -> void:
	var left: float = Fx.glide(self, Vector2(grid_pos * World.TILE_SIZE), delta)
	_anim_time += delta
	_hop = Fx.hop_of(left)
	_breath = 0.0 if left > 0.0 else sin(_anim_time * 2.0 + _anim_phase) * Fx.BREATH
	var threat: bool = _is_threatening()
	if threat != _threat:
		_threat = threat
		queue_redraw()
	if Fx.SMOOTH_MOVE and visible:
		queue_redraw()


func take_turn() -> float:
	var player: Player = world.player
	var delta: Vector2i = player.grid_pos - grid_pos
	var distance: int = maxi(absi(delta.x), absi(delta.y))  # distance en cases (diagonales incluses)
	# Le joueur et le monstre se voient mutuellement : on s'appuie sur le champ de vision du
	# joueur (les arbres et les murs bloquent donc aussi la vue des monstres).
	var reach: float = data.detect_range * player.get_detect_factor()  # posture du joueur : sprint = plus loin, accroupi = moins loin
	var sees: bool = distance <= reach and world.is_visible_cell(grid_pos)
	if sees:
		if distance <= reach and world.is_visible_cell(grid_pos):
			alert(player.grid_pos)
			if data.scream_radius > 0 and GameClock.elapsed_points >= _scream_ready_at:
				return _scream()
		if _can_melee(player.grid_pos):
			if in_front_arc(facing, _direction_to(player.grid_pos)):
				return _attack_player()
			return _turn_toward(player.grid_pos)   # à portée mais dans son dos / son flanc : il doit d'abord pivoter
		if has_target:
			if sees and _can_shoot(delta):
				face(_direction_to(player.grid_pos))   # il se tourne vers sa cible pour tirer (gratuit)
				return _shoot()
			if grid_pos == target_cell:
				has_target = false  # arrivé là où on a vu le joueur pour la dernière fois : plus personne
				return _rest(IDLE_COST)
			return _move_toward(target_cell)
	return _rest(IDLE_COST)


# --- Orientation ---

## Indice de la direction dans RING (haut, droite, bas, gauche) ; -1 pour une diagonale ou le vecteur nul.
static func ring_index(dir: Vector2i) -> int:
	return RING.find(dir)


## Le regard `facing_dir` couvre-t-il la direction `dir` (voisine, orthogonale ou diagonale) ? Oui pour la case en face et ses deux
## diagonales avant ; non pour les flancs et le dos.
static func in_front_arc(facing_dir: Vector2i, dir: Vector2i) -> bool:
	var d := Vector2i(signi(dir.x), signi(dir.y))
	if d == Vector2i.ZERO:
		return true
	return facing_dir.x * d.x + facing_dir.y * d.y >= 1


## Nombre de quarts de tour (0 à 2) entre deux directions ORTHOGONALES.
static func turn_distance(from_dir: Vector2i, to_dir: Vector2i) -> int:
	var a: int = ring_index(from_dir)
	var b: int = ring_index(to_dir)
	if a < 0 or b < 0:
		return 0
	var diff: int = posmod(b - a, RING.size())
	return mini(diff, RING.size() - diff)


## Regard à adopter pour faire face à `dir`. Orthogonale : cette direction. Diagonale : celle de ses deux composantes la plus proche
## du regard actuel (le moins de quarts de tour).
static func target_facing(current: Vector2i, dir: Vector2i) -> Vector2i:
	var d := Vector2i(signi(dir.x), signi(dir.y))
	if d == Vector2i.ZERO:
		return current
	if d.x == 0 or d.y == 0:
		return d
	var horizontal := Vector2i(d.x, 0)
	var vertical := Vector2i(0, d.y)
	return horizontal if turn_distance(current, horizontal) <= turn_distance(current, vertical) else vertical


## Nouveau regard après avoir pivoté de `max_steps` quarts de tour au plus vers `to_dir` (par le côté le plus court ; demi-tour : sens horaire).
static func turned(from_dir: Vector2i, to_dir: Vector2i, max_steps: int) -> Vector2i:
	var a: int = ring_index(from_dir)
	var b: int = ring_index(target_facing(from_dir, to_dir))
	if a < 0 or b < 0:
		return from_dir
	var diff: int = posmod(b - a, RING.size())
	var step: int = 1 if diff <= 2 else -1
	var count: int = mini(max_steps, mini(diff, RING.size() - diff))
	return RING[posmod(a + step * count, RING.size())]


func _direction_to(cell: Vector2i) -> Vector2i:
	var d: Vector2i = cell - grid_pos
	return Vector2i(signi(d.x), signi(d.y))


## Oriente le monstre sans coût (pas, tir) : un pas diagonal ne se produit pas (A* à 4 directions), une cible diagonale donne le
## côté le plus proche.
func face(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO:
		facing = target_facing(facing, dir)
		queue_redraw()


## Le joueur est-il dans la zone d'attaque du monstre (il frapperait à sa prochaine action si le joueur ne s'éloigne pas) ?
func _is_threatening() -> bool:
	if world == null or world.player == null or world.player.dead:
		return false
	var cell: Vector2i = world.player.grid_pos
	return _can_melee(cell) and in_front_arc(facing, _direction_to(cell))


## Pivote vers `cell` (TURN_STEPS_PER_ACTION quarts de tour) : durée d'un pas x TURN_COST_FACTOR, même variation de stamina qu'un pas.
func _turn_toward(cell: Vector2i) -> float:
	facing = turned(facing, _direction_to(cell), TURN_STEPS_PER_ACTION)
	queue_redraw()
	return _finish(data.move_cost * TURN_COST_FACTOR, _move_stamina_delta())


# --- Mêlée ---

## Le monstre peut-il frapper la case `cell` ? Voisine en orthogonal, ou en diagonale si l'une des deux cases de l'angle est
## franchissable (même règle que les diagonales du joueur : on ne frappe pas à travers l'angle de deux murs / arbres).
func _can_melee(cell: Vector2i) -> bool:
	var d: Vector2i = cell - grid_pos
	if absi(d.x) + absi(d.y) == 1:
		return true
	if absi(d.x) == 1 and absi(d.y) == 1:
		return world.can_player_enter(grid_pos + Vector2i(d.x, 0)) or world.can_player_enter(grid_pos + Vector2i(0, d.y))
	return false


# --- Stamina et temps (mêmes règles que le joueur) ---

## Pénalité de temps actuelle (0.0, 0.1, 0.2 ou 0.3), comme Player.get_time_penalty.
func time_penalty() -> float:
	var steps: int = mini(int((Player.STAMINA_MAX - stamina) / Player.STAMINA_STEP), Player.MAX_PENALTY_STEPS)
	return steps * Player.PENALTY_PER_STEP


## Applique la variation de stamina et renvoie le coût RÉEL de l'action = base x (1 + pénalité), comme Player._perform_action.
func _finish(base_cost: float, stamina_delta: float) -> float:
	var cost: float = base_cost * (1.0 + time_penalty())
	stamina = clampf(stamina + stamina_delta, 0.0, Player.STAMINA_MAX)
	return cost


## Variation de stamina pour UNE seconde d'attente : planche en eau peu profonde, récupération à terre.
func _wait_stamina_delta() -> float:
	var depth: int = world.swim_depth(grid_pos)
	if depth != TerrainDB.SWIM_NONE:
		return Player.swim_wait_stamina_delta(depth, 0.0)
	return Player.load_stamina_delta(0.0, Player.WAIT_REGEN_MAX)


## Variation de stamina pour UN pas, selon la case où le monstre se trouve (à appeler après le déplacement).
func _move_stamina_delta() -> float:
	var depth: int = world.swim_depth(grid_pos)
	if depth != TerrainDB.SWIM_NONE:
		return Player.swim_move_stamina_delta(depth, 0.0)
	return Player.load_stamina_delta(0.0, Player.MOVE_REGEN_MAX)


## Attendre / ne rien faire pendant `cost` secondes (récupère de la stamina, sauf en eau profonde).
func _rest(cost: float) -> float:
	return _finish(cost, _wait_stamina_delta() * cost)


## Le monstre sait où chercher (il a vu le joueur, ou s'est fait frapper). Les membres d'une meute proche le savent aussi.
func alert(cell: Vector2i) -> void:
	has_target = true
	target_cell = cell
	if data.pack_radius <= 0:
		return
	for other: Monster in world.monsters:
		if other == self or other.has_target or other.data.id != data.id:
			continue
		var d: Vector2i = other.grid_pos - grid_pos
		if maxi(absi(d.x), absi(d.y)) <= data.pack_radius:
			other.has_target = true
			other.target_cell = cell


func _attack_player() -> float:
	var use_special: bool = data.special_cost > 0.0 and _rng.randf() < data.special_chance
	var attack_label: String = data.special_name if use_special else data.attack_name
	var damage: float = data.special_damage if use_special else data.attack_damage
	var cost: float = data.special_cost if use_special else data.attack_cost
	var zones: Dictionary = data.special_zones if use_special else data.attack_zones
	var effect: Dictionary = data.special_effect if use_special else data.attack_effect
	var part: String = BodyPartDB.pick(zones, _rng.randf())  # partie du corps touchée (probabilités visibles dans l'infobulle)
	EventBus.message_logged.emit("%s utilise %s (%s) : -%d PV." % [data.display_name, attack_label, BodyPartDB.name_of(part), int(damage)])
	world.player.take_damage(damage, part)
	_apply_effect(effect, part)
	var infection_chance: float = data.special_infection if use_special else data.attack_infection
	if infection_chance > 0.0 and not world.player.dead and _rng.randf() < infection_chance:
		Infection.infect(world.player)
	return _finish(cost, -cost * ATTACK_STAMINA_PER_SECOND)

## Tire l'effet d'état d'un coup (chance) et l'inflige au joueur s'il est encore en vie.
func _apply_effect(effect: Dictionary, part: String) -> void:
	if effect.is_empty() or world.player.dead:
		return
	if _rng.randf() >= float(effect.get("chance", 1.0)):
		return
	StatusEffects.apply(world.player, effect, part)

# --- Tir à distance ---
func _can_shoot(delta: Vector2i) -> bool:
	return data.ranged_range > 0 and GameClock.elapsed_points >= _ranged_ready_at \
		and Vector2(delta).length() <= float(data.ranged_range)

func _shoot() -> float:
	_ranged_ready_at = GameClock.elapsed_points + data.ranged_cooldown
	var part: String = BodyPartDB.pick(data.ranged_zones, _rng.randf())
	EventBus.message_logged.emit("%s utilise %s (%s) : -%d PV." % [data.display_name, data.ranged_name, BodyPartDB.name_of(part), int(data.ranged_damage)])
	world.player.take_damage(data.ranged_damage, part)
	_apply_effect(data.ranged_effect, part)
	return _finish(data.ranged_cost, -data.ranged_cost * ATTACK_STAMINA_PER_SECOND)

# --- Hurlement ---
## Alerte tous les monstres dans le rayon : ils se dirigent vers la position du joueur.
func _scream() -> float:
	_scream_ready_at = GameClock.elapsed_points + data.scream_cooldown
	var cell: Vector2i = world.player.grid_pos
	var alerted: int = 0
	for other: Monster in world.monsters:
		if other == self:
			continue
		var d: Vector2i = other.grid_pos - grid_pos
		if maxi(absi(d.x), absi(d.y)) <= data.scream_radius:
			other.alert(cell)
			alerted += 1
	EventBus.message_logged.emit("%s pousse un %s !%s" % [data.display_name, data.scream_name.to_lower(),
		" Les créatures alentour accourent." if alerted > 0 else ""])
	return _finish(data.scream_cost, 0.0)

func _move_toward(cell: Vector2i) -> float:
	var path: Array[Vector2i] = world.find_path(grid_pos, cell)
	if path.size() < 2:
		has_target = false
		return _rest(IDLE_COST)
	var next_cell: Vector2i = path[1]
	if world.is_occupied(next_cell):
		return _rest(BLOCKED_COST)
	var step: Vector2i = next_cell - grid_pos
	var steps: int = 2 if (step.x != 0 and step.y != 0) else 1   # un pas diagonal vaut deux pas orthogonaux (comme pour le joueur)
	face(step)  # se déplacer l'oriente dans le sens du pas (gratuit)
	grid_pos = next_cell  # la position affichée suit en glissant (voir _process)
	position = Vector2(grid_pos * World.TILE_SIZE)
	return _finish(data.move_cost * steps, _move_stamina_delta() * steps)


## Renvoie true si le monstre meurt.
func take_damage(amount: float) -> bool:
	hp = maxf(hp - amount, 0.0)
	queue_redraw()
	return hp <= 0.0


## Lignes d'information (survol, mode regard) : PV, coûts, dégâts, PROBABILITÉS de toucher chaque partie du corps et compétences.
func get_tooltip_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("%s   PV %d/%d" % [data.display_name, ceili(hp), int(data.max_hp)])
	if time_penalty() > 0.0:
		lines.append("Essoufflé : actions +%d %% de durée" % roundi(time_penalty() * 100.0))
	lines.append("Déplacement : %.1f pts" % data.move_cost)
	lines.append("Pivoter (90°) : %.1f pts (frappe devant lui, flèche rouge)" % (data.move_cost * TURN_COST_FACTOR))
	lines.append("%s : %.1f pts, %d dégâts" % [data.attack_name, data.attack_cost, int(data.attack_damage)])
	for zone_line in BodyPartDB.zone_lines(data.attack_zones):
		lines.append("   → " + zone_line)
	if not data.attack_effect.is_empty():
		lines.append("   + " + MonsterData.effect_text(data.attack_effect))
	if data.attack_infection > 0.0:
		lines.append("   + Morsure infectieuse : %d%% d'infection" % roundi(data.attack_infection * 100.0))
	if data.special_cost > 0.0:
		lines.append("%s (spéciale, %d%%) : %.1f pts, %d dégâts" % [
			data.special_name, roundi(data.special_chance * 100.0), data.special_cost, int(data.special_damage)])
		for zone_line in BodyPartDB.zone_lines(data.special_zones):
			lines.append("   → " + zone_line)
		if not data.special_effect.is_empty():
			lines.append("   + " + MonsterData.effect_text(data.special_effect))
		if data.special_infection > 0.0:
			lines.append("   + Morsure infectieuse : %d%% d'infection" % roundi(data.special_infection * 100.0))
	if data.ranged_range > 0:
		lines.append("%s (portée %d, recharge %d s) : %.1f pts, %d dégâts" % [
			data.ranged_name, data.ranged_range, roundi(data.ranged_cooldown), data.ranged_cost, int(data.ranged_damage)])
		for zone_line in BodyPartDB.zone_lines(data.ranged_zones):
			lines.append("   → " + zone_line)
		if not data.ranged_effect.is_empty():
			lines.append("   + " + MonsterData.effect_text(data.ranged_effect))
	if data.scream_radius > 0:
		lines.append("%s : alerte les monstres à %d cases (recharge %d s)" % [data.scream_name, data.scream_radius, roundi(data.scream_cooldown)])
	if data.pack_radius > 0:
		lines.append("Chasse en meute (rayon %d)" % data.pack_radius)
	return lines

func get_tooltip_text() -> String:
	return "\n".join(get_tooltip_lines())


func _draw() -> void:
	var pivot := Vector2(World.TILE_SIZE / 2.0, World.TILE_SIZE - 10.0)  # bas et centre de la case
	if Fx.SHADOWS:
		var squeeze: float = 1.0 - _hop / 60.0
		draw_colored_polygon(Fx.ellipse_points(pivot + Vector2(0, 2), Fx.SHADOW_RADII * squeeze), Fx.SHADOW_COLOR)
	draw_set_transform(pivot + Vector2(0, -_hop), 0.0, Vector2(1.0 - _breath * 0.5, 1.0 + _breath))
	UlticaTiles.draw_sprite(self, _fg_sprite, -pivot)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if SHOW_FACING_ARROW:
		_draw_facing_arrow()
	# Barre de vie au-dessus de la tête (le sprite dépasse de 64 px au-dessus de la case).
	var ratio: float = hp / data.max_hp
	draw_rect(Rect2(8, -72, (World.TILE_SIZE - 16.0) * ratio, 12), Color.RED)


## Flèche rouge au sol qui pointe dans la direction du regard (haut, bas, gauche ou droite), aplatie comme l'ombre (perspective).
## Plus vive et plus grande quand le joueur est dans la zone d'attaque : le monstre frappera à sa prochaine action s'il ne s'éloigne pas.
func _draw_facing_arrow() -> void:
	var dir: Vector2 = Vector2(facing)
	var scale_factor: float = ARROW_THREAT_SCALE if _threat else 1.0
	var tip: Vector2 = ARROW_CENTER + dir * ARROW_RADII * scale_factor
	var back: Vector2 = ARROW_CENTER + dir * ARROW_RADII * 0.35
	var side: Vector2 = Vector2(-dir.y, dir.x) * ARROW_HALF_WIDTH * scale_factor
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), ARROW_THREAT_COLOR if _threat else ARROW_COLOR)
	draw_polyline(PackedVector2Array([tip, back + side, back - side, tip]), ARROW_OUTLINE, 3.0)
