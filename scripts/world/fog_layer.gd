class_name FogLayer
extends Node2D
## Brouillard de guerre, dessiné PAR-DESSUS tout le reste du monde :
##   case visible              -> rien
##   case déjà vue (mémoire)   -> assombrie
##   case jamais vue / chunk non chargé -> noire
## Le monde est infini : on ne dessine que les cases affichables à l'écran, autour du joueur. Cette zone dépend de la taille de
## la fenêtre ET du zoom de la caméra : en dézoomant, le brouillard reste identique (rien de plus n'est visible), il couvre juste
## plus de cases. Les cases d'une même rangée et de même teinte sont fusionnées en un seul rectangle.
## Mode regard (LookUI) : la caméra peut être décalée de `look_offset` cases ; la zone dessinée s'étend d'autant, pour que le brouillard
## recouvre toujours l'écran (le mode regard ne révèle rien).

const MARGIN_CELLS: int = 3        # cases dessinées en plus du bord de l'écran
const MAX_HALF_CELLS: int = 260    # garde-fou (très grand écran, zoom minimal, caméra décalée)

const NONE: Color = Color(0, 0, 0, 0)
const REMEMBERED: Color = Color(0, 0, 0, 0.6)

var world: World
var look_offset: Vector2i = Vector2i.ZERO   # décalage de la caméra (mode regard), en cases


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


## Demi-taille de la zone affichée, en cases (x, y), selon la fenêtre, le zoom de la caméra et le décalage du mode regard.
func _half_extent() -> Vector2i:
	var zoom: float = 1.0
	if world.player != null and world.player.camera != null:
		zoom = maxf(world.player.camera.zoom.x, 0.05)
	var size: Vector2 = get_viewport().get_visible_rect().size
	var cells: float = World.TILE_SIZE * zoom
	return Vector2i(
		mini(ceili(size.x / (2.0 * cells)) + MARGIN_CELLS + absi(look_offset.x), MAX_HALF_CELLS),
		mini(ceili(size.y / (2.0 * cells)) + MARGIN_CELLS + absi(look_offset.y), MAX_HALF_CELLS))


func _color_at(pos: Vector2i) -> Color:
	if world.visible_cells.has(pos):
		return NONE
	# Toit : une fois le bâtiment aperçu, sa surface est connue même si l'intérieur ne l'est pas. Si le bâtiment est
	# actuellement visible, le toit l'est aussi (aucun brouillard) ; sinon il reste dans la mémoire (assombri).
	var chunk := world.chunks.chunk_at(pos) as Chunk
	if chunk != null and chunk.roof_known and chunk.key != world.roof_hidden_chunk \
			and chunk.roof.size() == Chunk.CELLS \
			and chunk.roof[ChunkManager.index_of(pos)] != Chunk.ROOF_NONE:
		return NONE if world.visible_roof_chunks.has(chunk.key) else REMEMBERED
	return REMEMBERED if world.chunks.is_seen(pos) else Color.BLACK


func _draw() -> void:
	if world == null or world.player == null:
		return
	var center: Vector2i = world.player.grid_pos
	var half: Vector2i = _half_extent()
	var left: int = center.x - half.x
	var right: int = center.x + half.x
	for y in range(center.y - half.y, center.y + half.y + 1):
		var run_start: int = left
		var run_color: Color = NONE
		for x in range(left, right + 2):   # une case de plus : vide la dernière suite de la rangée
			var color: Color = _color_at(Vector2i(x, y)) if x <= right else NONE
			if color != run_color:
				if run_color.a > 0.0:
					draw_rect(Rect2(Vector2(run_start, y) * World.TILE_SIZE, Vector2(x - run_start, 1) * World.TILE_SIZE), run_color)
				run_start = x
				run_color = color
