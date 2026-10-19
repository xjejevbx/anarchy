extends SceneTree
## Test de la nage (jalon 9b). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_swimming.gd
## Code de sortie 0 = tout est bon. Teste les données de terrain et les formules de stamina / noyade (fonctions statiques de Player).

var _failures: int = 0


func _initialize() -> void:
	# --- Terrains : profondeur de nage ---
	_check(TerrainDB.swim_depth(TerrainDB.index_of("t_water_sh")) == TerrainDB.SWIM_SHALLOW, "eau peu profonde : nage peu profonde")
	_check(TerrainDB.swim_depth(TerrainDB.index_of("t_swater_sh")) == TerrainDB.SWIM_SHALLOW, "eau de marais : nage peu profonde")
	_check(TerrainDB.swim_depth(TerrainDB.index_of("t_water_dp")) == TerrainDB.SWIM_DEEP, "eau profonde : nage profonde")
	for id in ["t_grass", "t_mud", "t_sand", "t_bridge", "t_pavement", "t_floor", "t_tree"]:
		_check(TerrainDB.swim_depth(TerrainDB.index_of(id)) == TerrainDB.SWIM_NONE, "%s : pas de nage" % id)
	_check(not TerrainDB.is_walkable(TerrainDB.index_of("t_water_dp")), "eau profonde toujours non praticable À PIED (monstres)")
	_check(TerrainDB.is_walkable(TerrainDB.index_of("t_water_sh")), "eau peu profonde toujours praticable à pied (monstres, gués)")
	_check(TerrainDB.swim_depth(-1) == TerrainDB.SWIM_NONE and TerrainDB.swim_depth(9999) == TerrainDB.SWIM_NONE, "swim_depth : index invalide = pas de nage")

	# --- Un vrai chunk d'océan profond : la case est bien nageable ---
	var found: bool = false
	for world_seed in [1, 42]:
		if found:
			break
		var world_map: WorldMap = WorldMap.for_seed(world_seed)
		for y in range(-30000, 30000, 1000):
			for x in range(-30000, 30000, 1000):
				var cell := Vector2i(x, y)
				if found or world_map.kind_at(cell) != WorldMap.Kind.OCEAN_DEEP:
					continue
				var data: PackedByteArray = ChunkGenerator.generate(world_seed, ChunkManager.key_of(cell))
				var terrain: int = data[ChunkManager.index_of(cell)]
				_check(TerrainDB.swim_depth(terrain) == TerrainDB.SWIM_DEEP, "seed %d : case d'océan profond %s = eau profonde nageable" % [world_seed, cell])
				found = true
	if not found:
		print("  AVERTISSEMENT - aucun océan profond trouvé dans le relevé (contrôle sur un vrai chunk ignoré)")

	# --- Stamina : à terre, rien ne change ---
	_check(is_equal_approx(Player.load_stamina_delta(0.5, Player.MOVE_REGEN_MAX), 0.3), "à terre, ratio 0,5 : +0,3 par pas")
	_check(is_equal_approx(Player.load_stamina_delta(1.0, Player.MOVE_REGEN_MAX), 0.0), "à terre, ratio 1 : effet nul")
	_check(is_equal_approx(Player.load_stamina_delta(2.0, Player.MOVE_REGEN_MAX), -6.0), "à terre, ratio 2 : -(2 x 1 + 4 x 1) = -6")

	# --- Nager coûte de la stamina, plus en eau profonde, et la surcharge s'ajoute ---
	var shallow_move: float = Player.swim_move_stamina_delta(TerrainDB.SWIM_SHALLOW, 0.0)
	var deep_move: float = Player.swim_move_stamina_delta(TerrainDB.SWIM_DEEP, 0.0)
	_check(shallow_move < 0.0, "nager en eau peu profonde coûte de la stamina même à vide (%.2f)" % shallow_move)
	_check(deep_move < shallow_move, "nager en eau profonde coûte plus qu'en eau peu profonde (%.2f < %.2f)" % [deep_move, shallow_move])
	_check(Player.swim_move_stamina_delta(TerrainDB.SWIM_SHALLOW, 1.5) < shallow_move, "la surcharge augmente le coût de la nage")
	_check(is_equal_approx(Player.swim_move_stamina_delta(TerrainDB.SWIM_SHALLOW, 0.9), shallow_move), "sans surcharge, la charge ne change pas le coût de la nage")

	# --- Attendre : planche en eau peu profonde, surplace en eau profonde ---
	_check(Player.swim_wait_stamina_delta(TerrainDB.SWIM_SHALLOW, 0.5) > 0.0, "eau peu profonde : attendre récupère (planche)")
	_check(is_equal_approx(Player.swim_wait_stamina_delta(TerrainDB.SWIM_SHALLOW, 0.5), Player.load_stamina_delta(0.5, Player.WAIT_REGEN_MAX)), "planche = même récupération qu'attendre à terre")
	_check(Player.swim_wait_stamina_delta(TerrainDB.SWIM_SHALLOW, 1.5) < 0.0, "eau peu profonde, inventaire trop plein : attendre fait perdre de la stamina")
	_check(Player.swim_wait_stamina_delta(TerrainDB.SWIM_DEEP, 0.0) < 0.0, "eau profonde : attendre coûte de la stamina, même à vide")
	_check(Player.swim_wait_stamina_delta(TerrainDB.SWIM_DEEP, 1.5) < Player.swim_wait_stamina_delta(TerrainDB.SWIM_DEEP, 0.0), "eau profonde : la surcharge aggrave le surplace")

	# --- Noyade (dégâts au torse) ---
	_check(Player.drown_damage(1.0) > 0.0, "noyade : dégâts positifs")
	_check(is_equal_approx(Player.drown_damage(2.0), 2.0 * Player.drown_damage(1.0)), "noyade : proportionnelle à la durée de l'action")
	_check(Player.drown_damage(1.0) * 20.0 < BodyPartDB.max_hp_of("torso") * 2.0, "noyade : plusieurs dizaines d'actions avant la mort (laisse le temps de réagir)")

	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
