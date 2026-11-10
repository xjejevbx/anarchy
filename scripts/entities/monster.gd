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
## COMPORTEMENTS (jalon 6a, champ `behavior` de monsters.json) : « hostile » (défaut) ; « passive » : fuit le joueur (cerf, renard) et
## ne se défend que s'il est acculé ; « territorial » : ne repère le joueur que dans un rayon de TERRITORY_RADIUS cases et abandonne la
## poursuite au-delà de TERRITORY_LEASH (sanglier, ours).
## ARMURE : `data.armor` (capacité ARMOR(n)) retire n PV à chaque coup reçu, 1 PV au minimum.
##
## ÉTATS (jalon 6b, `state`) : « idle » (debout sur place, comportement d'avant) ; « sleep » : immobile, ne détecte rien, se réveille quand le
## joueur s'approche (wake_range x posture, visible, WAKE_CHANCE par tour), à un bruit (sprint, combat : voir World.make_noise), quand il est
## frappé ou quand un voisin se réveille ; AMBUSH : ne se réveille que si le joueur est à AMBUSH_RANGE cases (alors il surgit) ; « guard » :
## ne dort jamais, tient son poste (`home_cell`) et y revient (GUARD_LEASH). ERRATIC : ERRATIC_CHANCE des pas de poursuite au hasard.
##
## CAPACITÉS (jalon 6c) : AURA_RAD / FIRE_AURA / COLD_AURA (effet d'état sur le joueur proche, AURA_EFFECTS), REGEN(x) (x PV par seconde après
## REGEN_DELAY s sans dégât), LEAP (bond de 2-3 cases, en ligne) et CHARGE (course de 4 à 8 cases en ligne droite, premier coup x1.5) : voir
## _try_rush, GRAB / CONSTRICT (le coup draine la stamina ; l'immobilisation viendra avec le combat), SPLIT (chaque coup détache un petit monstre :
## World.spawn_split), EXPLODE(type) à la mort (World.explode), THROW(type) (le tir lance une explosion de rayon 1 sur le joueur),
## BURST (le tir fait BURST_SHOTS coups à dégâts réduits).
##
## Stamina : les monstres ont la même stamina que le joueur (Player.STAMINA_MAX) et les mêmes règles de ralentissement :
## chaque tranche de 30 % perdue ajoute +10 % à la durée de leurs actions (max +30 %). Se déplacer à terre regagne de la stamina,
## nager (eau peu profonde ; ils ne vont pas en eau profonde) en coûte, attendre régénère, attaquer fatigue.
## Mêmes fonctions statiques que le joueur (Player.load_stamina_delta, swim_move_stamina_delta, swim_wait_stamina_delta), charge nulle.

const IDLE_COST: float = 5.0   # rien à faire : on revient voir plus tard
const BLOCKED_COST: float = 1.0 # chemin bloqué : on attend un peu
const ATTACK_STAMINA_PER_SECOND: float = 1.0  # fatigue d'une attaque ou d'un tir : -1 par seconde d'action (le joueur : -2 pour 2 s)

# --- Comportements (jalon 6a) ---
const TERRITORY_RADIUS: float = 5.0   # territorial : portée de détection maximale (cases)
const TERRITORY_LEASH: int = 10       # territorial : au-delà de cette distance, il abandonne la poursuite
const FLEE_RANGE: float = 8.0         # passif : distance à laquelle il commence à fuir

# --- États (jalon 6b) ---
const WAKE_CHANCE: float = 0.15       # dormeur : probabilité de réveil par tour (5 s) quand le joueur est à portée et visible
const AMBUSH_RANGE: float = 2.0       # embuscade : distance à laquelle le monstre surgit
const GUARD_LEASH: int = 8            # garde : au-delà de cette distance de son poste, il abandonne la poursuite
const ERRATIC_CHANCE: float = 0.3     # ERRATIC : part des pas de poursuite faits au hasard
const WAKE_NEIGHBOR_RADIUS: int = 4   # un réveil réveille aussi les dormeurs à moins de N cases (ou pack_radius)

