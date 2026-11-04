extends SceneTree
## Test du jalon 6c (contamination, mutants, capacités des monstres). À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_contamination.gd
## Code de sortie 0 = tout est bon. Affiche aussi le nombre de sources par seed et le coût de la contamination (µs), pour régler les rayons.

const HALF_REGIONS: int = 3     # régions de -3 à +3 (7 x 7) : sources de référence
const SAMPLE_HALF: int = 70     # chunks de -70 à +70 (grille) pour comparer à la référence
const SAMPLE_STEP: int = 5

var _failures: int = 0


func _initialize() -> void:
	var seeds: Array[int] = []
	for text in ["1", "42", "cataclysme", "", "-7"]:
		seeds.append(WorldRng.seed_from_text(text))
	_check_data()
	for world_seed in seeds:
		_check_map(world_seed)
	_check_substitution(seeds[2])
	_check_abilities(WorldRng.seed_from_text("cataclysme"))
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


# --- Données ---

func _check_data() -> void:
	_check(ContaminationMap.errors().is_empty(), "ecology.json : sources de contamination valides %s" % str(ContaminationMap.errors()))
	var known: Array[String] = SettlementMap.for_seed(1).specials().place_ids()
	for id in ContaminationMap.source_ids():
		_check(known.has(id), "source « %s » : lieu défini dans specials.json" % id)
		var def: Dictionary = ContaminationMap.source_def(id)
		_check(SpawnGenerator.CONTAMINATION_TYPES.has(String(def["type"])), "source %s : type « %s » connu" % [id, def["type"]])
	_check(ContaminationMap.source_ids().size() >= 8, "au moins 8 sources (%d)" % ContaminationMap.source_ids().size())
	_check(SpawnGenerator.errors().is_empty(), "substitutions et groupes contaminés valides %s" % str(SpawnGenerator.errors()))
	for type_id in ["radiation", "toxic", "experiment", "fire", "cursed"]:
		_check(SpawnGenerator.group_ids().has("eco_contaminated_" + type_id), "groupe eco_contaminated_%s défini" % type_id)
	_check(SpawnGenerator.contaminated_group("eco_temperate_plain", {"level": 0.9, "type": "radiation"}) == "eco_contaminated_radiation", "au-dessus du seuil : faune mutante")
	_check(SpawnGenerator.contaminated_group("eco_temperate_plain", {"level": 0.3, "type": "radiation"}) == "eco_temperate_plain", "sous le seuil : faune normale")
	_check(SpawnGenerator.contaminated_group("eco_temperate_plain", {"level": 0.9, "type": "oil"}) == "eco_temperate_plain", "type sans groupe (pétrole) : faune normale")


# --- Carte de contamination ---

## Niveau de référence : toutes les sources de la fenêtre 7 x 7 régions, sans la logique de voisinage de ContaminationMap.
func _reference(sources: Array, coord: Vector2i) -> float:
	var best: float = 0.0
	for source: Dictionary in sources:
		var nearest: float = INF
		for cell: Vector2i in source["cells"]:
			nearest = minf(nearest, Vector2(coord).distance_to(Vector2(cell)))
		var radius: float = source["radius"]
		if nearest < radius:
			best = maxf(best, float(source["force"]) * (1.0 - nearest / radius))
	return best


