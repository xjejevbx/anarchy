class_name TestArena
extends RefCounted
## Arène de test (menu principal > « Arène de test ») : carte fermée, multi-zones et multi-étages, qui sert à essayer
## toutes les fonctionnalités du jeu sans dépendre de la génération procédurale.
##
## Organisation volontairement simple et centralisée ici : chaque fonctionnalité a SA zone (camp de départ, maison témoin,
## bassin de nage, arène de combat, bestiaire, lave) et ses coordonnées fixes. Pour tester une future fonctionnalité :
## 1) ajouter une zone ou un objet ci-dessous (terrain / mobilier / bestiaire / objets au sol) ;
## 2) ajouter l'étape correspondante dans scripts/ui/arena_guide_ui.gd.
## Tout est une FONCTION PURE de (seed, case, étage) : aucun état global, aucune dépendance à l'ordre de génération.
##
## Surface (88 x 60) :
##   x  1..19, y  1..19 : camp de départ (herbe, objets d'essai autour de (5, 5))
##   x 25..44, y  3..19 : maison témoin (toit calculé, portes, fenêtres, escaliers vers +1 et -1) ;
##                         à l'étage +1, les fenêtres laissent voir la surface en contrebas
##   x 48..72, y  1..25 : bassin (sable, eau peu profonde puis profonde) avec faune aquatique
##   x 26..53, y 30..54 : arène de combat (béton, clôture, zombies d'entraînement)
##   x  4..19, y 28..54 : bestiaire (terre, tous les types de monstres, endormis)
##   x 75..84, y  3..11 : lave décorative (roche tout autour)
##   chemins en trottoir : départ -> maison -> arène / bestiaire.
## Étages : +1 = étage de la maison ; -1 = sous-sol (roche + salle sous la maison, porte intérieure).

const WIDTH: int = 88
const HEIGHT: int = 60
const SPAWN_POS: Vector2i = Vector2i(5, 5)   # départ du joueur (dégagé, herbe)
const SEED_TEXT: String = "arene-de-test"
const CLEAR_RADIUS: float = 3.5               # pas d'arbre autour du départ
const TREE_DENSITY: float = 0.10

const HOUSE: Rect2i = Rect2i(25, 3, 20, 17)   # murs compris (x 25..44, y 3..19)
const HOUSE_DOORS: Array[Vector2i] = [Vector2i(25, 11), Vector2i(34, 19)]
const HOUSE_WINDOWS: Array[Vector2i] = [Vector2i(25, 7), Vector2i(35, 3), Vector2i(44, 7), Vector2i(38, 19)]
const STAIRS_UP: Vector2i = Vector2i(29, 6)     # surface : t_stairs_up -> étage +1
const STAIRS_DOWN: Vector2i = Vector2i(40, 16)  # surface : t_stairs_down -> sous-sol -1

const POND_SHORE: Rect2i = Rect2i(48, 1, 25, 25)  # sable (x 48..72, y 1..25)
const POND: Rect2i = Rect2i(50, 3, 21, 21)        # eau (x 50..70, y 3..23)
const POND_DEEP: Rect2i = Rect2i(54, 7, 13, 13)   # eau profonde (x 54..66, y 7..19)
const COMBAT: Rect2i = Rect2i(26, 30, 28, 25)     # x 26..53, y 30..54
const BESTIARY: Rect2i = Rect2i(4, 28, 16, 27)    # x 4..19, y 28..54
const LAVA: Rect2i = Rect2i(75, 3, 10, 9)         # roche (x 75..84, y 3..11)
const LAVA_CORE: Rect2i = Rect2i(76, 4, 8, 7)     # lave (x 76..83, y 4..10)

# Chemins en trottoir : ils passent APRÈS les zones (et ouvrent la clôture de l'arène).
const PATH_EAST: Rect2i = Rect2i(13, 10, 12, 2)    # départ -> porte ouest (x 13..24, y 10..11)
const PATH_SOUTH: Rect2i = Rect2i(23, 11, 2, 33)   # porte ouest -> arène (x 23..24, y 11..43)
const PATH_ARENA: Rect2i = Rect2i(23, 41, 5, 3)    # entrée de l'arène (x 23..27, y 41..43)
const PATH_BESTIARY: Rect2i = Rect2i(12, 12, 2, 17)  # départ -> bestiaire (x 12..13, y 12..28)