# --- Capacités (jalon 6c) ---
# Aura : effet d'état infligé (une fois par tour du monstre) au joueur à moins de `radius` cases.
const AURA_EFFECTS: Dictionary = {
	"AURA_RAD": {"id": "radiation", "chance": 1.0, "duration": 30.0, "dps": 0.15, "stamina": 0.0, "part": "torso", "radius": 2},
	"FIRE_AURA": {"id": "burn", "chance": 1.0, "duration": 4.0, "dps": 1.0, "stamina": 0.0, "part": "torso", "radius": 1},
	"COLD_AURA": {"id": "frostbite", "chance": 1.0, "duration": 8.0, "dps": 0.3, "stamina": 0.0, "part": "arm_l", "radius": 1},
}
const REGEN_DELAY: float = 5.0        # secondes sans dégât avant que REGEN agisse
const REGEN_MAX_STEP: float = 60.0    # plafond du temps compté en une fois (monstre resté longtemps hors du temps)
const LEAP_MIN: int = 2
const LEAP_MAX: int = 3
const LEAP_COOLDOWN: float = 8.0
const CHARGE_MIN: int = 4
const CHARGE_MAX: int = 8
const CHARGE_COOLDOWN: float = 10.0
const CHARGE_DAMAGE_FACTOR: float = 1.5
const THROW_RADIUS: int = 1           # THROW : explosion de rayon 1 sur le joueur
const BURST_SHOTS: int = 3
const BURST_DAMAGE_FACTOR: float = 0.5
const GRAB_STAMINA_DRAIN: float = 20.0
const GRAB_TEXT: String = "L'étreinte vous épuise : -%d de stamina."
const SPLIT_MIN_HP: float = 12.0      # un blob plus fragile ne se divise plus
const SPLIT_MAX_GENERATION: int = 3
const ABILITY_TEXT: Dictionary = {
	"AURA_RAD": "Aura radioactive (rayon 2) : irradie", "FIRE_AURA": "Aura de feu (rayon 1) : brûle", "COLD_AURA": "Aura de froid (rayon 1) : engelure",
	"REGEN": "Régénère", "LEAP": "Bondit sur sa cible (2 à 3 cases)", "CHARGE": "Charge en ligne droite (coup x1.5)",
	"GRAB": "Agrippe : draine la stamina", "CONSTRICT": "Étreint : draine la stamina", "SPLIT": "Se divise quand on le frappe",
	"SWARM": "Attaque en essaim", "THROW": "Lance des projectiles explosifs", "BURST": "Tire en rafale", "EXPLODE": "Explose à sa mort",
}

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
var state: String = "idle"              # "idle", "sleep" ou "guard" (voir en-tête)
var home_cell: Vector2i = Vector2i.ZERO # poste d'un garde (case d'apparition)
var z: int = 0                          # étage où se trouve le monstre (le monde ne simule que l'étage actif : voir ChunkManager.level)

var _rng := RandomNumberGenerator.new()
var _fg_sprite: String = ""
var _tint: Color = Color.WHITE          # teinte du sprite (blanc, sauf sprite de repli : data.tint)
var _ranged_ready_at: float = 0.0       # moment (points d'action) où le prochain tir est possible
var _scream_ready_at: float = 0.0       # idem pour le hurlement
var _anim_time: float = 0.0
var _anim_phase: float = 0.0            # déphase la respiration d'un monstre à l'autre (purement visuel)
var _hop: float = 0.0
var _breath: float = 0.0
var _threat: bool = false               # le joueur est dans sa zone d'attaque (flèche vive)
var generation: int = 0                 # SPLIT : 0 pour l'original, +1 par division
var _last_hurt: float = -1000.0         # moment (points d'action) du dernier dégât reçu (REGEN)
var _regen_clock: float = 0.0           # dernier moment compté par REGEN
var _rush_ready_at: float = 0.0         # moment où LEAP / CHARGE sont de nouveau possibles
var _attack_bonus: float = 1.0          # multiplicateur du prochain coup (charge)
var _dead: bool = false                 # a déjà subi le coup fatal (EXPLODE ne se déclenche qu'une fois)


