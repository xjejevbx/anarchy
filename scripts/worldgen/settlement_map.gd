class_name SettlementMap
extends RefCounted
## Villes et rues (docs/WORLD_GEN.md §5.2, jalon 3a). FONCTION PURE de (seed, coordonnées), comme WorldMap :
## les villes d'une région ne dépendent que de la seed et de la région (jamais d'une autre région déjà générée).
##
## Unité : la CELLULE macro = un chunk = 24 x 24 cases. Le monde est découpé en régions de region_size x region_size cellules ;
## chaque région tire 0 à 2 villes, qui tiennent entièrement dans la région (marge comprise). Une ville est une croix de rues
## principales plus, pour les grandes, une grille de rues secondaires ; les cellules voisines d'une rue sont des parcelles
## (LOT : futures maisons), les autres des jardins (YARD). Réglages dans data/worldgen/towns.json.
## Jalon 3b : les routes entre villes (RouteMap) sont aussi des cellules ROAD, hors de l'emprise des villes.
## Jalon 9 (correctif) : une rue ne traverse ni un lac ni l'océan (voir _is_water_body) ; une ville côtière a donc des rues coupées par la mer.
## Jalon 10 : pistes (SpecialMap) qui relient un lieu à une route : ce ne sont PAS des CellType (cell_type() les ignore) mais des
## cellules à part (track_mask / track_terrain) ; une route qui reçoit une piste y gagne un embranchement (road_mask). Les villes
## ne se fondent jamais sur une petite île. Départ « perdu sur une île » : island_spawn_cell().
## Jalon 11 : zonage urbain. Une parcelle qui reçoit un bâtiment reçoit une maison OU un bâtiment de ville (supermarché, banque,
## école...), selon sa zone (lot_zone : center / mid / outskirts, d'après sa distance au centre de la ville) et la taille de la ville.
## Réglages : zone_limits, size_urban_scale et zones de towns.json ; plans : mapgen/urban.json.
## Jalon 12 : cell_plan() renvoie aussi le plan d'un lieu « sur la route » (SpecialMap, accès on_road) ; la cellule reste de type ROAD.

const PATH: String = "res://data/worldgen/towns.json"

enum CellType { NONE, ROAD, LOT, YARD, SPECIAL }

# Bits du masque de connexions d'une cellule de route (même ordre que DIRS).
const DIR_N: int = 1
const DIR_E: int = 2
const DIR_S: int = 4
const DIR_W: int = 8
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
# Rue voisine vers laquelle se tourne la façade d'une maison : indice = rotation du plan (0 sud, 1 ouest, 2 nord, 3 est).
const HOUSE_FRONTS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]

# --- Géométrie d'une cellule de route (cases locales 0..23) : chaussée de 8, trottoirs de 2 de chaque côté ---
const ASPHALT_LO: int = 8
const ASPHALT_HI: int = 15
const SIDEWALK_LO: int = 6
const SIDEWALK_HI: int = 17
const LINE_A: int = 11             # lignes jaunes au centre des routes droites (2 cases, en pointillés)
const LINE_B: int = 12
const LINE_DASH_PERIOD: int = 6
const LINE_DASH_LENGTH: int = 4

# --- Géométrie d'une cellule de piste : bande de terre de 4 cases au centre (colonnes / lignes 10 à 13), qui couvre la sortie
# du chemin des plans de lieux (colonne 11 ou 12 selon la rotation) ---
const TRACK_LO: int = 10
const TRACK_HI: int = 13

const SPAWN_MAX_DISTANCE: int = 600  # on démarre en lisière d'une ville à moins de N cases de l'origine, sinon en pleine nature

# --- Départ « perdu sur une île » (jalon 10) : recherche en spirale de cellules macro, d'île en île ---
const ISLAND_SEARCH_STEP: int = 6        # écart entre deux cellules testées (cellules macro)
const ISLAND_SEARCH_RINGS: int = 120     # jusqu'à ~720 cellules macro de l'origine (~17 000 cases)
const ISLAND_SPOT_RADIUS: int = 10       # recherche d'une case de départ autour du centre de chaque cellule de l'île

# --- Zonage urbain (jalon 11) ---
const URBAN_CHANCE_MAX: float = 0.95     # plafond de la probabilité d'un bâtiment de ville (après l'échelle de taille)
const ZONE_CENTER: String = "center"
const ZONE_MID: String = "mid"
const ZONE_OUTSKIRTS: String = "outskirts"

