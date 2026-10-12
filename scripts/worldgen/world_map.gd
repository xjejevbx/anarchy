class_name WorldMap
extends RefCounted
## Carte du monde (docs/WORLD_GEN.md §5.1) : biomes, lacs, rivières. Tout est une FONCTION PURE de (seed, coordonnées) :
## des champs continus (altitude, humidité, rivière...) évalués à n'importe quelle case. Le terrain d'une case et la
## « cellule macro » de 24 x 24 (utile aux villes et routes) lisent donc la même source : aucune couture, aucun
## état partagé, aucune dépendance à l'ordre de génération. Réglages dans data/worldgen/biomes.json.
## Les bruits utilisent FastNoiseLite ; les décisions fines (arbres) n'utilisent que des entiers (WorldRng).

const PATH: String = "res://data/worldgen/biomes.json"
const SPAWN_CLEAR_RADIUS: float = 3.5   # pas d'arbre autour du point de départ
const SPAWN_STEP: int = 6               # pas de la recherche en spirale du point de départ (cases)
const SPAWN_MAX_RINGS: int = 400        # jusqu'à ~2400 cases de l'origine

## Nature d'une case ou d'une cellule (ORDRE = ordre de "kinds" dans biomes.json).
enum Kind { PLAIN, FOREST, SWAMP, LAKE_DEEP, LAKE_SHALLOW, RIVER_DEEP, RIVER_SHALLOW, SHORE_LAKE, BANK_RIVER }

static var _config: Dictionary = {}
static var _cache: Dictionary = {}  # seed -> WorldMap

var world_seed: int = 4444

var _altitude: FastNoiseLite
var _humidity: FastNoiseLite
var _river: FastNoiseLite
var _ford: FastNoiseLite
var _detail: FastNoiseLite
var _lake_level: float
var _lake_deep_margin: float
var _lake_shore: float
var _river_half_width: float
var _river_deep_half_width: float
var _river_bank: float
var _ford_level: float
var _swamp_humidity: float
var _swamp_altitude_max: float
var _forest_humidity: float
var _tree_plain: float
var _tree_forest: float
var _tree_swamp: float

var _t_grass: int
var _t_tree: int
var _t_water_sh: int
var _t_water_dp: int
var _t_swater_sh: int
var _t_mud: int
var _t_dirt: int
var _t_sand: int

var _spawn: Vector2i = Vector2i.ZERO


## Une instance par seed (les bruits sont construits une seule fois).
static func for_seed(seed_value: int) -> WorldMap:
	if not _cache.has(seed_value):
		_cache[seed_value] = WorldMap.new(seed_value)
	return _cache[seed_value]


static func _load_config() -> void:
	if not _config.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WorldMap : %s introuvable ou invalide." % PATH)
		return
	_config = parsed


func _init(seed_value: int = 0) -> void:
	world_seed = seed_value
	_load_config()
	var noise_cfg: Dictionary = _config["noise"]
	_altitude = _make_noise(noise_cfg["altitude"], 1)
	_humidity = _make_noise(noise_cfg["humidity"], 2)
	_river = _make_noise(noise_cfg["river"], 3)
	_ford = _make_noise(noise_cfg["ford"], 4)
	_detail = _make_noise(noise_cfg["detail"], 5)
	var lake: Dictionary = _config["lake"]
	_lake_level = lake["level"]
	_lake_deep_margin = lake["deep_margin"]
	_lake_shore = lake["shore"]
	var river: Dictionary = _config["river"]
	_river_half_width = river["half_width"]
	_river_deep_half_width = river["deep_half_width"]
	_river_bank = river["bank"]
	_ford_level = river["ford_level"]
	var land: Dictionary = _config["land"]
	_swamp_humidity = land["swamp_humidity"]
	_swamp_altitude_max = land["swamp_altitude_max"]
	_forest_humidity = land["forest_humidity"]
	var trees: Dictionary = _config["trees"]
	_tree_plain = trees["plain"]
	_tree_forest = trees["forest"]
	_tree_swamp = trees["swamp"]
	_t_grass = TerrainDB.index_of("t_grass")
	_t_tree = TerrainDB.index_of("t_tree")
	_t_water_sh = TerrainDB.index_of("t_water_sh")
	_t_water_dp = TerrainDB.index_of("t_water_dp")
	_t_swater_sh = TerrainDB.index_of("t_swater_sh")
	_t_mud = TerrainDB.index_of("t_mud")
	_t_dirt = TerrainDB.index_of("t_dirt")
	_t_sand = TerrainDB.index_of("t_sand")
	_spawn = _find_spawn()