func _ready() -> void:
	position = Vector2(grid_pos * World.TILE_SIZE)
	facing = RING[_rng.randi() % RING.size()]   # orientation de départ au hasard (World peut la remplacer juste après)
	# Chaque monstre garde la variante de sprite tirée à sa création.
	var variant_seed: int = randi()
	_anim_phase = float(variant_seed % 628) / 100.0
	_fg_sprite = UlticaTiles.pick_sprite(data.tile_id, "fg", variant_seed)  # la couche "bg" d'UltiCa (ombre) n'est plus dessinée : voir Fx
	if _fg_sprite == "":  # tuile absente du pack : sprite de repli, teinté (voir data.fallback_tile et data.tint)
		_fg_sprite = UlticaTiles.pick_sprite(data.fallback_tile, "fg", variant_seed)
		_tint = data.tint


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


## État à sauvegarder quand le chunk est déchargé ou lors d'une sauvegarde (voir ChunkManager) :
## World.restore_monster() le relit. Les Vector2i sont écrits en tableaux pour rester sûrs en JSON.
func to_dict() -> Dictionary:
	return {
		"id": data.id, "cell": [grid_pos.x, grid_pos.y], "hp": hp, "stamina": stamina,
		"facing": [facing.x, facing.y], "spotted": spotted, "state": state,
		"home": [home_cell.x, home_cell.y], "affixes": data.affixes.duplicate(), "z": z,
		"generation": generation, "next_action_time": next_action_time,
		"has_target": has_target, "target_cell": [target_cell.x, target_cell.y],
		"hidden_since": hidden_since, "ranged_ready_at": _ranged_ready_at,
		"scream_ready_at": _scream_ready_at, "last_hurt": _last_hurt,
		"regen_clock": _regen_clock, "rush_ready_at": _rush_ready_at,
		"attack_bonus": _attack_bonus,
	}


func take_turn() -> float:
	var player: Player = world.player
	var delta: Vector2i = player.grid_pos - grid_pos
	var distance: int = maxi(absi(delta.x), absi(delta.y))  # distance en cases (diagonales incluses)
	_regen_tick()
	_apply_auras(player, distance)
	if state == "sleep":
		return _sleep_turn(player, distance)
	if state == "guard" and has_target and maxi(absi(grid_pos.x - home_cell.x), absi(grid_pos.y - home_cell.y)) > GUARD_LEASH:
		has_target = false  # trop loin de son poste : il y retourne
	if data.behavior == "passive":
		return _passive_turn(player, delta, distance)
	# Le joueur et le monstre se voient mutuellement : on s'appuie sur le champ de vision du
	# joueur (les arbres et les murs bloquent donc aussi la vue des monstres).
	var reach: float = data.detect_range * player.get_detect_factor()  # posture du joueur : sprint = plus loin, accroupi = moins loin
	if data.behavior == "territorial":
		reach = minf(reach, TERRITORY_RADIUS)
		if has_target and distance > TERRITORY_LEASH:
			has_target = false  # le joueur est sorti de son territoire
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
		var rush: float = _try_rush(player, delta, distance)
		if rush >= 0.0:
			return rush
		if has_target:
			if sees and _can_shoot(delta):
				face(_direction_to(player.grid_pos))   # il se tourne vers sa cible pour tirer (gratuit)
				return _shoot()
			if grid_pos == target_cell:
				has_target = false  # arrivé là où on a vu le joueur pour la dernière fois : plus personne
				return _rest(IDLE_COST)
			return _move_toward(target_cell)
	if state == "guard" and grid_pos != home_cell:
		return _move_toward(home_cell)   # retour au poste
	return _rest(IDLE_COST)


# --- Capacités (jalon 6c) ---

## REGEN(x) : x PV par seconde de jeu écoulée, tant que le monstre n'a pas été touché depuis REGEN_DELAY secondes.
func _regen_tick() -> void:
	var now: float = GameClock.elapsed_points
	var elapsed: float = minf(now - _regen_clock, REGEN_MAX_STEP)
	_regen_clock = now
	if elapsed <= 0.0 or hp >= data.max_hp or hp <= 0.0 or not data.has_ability("REGEN"):
		return
	if now - _last_hurt < REGEN_DELAY:
		return
	hp = minf(data.max_hp, hp + data.ability_value("REGEN", 0.2) * elapsed)
	queue_redraw()


