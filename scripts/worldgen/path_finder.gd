class_name PathFinder
extends RefCounted
## A* borné à la demande (8 directions) sur les chunks chargés. Remplace l'ancien AStarGrid2D global : il n'y a plus de grille
## unique à reconstruire quand le monde bouge. Un chemin trop long ou trop compliqué est abandonné (le monstre reste alors sur place).
##
## Règles de la diagonale (les mêmes que pour le joueur, voir AutoPath) : un pas diagonal vaut DEUX pas orthogonaux (le monstre le
## paie en temps : voir Monster._move_toward) et n'est permis que si l'une des deux cases « de l'angle » est praticable (on ne se
## faufile pas entre deux murs / arbres qui se touchent par un coin). Coûts ENTIERS : à longueur égale, la diagonale est légèrement
## préférée (19 au lieu de 20), sinon A* choisirait presque toujours l'escalier de pas orthogonaux.

# --- Réglages ---
const MAX_EXPANSIONS: int = 1500   # nombre maximal de cases explorées par recherche
const MAX_RADIUS: int = 40         # le chemin ne s'éloigne jamais de plus de N cases du départ
const ORTHO_COST: int = 10
const DIAGONAL_COST: int = 19      # un peu moins que 2 x ORTHO_COST : à égalité de temps, on préfère la diagonale
const HEURISTIC_PER_STEP: int = 9  # distance de Manhattan x 9 : jamais supérieure au coût réel (admissible)

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]


## Chemin de `from` à `to` (les deux inclus), ou tableau vide si introuvable. Même convention que AStarGrid2D.get_id_path.
## Deux cases consécutives du chemin peuvent être en diagonale.
static func find(world: World, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if from == to:
		var single: Array[Vector2i] = [from]
		return single
	if not world.is_walkable(to):
		return empty
	var open: Dictionary = {}             # seaux : open[f] = cases de coût estimé f (coûts entiers, pas de tas nécessaire)
	var g_score: Dictionary = {from: 0}
	var came_from: Dictionary = {}
	var closed: Dictionary = {}
	var start_f: int = _heuristic(from, to)
	_push(open, start_f, from)
	var current_f: int = start_f
	var max_f: int = start_f
	var expansions: int = 0
	while expansions < MAX_EXPANSIONS:
		while current_f <= max_f and (not open.has(current_f) or (open[current_f] as Array).is_empty()):
			current_f += 1
		if current_f > max_f:
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
			var diagonal: bool = dir.x != 0 and dir.y != 0
			if diagonal and not (world.is_walkable(node + Vector2i(dir.x, 0)) or world.is_walkable(node + Vector2i(0, dir.y))):
				continue  # règle de l'angle
			var next_g: int = g + (DIAGONAL_COST if diagonal else ORTHO_COST)
			if next_g < int(g_score.get(next, 1 << 30)):
				g_score[next] = next_g
				came_from[next] = node
				var f: int = next_g + _heuristic(next, to)
				_push(open, f, next)
				current_f = mini(current_f, f)
				max_f = maxi(max_f, f)
	return empty


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.y - b.y)) * HEURISTIC_PER_STEP


static func _push(open: Dictionary, f: int, node: Vector2i) -> void:
	if not open.has(f):
		open[f] = []
	(open[f] as Array).append(node)


static func _rebuild(came_from: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [to]
	var current: Vector2i = to
	while current != from:
		current = came_from[current]
		path.append(current)
	path.reverse()
	return path
