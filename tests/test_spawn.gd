extends SceneTree
## Test du jalon 6a (bestiaire en JSON, population ambiante, monstres rattachés aux chunks). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_spawn.gd
## Code de sortie 0 = tout est bon. Complète tests/test_monsters.gd (qui contrôle les 14 monstres d'origine).

const RANGE: int = 3            # chunks de -3 à +3 autour de l'origine pour le déterminisme (49 chunks)
const SAMPLE_RANGE: int = 5     # chunks autour du départ pour les contrôles de placement

var _failures: int = 0


func _initialize() -> void:
	var seeds: Array[int] = []
	for text in ["1", "42", "cataclysme", "", "-7"]:
		seeds.append(WorldRng.seed_from_text(text))
	_check_data()
	_check_determinism(seeds)
	_check_placement(seeds)
	_check_persistence(WorldRng.seed_from_text("cataclysme"))
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


# --- Données ---

func _check_data() -> void:
	var errors: Array[String] = MonsterDB.errors()
	_check(errors.is_empty(), "monsters.json : aucune erreur de chargement %s" % str(errors))
	_check(MonsterDB.ids().size() >= 14, "au moins 14 monstres (%d)" % MonsterDB.ids().size())
	for legacy_id in MonsterData.IDS:
		_check(MonsterDB.has_id(legacy_id), "monstre d'origine présent : %s" % legacy_id)
	var zombie: MonsterData = MonsterDB.create("zombie")
	_check(is_equal_approx(zombie.max_hp, 20.0) and is_equal_approx(zombie.attack_damage, 4.0) and is_equal_approx(zombie.special_damage, 9.0)
		and is_equal_approx(zombie.special_infection, 0.5), "zombie : valeurs d'origine conservées dans le JSON")
	_check(MonsterDB.create("wolf").pack_radius == 12 and MonsterDB.create("zombie_screecher").scream_radius == 35, "loup (meute) et hurleur (cri) conservés")
	_check(MonsterDB.create("zombie_cop").armor == 1 and MonsterDB.create("crab_giant").armor == 2, "capacité ARMOR(n) lue (policier 1, crabe 2)")
	_check(MonsterDB.create("deer").behavior == "passive" and MonsterDB.create("boar").behavior == "territorial", "comportements passif / territorial lus")

	var names: Dictionary = {}
	for monster_id in MonsterDB.ids():
		var d: MonsterData = MonsterDB.create(monster_id)
		_check(d.id == monster_id and d.display_name != "", "%s : id et nom renseignés" % monster_id)
		_check(not names.has(d.display_name), "%s : nom unique (%s)" % [monster_id, d.display_name])
		names[d.display_name] = true
		_check(d.max_hp > 0.0 and d.move_cost > 0.0 and d.attack_cost > 0.0 and d.attack_damage > 0.0 and d.detect_range > 0, "%s : PV, coûts, dégâts positifs" % monster_id)
		_check(d.threat >= 1 and d.threat <= MonsterDB.MAX_THREAT, "%s : menace entre 1 et %d (%d)" % [monster_id, MonsterDB.MAX_THREAT, d.threat])
		_check_zones(monster_id + " attaque", d.attack_zones)
		_check_effect(monster_id + " attaque", d.attack_effect)
		if d.special_cost > 0.0:
			_check(d.special_name != "" and d.special_damage > 0.0 and d.special_chance > 0.0 and d.special_chance < 1.0, "%s : spéciale complète" % monster_id)
			_check_zones(monster_id + " spéciale", d.special_zones)
			_check_effect(monster_id + " spéciale", d.special_effect)
		if d.ranged_range > 0:
			_check(d.ranged_name != "" and d.ranged_cost > 0.0 and d.ranged_damage > 0.0 and d.ranged_cooldown > 0.0, "%s : tir à distance complet" % monster_id)
			_check_zones(monster_id + " tir", d.ranged_zones)
			_check_effect(monster_id + " tir", d.ranged_effect)
		if d.scream_radius > 0:
			_check(d.scream_cost > 0.0 and d.scream_cooldown > 0.0, "%s : hurlement complet" % monster_id)

	var spawn_errors: Array[String] = SpawnGenerator.errors()
	_check(spawn_errors.is_empty(), "spawn_groups.json et ecology.json : aucune erreur %s" % str(spawn_errors))
	_check(not SpawnGenerator.group_ids().is_empty(), "des groupes de spawn sont définis (%d)" % SpawnGenerator.group_ids().size())