## Auras : le joueur à portée subit l'effet d'état de chaque aura du monstre (l'effet se fusionne : il ne s'empile pas).
func _apply_auras(player: Player, distance: int) -> void:
	if player.dead:
		return
	for base: String in AURA_EFFECTS:
		var aura: Dictionary = AURA_EFFECTS[base]
		if data.has_ability(base) and distance <= int(aura["radius"]):
			StatusEffects.apply(player, aura, String(aura["part"]))


## LEAP (bond de 2-3 cases) et CHARGE (course de 4-8 cases en ligne droite) : le monstre se jette sur la case voisine du joueur, la ligne doit être
## libre. Renvoie le coût de l'action, ou -1.0 si rien n'a eu lieu. La charge double le premier coup qui suit.
func _try_rush(player: Player, delta: Vector2i, distance: int) -> float:
	if GameClock.elapsed_points < _rush_ready_at or distance < LEAP_MIN:
		return -1.0
	var aligned: bool = delta.x == 0 or delta.y == 0 or absi(delta.x) == absi(delta.y)
	if not aligned:
		return -1.0
	var dir := Vector2i(signi(delta.x), signi(delta.y))
	var is_leap: bool = data.has_ability("LEAP") and distance <= LEAP_MAX
	var is_charge: bool = data.has_ability("CHARGE") and (delta.x == 0 or delta.y == 0) and distance >= CHARGE_MIN and distance <= CHARGE_MAX
	if not is_leap and not is_charge:
		return -1.0
	for k in range(1, distance):   # cases entre le monstre et le joueur : libres et praticables
		var between: Vector2i = grid_pos + dir * k
		if not world.is_walkable(between) or world.is_occupied(between):
			return -1.0
	face(dir)
	grid_pos = player.grid_pos - dir
	position = Vector2(grid_pos * World.TILE_SIZE)
	if is_leap:
		_rush_ready_at = GameClock.elapsed_points + LEAP_COOLDOWN
		EventBus.message_logged.emit("%s bondit sur vous !" % data.display_name)
		return _finish(data.attack_cost, -data.attack_cost * ATTACK_STAMINA_PER_SECOND * 0.5)
	_rush_ready_at = GameClock.elapsed_points + CHARGE_COOLDOWN
	_attack_bonus = CHARGE_DAMAGE_FACTOR
	EventBus.message_logged.emit("%s charge !" % data.display_name)
	var run_cost: float = data.move_cost * minf(float(distance - 1), 3.0)
	return _finish(run_cost, -run_cost * ATTACK_STAMINA_PER_SECOND * 0.5)


## SPLIT : le coup reçu détache un petit monstre (la moitié des PV restants) sur une case voisine.
func _try_split() -> void:
	if not data.has_ability("SPLIT") or generation >= SPLIT_MAX_GENERATION or hp < SPLIT_MIN_HP:
		return
	var half: float = floorf(hp / 2.0)
	if world.spawn_split(self, half):
		hp -= half


## Coup fatal : EXPLODE(type) déclenche une explosion centrée sur le monstre.
func _on_death() -> void:
	var kind: String = data.ability_arg("EXPLODE")
	if kind != "":
		world.explode(grid_pos, -1, kind, self)


# --- Sommeil et réveil (jalon 6b) ---

## Tour d'un dormeur : se réveille si le joueur est à portée et visible (embuscade : seulement à AMBUSH_RANGE, et il surgit aussitôt).
func _sleep_turn(player: Player, distance: int) -> float:
	var ambush: bool = data.abilities.has("AMBUSH")
	var reach: float = float(data.wake_range) * player.get_detect_factor()
	if ambush:
		reach = minf(reach, AMBUSH_RANGE)
	if float(distance) <= reach and world.is_visible_cell(grid_pos) and (ambush or _rng.randf() < WAKE_CHANCE):
		if ambush:
			EventBus.message_logged.emit("%s surgit !" % data.display_name)
		alert(player.grid_pos)   # se réveille et se met en chasse
		return _finish(0.5, 0.0)
	return _rest(IDLE_COST)


