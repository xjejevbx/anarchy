class_name MonsterData
extends Resource
## Données d'un type de monstre. Pour l'instant définies en code ;
## on les chargera depuis des fichiers (JSON ou .tres) plus tard.

@export var display_name: String = "Monstre"
@export var tile_id: String = "mon_zombie"  # id de tuile UltiCa (voir UlticaTiles)
@export var max_hp: float = 20.0
@export var detect_range: int = 15

# Coûts en points d'action (1 point = 1 seconde in-game)
@export var move_cost: float = 1.2
@export var attack_name: String = "Attaque"
@export var attack_cost: float = 1.5
@export var attack_damage: float = 4.0
# Parties du corps visées : {id de data/body_parts.json: poids}. Les poids sont lus comme des pourcentages (leur somme est normalisée).
@export var attack_zones: Dictionary = {}

@export var special_name: String = ""
@export var special_cost: float = 0.0
@export var special_damage: float = 0.0
@export var special_chance: float = 0.0  # probabilité d'utiliser la spéciale à la place
@export var special_zones: Dictionary = {}


static func zombie() -> MonsterData:
	var d := MonsterData.new()
	d.display_name = "Zombie"
	d.tile_id = "mon_zombie"
	d.max_hp = 20.0
	d.move_cost = 1.2
	d.attack_name = "Griffure"
	d.attack_cost = 1.5
	d.attack_damage = 4.0
	d.attack_zones = {"head": 10, "torso": 36, "arm_l": 20, "arm_r": 20, "leg_l": 7, "leg_r": 7}
	d.special_name = "Morsure"
	d.special_cost = 3.5
	d.special_damage = 9.0
	d.special_chance = 0.3
	d.special_zones = {"head": 20, "torso": 26, "arm_l": 22, "arm_r": 22, "leg_l": 5, "leg_r": 5}
	return d
