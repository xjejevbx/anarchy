class_name UlticaTiles
extends RefCounted
## Accès aux sprites UltiCa (pack généré par tools/build_ultica_pack.py).
##
## Vocabulaire repris de CDDA :
##   - "tuile" (tile id)  : ex. "mon_zombie", avec une couche "fg" (devant) et "bg" (derrière)
##   - "sprite"           : une image, ex. "mon_zombie_3", avec un décalage de dessin
## Une couche peut avoir plusieurs variantes pondérées ; pick_sprite() en choisit une
## de façon déterministe à partir d'une graine (pour que l'herbe ne scintille pas).

const PACK_DIR: String = "res://assets/"

static var _loaded: bool = false
static var _sprites: Dictionary = {}   # nom -> {file, offset}
static var _tiles: Dictionary = {}     # id -> {fg: [...], bg: [...]}
static var _textures: Dictionary = {}  # cache nom -> Texture2D


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path: String = PACK_DIR + "tiles.json"
	if not FileAccess.file_exists(path):
		push_error("UlticaTiles : %s introuvable (copie le dossier assets/ultica dans le projet)." % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("UlticaTiles : tiles.json invalide.")
		return
	_sprites = parsed.get("sprites", {})
	_tiles = parsed.get("tiles", {})


## Choisit un sprite de la couche ("fg" ou "bg") d'une tuile. Renvoie "" s'il n'y en a pas.
static func pick_sprite(tile_id: String, layer: String, variant_seed: int) -> String:
	_ensure_loaded()
	var variants: Array = _tiles.get(tile_id, {}).get(layer, [])
	if variants.is_empty():
		return ""
	var total: int = 0
	for v: Dictionary in variants:
		total += int(v["weight"])
	var roll: int = absi(variant_seed) % maxi(total, 1)
	for v: Dictionary in variants:
		roll -= int(v["weight"])
		if roll < 0:
			return v["sprite"]
	return variants[0]["sprite"]


static func get_texture(sprite_name: String) -> Texture2D:
	_ensure_loaded()
	if _textures.has(sprite_name):
		return _textures[sprite_name]
	var info: Dictionary = _sprites.get(sprite_name, {})
	if info.is_empty():
		push_warning("UlticaTiles : sprite inconnu « %s »." % sprite_name)
		_textures[sprite_name] = null
		return null
	var tex := load(PACK_DIR + String(info["file"])) as Texture2D
	_textures[sprite_name] = tex
	return tex


## Décalage de dessin par rapport au coin haut-gauche de la case (ex. (0,-16) pour un personnage).
static func get_offset(sprite_name: String) -> Vector2:
	_ensure_loaded()
	var off: Array = _sprites.get(sprite_name, {}).get("offset", [0, 0])
	return Vector2(float(off[0]), float(off[1]))


## Dessine un sprite depuis la méthode _draw() de `canvas`. `cell_origin` = coin haut-gauche de la case.
static func draw_sprite(canvas: CanvasItem, sprite_name: String, cell_origin: Vector2, tint: Color = Color.WHITE) -> void:
	if sprite_name.is_empty():
		return
	var tex: Texture2D = get_texture(sprite_name)
	if tex == null:
		return
	canvas.draw_texture(tex, cell_origin + get_offset(sprite_name), tint)


## Dessine un sprite dans `box` (icônes d'interface) : sans décalage, centré, réduit si trop grand,
## jamais agrandi. Renvoie false si le sprite est introuvable (l'appelant dessine un repli).
static func draw_icon(canvas: CanvasItem, sprite_name: String, box: Rect2, tint: Color = Color.WHITE) -> bool:
	if sprite_name.is_empty():
		return false
	var tex: Texture2D = get_texture(sprite_name)
	if tex == null:
		return false
	var tex_size: Vector2 = tex.get_size()
	var factor: float = minf(1.0, minf(box.size.x / tex_size.x, box.size.y / tex_size.y))
	var draw_size: Vector2 = tex_size * factor
	canvas.draw_texture_rect(tex, Rect2(box.position + (box.size - draw_size) / 2.0, draw_size), false, tint)
	return true