static var _config: Dictionary = {}
static var _cache: Dictionary = {}  # seed -> SettlementMap

var world_seed: int = 0

var _world_map: WorldMap
var _region_size: int
var _margin: int
var _attempts: int
var _min_land_ratio: float
var _outer_ring_keep: float
var _yard_tree_keep: float
var _house_chance: float
var _count_weights: Array = []
var _sizes: Array = []
var _size_weights: Array = []
var _regions: Dictionary = {}   # Vector2i (région) -> Array de villes
var _spawn: Vector2i = Vector2i.ZERO
var _spawn_ready: bool = false
var _island_spawn: Vector2i = Vector2i.ZERO
var _island_spawn_found: bool = false
var _island_spawn_ready: bool = false
var _routes: RouteMap
var _specials: SpecialMap
var _zone_tables: Dictionary = {}   # zone -> {plans: Array (indices MapgenDB), weights: Array, radii: Array}, résolus à la demande

var _t_grass: int
var _t_tree: int
var _t_dirt: int
var _t_water_sh: int
var _t_water_dp: int
var _t_swater_sh: int
var _t_pavement: int
var _t_pavement_y: int
var _t_sidewalk: int
var _t_bridge: int


static func for_seed(seed_value: int) -> SettlementMap:
	if not _cache.has(seed_value):
		_cache[seed_value] = SettlementMap.new(seed_value)
	return _cache[seed_value]


static func _load_config() -> void:
	if not _config.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SettlementMap : %s introuvable ou invalide." % PATH)
		return
	_config = parsed


func _init(seed_value: int = 0) -> void:
	world_seed = seed_value
	_load_config()
	_world_map = WorldMap.for_seed(seed_value)
	_region_size = _config["region_size"]
	_margin = _config["margin"]
	_attempts = _config["attempts"]
	_min_land_ratio = _config["min_land_ratio"]
	_outer_ring_keep = _config["outer_ring_keep"]
	_yard_tree_keep = _config["yard_tree_keep"]
	_house_chance = float(_config.get("house_chance", 0.85))
	_count_weights = _config["count_weights"]
	_sizes = _config["sizes"]
	for size: Dictionary in _sizes:
		_size_weights.append(float(size["weight"]))
	_t_grass = TerrainDB.index_of("t_grass")
	_t_tree = TerrainDB.index_of("t_tree")
	_t_dirt = TerrainDB.index_of("t_dirt")
	_t_water_sh = TerrainDB.index_of("t_water_sh")
	_t_water_dp = TerrainDB.index_of("t_water_dp")
	_t_swater_sh = TerrainDB.index_of("t_swater_sh")
	_t_pavement = TerrainDB.index_of("t_pavement")
	_t_pavement_y = TerrainDB.index_of("t_pavement_y")
	_t_sidewalk = TerrainDB.index_of("t_sidewalk")
	_t_bridge = TerrainDB.index_of("t_bridge")
	_routes = RouteMap.new(self)
	_specials = SpecialMap.new(self)


static func region_size_cells() -> int:
	_load_config()
	return _config["region_size"]


static func route_config() -> Dictionary:
	_load_config()
	return _config.get("routes", {})


static func overlay_color(cell_type: int) -> Color:
	_load_config()
	var colors: Dictionary = _config["colors"]
	match cell_type:
		CellType.ROAD:
			return Color.html(String(colors["road"]))
		CellType.LOT:
			return Color.html(String(colors["lot"]))
		CellType.SPECIAL:
			return Color.html(String(colors.get("special", "#d65a5a")))
		_:
			return Color.html(String(colors["yard"]))


# --- Villes d'une région ---

## Villes d'une région : [{center: Vector2i (cellule), radius, spacing, size_id, name}] (mis en cache).
func towns_in_region(region: Vector2i) -> Array:
	if not _regions.has(region):
		_regions[region] = _generate_region(region)
	return _regions[region]


