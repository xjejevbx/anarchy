class_name FieldOfView
extends RefCounted
## Champ de vision par "recursive shadowcasting" (algorithme classique des roguelikes).
## Renvoie l'ensemble des cases visibles depuis `origin`, dans un rayon donné.
## Les cases opaques (murs, arbres) sont elles-mêmes visibles, mais bloquent ce qui est derrière.

# Transformations des 8 octants : [xx, xy, yx, yy]
const OCTANTS: Array = [
	[1, 0, 0, 1], [0, 1, 1, 0], [0, -1, 1, 0], [-1, 0, 0, 1],
	[-1, 0, 0, -1], [0, -1, -1, 0], [0, 1, -1, 0], [1, 0, 0, -1],
]


static func compute(world: World, origin: Vector2i, radius: int) -> Dictionary:
	var lit: Dictionary = {origin: true}
	for o: Array in OCTANTS:
		_cast(world, lit, origin, 1, 1.0, 0.0, radius, o[0], o[1], o[2], o[3])
	return lit


static func _cast(world: World, lit: Dictionary, origin: Vector2i, row: int, start: float, end: float,
		radius: int, xx: int, xy: int, yx: int, yy: int) -> void:
	if start < end:
		return
	var radius_sq: int = radius * radius
	var new_start: float = 0.0
	for j in range(row, radius + 1):
		var dx: int = -j - 1
		var dy: int = -j
		var blocked: bool = false
		while dx <= 0:
			dx += 1
			var cell := Vector2i(origin.x + dx * xx + dy * xy, origin.y + dx * yx + dy * yy)
			var l_slope: float = (dx - 0.5) / (dy + 0.5)
			var r_slope: float = (dx + 0.5) / (dy - 0.5)
			if start < r_slope:
				continue
			elif end > l_slope:
				break
			if dx * dx + dy * dy <= radius_sq and world.has_terrain(cell):
				lit[cell] = true
			var opaque: bool = world.is_opaque(cell)
			if blocked:
				if opaque:
					new_start = r_slope
					continue
				blocked = false
				start = new_start
			elif opaque and j < radius:
				blocked = true
				_cast(world, lit, origin, j + 1, start, l_slope, radius, xx, xy, yx, yy)
				new_start = r_slope
		if blocked:
			break