func _check_zones(label: String, zones: Dictionary) -> void:
	var sum: float = 0.0
	var valid: bool = not zones.is_empty()
	for part: String in zones:
		sum += float(zones[part])
		if not BodyPartDB.has_id(part):
			valid = false
	_check(valid and is_equal_approx(sum, 100.0), "%s : zones valides, somme = 100 (%.0f)" % [label, sum])


func _check_effect(label: String, effect: Dictionary) -> void:
	if effect.is_empty():
		return
	var effect_id: String = String(effect.get("id", ""))
	var ok: bool = effect_id == "" or StatusEffects.LABELS.has(effect_id)
	var chance: float = float(effect.get("chance", 1.0))
	ok = ok and chance > 0.0 and chance <= 1.0
	if effect_id != "":
		ok = ok and float(effect.get("duration", 0.0)) > 0.0 and float(effect.get("dps", 0.0)) > 0.0
	else:
		ok = ok and float(effect.get("stamina", 0.0)) > 0.0
	_check(ok, "%s : effet valide" % label)


# --- Déterminisme ---

func _chunk_keys(center: Vector3i, radius: int) -> Array[Vector3i]:
	var keys: Array[Vector3i] = []
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			keys.append(Vector3i(center.x + x, center.y + y, 0))
	return keys


func _prints(world_seed: int, keys: Array[Vector3i]) -> Dictionary:
	var result: Dictionary = {}
	for key in keys:
		result[key] = SpawnGenerator.fingerprint(world_seed, key)
	return result


func _check_determinism(seeds: Array[int]) -> void:
	for world_seed in seeds:
		var keys: Array[Vector3i] = _chunk_keys(Vector3i.ZERO, RANGE)
		var in_order: Dictionary = _prints(world_seed, keys)
		var reversed_keys: Array[Vector3i] = keys.duplicate()
		reversed_keys.reverse()
		var by_distance: Array[Vector3i] = keys.duplicate()
		by_distance.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.x * a.x + a.y * a.y < b.x * b.x + b.y * b.y)
		_check(in_order == _prints(world_seed, reversed_keys), "seed %d : monstres identiques, ordre inversé" % world_seed)
		_check(in_order == _prints(world_seed, by_distance), "seed %d : monstres identiques, ordre par distance" % world_seed)
		_check(in_order == _prints(world_seed, keys), "seed %d : deux générations identiques" % world_seed)
	_check(_prints(seeds[0], _chunk_keys(Vector3i.ZERO, RANGE)) != _prints(seeds[1], _chunk_keys(Vector3i.ZERO, RANGE)), "seeds 1 et 42 : populations différentes")


# --- Placement ---

func _check_placement(seeds: Array[int]) -> void:
	var max_per_chunk: int = SpawnGenerator.limit("max_per_chunk", 12)
	var budget: int = SpawnGenerator.limit("threat_budget", 30)
	var safe_radius: float = float(SpawnGenerator.limit("safe_radius", 12))
	var total: int = 0
	var low_total: int = 0
	var high_total: int = 0
	var zero_population_failures: int = 0
	for world_seed in seeds:
		var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
		var spawn: Vector2i = settlement.spawn_cell()
		var bad_cell: int = 0
		var bad_limit: int = 0
		var bad_safe: int = 0
		var bad_door: int = 0
		var duplicates: int = 0
		var unknown: int = 0
		var door: int = TerrainDB.index_of("t_door")
		for key in _chunk_keys(ChunkManager.key_of(spawn), SAMPLE_RANGE):
			var terrain: PackedByteArray = ChunkGenerator.generate(world_seed, key)
			var furniture: PackedByteArray = ChunkGenerator.generate_furniture(world_seed, key)
			var entries: Array[Dictionary] = SpawnGenerator.generate(world_seed, key, terrain, furniture)
			total += entries.size()
			low_total += SpawnGenerator.generate(world_seed, key, terrain, furniture, 0.5).size()
			high_total += SpawnGenerator.generate(world_seed, key, terrain, furniture, 2.0).size()
			if not SpawnGenerator.generate(world_seed, key, terrain, furniture, 0.0).is_empty():
				zero_population_failures += 1
			var threat_sum: int = 0
			var seen: Dictionary = {}
			if entries.size() > max_per_chunk:
				bad_limit += 1
			for entry: Dictionary in entries:
				var cell: Vector2i = entry["cell"]
				var monster_id: String = entry["monster"]
				if not MonsterDB.has_id(monster_id):
					unknown += 1
					continue
				threat_sum += MonsterDB.threat_of(monster_id)
				if seen.has(cell):
					duplicates += 1
				seen[cell] = true
				var index: int = ChunkManager.index_of(cell)
				var t: int = terrain[index]
				if ChunkManager.key_of(cell) != key or not TerrainDB.is_walkable(t) or TerrainDB.swim_depth(t) != TerrainDB.SWIM_NONE \
						or not FurnitureDB.is_walkable(furniture[index]):
					bad_cell += 1
				if Vector2(cell).distance_to(Vector2(spawn)) <= safe_radius:
					bad_safe += 1
				for dir: Vector2i in SpawnGenerator.RING:
					var n: Vector2i = cell + dir
					if ChunkManager.key_of(n) == key and terrain[ChunkManager.index_of(n)] == door:
						bad_door += 1
				if t == door:
					bad_door += 1
			if threat_sum > budget:
				bad_limit += 1
		_check(unknown == 0, "seed %d : tous les monstres tirés existent dans le bestiaire" % world_seed)
		_check(bad_cell == 0, "seed %d : monstres sur des cases praticables à pied, hors eau, dans leur chunk (%d anomalies)" % [world_seed, bad_cell])
		_check(bad_limit == 0, "seed %d : plafond de %d monstres et budget de menace %d respectés (%d chunks en défaut)" % [world_seed, max_per_chunk, budget, bad_limit])
		_check(bad_safe == 0, "seed %d : aucun monstre à moins de %d cases du départ (%d anomalies)" % [world_seed, int(safe_radius), bad_safe])
		_check(bad_door == 0, "seed %d : aucun monstre sur ou devant une porte (%d anomalies)" % [world_seed, bad_door])
		_check(duplicates == 0, "seed %d : jamais deux monstres sur la même case" % world_seed)
	_check(zero_population_failures == 0, "population 0 : aucun monstre (%d chunks en défaut)" % zero_population_failures)
	_check(total > 0, "des monstres sont générés autour du départ (%d sur 5 seeds)" % total)
	_check(low_total <= total and total <= high_total, "la population multiplie les effectifs (0.5 : %d <= 1 : %d <= 2 : %d)" % [low_total, total, high_total])


