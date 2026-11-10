class_name Infection
extends RefCounted
## Infection par morsure : le joueur se transforme PEU À PEU en zombie, sauf s'il prend des antibiotiques à temps.
## Ne modifie pas Player : le suivi se branche sur EventBus.time_advanced (comme StatusEffects). 1 point d'action = 1 seconde.
##
## Progression de 0 à 1 sur DURATION secondes de jeu. À 1 : le joueur meurt et un zombie se relève à sa place.
## Stades (symptômes cumulatifs) : incubation (rien), fièvre (stamina qui fond), délire (stamina qui fond plus vite),
## phase terminale (stamina + PV du torse qui fondent). Les antibiotiques guérissent complètement jusqu'à CURE_LIMIT ;
## au-delà ils ne font que reculer la progression de LATE_SETBACK (gagner du temps).
## Valeurs posées « à l'aveugle » : à régler en jeu (DURATION surtout).

const DURATION: float = 3600.0     # secondes de jeu entre la morsure et la transformation (1 h)
const CURE_LIMIT: float = 0.75     # au-delà : plus de guérison complète
const LATE_SETBACK: float = 0.15   # recul de la progression par dose prise trop tard

# at : seuil de progression ; drain : stamina perdue par seconde ; hp : PV du torse perdus par seconde.
const STAGES: Array[Dictionary] = [
	{"at": 0.0, "name": "Incubation", "drain": 0.0, "hp": 0.0, "msg": ""},
	{"at": 0.25, "name": "Fièvre", "drain": 0.1, "hp": 0.0,
		"msg": "Vous avez de la fièvre et des frissons : l'infection progresse."},
	{"at": 0.5, "name": "Délire", "drain": 0.25, "hp": 0.0,
		"msg": "Votre vision se trouble et vos membres tremblent : l'infection gagne du terrain."},
	{"at": 0.75, "name": "Phase terminale", "drain": 0.5, "hp": 0.03,
		"msg": "Votre peau grisonne et vous toussez du sang. Il est presque trop tard pour guérir."},
]

static var _current: Infection = null

var player: Player
var active: bool = false
var progress: float = 0.0
var stage: int = 0

var _carry: float = 0.0   # fractions de PV pas encore appliquées


static func of(target: Player) -> Infection:
	if _current == null or _current.player != target:
		if _current != null and EventBus.time_advanced.is_connected(_current._on_time):
			EventBus.time_advanced.disconnect(_current._on_time)
		_current = Infection.new(target)
	return _current


func _init(target: Player) -> void:
	player = target
	EventBus.time_advanced.connect(_on_time)


## Indice du stade pour une progression donnée (fonction pure, testée).
static func stage_for(value: float) -> int:
	var result: int = 0
	for i in STAGES.size():
		if value >= float(STAGES[i]["at"]):
			result = i
	return result


## Le joueur est-il infecté ?
static func is_infected(target: Player) -> bool:
	return _current != null and _current.player == target and _current.active


## Nom du stade en cours ("" si le joueur n'est pas infecté). Les pourcentages ne sont jamais montrés au joueur.
static func stage_label() -> String:
	if _current == null or not _current.active or not is_instance_valid(_current.player):
		return ""
	return String(STAGES[_current.stage]["name"])


## Infecte le joueur (sans effet s'il l'est déjà).
static func infect(target: Player) -> void:
	if target == null or target.dead:
		return
	var inf: Infection = of(target)
	if inf.active:
		return
	inf.active = true
	inf.progress = 0.0
	inf.stage = 0
	inf._carry = 0.0
	EventBus.message_logged.emit("La morsure est infectée ! Sans antibiotiques, vous allez devenir l'un d'eux (u : utiliser un objet).")


## Prise d'antibiotiques. Renvoie {used: bool (la dose est consommée), text: message du journal}.
static func take_antibiotics(target: Player) -> Dictionary:
	if not is_infected(target):
		return {"used": false, "text": "Vous n'êtes pas infecté : inutile de gaspiller des antibiotiques."}
	var inf: Infection = of(target)
	if inf.progress <= CURE_LIMIT:
		inf.active = false
		inf.progress = 0.0
		inf.stage = 0
		inf._carry = 0.0
		return {"used": true, "text": "Les antibiotiques font effet : l'infection est vaincue."}
	inf.progress = maxf(inf.progress - LATE_SETBACK, 0.0)
	inf.stage = stage_for(inf.progress)
	return {"used": true, "text": "Trop tard pour une guérison complète : les antibiotiques ralentissent seulement le mal."}


func _on_time(points: float) -> void:
	if not active:
		return
	if player == null or not is_instance_valid(player) or player.dead:
		active = false
		return
	progress = minf(progress + points / DURATION, 1.0)
	var target_stage: int = stage_for(progress)
	while stage < target_stage:
		stage += 1
		EventBus.message_logged.emit(String(STAGES[stage]["msg"]))
	var def: Dictionary = STAGES[stage]
	var drain: float = float(def["drain"]) * points
	if drain > 0.0:
		player.stamina = maxf(player.stamina - drain, 0.0)
		EventBus.stamina_changed.emit(player.stamina, Player.STAMINA_MAX, player.get_time_penalty())
	_carry += float(def["hp"]) * points
	var whole: float = floorf(_carry)
	if whole >= 1.0:
		_carry -= whole
		EventBus.message_logged.emit("L'infection vous ronge : -%d PV (Torse)." % int(whole))
		player.take_damage(whole, "torso")
		if player.dead:
			active = false
			return
	if progress >= 1.0:
		_turn()


## Transformation : le joueur meurt, un zombie se relève là où il est tombé.
func _turn() -> void:
	active = false
	EventBus.message_logged.emit("La fièvre vous terrasse... Vous devenez l'un des leurs.")
	var cell: Vector2i = player.grid_pos
	var world: World = player.world
	player.take_damage(BodyPartDB.max_hp_of("torso") * 10.0, "torso")
	if player.dead and world != null:
		world.spawn_monster(MonsterData.zombie(), cell)
		EventBus.message_logged.emit("Un zombie se relève à l'endroit où vous êtes tombé.")


## État de l'infection, copié pour la sauvegarde.
static func snapshot() -> Dictionary:
	if _current == null:
		return {}
	return {
		"active": _current.active,
		"progress": _current.progress,
		"stage": _current.stage,
		"carry": _current._carry,
	}


## Détache le gestionnaire courant (nouvelle partie ou chargement).
static func reset() -> void:
	if _current != null and EventBus.time_advanced.is_connected(_current._on_time):
		EventBus.time_advanced.disconnect(_current._on_time)
	_current = null


## Réapplique l'infection sauvegardée au joueur donné.
static func restore(target: Player, data: Dictionary) -> void:
	reset()
	if target == null or not bool(data.get("active", false)):
		return
	var inf: Infection = of(target)
	inf.active = true
	inf.progress = clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	inf.stage = stage_for(inf.progress)
	inf._carry = float(data.get("carry", 0.0))