# Mobilier fixe. Les coordonnées évitent portes, fenêtres et escaliers.
const FURNITURE_SURFACE: Array = [
	[Vector2i(42, 4), "f_bed"], [Vector2i(37, 4), "f_fridge"], [Vector2i(38, 4), "f_counter"],
	[Vector2i(26, 4), "f_bookcase"], [Vector2i(27, 5), "f_sofa"], [Vector2i(43, 7), "f_bathtub"],
	[Vector2i(32, 9), "f_table"], [Vector2i(31, 9), "f_chair"], [Vector2i(33, 9), "f_chair"],
	[Vector2i(32, 8), "f_chair"], [Vector2i(32, 10), "f_chair"], [Vector2i(43, 10), "f_crate"],
	[Vector2i(42, 14), "f_dresser"], [Vector2i(26, 18), "f_locker"], [Vector2i(43, 18), "f_safe"],
]
const FURNITURE_UPSTAIRS: Array = [
	[Vector2i(42, 4), "f_bed"], [Vector2i(26, 4), "f_bookcase"], [Vector2i(32, 9), "f_table"],
	[Vector2i(31, 9), "f_chair"], [Vector2i(42, 14), "f_dresser"], [Vector2i(43, 18), "f_crate"],
]
const FURNITURE_BASEMENT: Array = [
	[Vector2i(27, 5), "f_crate"], [Vector2i(30, 6), "f_surgery_table"], [Vector2i(42, 5), "f_hospital_bed"],
	[Vector2i(41, 8), "f_gurney"], [Vector2i(39, 15), "f_crate"], [Vector2i(28, 16), "f_safe"],
	[Vector2i(27, 17), "f_locker"], [Vector2i(42, 17), "f_morgue_drawer"],
]


## Terrain d'un chunk de l'arène (un octet par case, index TerrainDB).
static func generate(world_seed: int, key: Vector3i) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(Chunk.CELLS)
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var cell := Vector2i(key.x * Chunk.SIZE + lx, key.y * Chunk.SIZE + ly)
			data[ly * Chunk.SIZE + lx] = TerrainDB.index_of(terrain_id_at(world_seed, cell, key.z))
	return data


## Mobilier d'un chunk de l'arène (0 = rien, sinon index FurnitureDB).
static func generate_furniture(key: Vector3i) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(Chunk.CELLS)
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var cell := Vector2i(key.x * Chunk.SIZE + lx, key.y * Chunk.SIZE + ly)
			var furniture_id: String = furniture_id_at(cell, key.z)
			if furniture_id != "":
				data[ly * Chunk.SIZE + lx] = FurnitureDB.index_of(furniture_id)
	return data


## Id de terrain d'une case à un étage donné ; les coordonnées hors carte donnent mur / roche / vide.
static func terrain_id_at(world_seed: int, cell: Vector2i, z: int) -> String:
	if z > 0:
		return _upper_terrain(cell) if z == 1 else "t_air"
	if z < 0:
		return _basement_terrain(cell) if z == -1 else "t_rock"
	return _surface_terrain(world_seed, cell)


static func _surface_terrain(world_seed: int, cell: Vector2i) -> String:
	if not _inside_map(cell):
		return "t_wall_arena"
	if cell == STAIRS_UP:
		return "t_stairs_up"
	if cell == STAIRS_DOWN:
		return "t_stairs_down"
	if LAVA_CORE.has_point(cell):
		return "t_lava"
	if LAVA.has_point(cell):
		return "t_rock"
	if HOUSE.has_point(cell):
		if _is_perimeter(HOUSE, cell):
			if HOUSE_DOORS.has(cell):
				return "t_door"
			if HOUSE_WINDOWS.has(cell):
				return "t_window"
			return "t_wall_house"
		return "t_floor"
	if POND_SHORE.has_point(cell):
		if POND.has_point(cell):
			return "t_water_dp" if POND_DEEP.has_point(cell) else "t_water_sh"
		return "t_sand"
	# Les chemins passent AVANT l'arène de combat : ils ouvrent sa clôture côté ouest (entrée en trottoir).
	if _in_any_path(cell):
		return "t_sidewalk"
	if COMBAT.has_point(cell):
		if _is_perimeter(COMBAT, cell):
			return "t_fence"
		return "t_concrete"
	if BESTIARY.has_point(cell):
		return "t_dirt"
	if Vector2(cell).distance_to(Vector2(SPAWN_POS)) > CLEAR_RADIUS \
			and WorldRng.chance(world_seed, WorldRng.LAYER_TERRAIN, cell.x, cell.y, 0, TREE_DENSITY):
		return "t_tree"
	return "t_grass"


static func _upper_terrain(cell: Vector2i) -> String:
	if cell == STAIRS_UP:
		return "t_stairs_down"   # même case que l'escalier de montée de la surface
	if not HOUSE.has_point(cell):
		return "t_air"
	if _is_perimeter(HOUSE, cell):
		return "t_window" if HOUSE_WINDOWS.has(cell) else "t_wall_house"
	return "t_floor"


