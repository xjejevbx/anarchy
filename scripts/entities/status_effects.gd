class_name StatusEffects
extends RefCounted
## Effets d'état infligés au joueur par les monstres (saignement, poison, acide, irradiation, brûlure, engelure) + drain de stamina.
## Ne modifie pas Player : le suivi se branche sur EventBus.time_advanced (chaque action qui fait passer le temps).
## Un effet = dégâts par seconde sur une partie du corps pendant une durée ; le temps compté est celui des actions
## (1 point d'action = 1 seconde). Les dégâts s'accumulent en fractions et sont appliqués par PV entiers (`carry`).
## Définition d'un effet (dictionnaire, voir MonsterData.effect) : {id, chance, duration, dps, stamina, part}, plus (optionnel) `text` : message
## du drain de stamina (« %d » = la quantité). Jalon 6c : radiation (aura radioactive), burn (aura de feu, explosions), frostbite (aura de froid).

const LABELS: Dictionary = {
	"bleed": "Saignement", "poison": "Poison", "acid": "Brûlure acide",
	"radiation": "Irradiation", "burn": "Brûlure", "frostbite": "Engelure",
}  # effets avec dégâts par seconde
const START_TEXT: Dictionary = {
	"bleed": "Vous saignez !", "poison": "Vous êtes empoisonné !", "acid": "L'acide vous ronge !",
	"radiation": "Vous êtes irradié !", "burn": "Vous brûlez !", "frostbite": "Le froid vous mord !",
}
const END_TEXT: Dictionary = {
	"bleed": "Le saignement s'arrête.", "poison": "Le poison cesse d'agir.", "acid": "La brûlure d'acide s'estompe.",
	"radiation": "Les radiations se dissipent.", "burn": "Les flammes s'éteignent sur vous.", "frostbite": "L'engelure s'estompe.",
}
const DEFAULT_DRAIN_TEXT: String = "Une décharge vous vide de %d de stamina."

static var _current: StatusEffects = null

var player: Player
var effects: Dictionary = {}   # id -> {remaining, dps, part, carry}


## Gestionnaire d'effets du joueur donné (créé à la demande, branché sur le temps du jeu).
static func of(target: Player) -> StatusEffects:
	if _current == null or _current.player != target:
		if _current != null and EventBus.time_advanced.is_connected(_current._on_time):
			EventBus.time_advanced.disconnect(_current._on_time)
		_current = StatusEffects.new(target)
	return _current


func _init(target: Player) -> void:
	player = target
	EventBus.time_advanced.connect(_on_time)


## Texte court des effets en cours (HUD, menu « utiliser ») : « Saignement, Poison, Infection (Fièvre) », "" s'il n'y en a aucun.
static func summary() -> String:
	var parts: Array[String] = []
	if _current != null and is_instance_valid(_current.player) and not _current.player.dead:
		for id: String in _current.effects:
			parts.append(String(LABELS.get(id, id)))
	var stage: String = Infection.stage_label()
	if stage != "":
		parts.append("Infection (%s)" % stage)
	return ", ".join(parts)


## Applique un effet (déjà tiré : la chance est testée par l'appelant). `hit_part` : partie touchée par l'attaque.
static func apply(target: Player, effect: Dictionary, hit_part: String) -> void:
	if effect.is_empty() or target == null or target.dead:
		return
	var manager: StatusEffects = of(target)
	var drain: float = float(effect.get("stamina", 0.0))
	if drain > 0.0:
		manager._drain(drain, String(effect.get("text", DEFAULT_DRAIN_TEXT)))
	var id: String = String(effect.get("id", ""))
	if id == "":
		return
	var part: String = String(effect.get("part", hit_part))
	var existing: bool = manager.effects.has(id)
	manager.effects[id] = merge(manager.effects.get(id, {}), float(effect.get("duration", 0.0)),
		float(effect.get("dps", 0.0)), part)
	if not existing:
		EventBus.message_logged.emit(String(START_TEXT.get(id, "Vous subissez : %s." % id)))


## Fusion d'un effet déjà actif avec un nouveau coup : la durée et l'intensité les plus fortes l'emportent.
static func merge(old: Dictionary, duration: float, dps: float, part: String) -> Dictionary:
	if old.is_empty():
		return {"remaining": duration, "dps": dps, "part": part, "carry": 0.0}
	old["remaining"] = maxf(float(old["remaining"]), duration)
	old["dps"] = maxf(float(old["dps"]), dps)
	return old


func _drain(amount: float, text: String) -> void:
	player.stamina = maxf(player.stamina - amount, 0.0)
	EventBus.stamina_changed.emit(player.stamina, Player.STAMINA_MAX, player.get_time_penalty())
	EventBus.message_logged.emit(text % roundi(amount))


func _on_time(points: float) -> void:
	if player == null or not is_instance_valid(player) or player.dead:
		effects.clear()
		return
	for id: String in effects.keys():
		var e: Dictionary = effects[id]
		var seconds: float = minf(points, float(e["remaining"]))
		e["remaining"] = float(e["remaining"]) - points
		e["carry"] = float(e["carry"]) + float(e["dps"]) * seconds
		var whole: float = floorf(float(e["carry"]))
		if whole >= 1.0:
			e["carry"] = float(e["carry"]) - whole
			var part: String = String(e["part"])
			EventBus.message_logged.emit("%s : -%d PV (%s)." % [LABELS.get(id, id), int(whole), BodyPartDB.name_of(part)])
			player.take_damage(whole, part)
			if player.dead:
				effects.clear()
				return
		if float(e["remaining"]) <= 0.0:
			effects.erase(id)
			EventBus.message_logged.emit(String(END_TEXT.get(id, "L'effet se dissipe.")))
