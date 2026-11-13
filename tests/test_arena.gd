extends SceneTree
## Test de l'arène de test (menu principal > « Arène de test »). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_arena.gd
## Vérifie la carte fixe (zones, maison, bassin, lave, chemins, étages), le toit de la maison, le mobilier,
## les escaliers, les objets au sol, le bestiaire (cases compatibles avec le domaine, capacités couvertes)
## et le guide pas à pas. Charge l'arène par le VRAI chemin du menu (GameSession.Request.ARENA + main.tscn)
## pour vérifier aussi le contenu de démonstration créé par Main.
## Code de sortie 0 = tout est bon.

const TEST_ARENA = preload("res://scripts/worldgen/test_arena.gd")
const GUIDE_SCRIPT = preload("res://scripts/ui/arena_guide_ui.gd")
const MAIN_SCENE_PATH: String = "res://main.tscn"

const SEED: int = 123456789

# Capacités/mécaniques des monstres que le bestiaire doit couvrir (préfixe avant « (… »).
const REQUIRED_ABILITIES: Array[String] = [
	"AMBUSH", "AQUATIC", "ARMOR", "AURA_RAD", "BURST", "CHARGE", "COLD_AURA", "CONSTRICT",
	"DORMANT", "ERRATIC", "EXPLODE", "FIRE_AURA", "FLY", "GRAB", "GUARD", "LEAP", "LOOT_CARRIER",
	"RAISE", "REGEN", "SPLIT", "SPORE", "STEALTH", "SUMMON", "SWARM", "SWIM", "THROW",
]

var _failures: int = 0


func _initialize() -> void:
	GameClock.elapsed_points = 0.0
	_check_generation()
	_check_house_and_floors()
	_check_zones()
	_check_furniture()
	_check_ground_items()
	_check_bestiary_data()
	_check_live_arena()
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


# --- Carte pure (fonctions de TestArena) ---

func _check_generation() -> void:
	print("Arène : génération et bords")
	var key := Vector3i(0, 0, 0)
	var a: PackedByteArray = TEST_ARENA.generate(SEED, key)
	var b: PackedByteArray = TEST_ARENA.generate(SEED, key)
	_check(a == b, "génération déterministe à seed égale")
	_check(ChunkGenerator.generate(SEED, key, true) == a, "ChunkGenerator délègue bien l'arène à TestArena")
	_check(ChunkGenerator.generate_furniture(SEED, key, true) == TEST_ARENA.generate_furniture(key),
		"ChunkGenerator délègue bien le mobilier de l'arène")

	for x: int in [0, TEST_ARENA.WIDTH - 1]:
		var border_ok: bool = true
		for y in TEST_ARENA.HEIGHT:
			if TEST_ARENA.terrain_id_at(SEED, Vector2i(x, y), 0) != "t_wall_arena":
				border_ok = false
				break
		_check(border_ok, "bord vertical x=%d : mur sur toute la hauteur" % x)
	for y: int in [0, TEST_ARENA.HEIGHT - 1]:
		var border_ok: bool = true
		for x in TEST_ARENA.WIDTH:
			if TEST_ARENA.terrain_id_at(SEED, Vector2i(x, y), 0) != "t_wall_arena":
				border_ok = false
				break
		_check(border_ok, "bord horizontal y=%d : mur sur toute la largeur" % y)
	_check(TEST_ARENA.terrain_id_at(SEED, Vector2i(-1, 5), 0) == "t_wall_arena", "hors carte à gauche : mur")
	_check(TEST_ARENA.terrain_id_at(SEED, Vector2i(TEST_ARENA.WIDTH, 5), 0) == "t_wall_arena", "hors carte à droite : mur")
	_check(TEST_ARENA.terrain_id_at(SEED, TEST_ARENA.SPAWN_POS, 0) != "t_tree", "départ dégagé (pas d'arbre)")
	_check(TerrainDB.is_walkable(TerrainDB.index_of(TEST_ARENA.terrain_id_at(SEED, TEST_ARENA.SPAWN_POS, 0))),
		"case de départ praticable")