func _generate_region(region: Vector2i) -> Array:
	var rng: RandomNumberGenerator = WorldRng.rng_for(world_seed, WorldRng.LAYER_TOWN, region.x, region.y, 0)
	var count: int = _pick_weighted(_count_weights, rng.randf())
	var towns: Array = []
	for i in count:
		for attempt in _attempts:
			var size: Dictionary = _sizes[_pick_weighted(_size_weights, rng.randf())]
			var radius: int = size["radius"]
			var low: int = radius + _margin
			var high: int = _region_size - 1 - radius - _margin
			if high < low:
				continue
			var center := Vector2i(region.x * _region_size + rng.randi_range(low, high),
				region.y * _region_size + rng.randi_range(low, high))
			if not _site_ok(center, radius) or _overlaps(towns, center, radius):
				continue
			towns.append({"center": center, "radius": radius, "spacing": int(size["street_spacing"]),
				"size_id": String(size["id"]), "name": String(size["name"])})
			break
	return towns


static func _pick_weighted(weights: Array, roll: float) -> int:
	var total: float = 0.0
	for w in weights:
		total += float(w)
	var target: float = roll * total
	var acc: float = 0.0
	for i in weights.size():
		acc += float(weights[i])
		if target < acc:
			return i
	return weights.size() - 1


## Site acceptable : centre en plaine ou forêt (et pas sur une petite île : les îles n'ont pas de route),
## assez de terre constructible sous toute la ville.
func _site_ok(center: Vector2i, radius: int) -> bool:
	var center_kind: int = _world_map.cell_kind(center)
	if not WorldMap.is_habitable_land(center_kind): return false
	if _world_map.is_small_island(center): return false
	var good: int = 0
	var total: int = 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			total += 1
			if _is_buildable(_world_map.cell_kind(center + Vector2i(dx, dy))):
				good += 1
	return float(good) / float(total) >= _min_land_ratio


static func _overlaps(towns: Array, center: Vector2i, radius: int) -> bool:
	for t: Dictionary in towns:
		var d: Vector2i = center - (t["center"] as Vector2i)
		if maxi(absi(d.x), absi(d.y)) < radius + int(t["radius"]) + 3:
			return true
	return false


static func _is_buildable(kind: int) -> bool:
	return kind == WorldMap.Kind.PLAIN or kind == WorldMap.Kind.FOREST \
		or kind == WorldMap.Kind.SHORE_LAKE or kind == WorldMap.Kind.BANK_RIVER \
		or WorldMap.is_habitable_land(kind)


## Lac ou océan (profond ou non) : une rue ne le traverse pas (pas de pont dans une ville, contrairement aux routes
## entre villes et aux rivières). Remplace l'ancien `_is_lake`, qui oubliait l'océan (jalon 9).
static func _is_water_body(kind: int) -> bool:
	return kind == WorldMap.Kind.LAKE_DEEP or kind == WorldMap.Kind.LAKE_SHALLOW or WorldMap.is_ocean(kind)


## Ville qui contient cette cellule (dictionnaire vide si aucune).
func town_at(cell: Vector2i) -> Dictionary:
	var region := Vector2i(floori(float(cell.x) / _region_size), floori(float(cell.y) / _region_size))
	for t: Dictionary in towns_in_region(region):
		var d: Vector2i = cell - (t["center"] as Vector2i)
		if absi(d.x) <= int(t["radius"]) and absi(d.y) <= int(t["radius"]):
			return t
	return {}


# --- Nature d'une cellule ---

## La cellule fait-elle partie du réseau de rues de la ville (indépendamment de l'eau) ?
static func _is_street(town: Dictionary, cell: Vector2i) -> bool:
	var d: Vector2i = cell - (town["center"] as Vector2i)
	if absi(d.x) > int(town["radius"]) or absi(d.y) > int(town["radius"]):
		return false
	var spacing: int = town["spacing"]
	return d.x == 0 or d.y == 0 or (spacing > 0 and (posmod(d.x, spacing) == 0 or posmod(d.y, spacing) == 0))


func routes() -> RouteMap:
	return _routes


func specials() -> SpecialMap:
	return _specials


## {plan: indice MapgenDB, rot} de la cellule d'un lieu spécial, {} si elle n'en fait pas partie.
func special_plan(cell: Vector2i) -> Dictionary:
	var info: Dictionary = _specials.special_cell(cell)
	if info.is_empty():
		return {}
	var plan: int = MapgenDB.plan_by_id(String(info["plan"]))
	if plan < 0:
		return {}
	return {"plan": plan, "rot": int(info["rot"])}


