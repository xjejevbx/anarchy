extends Node
## Test du jalon 7 (sauvegarde / chargement : seed + deltas). À lancer à la demande :
##   godot --headless --path <projet> res://tests/test_save.tscn
## (scène et non `--script` : le test a besoin des autoloads GameClock / EventBus). Code de sortie 0 = tout est bon.
## Vérifie : sérialisation récursive des objets / inventaire / monstre, méta (seed 64 bits en chaîne, versions),
## deltas de terrain et de mobilier, objets au sol, joueur complet (PV, stamina, posture, zoom, stats, inventaire,
## objets à poser, repères de carte, effets d'état, infection), monstres vivants restaurés (PV, temps d'action, orientation) et
## monstres tués absents (chunk `populated` non repeuplé), puis suppression d'un emplacement.

var _failures: int = 0
var _slot: String = "test-save-jalon7"
var _slot_2: String = "test-save-jalon7-bis"


func _ready() -> void:
	GameClock.elapsed_points = 0.0
	StatusEffects.reset()
	Infection.reset()
	SaveGame.delete_slot(_slot)
	SaveGame.delete_slot(_slot_2)
	_check_serialization()
	_check_round_trip()
	_check_compatibility()
	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	get_tree().quit(_failures)


func _check_serialization() -> void:
	var bag := Item.create("backpack")
	bag.add_content(Item.create("can_beans", 3))
	bag.add_content(Item.create("pipe"))
	var item_data: Dictionary = bag.to_dict()
	var bag_back: Item = Item.from_dict(item_data)
	_check(bag_back.id == "backpack" and bag_back.contents.size() == 2, "objet : contenu récursif conservé")
	_check((bag_back.contents[0] as Item).id == "can_beans" and (bag_back.contents[0] as Item).count == 3,
		"objet : quantité d'une pile conservée")

	var inventory := Inventory.new()
	inventory.add_loose(bag)
	inventory.equip(Item.create("jacket_light"))
	var inventory_data: Dictionary = inventory.to_dict()
	var inventory_back := Inventory.new()
	inventory_back.apply_dict(inventory_data)
	_check(inventory_back.loose.size() == 1 and (inventory_back.loose[0] as Item).contents.size() == 2,
		"inventaire : objets sur soi et contenu conservés")
	_check((inventory_back.equipment.get("outer") as Item).id == "jacket_light",
		"inventaire : équipement conservé")