func _check_map(world_seed: int) -> void:
	var settlement: SettlementMap = SettlementMap.for_seed(world_seed)
	var sources: Array = []
	var by_type: Dictionary = {}
	for ry in range(-HALF_REGIONS, HALF_REGIONS + 1):
		for rx in range(-HALF_REGIONS, HALF_REGIONS + 1):
			for place: Dictionary in settlement.specials().region_places(Vector2i(rx, ry)):
				var id: String = place["id"]
				if ContaminationMap.source_ids().has(id):
					var def: Dictionary = ContaminationMap.source_def(id)
					sources.append({"id": id, "cells": place["cells"], "force": float(def["force"]), "radius": float(def["radius"])})
					by_type[id] = int(by_type.get(id, 0)) + 1
	print("       seed %d : %d sources %s" % [world_seed, sources.size(), str(by_type)])
	var mismatch: int = 0
	var checked: int = 0
	var contaminated: int = 0
	var coords: Array[Vector2i] = []
	for y in range(-SAMPLE_HALF, SAMPLE_HALF + 1, SAMPLE_STEP):
		for x in range(-SAMPLE_HALF, SAMPLE_HALF + 1, SAMPLE_STEP):
			coords.append(Vector2i(x, y))
	for source: Dictionary in sources:   # autour de chaque source, y compris près des frontières de région (voisinage)
		var cells: Array = source["cells"]
		var first: Vector2i = cells[0]
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(3, 0), Vector2i(-6, 2), Vector2i(0, 9), Vector2i(-12, -12), Vector2i(14, 5)]:
			coords.append(first + offset)
	for coord in coords:
		if absi(coord.x) > 2 * SettlementMap.region_size_cells() - 1 or absi(coord.y) > 2 * SettlementMap.region_size_cells() - 1:
			continue   # hors de la zone dont toutes les sources voisines sont dans la fenêtre de référence
		var level: float = float(ContaminationMap.sample(world_seed, coord)["level"])
		var expected: float = _reference(sources, coord)
		checked += 1
		if expected > 0.0:
			contaminated += 1
		if absf(level - expected) > 0.00001:
			mismatch += 1
	_check(mismatch == 0, "seed %d : contamination = référence sur %d chunks (%d contaminés, %d écarts)" % [world_seed, checked, contaminated, mismatch])
	var under_ok: bool = true
	for source: Dictionary in sources:
		for cell: Vector2i in source["cells"]:
			if float(ContaminationMap.sample(world_seed, cell)["level"]) < float(source["force"]) - 0.00001:
				under_ok = false
	_check(under_ok, "seed %d : sous un lieu, le niveau vaut au moins sa force" % world_seed)
	var bounded: bool = true
	for coord in coords:
		var level: float = float(ContaminationMap.sample(world_seed, coord)["level"])
		if level < 0.0 or level > 1.0:
			bounded = false
	_check(bounded, "seed %d : niveau toujours entre 0 et 1" % world_seed)
	var typed: bool = true
	for coord in coords:
		var sample: Dictionary = ContaminationMap.sample(world_seed, coord)
		if (float(sample["level"]) > 0.0) != (String(sample["type"]) != ""):
			typed = false
	_check(typed, "seed %d : un niveau positif a toujours un type" % world_seed)
	_check(float(ContaminationMap.sample(world_seed, Vector2i(5000, 5000))["level"]) >= 0.0, "chunk lointain : aucun plantage")
	var bench: Dictionary = ContaminationMap.benchmark(SettlementMap.new(world_seed), Vector2i.ZERO, 5)
	print("       perf contamination seed %d (instance neuve, 25 chunks) : %.1f ms, %d contaminés" % [world_seed, int(bench["us"]) / 1000.0, int(bench["contaminated"])])


# --- Substitution ---

func _plan_arrays(plan_id: String) -> Array[PackedByteArray]:
	var plan: int = MapgenDB.plan_by_id(plan_id)
	var terrain := PackedByteArray()
	var furniture := PackedByteArray()
	terrain.resize(Chunk.CELLS)
	furniture.resize(Chunk.CELLS)
	var nature: int = TerrainDB.index_of("t_grass")
	for i in Chunk.CELLS:
		var t: int = MapgenDB.terrain_at(plan, i)
		terrain[i] = nature if t == MapgenDB.NATURE else t
		furniture[i] = MapgenDB.furniture_at(plan, i)
	return [terrain, furniture]


