class_name AutoPath
extends RefCounted
## Chemin court (parcours en largeur, 4 directions) pour les déplacements automatiques du joueur : touche maintenue et double-clic.
## Il n'emprunte que les cases CONNUES du joueur (visibles ou déjà vues, voir World.is_known_walkable) : il contourne les arbres
## qu'on voit mais ne « devine » pas ce qui est caché. `prefer` : direction visée ; à longueur égale, ses axes sont essayés en premier
## (le chemin reste plutôt droit).

const MAX_EXPANSIONS: int = 4000


## Chemin de `from` à `to` (les deux inclus), ou tableau vide. `radius` : le chemin reste dans ce carré autour du départ.
static func find(world: World, from: Vector2i, to: Vector2i, radius: int, prefer: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if from == to:
		var single: Array[Vector2i] = [from]
		return single
	if not world.is_known_walkable(to):
		return empty
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
	for dir in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
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