static func _basement_terrain(cell: Vector2i) -> String:
	if cell == STAIRS_DOWN:
		return "t_stairs_up"     # même case que l'escalier de descente de la surface
	if not HOUSE.has_point(cell) or _is_perimeter(HOUSE, cell):
		return "t_rock"
	if cell.x == 34:             # cloison intérieure est / ouest, avec une porte à tester
		return "t_door" if cell.y == 11 else "t_wall_house"
	return "t_concrete"


static func furniture_id_at(cell: Vector2i, z: int) -> String:
	match z:
		0:
			return _furniture_in(FURNITURE_SURFACE, cell)
		1:
			return _furniture_in(FURNITURE_UPSTAIRS, cell)
		-1:
			return _furniture_in(FURNITURE_BASEMENT, cell)
	return ""


static func _furniture_in(entries: Array, cell: Vector2i) -> String:
	for entry: Array in entries:
		if entry[0] == cell:
			return String(entry[1])
	return ""


static func _inside_map(cell: Vector2i) -> bool:
	return cell.x > 0 and cell.y > 0 and cell.x < WIDTH - 1 and cell.y < HEIGHT - 1


static func _is_perimeter(rect: Rect2i, cell: Vector2i) -> bool:
	return cell.x == rect.position.x or cell.y == rect.position.y \
		or cell.x == rect.position.x + rect.size.x - 1 or cell.y == rect.position.y + rect.size.y - 1


static func _in_any_path(cell: Vector2i) -> bool:
	return PATH_EAST.has_point(cell) or PATH_SOUTH.has_point(cell) \
		or PATH_ARENA.has_point(cell) or PATH_BESTIARY.has_point(cell)


## Monstres du bestiaire : un représentant de chaque archétype et de chaque capacité actuelle (armure, aura,
## charge, constriction, grab, garde, dormeur, erratique, porteur de butin, vol, nage, etc.), placés sur des cases fixes.
## `state` vaut « sleep » pour qu'ils n'attaquent pas le joueur avant qu'il ne s'approche (terrain d'observation, pas un piège).
static func bestiary() -> Array[Dictionary]:
	return [
		# Rangée 1 : zombies de base.
		{"monster": "zombie", "cell": Vector2i(5, 29)}, {"monster": "zombie_child", "cell": Vector2i(8, 29)},
		{"monster": "zombie_fast", "cell": Vector2i(11, 29)}, {"monster": "zombie_crawler", "cell": Vector2i(14, 29)},
		{"monster": "zombie_brute", "cell": Vector2i(17, 29)},
		# Rangée 2 : attaques à distance et capacités.
		{"monster": "zombie_spitter", "cell": Vector2i(5, 32)}, {"monster": "zombie_screecher", "cell": Vector2i(8, 32)},
		{"monster": "zombie_electric", "cell": Vector2i(11, 32)}, {"monster": "zombie_soldier", "cell": Vector2i(14, 32)},
		{"monster": "zombie_dog", "cell": Vector2i(17, 32)},
		# Rangée 3 : animaux, charge et gros gabarits.
		{"monster": "wolf", "cell": Vector2i(5, 35)}, {"monster": "giant_spider", "cell": Vector2i(8, 35)},
		{"monster": "bear", "cell": Vector2i(11, 35)}, {"monster": "zombie_hulk", "cell": Vector2i(14, 35)},
		{"monster": "boar", "cell": Vector2i(17, 35)},
		# Rangée 4 : effets d'état, explosion et spécialistes.
		{"monster": "zombie_acidic", "cell": Vector2i(5, 38)}, {"monster": "zombie_bloated", "cell": Vector2i(8, 38)},
		{"monster": "zombie_gasbag", "cell": Vector2i(11, 38)}, {"monster": "zombie_necro", "cell": Vector2i(14, 38)},
		{"monster": "zombie_master", "cell": Vector2i(17, 38)},
		# Rangée 5 : mutants et expériences.
		{"monster": "zombie_predator", "cell": Vector2i(5, 41)}, {"monster": "frog_mutant", "cell": Vector2i(8, 41)},
		{"monster": "experiment_blob", "cell": Vector2i(11, 41)}, {"monster": "experiment_bloated", "cell": Vector2i(14, 41)},
		{"monster": "experiment_swarm", "cell": Vector2i(17, 41)},
		# Rangée 6 : volants.
		{"monster": "crow", "cell": Vector2i(5, 44)}, {"monster": "crow_mutant", "cell": Vector2i(8, 44)},
		{"monster": "mosquito_swarm", "cell": Vector2i(11, 44)}, {"monster": "vulture_mutant", "cell": Vector2i(14, 44)},
		{"monster": "seagull_mutant", "cell": Vector2i(17, 44)},
		# Rangée 7 : explosions, armure et tir en rafale.
		{"monster": "zombie_grenadier", "cell": Vector2i(5, 47)}, {"monster": "zombie_flamer", "cell": Vector2i(8, 47)},
		{"monster": "fire_hound", "cell": Vector2i(11, 47)}, {"monster": "experiment_acid_hound", "cell": Vector2i(14, 47)},
		{"monster": "zombie_swat", "cell": Vector2i(17, 47)},
		# Rangée 8 : auras, constriction, grab et garde.
		{"monster": "zombie_irradiated", "cell": Vector2i(5, 50)}, {"monster": "zombie_frozen", "cell": Vector2i(8, 50)},
		{"monster": "python_giant", "cell": Vector2i(11, 50)}, {"monster": "zombie_grabber", "cell": Vector2i(14, 50)},
		{"monster": "zombie_sniper", "cell": Vector2i(17, 50)},
		# Rangée 9 : butin, dormeur, erratique, spores et armure légère.
		{"monster": "zombie_hoarder", "cell": Vector2i(5, 53)}, {"monster": "zombie_patient", "cell": Vector2i(8, 53)},
		{"monster": "zombie_drunk", "cell": Vector2i(11, 53)}, {"monster": "zombie_overgrown", "cell": Vector2i(14, 53)},
		{"monster": "zombie_tough", "cell": Vector2i(17, 53)},
		# Arène de combat : cibles faciles pour le combat au corps à corps.
		{"monster": "zombie_child", "cell": Vector2i(34, 36)}, {"monster": "zombie_child", "cell": Vector2i(36, 36)},
		# Bassin : nageurs et faune aquatique (peu profonde puis profonde).
		{"monster": "zombie_swimmer", "cell": Vector2i(52, 5)}, {"monster": "zombie_drowned", "cell": Vector2i(68, 5)},
		{"monster": "piranha_swarm", "cell": Vector2i(56, 9)}, {"monster": "jellyfish", "cell": Vector2i(58, 9)},
		{"monster": "eel_electric", "cell": Vector2i(60, 9)}, {"monster": "shark", "cell": Vector2i(62, 9)},
		{"monster": "shark_mutant", "cell": Vector2i(64, 9)}, {"monster": "squid_giant", "cell": Vector2i(56, 15)},
		{"monster": "kraken", "cell": Vector2i(58, 15)},
	]