func _check_round_trip() -> void:
	var world_seed: int = WorldRng.seed_from_text("cataclysme")
	var world := World.new()
	world.world_seed = world_seed
	world.seed_text = "cataclysme"
	world.scenario = "default"
	add_child(world)
	var spawn: Vector2i = SettlementMap.for_seed(world_seed).spawn_cell()
	world.safe_centers.append(spawn)
	var player := _make_player(world, spawn)
	GameClock.elapsed_points = 0.0
	world.update_fov()

	# --- Joueur : état complet ---
	player.stamina = 61.5
	player.set_posture(Player.Posture.CROUCH)
	player.zoom_index = 3
	player.camera.zoom = Vector2.ONE * Player.ZOOM_LEVELS[player.zoom_index]
	player.avoid_scenery = false
	player.stats[StatDB.ids()[0]] = 7.0
	player.body["arm_l"] = 4.0
	player.inventory.loose.clear()
	player.inventory.equipment.clear()
	var bag := Item.create("backpack")
	bag.add_content(Item.create("can_beans", 3))
	bag.add_content(Item.create("antibiotics", 2))
	player.inventory.add_loose(bag)
	player.inventory.equip(Item.create("jacket_light"))
	player.pending_drops.append({"item": Item.create("pipe"), "cell": spawn + Vector2i(1, 1)})
	player.refresh_inventory()
	player.map_markers[Vector3i(spawn.x + 2, spawn.y - 3, 0)] = true

	StatusEffects.apply(player, {"id": "bleed", "chance": 1.0, "duration": 30.0, "dps": 0.5, "stamina": 0.0, "part": "arm_l"}, "arm_l")
	Infection.infect(player)
	var infection: Infection = Infection.of(player)
	infection.progress = 0.4
	infection.stage = Infection.stage_for(0.4)
	infection._carry = 0.25

	# --- Monde : objet au sol, terrain, mobilier, monstre vivant, monstre tué ---
	var item_cell: Vector2i = spawn + Vector2i(1, 0)
	world.add_ground_item(item_cell, Item.create("can_beans", 4))
	var terrain_cell: Vector2i = spawn + Vector2i(5, 5)
	var base_terrain: int = world.chunks.terrain_index(terrain_cell)
	var changed_terrain: int = TerrainDB.index_of("t_floor")
	if changed_terrain == base_terrain:
		changed_terrain = TerrainDB.index_of("t_grass")
	world.chunks.set_terrain(terrain_cell, changed_terrain)
	var furniture_cell: Vector2i = spawn + Vector2i(4, 5)
	var furniture_index: int = FurnitureDB.index_of(FurnitureDB.id_of(1))
	world.chunks.set_furniture(furniture_cell, furniture_index)

	var monster_cell: Vector2i = world.find_free_cell_near(spawn + Vector2i(3, 3))
	var monster: Monster = world.spawn_monster(MonsterData.create("zombie"), monster_cell)
	monster.hp = 7.5
	monster.stamina = 55.0
	monster.facing = Vector2i(-1, 0)
	monster.next_action_time = 12.5
	monster.has_target = true
	monster.target_cell = spawn
	monster.state = "idle"
	var monster_at: Vector2i = monster.grid_pos
	var killed: Monster = world.spawn_monster(MonsterData.create("zombie"), world.find_free_cell_near(spawn + Vector2i(-4, -3)))
	var killed_at: Vector2i = killed.grid_pos
	world.remove_monster(killed)

	# --- Sauvegarde ---
	var result: Dictionary = SaveGame.save(world, player, _slot)
	_check(bool(result.get("ok", false)), "sauvegarde écrite %s" % String(result.get("error", "")))
	_check(FileAccess.file_exists(SaveGame.meta_path(_slot)), "meta.json présent")
	var meta: Dictionary = SaveGame.read_meta(_slot)
	_check(int(meta.get("version", 0)) == SaveGame.VERSION, "version du format = %d" % SaveGame.VERSION)
	_check(int(meta.get("generator_version", 0)) == WorldRng.GENERATOR_VERSION, "version du générateur enregistrée")
	_check(String(meta.get("seed", "")) == str(world_seed), "seed 64 bits écrite en chaîne exacte")
	_check(String(meta.get("seed_text", "")) == "cataclysme", "seed affichée (texte) conservée")
	_check(int(meta.get("chunk_count", 0)) > 0, "des chunks modifiés sont écrits (%d)" % int(meta.get("chunk_count", 0)))
	_check(not (meta.get("player", {}) as Dictionary).is_empty(), "état du joueur dans meta.json")

	var chunk_dir := DirAccess.open(SaveGame.chunks_dir(_slot))
	_check(chunk_dir != null and chunk_dir.get_files().size() == int(meta.get("chunk_count", -1)),
		"un fichier JSON par chunk marqué modifié")
	var spawn_key: Vector3i = ChunkManager.key_of(spawn)
	_check(world.chunks.is_populated(spawn_key), "le chunk du départ est peuplé avant la sauvegarde")

	world.free()

	# --- Rechargement dans un monde NEUF (terrain régénéré + deltas) ---
	StatusEffects.reset()
	Infection.reset()
	GameClock.elapsed_points = 0.0
	var loaded_world := World.new()
	add_child(loaded_world)
	var loaded_result: Dictionary = SaveGame.load_world(loaded_world, _slot)
	_check(bool(loaded_result.get("ok", false)), "monde rechargé %s" % String(loaded_result.get("error", "")))
	_check(loaded_world.world_seed == world_seed and loaded_world.seed_text == "cataclysme",
		"seed restaurée (monde identique)")
	var loaded_meta: Dictionary = loaded_result.get("meta", {})
	var saved_spawn: Vector2i = SaveGame.saved_spawn(loaded_meta)
	var loaded_player: Player = _make_player(loaded_world, saved_spawn)
	var player_data: Dictionary = loaded_meta.get("player", {})
	SaveGame.apply_player(loaded_player, player_data)
	_check(loaded_player.grid_pos == saved_spawn, "case du joueur restaurée")
	_check(is_equal_approx(loaded_player.stamina, 61.5) and loaded_player.posture == Player.Posture.CROUCH,
		"stamina et posture restaurées")
	_check(loaded_player.zoom_index == 3 and loaded_player.camera.zoom == Vector2.ONE * Player.ZOOM_LEVELS[3],
		"zoom restauré")
	_check(not loaded_player.avoid_scenery, "option d'esquive restaurée")
	_check(is_equal_approx(loaded_player.body["arm_l"], 4.0), "PV par partie du corps restaurés")
	_check(is_equal_approx(float(loaded_player.stats[StatDB.ids()[0]]), 7.0), "stats restaurées")
	_check(loaded_player.inventory.loose.size() == 1, "inventaire : un objet sur soi")
	var loaded_bag := loaded_player.inventory.loose[0] as Item
	_check(loaded_bag.id == "backpack" and loaded_bag.contents.size() == 2
		and (loaded_bag.contents[0] as Item).count == 3, "inventaire : contenu du sac restauré")
	_check((loaded_player.inventory.equipment.get("outer") as Item).id == "jacket_light",
		"inventaire : vêtement équipé restauré")
	_check(loaded_player.pending_drops.size() == 1 and (loaded_player.pending_drops[0]["item"] as Item).id == "pipe",
		"objets en attente d'être posés restaurés")
	_check(loaded_player.map_markers.has(Vector3i(spawn.x + 2, spawn.y - 3, 0)),
		"repères de la carte du joueur restaurés")
	var effects: Dictionary = StatusEffects.snapshot()
	_check(effects.has("bleed") and is_equal_approx(float((effects["bleed"] as Dictionary)["remaining"]), 30.0),
		"effets d'état restaurés")
	_check(Infection.is_infected(loaded_player) and is_equal_approx(Infection.snapshot().get("progress", 0.0), 0.4),
		"infection restaurée (progression 40 %%)")

	var loaded_items: Array = loaded_world.get_ground_items(item_cell)
	_check(loaded_items.size() == 1 and (loaded_items[0] as Item).id == "can_beans" and (loaded_items[0] as Item).count == 4,
		"objet au sol restauré avec sa quantité")
	var terrain_chunk: Chunk = loaded_world.chunks.chunk_at(terrain_cell)
	_check(terrain_chunk != null and terrain_chunk.terrain[ChunkManager.index_of(terrain_cell)] == changed_terrain,
		"delta de terrain appliqué au chunk régénéré")
	var furniture_chunk: Chunk = loaded_world.chunks.chunk_at(furniture_cell)
	_check(furniture_chunk != null and furniture_chunk.furniture[ChunkManager.index_of(furniture_cell)] == furniture_index,
		"delta de mobilier appliqué au chunk régénéré")

	var restored: Monster = _find_monster(loaded_world, "zombie", monster_at)
	_check(restored != null, "monstre vivant restauré à sa case")
	if restored != null:
		_check(is_equal_approx(restored.hp, 7.5) and is_equal_approx(restored.stamina, 55.0),
			"monstre : PV et stamina restaurés")
		_check(restored.facing == Vector2i(-1, 0) and is_equal_approx(restored.next_action_time, 12.5),
			"monstre : orientation et prochain temps d'action restaurés")
		_check(restored.has_target and restored.target_cell == spawn, "monstre : cible restaurée")
	_check(_find_monster(loaded_world, "zombie", killed_at) == null, "monstre tué absent après chargement")
	_check(loaded_world.chunks.is_populated(spawn_key), "chunk rechargé marqué peuplé (pas de repeuplement)")
	var total_before: int = int(meta.get("chunk_count", 0))

	# --- Deuxième sauvegarde depuis la partie chargée (aller-retour stable) ---
	loaded_world.seed_text = "cataclysme"
	var second: Dictionary = SaveGame.save(loaded_world, loaded_player, _slot_2)
	_check(bool(second.get("ok", false)), "seconde sauvegarde écrite")
	var second_meta: Dictionary = SaveGame.read_meta(_slot_2)
	_check(String(second_meta.get("seed", "")) == str(world_seed), "seconde sauvegarde : même seed")
	_check(int(second_meta.get("chunk_count", 0)) > 0, "seconde sauvegarde : chunks présents")
	_check(total_before > 0, "première sauvegarde : chunks présents")
	loaded_world.free()
	StatusEffects.reset()
	Infection.reset()


