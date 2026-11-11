class_name MonsterData
extends Resource
## Données d'un type de monstre. Depuis le jalon 6a elles viennent de res://data/monsters.json (voir MonsterDB et docs/MONSTER_SPAWN.md) :
## create(id) délègue à MonsterDB. Les fonctions zombie(), wolf()... restent en façade (compatibilité tests, main.gd, Infection).
## Compétences spéciales (toutes optionnelles) :
##  - effets sur coup (attack_effect / special_effect / ranged_effect) : saignement, poison, acide, drain de stamina (StatusEffects) ;
##  - tir à distance (ranged_*) : visé dans le champ de vision, avec temps de recharge ;
##  - hurlement (scream_*) : alerte tous les monstres du rayon sur la position du joueur ;
##  - meute (pack_radius) : quand l'un voit le joueur, ses semblables proches le traquent aussi ;
##  - armure (armor, capacité ARMOR(n)) : réduit chaque coup reçu.

## Les 14 monstres d'origine (le bestiaire complet : MonsterDB.ids()).
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
# Noms utilisables dans le champ "zones" de monsters.json.
const ZONE_TABLES: Dictionary = {
	"humanoid": ZONES_HUMANOID, "bite": ZONES_BITE, "low": ZONES_LOW, "legs": ZONES_LEGS,
	"heavy": ZONES_HEAVY, "claw": ZONES_CLAW, "spit": ZONES_SPIT, "shock": ZONES_SHOCK,
}

@export var id: String = "zombie"
@export var display_name: String = "Monstre"
@export var gender: String = "m"             # "m" / "f" : accord des adjectifs d'affixes (jalon 6b)
@export var tile_id: String = "mon_zombie"  # id de tuile UltiCa (voir UlticaTiles)
@export var fallback_tile: String = "mon_zombie"   # dessiné (teinté) si tile_id est absent du pack
@export var tint: Color = Color.WHITE              # teinte du repli
@export var tags: Array[String] = []
@export var behavior: String = "hostile"     # hostile / passive (fuit) / territorial (n'attaque que de près)
@export var default_state: String = "idle"   # réservé (jalon 6b : sommeil, garde...)
@export var wake_range: int = 6              # réservé (jalon 6b)
@export var threat: int = 1                  # 1 à 10 : budget de menace par chunk
@export var armor: int = 0                   # PV retirés à chaque coup reçu (minimum 1 PV de dégâts)
@export var abilities: Array[String] = []    # capacités (MonsterDB.ABILITIES) ; toutes agissent depuis le jalon 6d (sauf LOOT_CARRIER)
@export var affixes: Array[String] = []      # modificateurs appliqués (monster_affixes.json), 0 à 2
@export var never_sleeps: bool = false       # affixe « enragé » : ne dort jamais
@export var summon_ids: Array[String] = []   # SUMMON / RAISE : monstres appelés ou relevés (champ "summons" de monsters.json)
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


## Le monstre a-t-il la capacité `base` (« EXPLODE » pour « EXPLODE(gas) ») ?
func has_ability(base: String) -> bool:
	for ability: String in abilities:
		if ability == base or ability.begins_with(base + "("):
			return true
	return false


## Argument d'une capacité : « gas » pour « EXPLODE(gas) », "" s'il n'y en a pas (ou si le monstre n'a pas la capacité).
func ability_arg(base: String) -> String:
	for ability: String in abilities:
		if ability.begins_with(base + "("):
			return ability.substr(base.length() + 1, ability.length() - base.length() - 2)
	return ""


## Argument numérique d'une capacité (« 0.3 » pour « REGEN(0.3) »), `fallback` s'il n'y en a pas.
func ability_value(base: String, fallback: float) -> float:
	var text: String = ability_arg(base)
	return text.to_float() if text != "" else fallback


## Fabrique un monstre depuis data/monsters.json (id inconnu : erreur et zombie).
static func create(monster_id: String) -> MonsterData:
	return MonsterDB.create(monster_id)


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


# --- Façade des anciennes fonctions (les valeurs sont dans data/monsters.json) ---

static func zombie() -> MonsterData:
	return MonsterDB.create("zombie")


static func zombie_child() -> MonsterData:
	return MonsterDB.create("zombie_child")


static func zombie_fast() -> MonsterData:
	return MonsterDB.create("zombie_fast")


static func zombie_crawler() -> MonsterData:
	return MonsterDB.create("zombie_crawler")


static func zombie_brute() -> MonsterData:
	return MonsterDB.create("zombie_brute")


static func zombie_hulk() -> MonsterData:
	return MonsterDB.create("zombie_hulk")


static func zombie_spitter() -> MonsterData:
	return MonsterDB.create("zombie_spitter")


static func zombie_screecher() -> MonsterData:
	return MonsterDB.create("zombie_screecher")


static func zombie_electric() -> MonsterData:
	return MonsterDB.create("zombie_electric")


static func zombie_soldier() -> MonsterData:
	return MonsterDB.create("zombie_soldier")


static func zombie_dog() -> MonsterData:
	return MonsterDB.create("zombie_dog")


static func wolf() -> MonsterData:
	return MonsterDB.create("wolf")


static func bear() -> MonsterData:
	return MonsterDB.create("bear")


static func giant_spider() -> MonsterData:
	return MonsterDB.create("giant_spider")
