class_name AutoPath
extends RefCounted
## Chemin court (parcours en largeur, 4 directions) pour les déplacements automatiques du joueur : touche maintenue et double-clic.
## Il n'emprunte que les cases CONNUES du joueur (visibles ou déjà vues, voir World.is_known_walkable) : il contourne les arbres
## qu'on voit mais ne « devine » pas ce qui est caché.
##
## Deux modes :
##  - `prefer` nul (double-clic, touche * du mode regard) : parmi tous les plus courts chemins, on prend celui qui reste le plus PROCHE
##    de la ligne droite départ -> arrivée (escalier régulier, comme une diagonale) au lieu d'une longue ligne droite puis d'une autre.
##    Méthode : distances calculées depuis l'arrivée, puis descente depuis le départ en choisissant, à chaque pas, la case voisine
##    (une de moins en distance) la plus proche de la ligne.
##  - `prefer` non nul (touche maintenue) : direction visée ; à longueur égale, ses axes sont essayés en premier (le chemin reste plutôt droit).

const MAX_EXPANSIONS: int = 4000
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


## Chemin de `from` à `to` (les deux inclus), ou tableau vide. `radius` : le chemin reste dans ce carré autour du départ.
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


## Plus court chemin le plus proche de la ligne droite from -> to.
static func _find_smooth(world: World, from: Vector2i, to: Vector2i, radius: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var dist: Dictionary = {to: 0}
	var queue: Array[Vector2i] = [to]
	var head: int = 0
	var reached: bool = false
	while head < queue.size() and head < MAX_EXPANSIONS and not reached:
		var node: Vector2i = queue[head]
		head += 1
		var next_dist: int = int(dist[node]) + 1
		for dir in DIRS:
			var next: Vector2i = node + dir
			if dist.has(next):
				continue
			if absi(next.x - from.x) > radius or absi(next.y - from.y) > radius:
				continue
			if next != from and not world.is_known_walkable(next):  # le départ est toujours permis (le joueur peut nager)
				continue
			dist[next] = next_dist
			if next == from:
				reached = true
				break
			queue.append(next)
	if not reached:
		return empty
	var line: Vector2i = to - from
	var path: Array[Vector2i] = [from]
	var current: Vector2i = from
	while current != to:
		var best: Vector2i = current
		var best_score: int = 1 << 60
		var wanted: int = int(dist[current]) - 1
		for dir in DIRS:
			var next: Vector2i = current + dir
			if not dist.has(next) or int(dist[next]) != wanted:
				continue
			var offset: Vector2i = next - from
			var score: int = absi(offset.x * line.y - offset.y * line.x)  # écart à la ligne droite (produit vectoriel)
			if score < best_score:
				best_score = score
				best = next
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