## Plan à poser sur une cellule (bâtiment d'une parcelle, cellule d'un lieu spécial, ou lieu posé sur une route : péage, barrage...) : {plan, rot} ou {}.
func cell_plan(cell: Vector2i) -> Dictionary:
	var type: int = cell_type(cell)
	if type == CellType.LOT:
		return lot_plan(cell)
	if type == CellType.SPECIAL:
		return special_plan(cell)
	if type == CellType.ROAD:
		return special_plan(cell)   # lieu posé SUR une route entre villes (jalon 12) ; {} pour une rue ou une route ordinaire
	return {}


## Nature d'une cellule : NONE / ROAD / LOT / YARD / SPECIAL (lieu spécial, jalon 4). Les routes entre villes (hors emprise des villes) sont des ROAD ;
## `with_routes` = false les ignore (mini-carte à grand zoom : le calcul des routes d'une région est coûteux).
## Les cellules de PISTE (jalon 10) restent NONE ici : voir track_mask().
func cell_type(cell: Vector2i, with_routes: bool = true, with_specials: bool = true) -> int:
	var type: int = town_cell_type(cell)
	if type != CellType.NONE or not with_routes:
		return type
	if is_wild_road(cell):
		return CellType.ROAD
	if with_specials and _specials.is_special(cell):
		return CellType.SPECIAL
	return CellType.NONE


## Cellule de route située hors de toute ville (route entre villes).
func is_wild_road(cell: Vector2i) -> bool:
	return town_at(cell).is_empty() and _routes.is_route(cell)


## Nature d'une cellule SANS les routes entre villes (ne dépend que des villes : utilisé par RouteMap).
func town_cell_type(cell: Vector2i) -> int:
	var town: Dictionary = town_at(cell)
	if town.is_empty():
		return CellType.NONE
	var kind: int = _world_map.cell_kind(cell)
	if _is_street(town, cell):
		return CellType.NONE if _is_water_body(kind) else CellType.ROAD  # pas de rue sur un lac ni sur l'océan
	var d: Vector2i = cell - (town["center"] as Vector2i)
	if maxi(absi(d.x), absi(d.y)) == int(town["radius"]) \
			and not WorldRng.chance(world_seed, WorldRng.LAYER_TOWN, cell.x, cell.y, 1, _outer_ring_keep):
		return CellType.NONE  # bord irrégulier
	if not _is_buildable(kind):
		return CellType.NONE
	for dir in DIRS:
		var neighbor: Vector2i = cell + dir
		if _is_street(town, neighbor) and not _is_water_body(_world_map.cell_kind(neighbor)):
			return CellType.LOT
	return CellType.YARD


## Bâtiment d'une parcelle : {} si aucun, sinon {plan: indice MapgenDB, rot: 0..3}. FONCTION PURE de (seed, cellule).
## C'est une maison (houses.json) ou, selon la zone et la taille de la ville, un bâtiment de ville (urban.json : voir lot_zone).
## La façade (le sud du plan) est tournée vers une rue voisine (voir HOUSE_FRONTS) ; s'il y en a plusieurs, le choix est tiré.
## Pas de bâtiment sur une berge, un marais ni une cellule d'eau (le plan écraserait l'eau).
func lot_plan(cell: Vector2i) -> Dictionary:
	if MapgenDB.plan_count() == 0 or town_cell_type(cell) != CellType.LOT:
		return {}
	var kind: int = _world_map.cell_kind(cell)
	if not WorldMap.is_habitable_land(kind): return {}
	if not WorldRng.chance(world_seed, WorldRng.LAYER_MAPGEN, cell.x, cell.y, 0, _house_chance):
		return {}
	var town: Dictionary = town_at(cell)
	var fronts: Array[int] = []
	for rot in HOUSE_FRONTS.size():
		var neighbor: Vector2i = cell + HOUSE_FRONTS[rot]
		if _is_street(town, neighbor) and not _is_water_body(_world_map.cell_kind(neighbor)):
			fronts.append(rot)
	if fronts.is_empty():
		return {}
	var plan: int = _urban_plan(cell, town)   # bâtiment de ville, ou -1 : maison
	if plan < 0:
		plan = MapgenDB.pick(WorldRng.unit(WorldRng.mix(world_seed, WorldRng.LAYER_MAPGEN, cell.x, cell.y, 1)))
	if plan < 0:
		return {}
	var rot_roll: int = WorldRng.mix(world_seed, WorldRng.LAYER_MAPGEN, cell.x, cell.y, 2) & 0x7FFFFFFF
	return {"plan": plan, "rot": fronts[rot_roll % fronts.size()]}