func _check_compatibility() -> void:
	var meta: Dictionary = SaveGame.read_meta(_slot_2)
	var bad_format: Dictionary = meta.duplicate(true)
	bad_format["version"] = 999
	_check(SaveGame.compatibility_error(bad_format) != "", "format inconnu refusé")
	var bad_generator: Dictionary = meta.duplicate(true)
	bad_generator["generator_version"] = WorldRng.GENERATOR_VERSION + 1
	_check(SaveGame.compatibility_error(bad_generator) != "", "générateur incompatible refusé")
	_check(SaveGame.compatibility_error(meta) == "", "sauvegarde compatible acceptée")
	_check(SaveGame.delete_slot(_slot), "suppression de l'emplacement")
	_check(not FileAccess.file_exists(SaveGame.meta_path(_slot)), "méta supprimée")
	_check(SaveGame.delete_slot(_slot_2), "suppression du second emplacement")
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SaveGame.slot_dir(_slot_2))),
		"dossier de sauvegarde supprimé")


func _make_player(world: World, spawn: Vector2i) -> Player:
	var player := Player.new()
	player.world = world
	player.grid_pos = spawn
	world.player = player
	world.add_entity(player)
	return player


func _find_monster(world: World, id: String, cell: Vector2i) -> Monster:
	for m: Monster in world.monsters:
		if m.data.id == id and m.grid_pos == cell:
			return m
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