func _check_substitution(world_seed: int) -> void:
	var arrays: Array[PackedByteArray] = _plan_arrays("camp_sites")   # camp_g : campeurs, randonneurs, ours (substituable)
	var plain_bears: int = 0
	var mutants: int = 0
	var clean_mutants: int = 0
	var bears_total: int = 0
	var off_set: int = 0
	var allowed: Array[String] = SpawnGenerator.group_monsters("camp_g")
	allowed.append("bear_mutant")
	for n in 120:
		var key := Vector3i(2000 + n, 2000, 0)
		for entry: Dictionary in SpawnGenerator.generate(world_seed, key, arrays[0], arrays[1], 3.0, [], "camp_sites"):
			if entry["monster"] == "bear_mutant":
				clean_mutants += 1
			if entry["monster"] == "bear":
				bears_total += 1
		for entry: Dictionary in SpawnGenerator.generate(world_seed, key, arrays[0], arrays[1], 3.0, [], "camp_sites", {"level": 1.0, "type": "radiation"}):
			if entry["monster"] == "bear":
				plain_bears += 1
			if entry["monster"] == "bear_mutant":
				mutants += 1
			if not allowed.has(String(entry["monster"])):
				off_set += 1
	_check(clean_mutants == 0, "sans contamination : aucun ours mutant (%d)" % clean_mutants)
	_check(bears_total > 0, "sans contamination : des ours normaux apparaissent (%d)" % bears_total)
	_check(mutants > 0, "contamination 1.0 (radiation) : des ours mutants apparaissent (%d, ours normaux restants : %d)" % [mutants, plain_bears])
	_check(off_set == 0, "seuls l'ours a une variante : les autres monstres du groupe ne changent pas (%d hors groupe)" % off_set)
	# Déterminisme avec contamination imposée.
	var key_a := Vector3i(2001, 2000, 0)
	_check(SpawnGenerator.generate(world_seed, key_a, arrays[0], arrays[1], 3.0, [], "camp_sites", {"level": 0.7, "type": "toxic"})
		== SpawnGenerator.generate(world_seed, key_a, arrays[0], arrays[1], 3.0, [], "camp_sites", {"level": 0.7, "type": "toxic"}), "substitution répétable")
	# Une règle « contaminate: false » ignore la contamination (centrale : cœur du réacteur).
	var reactor: Array[PackedByteArray] = _plan_arrays("npp_reactor")
	var rules: Array = SpawnGenerator.place_rules("npp_reactor")
	var flagged: bool = false
	for rule: Dictionary in rules:
		if rule.has("contaminate") and not bool(rule["contaminate"]):
			flagged = true
	_check(flagged, "npp_reactor : règle contaminate = false présente")
	_check(not SpawnGenerator.generate(world_seed, Vector3i(2002, 2000, 0), reactor[0], reactor[1], 3.0, [], "npp_reactor").is_empty(), "npp_reactor : des monstres apparaissent")
	# Affixes de contamination.
	var irradiated: MonsterData = MonsterDB.create("zombie", ["irradiated"])
	_check(irradiated.has_ability("AURA_RAD") and irradiated.display_name == "Zombie irradié", "affixe irradié : aura radioactive, nom accordé (%s)" % irradiated.display_name)
	_check(not MonsterDB.create("zombie_irradiated", ["irradiated"]).affixes.has("irradiated"), "un zombie déjà irradié (mutant) refuse l'affixe irradié")
	var toxic: MonsterData = MonsterDB.create("zombie", ["toxic"])
	_check(String(toxic.attack_effect.get("id", "")) == "poison", "affixe toxique : l'attaque empoisonne")
	_check(MonsterDB.create("zombie", ["charred"]).has_ability("FIRE_AURA") and MonsterDB.create("zombie", ["bloated"]).has_ability("EXPLODE"), "affixes calciné (aura de feu) et gonflé (explosion)")
	_check(MonsterDB.create("zombie", ["electrified"]).attack_effect.has("stamina"), "affixe électrifié : drain de stamina")
	_check(MonsterDB.create("zombie", ["frozen"]).has_ability("COLD_AURA"), "affixe gelé : aura de froid")
	# Essaims : un monstre SWARM arrive avec des voisins.
	var swarm_total: int = 0
	var plan: Array[PackedByteArray] = _plan_arrays("farm_field")
	for n in 80:
		for entry: Dictionary in SpawnGenerator.generate(world_seed, Vector3i(3000 + n, 3000, 0), plan[0], plan[1], 3.0, [], "farm_field", {"level": 1.0, "type": "experiment"}):
			if MonsterDB.has_ability(String(entry["monster"]), "SWARM"):
				swarm_total += 1
	print("       essaims en zone d'expérience sur les champs : %d membres SWARM sur 80 chunks (informatif)" % swarm_total)


