class_name Monster
extends Node2D
## Monstre : joue quand son "prochain moment d'action" est atteint.
## take_turn() fait UNE action et renvoie son coût en points d'action.
## Compétences (voir MonsterData) : attaque spéciale, effets d'état, tir à distance, hurlement, meute.

const IDLE_COST: float = 5.0   # rien à faire : on revient voir plus tard
const BLOCKED_COST: float = 1.0 # chemin bloqué : on attend un peu

var data: MonsterData
var world: World
var grid_pos: Vector2i = Vector2i.ZERO
var hp: float = 1.0
var next_action_time: float = 0.0
var has_target: bool = false            # sait où est (ou était) le joueur
var target_cell: Vector2i = Vector2i.ZERO
var spotted: bool = false               # déjà signalé au joueur (message « Vous apercevez... »)
var hidden_since: float = 0.0           # moment (points d'action) où il est sorti du champ de vision

var _rng := RandomNumberGenerator.new()
var _bg_sprite: String = ""
var _fg_sprite: String = ""
var _ranged_ready_at: float = 0.0       # moment (points d'action) où le prochain tir est possible
var _scream_ready_at: float = 0.0       # idem pour le hurlement
var _anim_time: float = 0.0
var _anim_phase: float = 0.0            # déphase la respiration d'un monstre à l'autre (purement visuel)
var _hop: float = 0.0
var _breath: float = 0.0


func _ready() -> void:
	position = Vector2(grid_pos * World.TILE_SIZE)
	# Chaque monstre garde la variante de sprite tirée à sa création.
	var variant_seed: int = randi()
	_anim_phase = float(variant_seed % 628) / 100.0
	_bg_sprite = UlticaTiles.pick_sprite(data.tile_id, "bg", variant_seed)
	_fg_sprite = UlticaTiles.pick_sprite(data.tile_id, "fg", variant_seed)


## Purement visuel : l'affichage glisse vers la case logique (déjà atteinte) avec un petit rebond.
func _process(delta: float) -> void:
	var left: float = Fx.glide(self, Vector2(grid_pos * World.TILE_SIZE), delta)
	_anim_time += delta
	_hop = Fx.hop_of(left)
	_breath = 0.0 if left > 0.0 else sin(_anim_time * 2.0 + _anim_phase) * Fx.BREATH
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
		if World.are_adjacent(grid_pos, player.grid_pos):
			return _attack_player()
		if has_target:
			if sees and _can_shoot(delta):
				return _shoot()
			if grid_pos == target_cell:
				has_target = false  # arrivé là où on a vu le joueur pour la dernière fois : plus personne
				return IDLE_COST
			return _move_toward(target_cell)
	return IDLE_COST


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
	EventBus.message_logged.emit("%s utilise %s : -%d PV." % [data.display_name, attack_label, int(damage)])
	world.player.take_damage(damage)
	return cost

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
	return data.ranged_cost

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
	return data.scream_cost

func _move_toward(cell: Vector2i) -> float:
	var path: Array[Vector2i] = world.find_path(grid_pos, cell)
	if path.size() < 2:
		has_target = false
		return IDLE_COST
	var next_cell: Vector2i = path[1]
	if world.is_occupied(next_cell):
		return BLOCKED_COST
	grid_pos = next_cell  # la position affichée suit en glissant (voir _process)
	position = Vector2(grid_pos * World.TILE_SIZE)
	return data.move_cost


## Renvoie true si le monstre meurt.
func take_damage(amount: float) -> bool:
	hp = maxf(hp - amount, 0.0)
	queue_redraw()
	return hp <= 0.0


## Lignes d'information (survol, mode regard) : PV, coûts, dégâts, PROBABILITÉS de toucher chaque partie du corps et compétences.
func get_tooltip_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("%s   PV %d/%d" % [data.display_name, ceili(hp), int(data.max_hp)])
	lines.append("Déplacement : %.1f pts" % data.move_cost)
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
		draw_colored_polygon(Fx.ellipse_points(pivot + Vector2(0, 2), Vector2(34.0, 11.0) * squeeze), Fx.SHADOW_COLOR)
	draw_set_transform(pivot + Vector2(0, -_hop), 0.0, Vector2(1.0 - _breath * 0.5, 1.0 + _breath))
	UlticaTiles.draw_sprite(self, _bg_sprite, -pivot)
	UlticaTiles.draw_sprite(self, _fg_sprite, -pivot)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Barre de vie au-dessus de la tête (le sprite dépasse de 64 px au-dessus de la case).
	var ratio: float = hp / data.max_hp
	draw_rect(Rect2(8, -72, (World.TILE_SIZE - 16.0) * ratio, 12), Color.RED)
