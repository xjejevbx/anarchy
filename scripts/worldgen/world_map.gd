class_name WorldMap
extends RefCounted
## Carte du monde (docs/WORLD_GEN.md §5.1 et §16) : continents, océans, climats, biomes, lacs, rivières. Tout est une FONCTION PURE
## de (seed, coordonnées) : des champs continus évalués à n'importe quelle case. Le terrain d'une case et la « cellule macro » de
## 24 x 24 (utile aux villes et routes) lisent donc la même source : aucune couture, aucun état partagé, aucune dépendance à
## l'ordre de génération. Réglages dans data/worldgen/biomes.json.
## Jalon 9 : pas de relief (ni collines, ni montagnes) ; la profondeur n'existe que pour l'eau (océan et lacs). La neige viendra
## avec les saisons. Les bruits utilisent FastNoiseLite ; les décisions fines (arbres) n'utilisent que des entiers (WorldRng).

const PATH: String = "res://data/worldgen/biomes.json"
const SPAWN_CLEAR_RADIUS: float = 3.5   # pas d'arbre autour du point de départ (appliqué par ChunkGenerator)
const SPAWN_STEP: int = 6               # pas de la recherche en spirale du point de départ (cases)
const SPAWN_MAX_RINGS: int = 400        # jusqu'à ~2400 cases de l'origine

## Nature d'une case ou d'une cellule (ORDRE = ordre de "kinds" dans biomes.json ET de RouteMap.KIND_IDS : ajouter à la FIN).
enum Kind { PLAIN, FOREST, SWAMP, LAKE_DEEP, LAKE_SHALLOW, RIVER_DEEP, RIVER_SHALLOW, SHORE_LAKE, BANK_RIVER,
	OCEAN_DEEP, OCEAN_SHALLOW, BEACH, TUNDRA, TAIGA, DESERT, SAVANNA, JUNGLE }

static var _config: Dictionary = {}
static var _cache: Dictionary = {}  # seed -> WorldMap

var world_seed: int = 0

var _altitude: FastNoiseLite
var _humidity: FastNoiseLite
var _river: FastNoiseLite
var _ford: FastNoiseLite
var _detail: FastNoiseLite
var _continent: FastNoiseLite
var _warp_x: FastNoiseLite
var _warp_y: FastNoiseLite
var _temperature: FastNoiseLite
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
var _trees: Dictionary = {}   # Kind -> probabilité d'arbre

# Planète
var _sea_level: float
var _shelf_margin: float
var _beach_width: float
var _warp_amplitude: float
var _origin_bonus: float
var _origin_radius: float
var _band_period: float
var _temp_noise: float
var _hot: float
var _cold: float
var _hot_humid: float
var _hot_dry: float
var _cold_humid: float
var _coast_humidity: float
var _interior_span: float
var _desert_river_scale: float

