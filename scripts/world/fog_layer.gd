class_name FogLayer
extends Node2D
## Brouillard de guerre, dessiné PAR-DESSUS tout le reste du monde :
##   case visible              -> rien
##   case déjà vue (mémoire)   -> assombrie
##   case jamais vue / chunk non chargé -> noire
## Le monde est infini : on ne dessine que les cases proches du joueur (au-delà, rien n'est affichable à l'écran).

const DRAW_RADIUS: int = 40  # en cases autour du joueur (doit dépasser la moitié de la fenêtre, en cases)

var world: World


func _draw() -> void:
	if world == null or world.player == null:
		return
	var center: Vector2i = world.player.grid_pos
	var cell_size := Vector2(World.TILE_SIZE, World.TILE_SIZE)
	var remembered := Color(0, 0, 0, 0.6)
	var chunks: ChunkManager = world.chunks
	for y in range(center.y - DRAW_RADIUS, center.y + DRAW_RADIUS + 1):
		for x in range(center.x - DRAW_RADIUS, center.x + DRAW_RADIUS + 1):
			var pos := Vector2i(x, y)
			if world.visible_cells.has(pos):
				continue
			var color: Color = remembered if chunks.is_seen(pos) else Color.BLACK
			draw_rect(Rect2(Vector2(pos * World.TILE_SIZE), cell_size), color)
