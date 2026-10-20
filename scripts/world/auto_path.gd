class_name AutoPath
extends RefCounted
## Chemin court pour les déplacements automatiques du joueur : touche maintenue, double-clic et touche * du mode regard.
## Il n'emprunte que les cases CONNUES du joueur (visibles ou déjà vues, voir World.is_known_walkable) : il contourne les arbres
## qu'on voit mais ne « devine » pas ce qui est caché.
##
## Deux modes :
##  - `prefer` nul (double-clic, touche * du mode regard) : recherche en 8 directions. Un pas diagonal compte pour DEUX pas
##    orthogonaux (coût 2, comme 7 / 9 / 1 / 3) et n'est permis que si l'une des deux cases « de l'angle » est libre (même règle que
##    Player._try_diagonal). Parmi tous les chemins de même coût, on prend celui qui reste le plus PROCHE de la ligne droite
##    départ -> arrivée, les diagonales étant préférées à égalité. Méthode : coûts calculés depuis l'arrivée (Dijkstra à seaux),
##    puis descente depuis le départ en choisissant à chaque pas le voisin qui rapproche le plus de la ligne.
##  - `prefer` non nul (touche maintenue) : BFS 4 directions ; à longueur égale, les axes de la direction visée sont essayés en premier
##    (le chemin reste plutôt droit).

const MAX_EXPANSIONS: int = 6000
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const DIRS8: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP,
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
const ORTHO_COST: int = 1
const DIAGONAL_COST: int = 2   # une diagonale = deux actions


## Chemin de `from` à `to` (les deux inclus), ou tableau vide. `radius` : le chemin reste dans ce carré autour du départ.
## Sans `prefer`, le chemin peut contenir des pas diagonaux (cases consécutives en diagonale).
static func find(world: World, from: Vector2i, to: Vector2i, radius: int, prefer: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if from == to:
		var single: Array[Vector2i] = [from]
		return single
	if not world.is_known_walkable(to):
		return empty
	if prefer == Vector2i.ZERO:
		return _find_smooth(world, from, to, radius)
	return _find_preferred(world, from, to, radius, prefer)


static func _is_diagonal(dir: Vector2i) -> bool:
	return dir.x != 0 and dir.y != 0


static func _passable(world: World, cell: Vector2i, from: Vector2i) -> bool:
	return cell == from or world.is_known_walkable(cell)


## Le pas `dir` depuis `a` est-il permis ? Case d'arrivée connue et praticable (le départ est toujours permis : le joueur peut nager) ;
## en diagonale, au moins une des deux cases de l'angle doit être libre.
static func _step_ok(world: World, a: Vector2i, dir: Vector2i, from: Vector2i) -> bool:
	if not _passable(world, a + dir, from):
		return false
	if _is_diagonal(dir):
		return _passable(world, a + Vector2i(dir.x, 0), from) or _passable(world, a + Vector2i(0, dir.y), from)
	return true


## Chemin de plus faible coût (diagonale = 2) le plus proche de la ligne droite from -> to.
static func _find_smooth(world: World, from: Vector2i, to: Vector2i, radius: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var dist: Dictionary = {to: 0}
	var buckets: Array = [[to]]   # buckets[d] = cases de coût d (coûts entiers, pas de tas nécessaire)
	var expansions: int = 0
	var d: int = 0
	while d < buckets.size() and expansions < MAX_EXPANSIONS:
		for node: Vector2i in (buckets[d] as Array):
			if int(dist[node]) != d:
				continue  # entrée périmée (une case a été atteinte moins cher entre-temps)
			expansions += 1
			for dir in DIRS8:
				var next: Vector2i = node + dir
				if absi(next.x - from.x) > radius or absi(next.y - from.y) > radius:
					continue
				if not _step_ok(world, node, dir, from):
					continue
				var next_cost: int = d + (DIAGONAL_COST if _is_diagonal(dir) else ORTHO_COST)
				if dist.has(next) and int(dist[next]) <= next_cost:
					continue
				dist[next] = next_cost
				while buckets.size() <= next_cost:
					buckets.append([])
				(buckets[next_cost] as Array).append(next)
		if dist.has(from) and int(dist[from]) <= d:
			break
		d += 1
	if not dist.has(from):
		return empty
	var line: Vector2i = to - from
	var path: Array[Vector2i] = [from]
	var current: Vector2i = from
	while current != to:
		var best: Vector2i = current
		var best_score: int = 1 << 60
		var best_diagonal: bool = false
		for dir in DIRS8:
			var next: Vector2i = current + dir
			var diagonal: bool = _is_diagonal(dir)
			var step: int = DIAGONAL_COST if diagonal else ORTHO_COST
			if not dist.has(next) or int(dist[next]) + step != int(dist[current]):
				continue
			var offset: Vector2i = next - from
			var score: int = absi(offset.x * line.y - offset.y * line.x)  # écart à la ligne droite (produit vectoriel)
			if score < best_score or (score == best_score and diagonal and not best_diagonal):
				best_score = score
				best = next
				best_diagonal = diagonal
		if best == current:
			return empty  # ne devrait pas arriver
		path.append(best)
		current = best
	return path


## Parcours en largeur depuis le départ ; à longueur égale, les axes de `prefer` sont essayés en premier.
static func _find_preferred(world: World, from: Vector2i, to: Vector2i, radius: int, prefer: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var dirs: Array[Vector2i] = _ordered_dirs(prefer)
	var came: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size() and head < MAX_EXPANSIONS:
		var node: Vector2i = queue[head]
		head += 1
		if node == to:
			return _rebuild(came, from, to)
		for dir in dirs:
			var next: Vector2i = node + dir
			if came.has(next):
				continue
			if absi(next.x - from.x) > radius or absi(next.y - from.y) > radius:
				continue
			if not world.is_known_walkable(next):
				continue
			came[next] = node
			queue.append(next)
	return empty


static func _ordered_dirs(prefer: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if prefer.x != 0:
		out.append(Vector2i(signi(prefer.x), 0))
	if prefer.y != 0:
		out.append(Vector2i(0, signi(prefer.y)))
	for dir in DIRS:
		if not out.has(dir):
			out.append(dir)
	return out


static func _rebuild(came: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [to]
	var current: Vector2i = to
	while current != from:
		current = came[current]
		path.append(current)
	path.reverse()
	return path
