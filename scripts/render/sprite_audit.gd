class_name SpriteAudit
extends RefCounted
## Audit des sprites au lancement : parcourt tout ce que les données demandent à UlticaTiles (terrains, mobilier, objets, monstres,
## murs, joueur) et liste ce qui ne peut PAS être chargé depuis assets/tiles.json : tuile absente, sprite absent, fichier png introuvable.
## Utilisé par MissingSpritesUI (écran au démarrage). Aucun effet sur le jeu : lecture seule.
## Pour ajouter une famille à contrôler : une fonction _xxx_refs() qui renvoie {id de tuile: [utilisateurs]} et une ligne dans run().

# Sprites de murs choisis directement par nom (ChunkManager.wall_sprite) : ce sont des NOMS DE SPRITE, pas des ids de tuile.
const WALL_SPRITES: Array[String] = [
	"t_wall_edge_ns", "t_wall_edge_ew", "t_wall_corner_nw", "t_wall_corner_ne", "t_wall_corner_se", "t_wall_corner_sw",
	"t_wall_t_connection_n", "t_wall_t_connection_e", "t_wall_t_connection_s", "t_wall_t_connection_w",
	"t_wall_end_piece_n", "t_wall_end_piece_e", "t_wall_end_piece_s", "t_wall_end_piece_w", "t_wall_unconnected",
]
const PLAYER_TILE: String = "player_male"


## [{name, note, total, entries: [{tile, reason, users: Array[String]}]}] : une famille par élément. `total` = nombre de tuiles contrôlées.
static func run() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	report.append(_category("Joueur", "", _player_refs(), false))
	report.append(_category("Terrains", "repli : carré de la couleur du terrain (magenta sans couleur)", _terrain_refs(), false))
	report.append(_category("Murs (sprites par nom)", "repli : carré de la couleur du terrain", _wall_refs(), true))
	report.append(_category("Mobilier", "repli : petit carré coloré", _furniture_refs(), false))
	report.append(_category("Objets", "repli : carré doré", _item_refs(), false))
	report.append(_category("Vêtements portés", "le vêtement n'est pas dessiné sur le joueur", _worn_refs(), false))
	report.append(_category("Monstres", "repli : sprite de zombie ou de loup teinté", _monster_refs(), false))
	return report


static func missing_count(report: Array[Dictionary]) -> int:
	var total: int = 0
	for category: Dictionary in report:
		total += (category["entries"] as Array).size()
	return total


static func _category(category_name: String, note: String, refs: Dictionary, by_sprite: bool) -> Dictionary:
	var entries: Array[Dictionary] = []
	var tiles: Array = refs.keys()
	tiles.sort()
	for tile: String in tiles:
		var reason: String = UlticaTiles.problem_with_sprite(tile) if by_sprite else UlticaTiles.problem_with_tile(tile)
		if reason != "":
			entries.append({"tile": tile, "reason": reason, "users": refs[tile]})
	return {"name": category_name, "note": note, "total": tiles.size(), "entries": entries}


static func _ref(refs: Dictionary, tile: String, user: String) -> void:
	if tile == "":
		return
	if not refs.has(tile):
		refs[tile] = []
	var users: Array = refs[tile]
	if not users.has(user):
		users.append(user)


static func _player_refs() -> Dictionary:
	var refs: Dictionary = {}
	_ref(refs, PLAYER_TILE, "sprite du joueur")
	return refs


static func _wall_refs() -> Dictionary:
	var refs: Dictionary = {}
	for sprite_name: String in WALL_SPRITES:
		_ref(refs, sprite_name, "murs")
	return refs


static func _terrain_refs() -> Dictionary:
	var refs: Dictionary = {}
	var i: int = 0
	while TerrainDB.id_of(i) != "":
		var id: String = TerrainDB.id_of(i)
		_ref(refs, TerrainDB.tile_of(i), id)
		_ref(refs, TerrainDB.ground_tile_of(i), id)
		i += 1
	return refs


static func _furniture_refs() -> Dictionary:
	var refs: Dictionary = {}
	for f in range(1, FurnitureDB.count() + 1):
		_ref(refs, FurnitureDB.tile_of(f), FurnitureDB.id_of(f))
	return refs


static func _item_refs() -> Dictionary:
	var refs: Dictionary = {}
	for id: String in ItemDB.ids():
		_ref(refs, String(ItemDB.get_def(id).get("tile", "")), id)
	return refs


static func _worn_refs() -> Dictionary:
	var refs: Dictionary = {}
	for id: String in ItemDB.ids():
		_ref(refs, String(ItemDB.get_def(id).get("worn_tile", "")), id)
	return refs


static func _monster_refs() -> Dictionary:
	var refs: Dictionary = {}
	for id: String in MonsterDB.ids():
		var def: Dictionary = MonsterDB.def_of(id)
		_ref(refs, String(def.get("tile", "mon_" + id)), String(def.get("name", id)))
	return refs