# --- Chunks propriétaires : réserve et restauration ---

func _signature(world: World) -> Array[String]:
	var out: Array[String] = []
	for m in world.monsters:
		out.append("%s@%d,%d hp=%.1f" % [m.data.id, m.grid_pos.x, m.grid_pos.y, m.hp])
	out.sort()
	return out


func _check_persistence(world_seed: int) -> void:
	var world := World.new()
	world.world_seed = world_seed
	root.add_child(world)
	var spawn: Vector2i = SettlementMap.for_seed(world_seed).spawn_cell()
	var far: Vector2i = spawn + Vector2i(Chunk.SIZE * 14, 0)
	world.chunks.update_around(spawn)
	var before: Array[String] = _signature(world)
	print("       persistance : %d monstres autour du départ (seed %d)" % [before.size(), world_seed])
	if before.is_empty():
		print("  AVERTISSEMENT - aucun monstre autour du départ de cette seed : contrôles de persistance ignorés")
		world.queue_free()
		return
	_check(world.chunks.is_populated(ChunkManager.key_of(spawn)), "le chunk du départ est marqué peuplé")

	world.chunks.update_around(far)  # tout le départ est déchargé
	_check(world.chunks.stored_monster_count() == before.size() and not _signature(world).has(before[0]),
		"déchargement : les %d monstres sont en réserve et quittent le monde" % before.size())

	world.chunks.update_around(spawn)
	_check(_signature(world) == before, "rechargement : mêmes monstres, mêmes cases, mêmes PV")
	_check(world.chunks.stored_monster_count() == 0, "la réserve est vidée après restauration")

	# Un monstre tué reste tué (le chunk n'est jamais repeuplé).
	var victim: Monster = world.monsters[0]
	var victim_label: String = "%s@%d,%d hp=%.1f" % [victim.data.id, victim.grid_pos.x, victim.grid_pos.y, victim.hp]
	world.remove_monster(victim)
	var after_kill: Array[String] = _signature(world)
	world.chunks.update_around(far)
	world.chunks.update_around(spawn)
	_check(_signature(world) == after_kill and not _signature(world).has(victim_label), "un monstre tué ne réapparaît pas après déchargement / rechargement")

	# Un monstre blessé garde ses PV.
	var wounded: Monster = world.monsters[0]
	wounded.hp = maxf(wounded.hp - 3.0, 1.0)
	var after_wound: Array[String] = _signature(world)
	world.chunks.update_around(far)
	world.chunks.update_around(spawn)
	_check(_signature(world) == after_wound, "un monstre blessé garde ses PV après rechargement")
	world.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
