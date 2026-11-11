extends Node
## Test du jalon 6d (domaines de déplacement, aquatiques, uniques, SUMMON / RAISE, STEALTH, BLIND_HEARING, rattrapage de la faune). À lancer :
##   godot --headless --path <projet> res://tests/test_jalon6d.tscn
## (scène et non `--script` : le test a besoin des autoloads GameClock / EventBus). Code de sortie 0 = tout est bon.

var _failures: int = 0


func _ready() -> void:
	_check_data()
	_check_domains()
	_check_uniques(WorldRng.seed_from_text("cataclysme"))
	_check_world(WorldRng.seed_from_text("cataclysme"))
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	get_tree().quit(_failures)


func _check_data() -> void:
	_check(MonsterDB.errors().is_empty(), "bestiaire : aucune erreur %s" % str(MonsterDB.errors()))
	_check(SpawnGenerator.errors().is_empty(), "groupes, règles et uniques valides %s" % str(SpawnGenerator.errors()))
	for id in ["piranha_swarm", "eel_electric", "jellyfish", "shark", "shark_mutant", "squid_giant", "kraken", "pirate_captain", "zombie_pirate"]:
		_check(MonsterDB.has_id(id), "monstre aquatique / marin défini : %s" % id)
	for id in ["piranha_swarm", "shark", "kraken"]:
		_check(MonsterDB.has_ability(id, "AQUATIC"), "%s : capacité AQUATIC" % id)
	_check(MonsterDB.tags_of("kraken").has("unique") and MonsterDB.tags_of("pirate_captain").has("unique"), "uniques : tag « unique »")
	for id in ["zombie_master", "zombie_necro"]:
		_check(MonsterDB.has_ability(id, "SUMMON") or MonsterDB.has_ability(id, "RAISE"), "%s : capacité d'appel" % id)
	for group_id in ["eco_water_shallow", "eco_ocean_deep", "pirate_g", "shipwreck_g"]:
		_check(SpawnGenerator.group_ids().has(group_id), "groupe %s défini" % group_id)


func _check_domains() -> void:
	_check(Monster.domain_of(MonsterDB.create("zombie")) == World.DOMAIN_WALK, "zombie : marche")
	_check(Monster.domain_of(MonsterDB.create("crow")) == World.DOMAIN_FLY, "corbeau : vol")
	_check(Monster.domain_of(MonsterDB.create("zombie_swimmer")) == World.DOMAIN_SWIM, "zombie nageur : nage")
	_check(Monster.domain_of(MonsterDB.create("shark")) == World.DOMAIN_AQUATIC, "requin : aquatique")


func _check_uniques(world_seed: int) -> void:
	# Le tirage d'un unique ne dépend que de (seed, chunk, id) : deux appels identiques donnent le même résultat.
	var plan: int = MapgenDB.plan_by_id("pirate_fort")
	_check(plan >= 0, "plan pirate_fort existe")
	if plan < 0:
		return
	var terrain := PackedByteArray()
	var furniture := PackedByteArray()
	terrain.resize(Chunk.CELLS)
	furniture.resize(Chunk.CELLS)
	var nature: int = TerrainDB.index_of("t_grass")
	for i in Chunk.CELLS:
		var t: int = MapgenDB.terrain_at(plan, i)
		terrain[i] = nature if t == MapgenDB.NATURE else t
		furniture[i] = MapgenDB.furniture_at(plan, i)
	var captains: int = 0
	var repeatable: bool = true
	var over: int = 0
	for n in 60:
		var key := Vector3i(4000 + n, 4000, 0)
		var a: Array[Dictionary] = SpawnGenerator.generate(world_seed, key, terrain, furniture, 1.0, [], "pirate_fort")
		if a != SpawnGenerator.generate(world_seed, key, terrain, furniture, 1.0, [], "pirate_fort"):
			repeatable = false
		var here: int = 0
		for entry: Dictionary in a:
			if entry["monster"] == "pirate_captain":
				here += 1
		captains += here
		if here > 1:
			over += 1
	_check(repeatable, "fort pirate : génération répétable (uniques compris)")
	_check(over == 0, "au plus un capitaine pirate par chunk")
	_check(captains > 0 and captains < 60, "capitaine pirate : apparaît parfois (%d sur 60 chunks, chance 0,7)" % captains)


