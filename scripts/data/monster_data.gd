class_name MonsterData
extends Resource
## Données d'un type de monstre. Pour l'instant définies en code (create(id) / IDS) ; on les chargera depuis un JSON plus tard.
## Compétences spéciales (toutes optionnelles) :
##  - effets sur coup (attack_effect / special_effect / ranged_effect) : saignement, poison, acide, drain de stamina (StatusEffects) ;
##  - tir à distance (ranged_*) : visé dans le champ de vision, avec temps de recharge ;
##  - hurlement (scream_*) : alerte tous les monstres du rayon sur la position du joueur ;
##  - meute (pack_radius) : quand l'un voit le joueur, ses semblables proches le traquent aussi.

## Ids disponibles pour create() (ordre d'ajout : ajouter à la suite).
const IDS: Array[String] = [
	"zombie", "zombie_child", "zombie_fast", "zombie_crawler", "zombie_brute", "zombie_hulk", "zombie_spitter",
	"zombie_screecher", "zombie_electric", "zombie_soldier", "zombie_dog", "wolf", "bear", "giant_spider",
]

# Tables de zones touchées (poids lus comme des %, somme = 100).
const ZONES_HUMANOID: Dictionary = {"head": 10, "torso": 36, "arm_l": 20, "arm_r": 20, "leg_l": 7, "leg_r": 7}
const ZONES_BITE: Dictionary = {"head": 20, "torso": 26, "arm_l": 22, "arm_r": 22, "leg_l": 5, "leg_r": 5}
const ZONES_LOW: Dictionary = {"head": 5, "torso": 25, "arm_l": 10, "arm_r": 10, "leg_l": 25, "leg_r": 25}
const ZONES_LEGS: Dictionary = {"leg_l": 50, "leg_r": 50}
const ZONES_HEAVY: Dictionary = {"head": 8, "torso": 50, "arm_l": 14, "arm_r": 14, "leg_l": 7, "leg_r": 7}
const ZONES_CLAW: Dictionary = {"head": 12, "torso": 38, "arm_l": 18, "arm_r": 18, "leg_l": 7, "leg_r": 7}
const ZONES_SPIT: Dictionary = {"head": 40, "torso": 40, "arm_l": 10, "arm_r": 10}
const ZONES_SHOCK: Dictionary = {"head": 10, "torso": 60, "arm_l": 15, "arm_r": 15}

@export var id: String = "zombie"
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
@export var attack_effect: Dictionary = {}   # voir effect()

@export var special_name: String = ""
@export var special_cost: float = 0.0
@export var special_damage: float = 0.0
@export var special_chance: float = 0.0  # probabilité d'utiliser la spéciale à la place
@export var special_zones: Dictionary = {}
@export var special_effect: Dictionary = {}

# Morsure infectieuse : probabilité (0..1) d'infecter le joueur quand cette attaque touche (voir Infection)
@export var attack_infection: float = 0.0
@export var special_infection: float = 0.0

# Tir à distance (ranged_range = 0 : aucun)
@export var ranged_name: String = ""
@export var ranged_range: int = 0
@export var ranged_cost: float = 0.0
@export var ranged_damage: float = 0.0
@export var ranged_cooldown: float = 0.0   # secondes entre deux tirs
@export var ranged_zones: Dictionary = {}
@export var ranged_effect: Dictionary = {}

# Hurlement (scream_radius = 0 : aucun)
@export var scream_name: String = "Hurlement"
@export var scream_radius: int = 0
@export var scream_cost: float = 0.0
@export var scream_cooldown: float = 0.0

# Meute (0 : le monstre chasse seul)
@export var pack_radius: int = 0


static func create(monster_id: String) -> MonsterData:
	match monster_id:
		"zombie": return zombie()
		"zombie_child": return zombie_child()
		"zombie_fast": return zombie_fast()
		"zombie_crawler": return zombie_crawler()
		"zombie_brute": return zombie_brute()
		"zombie_hulk": return zombie_hulk()
		"zombie_spitter": return zombie_spitter()
		"zombie_screecher": return zombie_screecher()
		"zombie_electric": return zombie_electric()
		"zombie_soldier": return zombie_soldier()
		"zombie_dog": return zombie_dog()
		"wolf": return wolf()
		"bear": return bear()
		"giant_spider": return giant_spider()
	push_error("MonsterData : monstre inconnu « %s »." % monster_id)
	return zombie()