## Id du plan posé sur une parcelle (« house_small », « urban_bank »...), "" si la parcelle n'a pas de bâtiment.
func lot_plan_id(cell: Vector2i) -> String:
	var info: Dictionary = lot_plan(cell)
	return MapgenDB.plan_id(int(info["plan"])) if not info.is_empty() else ""


# --- Zonage urbain (jalon 11) ---

## Zone d'une parcelle (ZONE_CENTER / ZONE_MID / ZONE_OUTSKIRTS), "" hors de toute ville. Selon la distance de Tchebychev au centre de la
## ville, comparée à son rayon. Entiers seulement : zone_limits de towns.json est en pourcents du rayon (center : jusqu'à N %, mid : jusqu'à M %).
func lot_zone(cell: Vector2i) -> String:
	var town: Dictionary = town_at(cell)
	if town.is_empty():
		return ""
	var d: Vector2i = cell - (town["center"] as Vector2i)
	var distance: int = maxi(absi(d.x), absi(d.y))
	var radius: int = maxi(int(town["radius"]), 1)
	var limits: Dictionary = _config.get("zone_limits", {})
	if distance * 100 <= int(limits.get("center", 50)) * radius:
		return ZONE_CENTER
	if distance * 100 <= int(limits.get("mid", 75)) * radius:
		return ZONE_MID
	return ZONE_OUTSKIRTS


## Indice MapgenDB du bâtiment de ville de la parcelle, -1 si elle reçoit une maison. Deux tirages indépendants, fonctions pures de
## (seed, cellule) : couche MAPGEN, indice 3 (urbain ou maison), indice 4 (quel bâtiment). Les indices 0, 1 et 2 restent ceux des maisons.
func _urban_plan(cell: Vector2i, town: Dictionary) -> int:
	var zones: Dictionary = _config.get("zones", {})
	var zone: String = lot_zone(cell)
	if not zones.has(zone):
		return -1
	var size_scales: Dictionary = _config.get("size_urban_scale", {})
	var size_scale: float = float(size_scales.get(String(town["size_id"]), 1.0))
	var chance: float = minf(float((zones[zone] as Dictionary).get("urban_chance", 0.0)) * size_scale, URBAN_CHANCE_MAX)
	if chance <= 0.0 or not WorldRng.chance(world_seed, WorldRng.LAYER_MAPGEN, cell.x, cell.y, 3, chance):
		return -1
	var table: Dictionary = _zone_table(zone)
	var plans: Array = table["plans"]
	var weights: Array = table["weights"]
	var radii: Array = table["radii"]
	var radius: int = town["radius"]
	var total: float = 0.0
	for i in plans.size():
		if int(radii[i]) <= radius:
			total += float(weights[i])
	if total <= 0.0:
		return -1
	var target: float = WorldRng.unit(WorldRng.mix(world_seed, WorldRng.LAYER_MAPGEN, cell.x, cell.y, 4)) * total
	var acc: float = 0.0
	var last: int = -1
	for i in plans.size():
		if int(radii[i]) > radius:
			continue
		acc += float(weights[i])
		last = int(plans[i])
		if target < acc:
			return last
	return last


## Table des bâtiments d'une zone, plans résolus en indices MapgenDB (un plan inconnu est ignoré avec un avertissement).
func _zone_table(zone: String) -> Dictionary:
	if _zone_tables.has(zone):
		return _zone_tables[zone]
	var plans: Array = []
	var weights: Array = []
	var radii: Array = []
	var zone_def: Dictionary = (_config.get("zones", {}) as Dictionary).get(zone, {})
	var buildings: Array = zone_def.get("buildings", [])
	for entry: Dictionary in buildings:
		var plan_name: String = String(entry.get("plan", ""))
		var plan: int = MapgenDB.plan_by_id(plan_name)
		if plan < 0:
			push_warning("SettlementMap : zone « %s » : plan « %s » introuvable (ignoré)." % [zone, plan_name])
			continue
		plans.append(plan)
		weights.append(maxf(float(entry.get("weight", 1.0)), 0.0))
		radii.append(int(entry.get("min_radius", 0)))
	var table: Dictionary = {"plans": plans, "weights": weights, "radii": radii}
	_zone_tables[zone] = table
	return table