func _check_house_and_floors() -> void:
	print("Arène : maison, toit et étages")
	_check(_id(Vector2i(30, 10), 0) == "t_floor", "maison : intérieur en plancher")
	_check(_id(Vector2i(25, 11), 0) == "t_door", "maison : porte ouest")
	_check(_id(Vector2i(34, 19), 0) == "t_door", "maison : porte sud")
	_check(_id(Vector2i(35, 3), 0) == "t_window", "maison : fenêtre nord")
	_check(_id(Vector2i(44, 7), 0) == "t_window", "maison : fenêtre est")
	_check(_id(Vector2i(25, 6), 0) == "t_wall_house", "maison : mur ouest")
	_check(_id(Vector2i(30, 10), 1) == "t_floor", "étage +1 : plancher")
	_check(_id(Vector2i(26, 3), 1) == "t_wall_house", "étage +1 : mur")
	_check(_id(Vector2i(20, 10), 1) == "t_air", "étage +1 : vide hors maison")
	_check(TerrainDB.is_air(TerrainDB.index_of(_id(Vector2i(20, 10), 1))), "étage +1 : le vide est bien du t_air")
	_check(_id(Vector2i(30, 10), -1) == "t_concrete", "sous-sol : salle en béton")
	_check(_id(Vector2i(34, 11), -1) == "t_door", "sous-sol : porte de cloison")
	_check(_id(Vector2i(34, 10), -1) == "t_wall_house", "sous-sol : cloison")
	_check(_id(Vector2i(20, 10), -1) == "t_rock", "sous-sol : roche hors maison")
	_check(_id(Vector2i(30, 10), 2) == "t_air", "étage +2 : vide")
	_check(_id(Vector2i(30, 10), -2) == "t_rock", "sous-sol -2 : roche")

	_check(_id(TEST_ARENA.STAIRS_UP, 0) == "t_stairs_up", "escalier de montée (surface)")
	_check(_id(TEST_ARENA.STAIRS_UP, 1) == "t_stairs_down", "escalier inverse à l'étage +1")
	_check(_id(TEST_ARENA.STAIRS_DOWN, 0) == "t_stairs_down", "escalier de descente (surface)")
	_check(_id(TEST_ARENA.STAIRS_DOWN, -1) == "t_stairs_up", "escalier inverse au sous-sol")


func _check_zones() -> void:
	print("Arène : zones et chemins")
	_check(_id(Vector2i(60, 13), 0) == "t_water_dp", "bassin : eau profonde au centre")
	_check(_id(Vector2i(51, 5), 0) == "t_water_sh", "bassin : eau peu profonde")
	_check(_id(Vector2i(48, 5), 0) == "t_sand", "bassin : plage de sable")
	_check(_id(Vector2i(40, 40), 0) == "t_concrete", "arène de combat : béton")
	_check(_id(Vector2i(26, 40), 0) == "t_fence", "arène de combat : clôture")
	_check(_id(Vector2i(26, 42), 0) == "t_sidewalk", "entrée ouest de l'arène de combat (trottoir)")
	_check(_id(Vector2i(10, 40), 0) == "t_dirt", "bestiaire : terre")
	_check(_id(Vector2i(80, 7), 0) == "t_lava", "zone de lave : lave")
	_check(_id(Vector2i(75, 7), 0) == "t_rock", "zone de lave : roche autour")
	_check(_id(Vector2i(20, 10), 0) == "t_sidewalk", "chemin départ -> maison")
	_check(_id(Vector2i(13, 10), 0) == "t_sidewalk", "chemin départ -> bestiaire")


func _check_furniture() -> void:
	print("Arène : mobilier")
	_check(TEST_ARENA.furniture_id_at(Vector2i(42, 4), 0) == "f_bed", "surface : lit")
	_check(TEST_ARENA.furniture_id_at(Vector2i(38, 4), 0) == "f_counter", "surface : comptoir")
	_check(TEST_ARENA.furniture_id_at(Vector2i(42, 4), 1) == "f_bed", "étage +1 : lit")
	_check(TEST_ARENA.furniture_id_at(Vector2i(30, 6), -1) == "f_surgery_table", "sous-sol : table d'opération")
	_check(TEST_ARENA.furniture_id_at(Vector2i(42, 17), -1) == "f_morgue_drawer", "sous-sol : tiroir de morgue")
	_check(TEST_ARENA.furniture_id_at(Vector2i(30, 6), 0) == "", "pas de mobilier du sous-sol à la surface")

	var placed: int = 0
	for cell: Vector2i in [Vector2i(42, 4), Vector2i(32, 9)]:
		var index: int = FurnitureDB.index_of(TEST_ARENA.furniture_id_at(cell, 0))
		if index > 0:
			placed += 1
	_check(placed == 2, "les meubles de la surface existent dans FurnitureDB")
	_check(not FurnitureDB.is_walkable(FurnitureDB.index_of("f_bed")), "un lit bloque le déplacement")
	_check(FurnitureDB.is_walkable(FurnitureDB.index_of("f_chair")), "une chaise est traversable")