## Effet d'état d'un coup. id : "bleed" / "poison" / "acid" ("" = seulement le drain de stamina) ; chance : 0..1 ;
## duration (s) ; dps : PV par seconde ; stamina : stamina retirée d'un coup ; part : partie du corps (défaut : la partie touchée).
static func effect(effect_id: String, chance: float, duration: float, dps: float, stamina: float = 0.0, part: String = "") -> Dictionary:
	var e: Dictionary = {"id": effect_id, "chance": chance, "duration": duration, "dps": dps, "stamina": stamina}
	if part != "":
		e["part"] = part
	return e


## Texte lisible d'un effet (infobulle, mode regard) : « 35% : Saignement (10 s, 0.5 PV/s) ».
static func effect_text(e: Dictionary) -> String:
	if e.is_empty():
		return ""
	var bits: Array[String] = []
	var effect_id: String = String(e.get("id", ""))
	if effect_id != "":
		bits.append("%s (%d s, %.1f PV/s)" % [StatusEffects.LABELS.get(effect_id, effect_id), roundi(float(e.get("duration", 0.0))), float(e.get("dps", 0.0))])
	var stamina: float = float(e.get("stamina", 0.0))
	if stamina > 0.0:
		bits.append("-%d stamina" % roundi(stamina))
	return "%d%% : %s" % [roundi(float(e.get("chance", 1.0)) * 100.0), ", ".join(bits)]


static func _make(monster_id: String, name: String, tile: String, hp: float, move: float, detect: int,
		atk_name: String, atk_cost: float, atk_damage: float, zones: Dictionary) -> MonsterData:
	var d := MonsterData.new()
	d.id = monster_id
	d.display_name = name
	d.tile_id = tile
	d.max_hp = hp
	d.move_cost = move
	d.detect_range = detect
	d.attack_name = atk_name
	d.attack_cost = atk_cost
	d.attack_damage = atk_damage
	d.attack_zones = zones.duplicate()
	return d


static func _special(d: MonsterData, name: String, cost: float, damage: float, chance: float, zones: Dictionary) -> void:
	d.special_name = name
	d.special_cost = cost
	d.special_damage = damage
	d.special_chance = chance
	d.special_zones = zones.duplicate()


static func zombie() -> MonsterData:
	var d: MonsterData = _make("zombie", "Zombie", "mon_zombie", 20.0, 1.2, 15, "Griffure", 1.5, 4.0, ZONES_HUMANOID)
	_special(d, "Morsure", 3.5, 9.0, 0.3, ZONES_BITE)
	d.special_infection = 0.5
	return d


## Petit, faible, mais plus vif qu'un zombie ordinaire.
static func zombie_child() -> MonsterData:
	var d: MonsterData = _make("zombie_child", "Zombie enfant", "mon_zombie_child", 15.0, 1.0, 12, "Griffure", 1.2, 2.0, ZONES_LOW)
	return d


## Zombie coureur : se déplace presque deux fois plus vite, frappe vite, voit de loin.
static func zombie_fast() -> MonsterData:
	var d: MonsterData = _make("zombie_fast", "Zombie rapide", "mon_zombie_fast", 25.0, 0.7, 18, "Griffure", 1.0, 3.0, ZONES_HUMANOID)
	_special(d, "Morsure frénétique", 2.0, 6.0, 0.2, ZONES_BITE)
	d.special_infection = 0.4
	return d


## Rampant : lent, fragile, vise les jambes ; son agrippement épuise.
static func zombie_crawler() -> MonsterData:
	var d: MonsterData = _make("zombie_crawler", "Zombie rampant", "mon_zombie_crawler", 18.0, 2.2, 10, "Griffure", 1.5, 3.0, ZONES_LOW)
	_special(d, "Agrippement", 3.0, 3.0, 0.35, ZONES_LEGS)
	d.special_effect = effect("", 1.0, 0.0, 0.0, 15.0)
	return d


## Brute : très résistante, coups lourds, écrasement occasionnel.
static func zombie_brute() -> MonsterData:
	var d: MonsterData = _make("zombie_brute", "Zombie brute", "mon_zombie_brute", 80.0, 1.5, 15, "Coup de poing", 2.0, 8.0, ZONES_HEAVY)
	_special(d, "Coup écrasant", 4.0, 18.0, 0.25, ZONES_HEAVY)
	return d


