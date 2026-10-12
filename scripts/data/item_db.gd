class_name ItemDB
extends RefCounted
## Base de données d'objets, chargée depuis res://data/items.json (voir le champ "_doc" du fichier).
## Champs : name, weight (kg), size [longueur, largeur] (cm), tile (id UltiCa), slot, worn_tile,
## capacity_bonus (kg ajoutés à la capacité du joueur), stackable, container {...}.

const ITEMS_PATH: String = "res://data/items.json"

# Emplacements d'équipement (ordre d'affichage dans l'inventaire) et leurs noms.
const SLOTS: Array[String] = ["head", "torso", "outer", "legs", "feet", "back"]
const SLOT_NAMES: Dictionary = {
	"head": "Tête", "torso": "Haut", "outer": "Veste", "legs": "Jambes", "feet": "Pieds", "back": "Dos",
}
# Ordre de dessin des vêtements sur le sprite du joueur (du dessous au dessus).
const WORN_DRAW_ORDER: Array[String] = ["feet", "legs", "torso", "outer", "head", "back"]

static var _loaded: bool = false
static var _items: Dictionary = {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(ITEMS_PATH):
		push_error("ItemDB : %s introuvable." % ITEMS_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ItemDB : items.json invalide.")
		return
	_items = parsed.get("items", {})


static func get_def(item_id: String) -> Dictionary:
	_ensure_loaded()
	if not _items.has(item_id):
		push_warning("ItemDB : objet inconnu « %s »." % item_id)
		return {}
	return _items[item_id]
