class_name Monster
extends Node2D
## Monstre : joue quand son "prochain moment d'action" est atteint.
## take_turn() fait UNE action et renvoie son coût en points d'action.

const IDLE_COST: float = 5.0   # rien à faire : on revient voir plus tard
const BLOCKED_COST: float = 1.0 # chemin bloqué : on attend un peu

var data: MonsterData
var world: World
var grid_pos: Vector2i = Vector2i.ZERO
var hp: float = 1.0
var next_action_time: float = 0.0
var has_target: bool = false            # sait où est (ou était) le joueur
var target_cell: Vector2i = Vector2i.ZERO

var _rng := RandomNumberGenerator.new()
var _bg_sprite: String = ""
var _fg_sprite: String = ""


func _ready() -> void:
	position = Vector2(grid_pos * World.TILE_SIZE)
	# Chaque monstre garde la variante de sprite tirée à sa création.
	var variant_seed: int = randi()
	_bg_sprite = UlticaTiles.pick_sprite(data.tile_id, "bg", variant_seed)
	_fg_sprite = UlticaTiles.pick_sprite(data.tile_id, "fg", variant_seed)


func take_turn() -> float:
	var player: Player = world.player
	var delta: Vector2i = player.grid_pos - grid_pos
	var distance: int = maxi(absi(delta.x), absi(delta.y))  # distance en cases (diagonales incluses)
	# Le joueur et le monstre se voient mutuellement : on s'appuie sur le champ de vision du
	# joueur (les arbres et les murs bloquent donc aussi la vue des monstres).
	if distance <= data.detect_range and world.is_visible_cell(grid_pos):
		alert(player.grid_pos)
	if World.are_adjacent(grid_pos, player.grid_pos):
		return _attack_player()
	if has_target:
		if grid_pos == target_cell:
			has_target = false  # arrivé là où on a vu le joueur pour la dernière fois : plus personne
			return IDLE_COST
		return _move_toward(target_cell)
	return IDLE_COST


## Le monstre sait où chercher (il a vu le joueur, ou s'est fait frapper).
func alert(cell: Vector2i) -> void:
	has_target = true
	target_cell = cell


func _attack_player() -> float:
	var use_special: bool = data.special_cost > 0.0 and _rng.randf() < data.special_chance
	var attack_label: String = data.special_name if use_special else data.attack_name
	var damage: float = data.special_damage if use_special else data.attack_damage
	var cost: float = data.special_cost if use_special else data.attack_cost
	EventBus.message_logged.emit("%s utilise %s : -%d PV." % [data.display_name, attack_label, int(damage)])
	world.player.take_damage(damage)
	return cost


func _move_toward(cell: Vector2i) -> float:
	var path: Array[Vector2i] = world.find_path(grid_pos, cell)
	if path.size() < 2:
		has_target = false
		return IDLE_COST
	var next_cell: Vector2i = path[1]
	if world.is_occupied(next_cell):
		return BLOCKED_COST
	grid_pos = next_cell
	position = Vector2(grid_pos * World.TILE_SIZE)
	return data.move_cost


## Renvoie true si le monstre meurt.
func take_damage(amount: float) -> bool:
	hp = maxf(hp - amount, 0.0)
	queue_redraw()
	return hp <= 0.0


func get_tooltip_text() -> String:
	var lines: Array[String] = []
	lines.append("%s   PV %d/%d" % [data.display_name, ceili(hp), int(data.max_hp)])
	lines.append("Déplacement : %.1f pts" % data.move_cost)
	lines.append("%s : %.1f pts, %d dégâts" % [data.attack_name, data.attack_cost, int(data.attack_damage)])
	if data.special_cost > 0.0:
		lines.append("%s (spéciale, %d%%) : %.1f pts, %d dégâts" % [
			data.special_name, roundi(data.special_chance * 100.0), data.special_cost, int(data.special_damage)])
	return "\n".join(lines)


func _draw() -> void:
	UlticaTiles.draw_sprite(self, _bg_sprite, Vector2.ZERO)
	UlticaTiles.draw_sprite(self, _fg_sprite, Vector2.ZERO)
	# Barre de vie au-dessus de la tête (le sprite dépasse de 16 px au-dessus de la case).
	var ratio: float = hp / data.max_hp
	draw_rect(Rect2(2, -18, (World.TILE_SIZE - 4.0) * ratio, 3), Color.RED)