func _check_ground_items() -> void:
	print("Arène : objets au sol")
	var known: Dictionary = {}
	for item_id: String in ItemDB.ids():
		known[item_id] = true
	var levels: Dictionary = {}
	for entry: Dictionary in TEST_ARENA.ground_items():
		var item_id: String = String(entry["item"])
		var cell: Vector2i = entry["cell"]
		var level: int = int(entry.get("level", 0))
		levels[level] = true
		_check(known.has(item_id), "objet connu : %s" % item_id)
		_check(level >= -1 and level <= 1, "étage valide pour %s : %d" % [item_id, level])
		var terrain_id: String = TEST_ARENA.terrain_id_at(SEED, cell, level)
		var terrain_ok: bool = TerrainDB.is_walkable(TerrainDB.index_of(terrain_id))
		var furniture_id: String = TEST_ARENA.furniture_id_at(cell, level)
		var furniture_ok: bool = furniture_id == "" or FurnitureDB.is_walkable(FurnitureDB.index_of(furniture_id))
		_check(terrain_ok and furniture_ok,
			"case libre pour %s en (%d, %d), étage %d" % [item_id, cell.x, cell.y, level])
	for level: int in [0, 1, -1]:
		_check(levels.has(level), "des objets de test existent à l'étage %d" % level)


func _check_bestiary_data() -> void:
	print("Arène : bestiaire (données)")
	var cells: Dictionary = {}
	var abilities: Dictionary = {}
	for entry: Dictionary in TEST_ARENA.bestiary():
		var monster_id: String = String(entry["monster"])
		var cell: Vector2i = entry["cell"]
		_check(MonsterDB.has_id(monster_id), "monstre connu : %s" % monster_id)
		_check(not cells.has(cell), "case unique pour %s en (%d, %d)" % [monster_id, cell.x, cell.y])
		cells[cell] = true
		if not MonsterDB.has_id(monster_id):
			continue
		var data: MonsterData = MonsterDB.create(monster_id)
		for ability: String in data.abilities:
			abilities[ability.get_slice("(", 0)] = true
	for ability: String in REQUIRED_ABILITIES:
		_check(abilities.has(ability), "capacité couverte par le bestiaire : %s" % ability)


# --- Arène réelle, lancée par le chemin du menu ---

