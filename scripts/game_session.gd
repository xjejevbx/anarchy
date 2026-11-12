class_name GameSession
extends RefCounted
## Demande de changement de partie qui survit à `reload_current_scene()` (menu principal, nouvelle partie, arène, chargement).
## `Main` la consomme une seule fois au démarrage ; sans demande, il affiche l'écran des sauvegardes.

enum Request { MENU, NEW_GAME, ARENA, LOAD }

static var mode: int = Request.MENU
static var seed_text: String = ""
static var scenario: String = "default"
static var slot: String = ""


static func request_new_game(seed_value: String, scenario_value: String) -> void:
	mode = Request.NEW_GAME
	seed_text = seed_value
	scenario = scenario_value
	slot = ""


static func request_load(slot_value: String) -> void:
	mode = Request.LOAD
	slot = slot_value
	seed_text = ""
	scenario = "default"


## Arène de test : seed fixe et contenu de démonstration (voir TestArena et Main).
static func request_arena() -> void:
	mode = Request.ARENA
	seed_text = ""
	scenario = "default"
	slot = ""


static func request_menu() -> void:
	mode = Request.MENU
	seed_text = ""
	scenario = "default"
	slot = ""


static func has_request() -> bool:
	return mode != Request.MENU


## Consomme la demande (retour au menu après lecture).
static func take() -> Dictionary:
	var request: Dictionary = {"mode": mode, "seed_text": seed_text, "scenario": scenario, "slot": slot}
	request_menu()
	return request