var _t_grass: int
var _t_tree: int
var _t_water_sh: int
var _t_water_dp: int
var _t_swater_sh: int
var _t_mud: int
var _t_dirt: int
var _t_sand: int
var _t_grass_dead: int
var _t_grass_long: int
var _t_moss: int

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
	# Couches de bruit : 1 à 5 existantes (ne jamais renuméroter), 6 et suivantes = planète.
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
	_trees = {
		Kind.PLAIN: float(trees["plain"]), Kind.FOREST: float(trees["forest"]), Kind.SWAMP: float(trees["swamp"]),
		Kind.TUNDRA: float(trees.get("tundra", 0.004)), Kind.TAIGA: float(trees.get("taiga", 0.30)),
		Kind.DESERT: float(trees.get("desert", 0.0)), Kind.SAVANNA: float(trees.get("savanna", 0.015)),
		Kind.JUNGLE: float(trees.get("jungle", 0.35)),
	}
	var planet: Dictionary = _config["planet"]
	var continent: Dictionary = planet["continent"]
	_continent = _make_noise(continent, 6)
	_warp_x = _make_noise({"frequency": continent["warp_frequency"], "octaves": 2}, 7)
	_warp_y = _make_noise({"frequency": continent["warp_frequency"], "octaves": 2}, 8)
	_warp_amplitude = continent["warp_amplitude"]
	_origin_bonus = continent["origin_bonus"]
	_origin_radius = maxf(float(continent["origin_radius"]), 1.0)
	_sea_level = planet["sea_level"]
	_shelf_margin = planet["shelf_margin"]
	_beach_width = planet["beach"]
	var climate: Dictionary = planet["climate"]
	_temperature = _make_noise({"frequency": climate["temp_frequency"], "octaves": 2}, 9)
	_band_period = float(climate["band_height"]) * 4.0   # pôle, tempéré, tropical, tempéré, pôle...
	_temp_noise = climate["temp_noise"]
	_hot = climate["hot"]
	_cold = climate["cold"]
	_hot_humid = climate["hot_humid"]
	_hot_dry = climate["hot_dry"]
	_cold_humid = climate["cold_humid"]
	_coast_humidity = climate["coast_humidity"]
	_interior_span = maxf(float(climate["interior_span"]), 0.001)
	_desert_river_scale = climate["desert_river_scale"]
	_t_grass = TerrainDB.index_of("t_grass")
	_t_tree = TerrainDB.index_of("t_tree")
	_t_water_sh = TerrainDB.index_of("t_water_sh")
	_t_water_dp = TerrainDB.index_of("t_water_dp")
	_t_swater_sh = TerrainDB.index_of("t_swater_sh")
	_t_mud = TerrainDB.index_of("t_mud")
	_t_dirt = TerrainDB.index_of("t_dirt")
	_t_sand = TerrainDB.index_of("t_sand")
	_t_grass_dead = TerrainDB.index_of("t_grass_dead")
	_t_grass_long = TerrainDB.index_of("t_grass_long")
	_t_moss = TerrainDB.index_of("t_moss")
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


# --- Champs planétaires ---

## Continent SANS le bonus de l'origine (sert à l'humidité : côtes humides, intérieur sec).
func _continent_noise(x: float, y: float) -> float:
	var wx: float = _warp_x.get_noise_2d(x, y) * _warp_amplitude
	var wy: float = _warp_y.get_noise_2d(x + 7919.0, y - 7919.0) * _warp_amplitude
	return _continent.get_noise_2d(x + wx, y + wy)


## Relève le continent autour de (0, 0) : le départ par défaut est toujours sur terre (les scénarios choisiront leur lieu plus tard).
func _origin_lift(x: float, y: float) -> float:
	var t: float = clampf(1.0 - sqrt(x * x + y * y) / _origin_radius, 0.0, 1.0)
	return _origin_bonus * t * t * (3.0 - 2.0 * t)


## Valeur du continent (océan sous sea_level).
func continent_at(cell: Vector2i) -> float:
	return _continent_noise(cell.x, cell.y) + _origin_lift(cell.x, cell.y)


## Température : bandes de latitude (y) qui se répètent à l'infini + bruit. 0 = tempéré (origine), 1 = tropical, -1 = glacial.
func temperature_at(cell: Vector2i) -> float:
	return sin(TAU * float(cell.y) / _band_period) + _temperature.get_noise_2d(cell.x, cell.y) * _temp_noise


# --- Nature d'une case / d'une cellule ---

func kind_at(cell: Vector2i) -> int:
	var x: float = cell.x
	var y: float = cell.y
	var c_noise: float = _continent_noise(x, y)
	var c: float = c_noise + _origin_lift(x, y)
	if c < _sea_level:  # sortie rapide : l'océan ne demande aucun autre calcul
		return Kind.OCEAN_DEEP if c < _sea_level - _shelf_margin else Kind.OCEAN_SHALLOW
	var altitude: float = _altitude.get_noise_2d(x, y)
	if altitude < _lake_level:
		return Kind.LAKE_DEEP if altitude < _lake_level - _lake_deep_margin else Kind.LAKE_SHALLOW
	var temperature: float = temperature_at(cell)
	var humidity: float = _humidity.get_noise_2d(x, y) \
		+ _coast_humidity * (0.5 - clampf((c_noise - _sea_level) / _interior_span, 0.0, 1.0))
	var scale: float = _desert_river_scale if (temperature > _hot and humidity < _hot_dry) else 1.0
	var river: float = absf(_river.get_noise_2d(x, y))
	var half_width: float = _river_half_width * scale
	if river < half_width:
		if river < _river_deep_half_width * scale and _ford.get_noise_2d(x, y) < _ford_level:
			return Kind.RIVER_DEEP
		return Kind.RIVER_SHALLOW  # peu profond : un gué
	if c < _sea_level + _beach_width:
		return Kind.BEACH
	if altitude < _lake_level + _lake_shore:
		return Kind.SHORE_LAKE
	if river < half_width + _river_bank * scale:
		return Kind.BANK_RIVER
	if temperature > _hot:
		if humidity > _hot_humid:
			return Kind.JUNGLE
		return Kind.DESERT if humidity < _hot_dry else Kind.SAVANNA
	if temperature < _cold:
		return Kind.TAIGA if humidity > _cold_humid else Kind.TUNDRA
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


