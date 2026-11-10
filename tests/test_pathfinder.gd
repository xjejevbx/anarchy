extends SceneTree
## Test de l'A* des monstres (8 directions, règle de l'angle). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_pathfinder.gd
## Utilise l'arène de test : la zone de départ (rayon 3,5 autour de (5, 5)) est sans arbre. Code de sortie 0 = tout est bon.

var _failures: int = 0


func _initialize() -> void:
	var world := World.new()
	world.use_arena = true
	root.add_child(world)
	world.chunks.update_around(Vector2i(5, 5))

	# L'arène déterministe peut placer des arbres dans le coin testé : on force les cases du test à être libres.
	# Les murs de l'arène en (0, 1) et (1, 0) restent des murs.
	var grass: int = TerrainDB.index_of("t_grass")
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 2)]:
		world.chunks.set_terrain(cell, grass)

	# Ligne droite en diagonale : 4 pas diagonaux (5 cases), pas un escalier de 8 pas.
	var diagonal: Array[Vector2i] = PathFinder.find(world, Vector2i(3, 3), Vector2i(7, 7))
	_check(diagonal.size() == 5, "(3,3) -> (7,7) : 5 cases avec des diagonales (%d)" % diagonal.size())
	var diagonal_steps: int = 0
	for i in range(1, diagonal.size()):
		var d: Vector2i = diagonal[i] - diagonal[i - 1]
		if d.x != 0 and d.y != 0:
			diagonal_steps += 1
	_check(diagonal_steps == 4, "le chemin utilise 4 pas diagonaux (%d)" % diagonal_steps)
	# Ligne droite orthogonale : inchangée.
	var straight: Array[Vector2i] = PathFinder.find(world, Vector2i(3, 5), Vector2i(7, 5))
	_check(straight.size() == 5, "(3,5) -> (7,5) : 5 cases en ligne droite (%d)" % straight.size())
	# Départ = arrivée, arrivée non praticable (mur de l'arène en (0, 0)).
	_check(PathFinder.find(world, Vector2i(5, 5), Vector2i(5, 5)).size() == 1, "même case : chemin d'une case")
	_check(PathFinder.find(world, Vector2i(5, 5), Vector2i(0, 0)).is_empty(), "arrivée dans un mur : aucun chemin")
	# Règle de l'angle : la case (1, 1) a deux murs voisins vers le coin (0, 1) et (1, 0) : on ne s'y glisse pas en diagonale depuis (2, 2)
	# sans passer par une case libre (ici (1, 2) et (2, 1) sont libres, donc le pas est permis).
	var corner: Array[Vector2i] = PathFinder.find(world, Vector2i(2, 2), Vector2i(1, 1))
	_check(corner.size() == 2, "(2,2) -> (1,1) : une diagonale permise (cases d'angle libres) (%d)" % corner.size())
	# Les pas ne dépassent jamais une case de distance (Chebyshev).
	var continuous: bool = true
	for i in range(1, diagonal.size()):
		var d2: Vector2i = diagonal[i] - diagonal[i - 1]
		if maxi(absi(d2.x), absi(d2.y)) != 1:
			continuous = false
	_check(continuous, "cases consécutives toujours voisines")

	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