## Réveille le monstre (et les dormeurs voisins, qui restent sans cible). Sans effet s'il ne dort pas.
func wake() -> void:
	if state != "sleep":
		return
	state = "idle"
	queue_redraw()
	var radius: int = data.pack_radius if data.pack_radius > 0 else WAKE_NEIGHBOR_RADIUS
	for other: Monster in world.monsters:
		if other.state == "sleep" and not other.data.abilities.has("AMBUSH") \
				and maxi(absi(other.grid_pos.x - grid_pos.x), absi(other.grid_pos.y - grid_pos.y)) <= radius:
			other.state = "idle"
			other.queue_redraw()


# --- Comportement passif (cerf, renard) ---

## Fuit le joueur tant qu'il le voit à moins de FLEE_RANGE cases ; acculé, il se défend ; sinon il reste tranquille.
func _passive_turn(player: Player, _delta: Vector2i, distance: int) -> float:
	var reach: float = minf(float(data.detect_range) * player.get_detect_factor(), FLEE_RANGE)
	if float(distance) > reach or not world.is_visible_cell(grid_pos):
		return _rest(IDLE_COST)
	var best: Vector2i = grid_pos
	var best_d2: int = (player.grid_pos - grid_pos).length_squared()
	for dir: Vector2i in RING:
		var candidate: Vector2i = grid_pos + dir
		if not world.is_walkable(candidate) or world.is_occupied(candidate) or world.swim_depth(candidate) != TerrainDB.SWIM_NONE:
			continue
		var d2: int = (player.grid_pos - candidate).length_squared()
		if d2 > best_d2:
			best_d2 = d2
			best = candidate
	if best != grid_pos:
		face(best - grid_pos)
		grid_pos = best
		position = Vector2(grid_pos * World.TILE_SIZE)
		return _finish(data.move_cost, _move_stamina_delta())
	if _can_melee(player.grid_pos):
		return _attack_player()  # acculé : il se défend
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
	wake()
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
	var damage: float = (data.special_damage if use_special else data.attack_damage) * _attack_bonus
	_attack_bonus = 1.0   # la charge ne vaut que pour le premier coup
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
	if (data.has_ability("GRAB") or data.has_ability("CONSTRICT")) and not world.player.dead:
		StatusEffects.apply(world.player, {"id": "", "chance": 1.0, "duration": 0.0, "dps": 0.0, "stamina": GRAB_STAMINA_DRAIN, "text": GRAB_TEXT}, part)
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
	if data.has_ability("THROW"):   # projectile explosif : zone de rayon 1 autour du joueur
		EventBus.message_logged.emit("%s lance %s !" % [data.display_name, data.ranged_name.to_lower()])
		world.explode(world.player.grid_pos, THROW_RADIUS, data.ability_arg("THROW"), self)
		return _finish(data.ranged_cost, -data.ranged_cost * ATTACK_STAMINA_PER_SECOND)
	if data.has_ability("BURST"):   # rafale : plusieurs coups à dégâts réduits, chacun sur sa partie du corps
		var hit_names: Array[String] = []
		var total: float = 0.0
		for shot in BURST_SHOTS:
			if world.player.dead:
				break
			var shot_part: String = BodyPartDB.pick(data.ranged_zones, _rng.randf())
			var shot_damage: float = data.ranged_damage * BURST_DAMAGE_FACTOR
			hit_names.append(BodyPartDB.short_of(shot_part))
			total += shot_damage
			world.player.take_damage(shot_damage, shot_part)
		EventBus.message_logged.emit("%s tire une rafale (%s) : -%d PV." % [data.display_name, ", ".join(hit_names), int(total)])
		return _finish(data.ranged_cost, -data.ranged_cost * ATTACK_STAMINA_PER_SECOND)
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
	if data.abilities.has("ERRATIC") and _rng.randf() < ERRATIC_CHANCE:
		var wander: float = _wander_step()
		if wander >= 0.0:
			return wander
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