## Eau profonde (lac, rivière ou océan) : infranchissable à pied (la nage viendra au jalon 9b).
static func is_deep_water(kind: int) -> bool:
	return kind == Kind.LAKE_DEEP or kind == Kind.RIVER_DEEP or kind == Kind.OCEAN_DEEP


static func is_ocean(kind: int) -> bool:
	return kind == Kind.OCEAN_DEEP or kind == Kind.OCEAN_SHALLOW


## Terre où l'on peut fonder une ville, bâtir une maison ou placer un lieu : tout sauf eau, plage, marais et désert.
static func is_habitable_land(kind: int) -> bool:
	return kind == Kind.PLAIN or kind == Kind.FOREST or kind == Kind.SAVANNA or kind == Kind.TAIGA \
		or kind == Kind.TUNDRA or kind == Kind.JUNGLE


# --- Terrain d'une case ---

## Index TerrainDB de la case (fonction pure de seed, case et z).
func terrain_at(cell: Vector2i, z: int = 0) -> int:
	var kind: int = kind_at(cell)
	match kind:
		Kind.LAKE_DEEP, Kind.RIVER_DEEP, Kind.OCEAN_DEEP:
			return _t_water_dp
		Kind.LAKE_SHALLOW, Kind.RIVER_SHALLOW, Kind.OCEAN_SHALLOW:
			return _t_water_sh
		Kind.SHORE_LAKE, Kind.BEACH:
			return _t_sand
		Kind.BANK_RIVER:
			return _t_dirt
	var detail: float = _detail.get_noise_2d(cell.x, cell.y)
	var ground: int = _t_grass
	match kind:
		Kind.SWAMP:
			if detail < -0.25:
				return _t_swater_sh  # mare : pas d'arbre
			ground = _t_mud if detail < 0.1 else _t_grass
		Kind.FOREST:
			ground = _t_dirt if detail < -0.4 else _t_grass
		Kind.TUNDRA:
			ground = _t_moss if detail < -0.1 else _t_grass_dead
		Kind.TAIGA:
			ground = _t_moss if detail < 0.0 else _t_grass
		Kind.DESERT:
			ground = _t_dirt if detail < -0.2 else _t_sand
		Kind.SAVANNA:
			ground = _t_grass if detail < -0.2 else _t_grass_dead
		Kind.JUNGLE:
			ground = _t_grass if detail < -0.3 else _t_grass_long
		_:
			ground = _t_dirt if detail < -0.45 else _t_grass  # plaques de terre nue
	var tree_probability: float = _trees.get(kind, 0.0)
	if tree_probability > 0.0 and WorldRng.chance(world_seed, WorldRng.LAYER_TERRAIN, cell.x, cell.y, z, tree_probability):
		return _t_tree  # sprite d'arbre unique pour l'instant (sapin, palmier : voir docs/MISSING_SPRITE.md)
	return ground


# --- Point de départ ---

## Départ par défaut en PLEINE NATURE : première zone de terre tempérée sèche en spirale depuis l'origine (déterministe).
## Repli de SettlementMap.spawn_cell(), qui préfère la lisière d'une ville. Les scénarios de départ (porte-avions, hôpital...)
## viendront plus tard et choisiront leur propre lieu.
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


## Bon départ : la case et ses 8 voisines à SPAWN_STEP cases sont de la plaine ou de la forêt (climat tempéré).
func _is_good_spawn(center: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var kind: int = kind_at(center + Vector2i(dx, dy) * SPAWN_STEP)
			if kind != Kind.PLAIN and kind != Kind.FOREST:
				return false
	return true