## Objets de test au sol : {cell, item, count?, level?}. Le niveau vaut 0 (surface) par défaut.
static func ground_items() -> Array[Dictionary]:
	return [
		# Autour du départ (inventaire, ramassage, équipement, contenants).
		{"cell": Vector2i(6, 5), "item": "backpack_military"}, {"cell": Vector2i(6, 5), "item": "backpack"},
		{"cell": Vector2i(6, 5), "item": "bag_curtain"},
		{"cell": Vector2i(5, 6), "item": "jacket_light"}, {"cell": Vector2i(5, 6), "item": "pants_cargo"},
		{"cell": Vector2i(5, 6), "item": "hat_ball"},
		{"cell": Vector2i(4, 5), "item": "2x4"}, {"cell": Vector2i(4, 5), "item": "sheet_metal_small"},
		{"cell": Vector2i(4, 5), "item": "pipe"}, {"cell": Vector2i(4, 5), "item": "stick"},
		{"cell": Vector2i(5, 4), "item": "can_beans", "count": 4},
		{"cell": Vector2i(5, 4), "item": "bottle_plastic", "count": 2},
		{"cell": Vector2i(5, 4), "item": "rope_6"}, {"cell": Vector2i(6, 6), "item": "antibiotics", "count": 3},
		# Maison et étage.
		{"cell": Vector2i(29, 9), "item": "antibiotics", "count": 2},
		{"cell": Vector2i(30, 9), "item": "can_beans", "count": 2},
		{"cell": Vector2i(30, 10), "item": "backpack", "level": 1},
		# Sous-sol.
		{"cell": Vector2i(38, 15), "item": "antibiotics", "count": 2, "level": -1},
		{"cell": Vector2i(40, 12), "item": "rope_6", "level": -1},
		{"cell": Vector2i(28, 8), "item": "backpack", "level": -1},
		# Arène de combat et bord du bassin.
		{"cell": Vector2i(28, 42), "item": "pipe"}, {"cell": Vector2i(29, 42), "item": "stick"},
		{"cell": Vector2i(49, 22), "item": "rope_6"}, {"cell": Vector2i(72, 22), "item": "sheet_metal_small"},
	]