func _check_live_arena() -> void:
	print("Arène : lancement par le menu")
	GameSession.request_arena()
	var main: Node = load(MAIN_SCENE_PATH).instantiate()
	main.set("show_missing_sprites", false)   # audit des sprites inutile et bruyant en test headless
	root.add_child(main)

	var world: World = null
	var guide: Node = null
	for child: Node in main.get_children():
		if child is World:
			world = child
		elif child.get_script() == GUIDE_SCRIPT:
			guide = child
	_check(world != null, "le menu lance bien l'arène (World créé)")
	_check(guide != null, "le guide de test est ajouté à l'interface")
	if world == null:
		return
	_check(world.use_arena, "le monde est en mode arène")
	_check(world.get_level() == 0, "départ à la surface")
	var player: Player = world.player
	_check(player != null, "le joueur existe")
	if player == null:
		return
	_check(player.grid_pos == TEST_ARENA.SPAWN_POS, "le joueur apparaît sur la case de départ")
	_check(world.monsters.size() == TEST_ARENA.bestiary().size(),
		"tout le bestiaire est placé (%d monstres)" % TEST_ARENA.bestiary().size())
	_check(world.get_monster_at(TEST_ARENA.SPAWN_POS) == null, "aucun monstre sur la case de départ")

	# Tous les objets de démonstration sont réellement au sol, au bon étage.
	var missing_items: Array[String] = []
	for entry: Dictionary in TEST_ARENA.ground_items():
		var cell: Vector2i = entry["cell"]
		var level: int = int(entry.get("level", 0))
		var wanted: String = String(entry["item"])
		var found: bool = false
		for item: Item in world.get_ground_items_at(level, cell):
			if item.id == wanted:
				found = true
				break
		if not found:
			missing_items.append("%s@%d:(%d,%d)" % [wanted, level, cell.x, cell.y])
	_check(missing_items.is_empty(), "objets au sol placés%s" % ("" if missing_items.is_empty() else " : " + ", ".join(missing_items)))

	# Chaque monstre est sur une case compatible avec son domaine de déplacement.
	var bad_cells: Array[String] = []
	for entry: Dictionary in TEST_ARENA.bestiary():
		var monster_id: String = String(entry["monster"])
		var cell: Vector2i = entry["cell"]
		var data: MonsterData = MonsterDB.create(monster_id)
		var domain: int = Monster.domain_of(data)
		var monster: Monster = world.get_monster_at(cell)
		if monster == null or not world.monster_can_enter(cell, domain):
			bad_cells.append("%s@(%d,%d)" % [monster_id, cell.x, cell.y])
	_check(bad_cells.is_empty(), "cases du bestiaire compatibles avec le domaine%s" % ("" if bad_cells.is_empty() else " : " + ", ".join(bad_cells)))

	# Toit de la maison : calculé aussi en arène (surface uniquement).
	var house_chunk: Chunk = world.chunks.chunk_at(Vector2i(30, 10))
	_check(house_chunk != null, "chunk de la maison chargé")
	if house_chunk != null:
		var index: int = ChunkManager.index_of(Vector2i(30, 10))
		_check(house_chunk.roof.size() == Chunk.CELLS, "empreinte de toit calculée en arène")
		_check(house_chunk.roof.size() == Chunk.CELLS and house_chunk.roof[index] == Chunk.ROOF_COVER,
			"intérieur de la maison couvert par le toit")
		var door_chunk: Chunk = world.chunks.chunk_at(Vector2i(25, 11))
		var door_index: int = ChunkManager.index_of(Vector2i(25, 11))
		_check(door_chunk != null and door_chunk.roof.size() == Chunk.CELLS \
			and door_chunk.roof[door_index] == Chunk.ROOF_OPENING, "porte visible sous le toit")

	# Mobilier chargé et praticabilité.
	var bed_index: int = world.chunks.furniture_at_level(Vector2i(42, 4), 0)
	_check(bed_index == FurnitureDB.index_of("f_bed"), "mobilier chargé dans le chunk de la maison")
	_check(not world.is_walkable(Vector2i(42, 4)), "le lit bloque la case")

	# Escaliers utilisables dans les deux sens.
	_check(world.use_stairs(TEST_ARENA.STAIRS_UP, 1), "montée surface -> étage +1")
	_check(world.get_level() == 1, "étage actif = +1")
	# Depuis un étage, les cases vides s'appuient sur la surface : terrain, mobilier et toits du dessous.
	_check(world.chunks.surface_terrain_at(Vector2i(20, 10)) == TerrainDB.index_of("t_sidewalk"),
		"étage +1 : chemin de la surface visible en contrebas")
	_check(world.chunks.surface_terrain_at(Vector2i(6, 5)) == TerrainDB.index_of("t_grass"),
		"étage +1 : herbe de la surface visible en contrebas")
	_check(world.chunks.surface_furniture_at(Vector2i(42, 4)) == FurnitureDB.index_of("f_bed"),
		"étage +1 : mobilier de la surface accessible")
	_check(world.chunks.surface_roof_at(Vector2i(30, 10)) == Chunk.ROOF_COVER,
		"étage +1 : toit de la maison calculé en contrebas")
	_check(world.chunks.surface_roof_at(Vector2i(20, 10)) == Chunk.ROOF_NONE,
		"étage +1 : pas de toit sur le chemin")
	_check(guide != null and guide._sees_open_air(world), "guide : une fenêtre d'étage laisse voir le vide extérieur")
	_check(world.use_stairs(TEST_ARENA.STAIRS_UP, -1), "descente étage +1 -> surface")
	_check(world.get_level() == 0, "étage actif = 0")
	_check(world.use_stairs(TEST_ARENA.STAIRS_DOWN, -1), "descente surface -> sous-sol")
	_check(world.get_level() == -1, "étage actif = -1")
	_check(world.use_stairs(TEST_ARENA.STAIRS_DOWN, 1), "remontée sous-sol -> surface")
	_check(world.get_level() == 0, "étage actif = 0 après remontée")

	# Guide : étapes uniques, textes/hints renseignés, validation et réinitialisation.
	var steps: Array = guide.get_script().get_script_constant_map().get("STEPS", [])
	_check(steps.size() >= 20, "guide : au moins 20 étapes (%d)" % steps.size())
	var ids: Dictionary = {}
	for step: Dictionary in steps:
		var step_id: String = String(step.get("id", ""))
		_check(step_id != "" and not ids.has(step_id), "guide : identifiant unique « %s »" % step_id)
		ids[step_id] = true
		_check(String(step.get("text", "")) != "" and String(step.get("hint", "")) != "",
			"guide : texte et aide renseignés pour « %s »" % step_id)
	guide._mark("move")
	_check(guide._done.has("move"), "guide : une étape peut être validée")
	guide._mark("move")
	_check(guide._done.size() == 1, "guide : une étape validée n'est comptée qu'une fois")
	guide._reset()
	_check(guide._done.is_empty(), "guide : réinitialisation")
	_check(guide._current_index() == 0, "guide : la première étape redevient courante")


# --- Utilitaires ---

func _id(cell: Vector2i, z: int) -> String:
	return TEST_ARENA.terrain_id_at(SEED, cell, z)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
