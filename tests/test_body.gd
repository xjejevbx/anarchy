extends SceneTree
## Test de la santé par parties du corps et des zones touchées par les monstres. À lancer à la demande :
##   godot --headless --path <projet> --script res://tests/test_body.gd
## Code de sortie 0 = tout est bon.

var _failures: int = 0


func _initialize() -> void:
	# --- Données ---
	var ids: Array[String] = BodyPartDB.ids()
	_check(ids.size() == 6, "6 parties du corps (%d)" % ids.size())
	for id in ids:
		_check(BodyPartDB.max_hp_of(id) > 0.0, "%s : PV max positifs" % id)
	_check(BodyPartDB.is_vital("head") and BodyPartDB.is_vital("torso"), "tête et torse sont vitaux")
	_check(not BodyPartDB.is_vital("arm_l") and not BodyPartDB.is_vital("leg_r"), "les membres ne sont pas vitaux")
	_check(is_equal_approx(BodyPartDB.total_max_hp(), 280.0), "total des PV max = 280 (%.0f)" % BodyPartDB.total_max_hp())

	# --- Tirage pondéré ---
	var zones: Dictionary = {"head": 1, "torso": 3}
	_check(BodyPartDB.pick(zones, 0.0) == "head", "pick : 0,00 -> tête")
	_check(BodyPartDB.pick(zones, 0.24) == "head", "pick : 0,24 -> tête")
	_check(BodyPartDB.pick(zones, 0.25) == "torso", "pick : 0,25 -> torse")
	_check(BodyPartDB.pick(zones, 0.999) == "torso", "pick : 0,999 -> torse")
	_check(BodyPartDB.pick({}, 0.5) == "torso", "pick : zones vides -> torse")

	# --- Zombie : zones valides, somme 100 %, texte lisible ---
	var zombie: MonsterData = MonsterData.zombie()
	for entry: Array in [["Griffure", zombie.attack_zones], ["Morsure", zombie.special_zones]]:
		var table: Dictionary = entry[1]
		var sum: float = 0.0
		var valid: bool = true
		for id: String in table:
			sum += float(table[id])
			if not BodyPartDB.has_id(id):
				valid = false
		_check(valid, "%s : toutes les zones existent dans body_parts.json" % entry[0])
		_check(is_equal_approx(sum, 100.0), "%s : somme des zones = 100 (%.0f)" % [entry[0], sum])
		_check(BodyPartDB.zone_lines(table).size() == 2, "%s : probabilités affichées sur 2 lignes" % entry[0])
	_check(BodyPartDB.zone_lines(zombie.attack_zones)[0] == "Tête 10% · Torse 36% · Bras g. 20%", "texte des zones de la griffure")

	print("RÉSULTAT : %s (%d échec(s))" % ["OK" if _failures == 0 else "ÉCHEC", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		print("  ECHEC - ", label)
		_failures += 1
