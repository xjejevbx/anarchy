extends SceneTree
## Test du bestiaire (MonsterData) et des effets d'état. À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_monsters.gd
## Code de sortie 0 = tout est bon.

var _failures: int = 0


func _initialize() -> void:
	var names: Dictionary = {}
	var missing_tiles: Array[String] = []
	_check(MonsterData.IDS.size() >= 14, "au moins 14 types de monstres (%d)" % MonsterData.IDS.size())
	for monster_id in MonsterData.IDS:
		var d: MonsterData = MonsterData.create(monster_id)
		_check(d.id == monster_id, "%s : id cohérent" % monster_id)
		_check(not names.has(d.display_name), "%s : nom unique (%s)" % [monster_id, d.display_name])
		names[d.display_name] = true
		_check(d.max_hp > 0.0 and d.move_cost > 0.0 and d.attack_cost > 0.0 and d.attack_damage > 0.0, "%s : PV, coûts et dégâts positifs" % monster_id)
		_check(d.detect_range > 0 and d.tile_id != "", "%s : portée de détection et tuile renseignées" % monster_id)
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
		if UlticaTiles.pick_sprite(d.tile_id, "fg", 0) == "":
			missing_tiles.append("%s (%s)" % [monster_id, d.tile_id])
	if not missing_tiles.is_empty():
		print("  AVERTISSEMENT - tuiles de monstres absentes du pack : ", ", ".join(missing_tiles))

	# --- Zombie d'origine inchangé ---
	var zombie: MonsterData = MonsterData.zombie()
	_check(is_equal_approx(zombie.max_hp, 20.0) and is_equal_approx(zombie.attack_damage, 4.0) and is_equal_approx(zombie.special_damage, 9.0), "zombie : valeurs d'origine conservées")

	# --- Infection (morsures) ---
	var infectious: Array[String] = []
	for monster_id in MonsterData.IDS:
		var m: MonsterData = MonsterData.create(monster_id)
		_check(m.attack_infection >= 0.0 and m.attack_infection <= 1.0 and m.special_infection >= 0.0 and m.special_infection <= 1.0,
			"%s : probabilités d'infection entre 0 et 1" % monster_id)
		if m.attack_infection > 0.0 or m.special_infection > 0.0:
			infectious.append(monster_id)
	_check(infectious.has("zombie") and infectious.has("zombie_dog"), "le zombie et le chien zombie infectent (%s)" % ", ".join(infectious))
	_check(not infectious.has("wolf") and not infectious.has("bear"), "les animaux sains n'infectent pas")
	_check(Infection.stage_for(0.0) == 0 and Infection.stage_for(0.24) == 0 and Infection.stage_for(0.25) == 1
		and Infection.stage_for(0.5) == 2 and Infection.stage_for(0.75) == 3 and Infection.stage_for(1.0) == 3, "stades de l'infection selon la progression")
	_check(Infection.CURE_LIMIT > 0.0 and Infection.CURE_LIMIT < 1.0 and Infection.LATE_SETBACK > 0.0 and Infection.DURATION > 0.0, "réglages d'infection cohérents")
	var antibiotics: Dictionary = ItemDB.get_def("antibiotics")
	var use: Dictionary = antibiotics.get("use", {})
	_check(String(use.get("action", "")) == "antibiotic" and float(use.get("time", 0.0)) > 0.0, "antibiotiques : objet utilisable (items.json)")

	# --- Fusion d'effets ---
	var first: Dictionary = StatusEffects.merge({}, 10.0, 0.5, "arm_l")
	_check(is_equal_approx(float(first["remaining"]), 10.0) and first["part"] == "arm_l", "merge : nouvel effet")
	var merged: Dictionary = StatusEffects.merge(first, 6.0, 0.8, "torso")
	_check(is_equal_approx(float(merged["remaining"]), 10.0) and is_equal_approx(float(merged["dps"]), 0.8) and merged["part"] == "arm_l",
		"merge : la durée et l'intensité les plus fortes l'emportent, la partie initiale reste")

	# --- Textes ---
	_check(MonsterData.effect_text(MonsterData.effect("bleed", 0.35, 10.0, 0.6)) == "35% : Saignement (10 s, 0.6 PV/s)", "texte d'effet : saignement")
	_check(MonsterData.effect_text(MonsterData.effect("", 1.0, 0.0, 0.0, 30.0)) == "100% : -30 stamina", "texte d'effet : drain de stamina")

	# --- Orientation des monstres ---
	_check_facing()

	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check_facing() -> void:
	var up := Vector2i(0, -1)
	var right := Vector2i(1, 0)
	var down := Vector2i(0, 1)
	var left := Vector2i(-1, 0)
	_check(Monster.RING.size() == 4, "orientation : 4 directions (haut, droite, bas, gauche)")
	# Zone d'attaque : la case en face et ses deux diagonales avant, pas les flancs ni le dos.
	_check(Monster.in_front_arc(up, up) and Monster.in_front_arc(up, Vector2i(1, -1)) and Monster.in_front_arc(up, Vector2i(-1, -1)), "zone : face + 2 diagonales avant (regard haut)")
	_check(not Monster.in_front_arc(up, right) and not Monster.in_front_arc(up, left) and not Monster.in_front_arc(up, down), "zone : flancs et dos exclus (regard haut)")
	_check(not Monster.in_front_arc(up, Vector2i(1, 1)) and not Monster.in_front_arc(up, Vector2i(-1, 1)), "zone : diagonales arrière exclues (regard haut)")
	_check(Monster.in_front_arc(right, Vector2i(1, 1)) and Monster.in_front_arc(right, Vector2i(1, -1)) and not Monster.in_front_arc(right, Vector2i(-1, 1)), "zone : regard droite")
	# Pivotement : quarts de tour, par le côté le plus court.
	_check(Monster.turn_distance(up, right) == 1 and Monster.turn_distance(up, left) == 1 and Monster.turn_distance(up, down) == 2, "distance de pivotement")
	_check(Monster.turned(up, right, 1) == right and Monster.turned(up, left, 1) == left, "un quart de tour vers le côté")
	_check(Monster.turned(up, down, 1) == right and Monster.turned(up, down, 2) == down, "demi-tour : un quart par action, sens horaire")
	_check(Monster.turned(up, Vector2i(1, 1), 1) == right, "cible en diagonale (bas-droite) : pivote vers le côté le plus proche (droite)")
	_check(Monster.turned(left, Vector2i(1, 1), 1) == down, "cible en diagonale (bas-droite) depuis la gauche : bas, pas droite")
	_check(Monster.target_facing(up, Vector2i(1, -1)) == up and Monster.target_facing(up, Vector2i.ZERO) == up, "diagonale avant : déjà bien orienté")
	_check(Monster.TURN_COST_FACTOR > 0.0 and Monster.TURN_STEPS_PER_ACTION >= 1, "réglages de pivotement cohérents")


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
	if effect.has("part"):
		ok = ok and BodyPartDB.has_id(String(effect["part"]))
	_check(ok, "%s : effet valide" % label)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