func _check_world(world_seed: int) -> void:
	var world := World.new()
	world.world_seed = world_seed
	add_child(world)
	var spawn: Vector2i = SettlementMap.for_seed(world_seed).spawn_cell()
	var player := Player.new()
	player.world = world
	player.grid_pos = spawn
	world.player = player
	world.add_entity(player)
	world.chunks.update_around(spawn)
	for m in world.monsters.duplicate():
		world.remove_monster(m)
	var base: Vector2i = world.find_free_cell_near(spawn + Vector2i(4, 4))

	# Cadavres : RAISE retire le plus proche dans la portée, jamais hors portée.
	world.add_corpse(base, "zombie")
	_check(world.take_corpse_near(base + Vector2i(10, 0), 3).is_empty(), "cadavre hors de portée : non pris")
	var corpse: Dictionary = world.take_corpse_near(base + Vector2i(1, 0), 3)
	_check(String(corpse.get("id", "")) == "zombie", "cadavre à portée : pris")
	_check(world.take_corpse_near(base, 3).is_empty(), "un cadavre n'est relevé qu'une fois")

	# SUMMON : spawn_near crée un monstre en chasse sur une case libre voisine.
	var before: int = world.monsters.size()
	var summoned: Monster = world.spawn_near(base, "zombie", 2, true)
	_check(summoned != null and world.monsters.size() == before + 1 and summoned.has_target, "spawn_near : monstre créé, en chasse")
	if summoned != null:
		world.remove_monster(summoned)

	# Bruit : les aveugles n'entendent que le bruit récent et proche.
	GameClock.elapsed_points = 100.0
	world.record_noise(base, 3)
	_check(world.hears_noise(base + Vector2i(2, 0)), "bruit : entendu à portée")
	_check(not world.hears_noise(base + Vector2i(6, 0)), "bruit : pas entendu trop loin")
	GameClock.elapsed_points += World.NOISE_MEMORY + 1.0
	_check(not world.hears_noise(base), "bruit : oublié après NOISE_MEMORY")

	# Domaines : un aquatique n'entre pas sur la terre ; un marcheur n'entre pas en eau profonde.
	var land: Vector2i = spawn
	_check(world.monster_can_enter(land, World.DOMAIN_WALK) and not world.monster_can_enter(land, World.DOMAIN_AQUATIC), "case de terre : marche oui, aquatique non")
	_check(world.monster_can_enter(land, World.DOMAIN_FLY) or world.swim_depth(land) != TerrainDB.SWIM_NONE, "case de terre : vol possible")

	# Rattrapage de la faune : absence longue, les ambiants partent (ou non), les uniques et ceux des lieux restent.
	var key: Vector3i = ChunkManager.key_of(spawn)
	var chunk: Chunk = world.chunks.chunks[key]
	var saved: Array = []
	for n in 40:
		saved.append({"id": "wolf", "cell": [spawn.x, spawn.y], "ambient": true})
	saved.append({"id": "kraken", "cell": [spawn.x, spawn.y], "ambient": true})
	saved.append({"id": "zombie", "cell": [spawn.x, spawn.y], "ambient": false})
	var gains: Array[Dictionary] = []
	GameClock.elapsed_points = ChunkManager.CATCHUP_AFTER * 3.0
	var kept: Array = world.chunks._migrate(key, chunk, saved, gains)
	var kept_wolves: int = 0
	var kept_kraken: int = 0
	var kept_zombie: int = 0
	for entry: Dictionary in kept:
		match String(entry["id"]):
			"wolf":
				kept_wolves += 1
			"kraken":
				kept_kraken += 1
			"zombie":
				kept_zombie += 1
	_check(kept_wolves < 40 and kept_wolves > 0, "rattrapage : une part des ambiants part (%d / 40 restent)" % kept_wolves)
	_check(kept_kraken == 1 and kept_zombie == 1, "rattrapage : l'unique et le monstre de lieu restent")
	var again: Array[Dictionary] = []
	var kept_again: Array = world.chunks._migrate(key, chunk, saved, again)
	_check(kept_again == kept and again == gains, "rattrapage : même tirage pour le même chunk et la même période")
	for entry: Dictionary in gains:
		_check(bool(entry.get("ambient", false)), "rattrapage : les arrivants sont des ambiants")
	world.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