## Masque des connexions d'une cellule de route (DIR_N | DIR_E | DIR_S | DIR_W) : rues ou routes voisines, et pistes qui s'y raccordent
## (jalon 10 : la chaussée gagne alors un embranchement jusqu'au bord de la cellule). Sur une cellule de piste, donne ses voisines
## de route (le masque de la piste elle-même est track_mask()).
func road_mask(cell: Vector2i) -> int:
	var mask: int = 0
	for i in DIRS.size():
		var neighbor: Vector2i = cell + DIRS[i]
		if cell_type(neighbor, true, false) == CellType.ROAD or _specials.track_links(neighbor, 1 << ((i + 2) % 4)):
			mask |= 1 << i
	return mask


# --- Pistes (jalon 10) ---

## Masque de connexions de la piste qui traverse cette cellule (bits DIR_*), -1 si ce n'est pas une cellule de piste.
func track_mask(cell: Vector2i) -> int:
	return _specials.track_mask(cell)


## Terrain d'une case (lx, ly locaux) d'une cellule de piste : une bande de terre de 4 cases vers chaque connexion ; autour, la nature.
func track_terrain(mask: int, lx: int, ly: int, base: int) -> int:
	var in_cols: bool = lx >= TRACK_LO and lx <= TRACK_HI
	var in_rows: bool = ly >= TRACK_LO and ly <= TRACK_HI
	var dirt: bool = in_cols and in_rows
	if mask & DIR_N != 0 and in_cols and ly <= TRACK_HI:
		dirt = true
	if mask & DIR_S != 0 and in_cols and ly >= TRACK_LO:
		dirt = true
	if mask & DIR_E != 0 and in_rows and lx >= TRACK_LO:
		dirt = true
	if mask & DIR_W != 0 and in_rows and lx <= TRACK_HI:
		dirt = true
	return _t_dirt if dirt else base


# --- Terrain des cases d'une cellule de route ou de parcelle ---

func _is_water(terrain: int) -> bool:
	return terrain == _t_water_sh or terrain == _t_water_dp or terrain == _t_swater_sh


func _clear_tree(terrain: int) -> int:
	return _t_grass if terrain == _t_tree else terrain


## Terrain d'une case (lx, ly locaux) d'une cellule de route, selon le masque de connexions. `base` = terrain naturel :
## l'eau sous la chaussée ou le trottoir devient un PONT ; hors de la route, les arbres sont enlevés.
func road_terrain(mask: int, lx: int, ly: int, base: int, keep_nature: bool = false) -> int:
	var in_asphalt_cols: bool = lx >= ASPHALT_LO and lx <= ASPHALT_HI
	var in_asphalt_rows: bool = ly >= ASPHALT_LO and ly <= ASPHALT_HI
	var in_sidewalk_cols: bool = lx >= SIDEWALK_LO and lx <= SIDEWALK_HI
	var in_sidewalk_rows: bool = ly >= SIDEWALK_LO and ly <= SIDEWALK_HI
	var asphalt: bool = false
	var sidewalk: bool = false
	if mask == 0:  # rue isolée : petite place carrée
		asphalt = in_asphalt_cols and in_asphalt_rows
		sidewalk = in_sidewalk_cols and in_sidewalk_rows and not asphalt
	else:
		asphalt = in_asphalt_cols and in_asphalt_rows  # carrefour central
		if mask & DIR_N != 0:
			if in_asphalt_cols and ly <= ASPHALT_HI:
				asphalt = true
			elif in_sidewalk_cols and ly <= SIDEWALK_HI:
				sidewalk = true
		if mask & DIR_S != 0:
			if in_asphalt_cols and ly >= ASPHALT_LO:
				asphalt = true
			elif in_sidewalk_cols and ly >= SIDEWALK_LO:
				sidewalk = true
		if mask & DIR_E != 0:
			if in_asphalt_rows and lx >= ASPHALT_LO:
				asphalt = true
			elif in_sidewalk_rows and lx >= SIDEWALK_LO:
				sidewalk = true
		if mask & DIR_W != 0:
			if in_asphalt_rows and lx <= ASPHALT_HI:
				asphalt = true
			elif in_sidewalk_rows and lx <= SIDEWALK_HI:
				sidewalk = true
	var water: bool = _is_water(base)
	if asphalt:
		if water:
			return _t_bridge
		if mask == (DIR_N | DIR_S) and (lx == LINE_A or lx == LINE_B) and ly % LINE_DASH_PERIOD < LINE_DASH_LENGTH:
			return _t_pavement_y
		if mask == (DIR_E | DIR_W) and (ly == LINE_A or ly == LINE_B) and lx % LINE_DASH_PERIOD < LINE_DASH_LENGTH:
			return _t_pavement_y
		return _t_pavement
	if sidewalk:
		return _t_bridge if water else _t_sidewalk
	return base if keep_nature else _clear_tree(base)  # route entre villes : la nature reste autour de la chaussée