## Hulk : monstre de fin de partie, énorme réserve de PV et dégâts dévastateurs.
static func zombie_hulk() -> MonsterData:
	var d: MonsterData = _make("zombie_hulk", "Zombie colosse", "mon_zombie_hulk", 180.0, 1.3, 15, "Poing", 2.5, 14.0, ZONES_HEAVY)
	_special(d, "Écrasement", 5.0, 28.0, 0.25, ZONES_HEAVY)
	return d


## Cracheur : crache de l'acide à distance (brûlure sur la partie touchée), griffe de près.
static func zombie_spitter() -> MonsterData:
	var d: MonsterData = _make("zombie_spitter", "Zombie cracheur", "mon_zombie_spitter", 30.0, 1.4, 20, "Griffure", 1.5, 3.0, ZONES_HUMANOID)
	d.ranged_name = "Crachat d'acide"
	d.ranged_range = 7
	d.ranged_cost = 2.5
	d.ranged_damage = 4.0
	d.ranged_cooldown = 8.0
	d.ranged_zones = ZONES_SPIT.duplicate()
	d.ranged_effect = effect("acid", 1.0, 5.0, 0.8)
	return d


## Hurleur : faible au corps à corps, mais son cri attire tous les monstres des environs.
static func zombie_screecher() -> MonsterData:
	var d: MonsterData = _make("zombie_screecher", "Zombie hurleur", "mon_zombie_screecher", 25.0, 1.3, 25, "Griffure", 1.5, 3.0, ZONES_HUMANOID)
	d.scream_name = "Hurlement strident"
	d.scream_radius = 35
	d.scream_cost = 3.0
	d.scream_cooldown = 25.0
	return d


## Électrique : sa décharge vide la stamina du joueur.
static func zombie_electric() -> MonsterData:
	var d: MonsterData = _make("zombie_electric", "Zombie électrique", "mon_zombie_electric", 45.0, 1.3, 15, "Coup", 1.5, 4.0, ZONES_HUMANOID)
	_special(d, "Décharge électrique", 3.0, 8.0, 0.3, ZONES_SHOCK)
	d.special_effect = effect("", 1.0, 0.0, 0.0, 30.0)
	return d


## Soldat : endurant, coups de crosse puissants, morsure occasionnelle.
static func zombie_soldier() -> MonsterData:
	var d: MonsterData = _make("zombie_soldier", "Zombie soldat", "mon_zombie_soldier", 60.0, 1.3, 16, "Coup de crosse", 1.8, 7.0, ZONES_HUMANOID)
	_special(d, "Morsure", 3.0, 9.0, 0.2, ZONES_BITE)
	d.special_infection = 0.4
	return d


## Chien zombie : rapide, mord les jambes, risque de saignement.
static func zombie_dog() -> MonsterData:
	var d: MonsterData = _make("zombie_dog", "Chien zombie", "mon_zombie_dog", 28.0, 0.7, 20, "Morsure", 1.2, 4.0, ZONES_LOW)
	d.attack_effect = effect("bleed", 0.25, 8.0, 0.5)
	d.attack_infection = 0.15
	return d


## Loup : chasse en meute (un loup qui te voit alerte ses voisins), morsures qui saignent.
static func wolf() -> MonsterData:
	var d: MonsterData = _make("wolf", "Loup", "mon_wolf", 35.0, 0.8, 22, "Morsure", 1.3, 6.0, ZONES_LOW)
	d.attack_effect = effect("bleed", 0.35, 10.0, 0.6)
	d.pack_radius = 12
	return d


## Ours : très résistant, coups de patte puissants, morsure qui provoque de graves saignements.
static func bear() -> MonsterData:
	var d: MonsterData = _make("bear", "Ours", "mon_bear", 130.0, 1.1, 12, "Coup de patte", 2.0, 12.0, ZONES_CLAW)
	_special(d, "Morsure", 3.0, 16.0, 0.25, ZONES_BITE)
	d.special_effect = effect("bleed", 0.6, 12.0, 0.8)
	return d


## Veuve noire géante : sa morsure injecte un poison tenace.
static func giant_spider() -> MonsterData:
	var d: MonsterData = _make("giant_spider", "Veuve noire géante", "mon_spider_widow_giant", 45.0, 1.0, 14, "Morsure", 1.5, 4.0, ZONES_BITE)
	d.attack_effect = effect("poison", 0.7, 20.0, 0.5, 0.0, "torso")
	return d