# --- Capacités ---

func _check_abilities(world_seed: int) -> void:
	# Tables : tout argument d'EXPLODE / THROW existe dans World.EXPLOSIONS, tout effet d'aura ou d'explosion est connu de StatusEffects.
	var unknown: Array[String] = []
	for monster_id in MonsterDB.ids():
		var d: MonsterData = MonsterDB.create(monster_id)
		for base in ["EXPLODE", "THROW"]:
			if d.has_ability(base) and not World.EXPLOSIONS.has(d.ability_arg(base)):
				unknown.append("%s %s" % [monster_id, base])
	_check(unknown.is_empty(), "EXPLODE / THROW : types d'explosion connus %s" % str(unknown))
	for base: String in Monster.AURA_EFFECTS:
		_check(StatusEffects.LABELS.has(String((Monster.AURA_EFFECTS[base] as Dictionary)["id"])), "aura %s : effet d'état connu" % base)
	for kind: String in World.EXPLOSIONS:
		var effect: Dictionary = (World.EXPLOSIONS[kind] as Dictionary)["effect"]
		_check(effect.is_empty() or String(effect.get("id", "")) == "" or StatusEffects.LABELS.has(String(effect["id"])), "explosion %s : effet d'état connu" % kind)
	_check(MonsterDB.create("zombie_grenadier").ability_arg("THROW") == "frag" and MonsterDB.create("experiment_flesh_mass").ability_value("REGEN", 0.0) == 0.3,
		"arguments de capacités lus (THROW(frag), REGEN(0.3))")

	var world := World.new()
	world.world_seed = world_seed
	root.add_child(world)
	var spawn: Vector2i = SettlementMap.for_seed(world_seed).spawn_cell()
	world.chunks.update_around(spawn)
	for m in world.monsters.duplicate():
		world.remove_monster(m)
	var base_cell: Vector2i = world.find_free_cell_near(spawn)

	# Explosion : tue les faibles du rayon, épargne les lointains ; le gaz ne blesse pas.
	var weak: Monster = world.spawn_monster_at({"monster": "zombie", "cell": base_cell, "facing": Vector2i(0, 1), "state": "idle", "affixes": []})
	weak.hp = 4.0
	var near_strong: Monster = world.spawn_monster_at({"monster": "zombie_brute", "cell": world.find_free_cell_near(base_cell + Vector2i(1, 1)), "facing": Vector2i(0, 1), "state": "idle", "affixes": []})
	var far: Monster = world.spawn_monster_at({"monster": "zombie", "cell": world.find_free_cell_near(base_cell + Vector2i(7, 0)), "facing": Vector2i(0, 1), "state": "idle", "affixes": []})
	world.explode(base_cell, 2, "gas", null)
	_check(weak.hp == 4.0 and world.monsters.has(weak), "explosion de gaz : aucun dégât aux monstres")
	var brute_hp: float = near_strong.hp
	world.explode(base_cell, 2, "acid", null)
	_check(not world.monsters.has(weak), "explosion d'acide : le monstre faible du rayon est tué et retiré")
	_check(world.monsters.has(near_strong) and near_strong.hp < brute_hp, "explosion d'acide : le brute du rayon est blessé")
	_check(world.monsters.has(far) and far.hp == far.data.max_hp, "explosion d'acide : le monstre lointain est épargné")

	# EXPLODE(type) à la mort : l'expérience gonflée tue le zombie voisin.
	var bloated: Monster = world.spawn_monster_at({"monster": "experiment_bloated", "cell": world.find_free_cell_near(base_cell + Vector2i(0, -3)), "facing": Vector2i(0, 1), "state": "idle", "affixes": []})
	var victim: Monster = world.spawn_monster_at({"monster": "zombie", "cell": world.find_free_cell_near(bloated.grid_pos + Vector2i(1, 0)), "facing": Vector2i(0, 1), "state": "idle", "affixes": []})
	victim.hp = 3.0
	var killed: bool = bloated.take_damage(9999.0)
	_check(killed and not world.monsters.has(victim), "EXPLODE(acid) à la mort : le voisin fragile est tué par l'explosion")
	_check(bloated.take_damage(1.0), "un monstre déjà mort ne ré-explose pas (pas de boucle)")
	world.remove_monster(bloated)

	# REGEN : régénère après 5 s sans dégât, pas avant.
	var bear: Monster = world.spawn_monster_at({"monster": "bear_mutant", "cell": world.find_free_cell_near(base_cell + Vector2i(-4, 3)), "facing": Vector2i(0, 1), "state": "idle", "affixes": []})
	bear.hp = 100.0
	bear._last_hurt = -1000.0
	bear._regen_clock = GameClock.elapsed_points
	GameClock.elapsed_points += 10.0
	bear._regen_tick()
	_check(is_equal_approx(bear.hp, 102.0), "REGEN(0.2) : +2 PV en 10 s (%.2f)" % bear.hp)
	bear.take_damage(1.0)
	var after_hit: float = bear.hp
	GameClock.elapsed_points += 3.0
	bear._regen_tick()
	_check(is_equal_approx(bear.hp, after_hit), "REGEN : rien dans les 5 s qui suivent un coup")
	GameClock.elapsed_points += 10.0
	bear._regen_tick()
	_check(bear.hp > after_hit, "REGEN : reprend ensuite (%.2f > %.2f)" % [bear.hp, after_hit])
	world.remove_monster(bear)

	# SPLIT : chaque coup détache un petit monstre, jusqu'à la génération maximale.
	var blob: Monster = world.spawn_monster_at({"monster": "experiment_blob", "cell": world.find_free_cell_near(base_cell + Vector2i(4, -4)), "facing": Vector2i(0, 1), "state": "idle", "affixes": []})
	var before: int = world.monsters.size()
	blob.take_damage(5.0)
	_check(world.monsters.size() == before + 1 and is_equal_approx(blob.hp, 28.0), "SPLIT : un coup détache un blob (parent %.0f PV)" % blob.hp)
	var child: Monster = world.monsters[world.monsters.size() - 1]
	_check(child.generation == 1 and is_equal_approx(child.hp, 27.0) and child.data.id == "experiment_blob", "SPLIT : l'enfant est de génération 1 avec la moitié des PV")
	var deep: Monster = child
	for generation in range(2, Monster.SPLIT_MAX_GENERATION + 3):
		deep.hp = 40.0
		var count: int = world.monsters.size()
		deep.take_damage(1.0)
		if world.monsters.size() > count:
			deep = world.monsters[world.monsters.size() - 1]
	_check(deep.generation <= Monster.SPLIT_MAX_GENERATION, "SPLIT : jamais au-delà de la génération %d (atteinte : %d)" % [Monster.SPLIT_MAX_GENERATION, deep.generation])
	var saved: Dictionary = child.to_dict()
	_check(int(saved["generation"]) == 1, "to_dict garde la génération")

	# Auras : la table agit sur les bons rayons.
	_check(int((Monster.AURA_EFFECTS["AURA_RAD"] as Dictionary)["radius"]) > int((Monster.AURA_EFFECTS["FIRE_AURA"] as Dictionary)["radius"]), "l'aura radioactive porte plus loin que le feu")
	world.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
