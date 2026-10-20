class_name Fx
extends RefCounted
## Effets purement VISUELS : ombres, glissement des entités, poussière de pas, éclaboussures, vent sur les arbres.
## Aucun effet ne touche à la logique du jeu (cases, temps, tours) : tout peut être désactivé ici sans conséquence.
## Les particules sont créées dans `World.fx` (calque au-dessus des entités, sous le brouillard).

# --- Interrupteurs et réglages ---
const SHADOWS: bool = true
const SMOOTH_MOVE: bool = true
const DUST: bool = true
const SPLASH: bool = true
const WIND: bool = true

const SHADOW_COLOR: Color = Color(0, 0, 0, 0.3)
const SHADOW_RADII: Vector2 = Vector2(46.0, 15.0)   # rayons de l'ombre du joueur et des monstres (pixels, case de 128 px)
const MOVE_SMOOTHING: float = 28.0     # plus grand = glisse plus vite vers la case (la logique est, elle, instantanée)
const HOP_HEIGHT: float = 9.0          # petit rebond (pixels) pendant un pas
const BREATH: float = 0.012            # respiration à l'arrêt (étirement vertical)
const WIND_AMPLITUDE: float = 0.035    # balancement du haut de la canopée, en part de la hauteur du sprite
const WIND_SPEED: float = 1.3
const WIND_SHADER_PATH: String = "res://shaders/tree_wind.gdshader"

static var _wind_material: ShaderMaterial = null
static var _soft_texture: Texture2D = null


# --- Géométrie ---

## Points d'une ellipse (pour les ombres et les ondes). `closed` : répète le premier point (pour draw_polyline).
static func ellipse_points(center: Vector2, radii: Vector2, segments: int = 20, closed: bool = false) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle: float = TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	if closed:
		points.append(points[0])
	return points


# --- Glissement ---

## Rapproche le nœud de `target` (pixels) de façon exponentielle et renvoie la distance restante.
## La case logique est déjà atteinte : seul l'affichage rattrape. Téléportation (> 3 cases) : on saute directement.
static func glide(node: Node2D, target: Vector2, delta: float) -> float:
	var gap: Vector2 = target - node.position
	if not SMOOTH_MOVE or gap.length() > World.TILE_SIZE * 3.0:
		node.position = target
		return 0.0
	node.position += gap * (1.0 - exp(-MOVE_SMOOTHING * delta))
	var left: float = (target - node.position).length()
	if left < 0.5:
		node.position = target
		return 0.0
	return left


## Hauteur du rebond selon la distance restante à parcourir (0 à l'arrêt).
static func hop_of(left: float) -> float:
	if left <= 0.0:
		return 0.0
	return sin(clampf(left / World.TILE_SIZE, 0.0, 1.0) * PI) * HOP_HEIGHT


# --- Vent ---

## Matériau partagé par tous les arbres (null si le vent est désactivé ou le shader absent).
static func wind_material() -> ShaderMaterial:
	if not WIND:
		return null
	if _wind_material == null:
		var shader := load(WIND_SHADER_PATH) as Shader
		if shader == null:
			return null
		_wind_material = ShaderMaterial.new()
		_wind_material.shader = shader
		_wind_material.set_shader_parameter("amplitude", WIND_AMPLITUDE)
		_wind_material.set_shader_parameter("speed", WIND_SPEED)
	return _wind_material


# --- Particules ---

static func _soft() -> Texture2D:
	if _soft_texture == null:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		gradient.offsets = PackedFloat32Array([0.0, 1.0])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 32
		texture.height = 32
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		_soft_texture = texture
	return _soft_texture


