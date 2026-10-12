class_name PathFinder
extends RefCounted
## A* borné à la demande (4 directions, coût 1 par case) sur les chunks chargés. Remplace l'ancien AStarGrid2D
## global : il n'y a plus de grille unique à reconstruire quand le monde bouge. Un chemin trop long ou trop
## compliqué est abandonné (le monstre reste alors sur place).

# --- Réglages ---
const MAX_EXPANSIONS: int = 1500   # nombre maximal de cases explorées par recherche
const MAX_RADIUS: int = 40         # le chemin ne s'éloigne jamais de plus de N cases du départ

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


## Chemin de `from` à `to` (les deux inclus), ou tableau vide si introuvable. Même convention que AStarGrid2D.get_id_path.
static func find(world: World, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if from == to:
		var single: Array[Vector2i] = [from]
		return single
	if not world.is_walkable(to):
		return empty
	var open: Array = []                  # seaux : open[f] = cases de coût estimé f (coûts entiers, pas de tas nécessaire)
	var g_score: Dictionary = {from: 0}
	var came_from: Dictionary = {}
	var closed: Dictionary = {}
	_push(open, _heuristic(from, to), from)
	var current_f: int = 0
	var expansions: int = 0
	while expansions < MAX_EXPANSIONS:
		while current_f < open.size() and (open[current_f] as Array).is_empty():
			current_f += 1
		if current_f >= open.size():
			break
		var node: Vector2i = (open[current_f] as Array).pop_back()
		if closed.has(node):
			continue
		if node == to:
			return _rebuild(came_from, from, to)
		closed[node] = true
		expansions += 1
		var g: int = g_score[node]
		for dir in DIRS:
			var next: Vector2i = node + dir
			if closed.has(next):
				continue
			if absi(next.x - from.x) > MAX_RADIUS or absi(next.y - from.y) > MAX_RADIUS:
				continue
			if not world.is_walkable(next):
				continue
			var next_g: int = g + 1
			if next_g < int(g_score.get(next, 1 << 30)):
				g_score[next] = next_g
				came_from[next] = node
				var f: int = next_g + _heuristic(next, to)
				_push(open, f, next)
				current_f = mini(current_f, f)
	return empty


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _push(open: Array, f: int, node: Vector2i) -> void:
	while open.size() <= f:
		open.append([])
	(open[f] as Array).append(node)


static func _rebuild(came_from: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [to]
	var current: Vector2i = to
	while current != from:
		current = came_from[current]
		path.append(current)
	path.reverse()
	return path