## Un pas dans une direction libre tirée au hasard (ERRATIC). Renvoie le coût, ou -1.0 si aucune case n'est libre.
func _wander_step() -> float:
	var options: Array[Vector2i] = []
	for dir: Vector2i in RING:
		var candidate: Vector2i = grid_pos + dir
		if world.is_walkable(candidate) and not world.is_occupied(candidate) and world.swim_depth(candidate) == TerrainDB.SWIM_NONE:
			options.append(candidate)
	if options.is_empty():
		return -1.0
	var next_cell: Vector2i = options[_rng.randi() % options.size()]
	face(next_cell - grid_pos)
	grid_pos = next_cell
	position = Vector2(grid_pos * World.TILE_SIZE)
	return _finish(data.move_cost, _move_stamina_delta())


## Renvoie true si le monstre meurt. L'armure (data.armor) retire des PV à chaque coup, 1 PV au minimum.
func take_damage(amount: float) -> bool:
	var dealt: float = amount
	if data.armor > 0:
		dealt = maxf(amount - float(data.armor), 1.0)
	hp = maxf(hp - dealt, 0.0)
	_last_hurt = GameClock.elapsed_points
	wake()  # un dormeur frappé se réveille
	queue_redraw()
	if hp <= 0.0:
		if not _dead:
			_dead = true
			_on_death()
		return true
	_try_split()
	return false


## Lignes d'information (survol, mode regard) : PV, coûts, dégâts, PROBABILITÉS de toucher chaque partie du corps et compétences.
func get_tooltip_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("%s   PV %d/%d" % [data.display_name, ceili(hp), int(data.max_hp)])
	if time_penalty() > 0.0:
		lines.append("Essoufflé : actions +%d %% de durée" % roundi(time_penalty() * 100.0))
	if state == "sleep":
		lines.append("Endormi" + (" (embuscade : surgit à %d cases)" % roundi(AMBUSH_RANGE) if data.abilities.has("AMBUSH") else " : se réveille au bruit ou si l'on approche"))
	elif state == "guard":
		lines.append("En garde : tient son poste")
	if data.armor > 0:
		lines.append("Armure : -%d PV par coup reçu" % data.armor)
	if data.behavior == "passive":
		lines.append("Passif : fuit, ne se défend que s'il est acculé")
	elif data.behavior == "territorial":
		lines.append("Territorial : n'attaque que si on s'approche (à moins de %d cases)" % roundi(TERRITORY_RADIUS))
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
	for ability: String in data.abilities:
		var base: String = ability.substr(0, ability.find("(")) if ability.contains("(") else ability
		if ABILITY_TEXT.has(base):
			var arg: String = data.ability_arg(base)
			lines.append(String(ABILITY_TEXT[base]) + ((" (%s)" % arg) if arg != "" and base != "AURA_RAD" else ""))
	if not data.affixes.is_empty():
		lines.append("Modificateurs : " + ", ".join(PackedStringArray(data.affixes)))
	return lines

func get_tooltip_text() -> String:
	return "\n".join(get_tooltip_lines())


func _draw() -> void:
	var pivot := Vector2(World.TILE_SIZE / 2.0, World.TILE_SIZE - 10.0)  # bas et centre de la case
	if Fx.SHADOWS:
		var squeeze: float = 1.0 - _hop / 60.0
		draw_colored_polygon(Fx.ellipse_points(pivot + Vector2(0, 2), Fx.SHADOW_RADII * squeeze), Fx.SHADOW_COLOR)
	draw_set_transform(pivot + Vector2(0, -_hop), 0.0, Vector2(1.0 - _breath * 0.5, 1.0 + _breath))
	UlticaTiles.draw_sprite(self, _fg_sprite, -pivot, _tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if SHOW_FACING_ARROW:
		_draw_facing_arrow()
	if state == "sleep":
		draw_string(ThemeDB.fallback_font, Vector2(36, -82), "Zzz", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0.8, 0.9, 1.0))
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