static func _fade(color: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color, Color(color, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	return gradient


static func _emitter(world: World, pos: Vector2, amount: int, lifetime: float, color: Color) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.position = pos
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.texture = _soft()
	particles.color_ramp = _fade(color)
	particles.finished.connect(particles.queue_free)
	world.fx.add_child(particles)
	particles.emitting = true
	return particles


## Petit nuage de poussière.
static func dust(world: World, pos: Vector2, color: Color, amount: int) -> void:
	var p: CPUParticles2D = _emitter(world, pos, amount, 0.55, color)
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 45.0
	p.damping_min = 60.0
	p.damping_max = 90.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 14.0


## Gouttes qui retombent, onde à la surface et, en eau profonde, quelques bulles.
static func splash(world: World, pos: Vector2, deep: bool) -> void:
	var drops: CPUParticles2D = _emitter(world, pos, 16 if deep else 10, 0.6, Color(0.78, 0.9, 1.0, 0.9))
	drops.direction = Vector2(0, -1)
	drops.spread = 55.0
	drops.gravity = Vector2(0, 700)
	drops.initial_velocity_min = 140.0
	drops.initial_velocity_max = 260.0
	drops.scale_amount_min = 0.12
	drops.scale_amount_max = 0.25
	var ripple := Ripple.new()
	ripple.position = pos
	world.fx.add_child(ripple)
	if deep:
		var bubbles: CPUParticles2D = _emitter(world, pos, 4, 1.0, Color(1, 1, 1, 0.6))
		bubbles.explosiveness = 0.3
		bubbles.direction = Vector2(0, -1)
		bubbles.spread = 40.0
		bubbles.gravity = Vector2(0, -60)
		bubbles.initial_velocity_min = 20.0
		bubbles.initial_velocity_max = 50.0
		bubbles.scale_amount_min = 0.15
		bubbles.scale_amount_max = 0.25


## Couleur de la poussière sur un terrain (alpha 0 = aucune).
static func dust_color(world: World, cell: Vector2i) -> Color:
	match TerrainDB.id_of(world.chunks.terrain_index(cell)):
		"t_sand":
			return Color(0.88, 0.80, 0.58, 0.6)
		"t_dirt", "t_mud", "t_field":
			return Color(0.55, 0.42, 0.28, 0.55)
		"t_grass", "t_grass_dead", "t_grass_long", "t_moss":
			return Color(0.55, 0.58, 0.38, 0.35)
		"t_pavement", "t_pavement_y", "t_sidewalk", "t_concrete":
			return Color(0.75, 0.75, 0.75, 0.3)
	return Color(0, 0, 0, 0)


## Effets d'un pas du joueur : éclaboussures dans l'eau, poussière sinon (sprint : partout ; marche : sable et terre ; accroupi : rien).
static func footstep(world: World, from_cell: Vector2i, to_cell: Vector2i, sprint: bool, crouch: bool,
		was_swimming: bool, swimming: bool) -> void:
	if world == null or world.fx == null:
		return
	if swimming:
		if SPLASH:
			splash(world, _feet(to_cell), world.is_deep_water(to_cell))
		return
	if was_swimming:
		if SPLASH:
			splash(world, _feet(from_cell), false)
		return
	if not DUST or crouch:
		return
	var color: Color = dust_color(world, from_cell)
	if color.a <= 0.0:
		return
	if sprint:
		dust(world, _feet(from_cell), color, 7)
	elif color.a >= 0.5:
		dust(world, _feet(from_cell), Color(color, color.a * 0.8), 3)


static func _feet(cell: Vector2i) -> Vector2:
	return Vector2(cell * World.TILE_SIZE) + Vector2(World.TILE_SIZE / 2.0, World.TILE_SIZE * 0.9)


## Onde qui s'élargit à la surface de l'eau.
class Ripple extends Node2D:
	var age: float = 0.0
	var duration: float = 0.7
	var max_radius: float = 60.0

	func _process(delta: float) -> void:
		age += delta
		if age >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = age / duration
		var radius: float = max_radius * (0.3 + 0.7 * k)
		draw_polyline(Fx.ellipse_points(Vector2.ZERO, Vector2(radius, radius * 0.4), 24, true),
			Color(1, 1, 1, 0.5 * (1.0 - k)), 3.0)