## Terrain d'une case de parcelle ou de jardin : les arbres sont enlevés (sauf quelques-uns).
func lot_terrain(base: int, cell: Vector2i) -> int:
	if base == _t_tree and not WorldRng.chance(world_seed, WorldRng.LAYER_TOWN, cell.x, cell.y, 2, _yard_tree_keep):
		return _t_grass
	return base


# --- Point de départ ---

## Départ du joueur : au bout d'une rue de la ville la plus proche de l'origine (à moins de SPAWN_MAX_DISTANCE cases),
## sinon en pleine nature (WorldMap.spawn_cell()). Déterministe.
func spawn_cell() -> Vector2i:
	if not _spawn_ready:
		_spawn = _find_spawn()
		_spawn_ready = true
	return _spawn


## Ville la plus proche de l'origine (dictionnaire vide si aucune à portée).
func nearest_town() -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	var reach: int = ceili(float(SPAWN_MAX_DISTANCE) / float(_region_size * Chunk.SIZE)) + 1
	for ry in range(-reach, reach + 1):
		for rx in range(-reach, reach + 1):
			for t: Dictionary in towns_in_region(Vector2i(rx, ry)):
				var distance: float = Vector2((t["center"] as Vector2i) * Chunk.SIZE).length()
				if distance <= SPAWN_MAX_DISTANCE and distance < best_distance:
					best = t
					best_distance = distance
	return best


func _find_spawn() -> Vector2i:
	var town: Dictionary = nearest_town()
	if town.is_empty():
		return _world_map.spawn_cell()
	var center: Vector2i = town["center"]
	var radius: int = town["radius"]
	var half: Vector2i = Vector2i(Chunk.SIZE / 2 - 1, Chunk.SIZE / 2 - 1)
	for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:  # extrémités des rues principales
		var cell: Vector2i = center + dir * radius
		if cell_type(cell) == CellType.ROAD and _is_buildable(_world_map.cell_kind(cell)):
			return cell * Chunk.SIZE + half
	return _world_map.spawn_cell()


# --- Scénario « perdu sur une île » (jalon 10) ---

## Une île de départ a-t-elle été trouvée près de l'origine ? (sinon island_spawn_cell() renvoie le départ par défaut)
func has_island_spawn() -> bool:
	_ensure_island_spawn()
	return _island_spawn_found


## Départ sur une petite île : la première rencontrée en spirale depuis l'origine, assez grande (island_spawn_min_cells), dont une
## cellule macro est libre (ni rue, ni lieu, ni piste) et porte une case dégagée de terre habitable. Déterministe.
func island_spawn_cell() -> Vector2i:
	_ensure_island_spawn()
	return _island_spawn


func _ensure_island_spawn() -> void:
	if _island_spawn_ready:
		return
	_island_spawn_ready = true
	_island_spawn = spawn_cell()
	for ring in range(1, ISLAND_SEARCH_RINGS + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var macro := Vector2i(dx, dy) * ISLAND_SEARCH_STEP
				var size: int = _world_map.island_size(macro)
				if size < _world_map.island_spawn_min_cells() or size >= _world_map.island_max_cells():
					continue
				var spot: Vector2i = _island_spot(macro)
				if spot != Vector2i(1 << 30, 1 << 30):
					_island_spawn = spot
					_island_spawn_found = true
					return


## Case de départ d'une île (à partir d'une de ses cellules), ou (2^30, 2^30) s'il n'y en a pas.
func _island_spot(any_cell: Vector2i) -> Vector2i:
	for macro: Vector2i in _world_map.island_cells(any_cell):
		if cell_type(macro) != CellType.NONE or track_mask(macro) >= 0:
			continue
		var center: Vector2i = macro * Chunk.SIZE + WorldMap.CELL_CENTER
		for r in range(0, ISLAND_SPOT_RADIUS + 1):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var case: Vector2i = center + Vector2i(dx, dy)
					if _world_map.is_good_spawn_case(case):
						return case
	return Vector2i(1 << 30, 1 << 30)