func _make_noise(cfg: Dictionary, layer: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = WorldRng.mix(world_seed, WorldRng.LAYER_BIOME, layer) & 0x7FFFFFFF
	noise.frequency = cfg["frequency"]
	var octaves: int = cfg["octaves"]
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	return noise


# --- Nature d'une case / d'une cellule ---

func kind_at(cell: Vector2i) -> int:
	var x: float = cell.x
	var y: float = cell.y
	var altitude: float = _altitude.get_noise_2d(x, y)
	if altitude < _lake_level:
		return Kind.LAKE_DEEP if altitude < _lake_level - _lake_deep_margin else Kind.LAKE_SHALLOW
	var river: float = absf(_river.get_noise_2d(x, y))
	if river < _river_half_width:
		if river < _river_deep_half_width and _ford.get_noise_2d(x, y) < _ford_level:
			return Kind.RIVER_DEEP
		return Kind.RIVER_SHALLOW  # peu profond : un gué
	if altitude < _lake_level + _lake_shore:
		return Kind.SHORE_LAKE
	if river < _river_half_width + _river_bank:
		return Kind.BANK_RIVER
	var humidity: float = _humidity.get_noise_2d(x, y)
	if humidity > _swamp_humidity and altitude < _swamp_altitude_max:
		return Kind.SWAMP
	if humidity > _forest_humidity:
		return Kind.FOREST
	return Kind.PLAIN


## Nature d'une cellule macro de 24 x 24 (échantillonnée en son centre).
func cell_kind(cell_coord: Vector2i) -> int:
	return kind_at(cell_coord * Chunk.SIZE + Vector2i(Chunk.SIZE / 2, Chunk.SIZE / 2))


static func kind_name(kind: int) -> String:
	_load_config()
	return String((_config["kinds"] as Array)[kind]["name"])


static func kind_color(kind: int) -> Color:
	_load_config()
	return Color.html(String((_config["kinds"] as Array)[kind]["color"]))


static func kind_count() -> int:
	_load_config()
	return (_config["kinds"] as Array).size()


## Eau praticable à pied (eau peu profonde ou de marais) ou terre ferme : tout sauf l'eau profonde.
static func is_deep_water(kind: int) -> bool:
	return kind == Kind.LAKE_DEEP or kind == Kind.RIVER_DEEP


# --- Terrain d'une case ---

## Index TerrainDB de la case (fonction pure de seed, case et z).
func terrain_at(cell: Vector2i, z: int = 0) -> int:
	if Vector2(cell).distance_to(Vector2(_spawn)) <= SPAWN_CLEAR_RADIUS:
		return _t_grass
	var kind: int = kind_at(cell)
	match kind:
		Kind.LAKE_DEEP, Kind.RIVER_DEEP:
			return _t_water_dp
		Kind.LAKE_SHALLOW, Kind.RIVER_SHALLOW:
			return _t_water_sh
		Kind.SHORE_LAKE:
			return _t_sand
		Kind.BANK_RIVER:
			return _t_dirt
	var detail: float = _detail.get_noise_2d(cell.x, cell.y)
	var ground: int = _t_grass
	var tree_probability: float = _tree_plain
	match kind:
		Kind.SWAMP:
			if detail < -0.25:
				return _t_swater_sh  # mare : pas d'arbre
			ground = _t_mud if detail < 0.1 else _t_grass
			tree_probability = _tree_swamp
		Kind.FOREST:
			ground = _t_dirt if detail < -0.4 else _t_grass
			tree_probability = _tree_forest
		_:
			ground = _t_dirt if detail < -0.45 else _t_grass  # plaques de terre nue
	if WorldRng.chance(world_seed, WorldRng.LAYER_TERRAIN, cell.x, cell.y, z, tree_probability):
		return _t_tree
	return ground


# --- Point de départ ---

## Case de départ du joueur : première zone de terre sèche dégagée en spirale depuis l'origine (déterministe).
func spawn_cell() -> Vector2i:
	return _spawn


func _find_spawn() -> Vector2i:
	for ring in range(0, SPAWN_MAX_RINGS):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var candidate := Vector2i(dx * SPAWN_STEP, dy * SPAWN_STEP)
				if _is_good_spawn(candidate):
					return candidate
	return Vector2i.ZERO


## Bon départ : la case et ses 8 voisines à SPAWN_STEP cases sont de la plaine ou de la forêt.
func _is_good_spawn(center: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var kind: int = kind_at(center + Vector2i(dx, dy) * SPAWN_STEP)
			if kind != Kind.PLAIN and kind != Kind.FOREST:
				return false
	return true
