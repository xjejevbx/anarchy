class_name RouteMap
extends RefCounted
## Routes entre villes (docs/WORLD_GEN.md §5.3, jalon 3b). FONCTION PURE de (seed, centres de villes) : une route ne dépend
## que des deux villes qu'elle relie, jamais de l'ordre dans lequel le monde est exploré.
##
## Graphe : chaque ville se relie à ses `near_count` plus proches voisines (3 pour une grande ville), cherchées dans les régions
## voisines (leurs centres se calculent sans générer de chunk). Une arête (a, b) existe si b est parmi les plus proches de a
## OU a parmi les plus proches de b, à moins de `max_link_distance` cellules. Départage : (distance², x, y) du centre.
## Chemin : A* en 4 directions sur les cellules macro, coûts ENTIERS par nature de case (forêt chère, marais très cher,
## lacs interdits ; les rivières se franchissent, le pont est posé par SettlementMap.road_terrain). Dans l'emprise d'une ville,
## seules ses rues sont franchissables : la route entre par le bout d'une rue et rejoint le centre par le réseau existant.
## Calcul à la demande, mis en cache par arête (clé = les deux centres) et par région (cellules de route situées dans la région).
## Réglages : section "routes" de data/worldgen/towns.json.

# MÊME ORDRE que l'énumération WorldMap.Kind ET que "kinds" de biomes.json (ajouter à la FIN, partout). Les coûts sont indexés par
# WorldMap.Kind et SpecialMap retrouve les biomes par leur position ici : un ordre différent décale tout (le test le vérifie).
const KIND_IDS: Array[String] = ["plain", "forest", "swamp", "lake_deep", "lake_shallow", "river_deep", "river_shallow",
	"shore_lake", "bank_river", "ocean_deep", "ocean_shallow", "beach", "tundra", "taiga", "desert", "savanna", "jungle"]
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const INFINITE: int = 1 << 30
const SEQ_BITS: int = 24   # clé de la file : (f << 40) | (h << 24) | ordre d'insertion (départage déterministe, tracé plutôt droit)
const H_BITS: int = 16

var astar_runs: int = 0    # nombre d'A* exécutés (mesures)
var astar_us: int = 0      # temps cumulé des A* (µs)

var _settlement_ref: WeakRef   # faible : SettlementMap possède cette instance (évite un cycle de références)
var _world_map: WorldMap
var _region_size: int
var _near_count: int
var _near_count_by_size: Dictionary = {}
var _neighbor_window: int
var _max_link_distance: int
var _margin: int
var _max_expansions: int
var _heuristic_cost: int
var _road_cost: int
var _kind_cost: Array[int] = []
var _window: int                 # régions autour d'une région dont les villes peuvent la traverser
var _near_cache: Dictionary = {}   # centre Vector2i -> Array de villes voisines
var _paths: Dictionary = {}        # Vector4i (centre min, centre max) -> Array[Vector2i]
var _index: Dictionary = {}        # Vector2i (région) -> Dictionary {cellule: true}
var _heap_keys: PackedInt64Array = PackedInt64Array()
var _heap_nodes: PackedInt32Array = PackedInt32Array()


func _init(settlement: SettlementMap) -> void:
	_settlement_ref = weakref(settlement)
	_world_map = WorldMap.for_seed(settlement.world_seed)
	var cfg: Dictionary = SettlementMap.route_config()
	_region_size = SettlementMap.region_size_cells()
	_near_count = int(cfg.get("near_count", 2))
	_near_count_by_size = cfg.get("near_count_by_size", {})
	_neighbor_window = int(cfg.get("neighbor_window", 2))
	_max_link_distance = int(cfg.get("max_link_distance", 80))
	_margin = int(cfg.get("margin", 16))
	_max_expansions = int(cfg.get("max_expansions", 20000))
	_heuristic_cost = int(cfg.get("heuristic_cost", 20))
	_road_cost = int(cfg.get("road_cost", 4))
	var costs: Dictionary = cfg.get("costs", {})
	_kind_cost.resize(KIND_IDS.size())
	for i in KIND_IDS.size():
		var c: int = int(costs.get(KIND_IDS[i], -1))
		_kind_cost[i] = c if c > 0 else -1   # <= 0 : interdit
	# Toute arête qui traverse une région a ses deux villes à moins de (distance max + marge) de cette région.
	_window = ceili(float(_max_link_distance + _margin) / float(_region_size))


func _settlement() -> SettlementMap:
	return _settlement_ref.get_ref() as SettlementMap


func _region_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / _region_size), floori(float(cell.y) / _region_size))


# --- Requêtes ---

## La cellule macro est-elle une cellule de route (hors emprise des villes) ?
func is_route(cell: Vector2i) -> bool:
	return region_cells(_region_of(cell)).has(cell)


## Cellules de route situées dans la région (calculées une fois, puis en cache).
func region_cells(region: Vector2i) -> Dictionary:
	if _index.has(region):
		return _index[region]
	var settlement: SettlementMap = _settlement()
	var cells: Dictionary = {}
	var low: Vector2i = region * _region_size
	var high: Vector2i = low + Vector2i(_region_size - 1, _region_size - 1)
	var seen_edges: Dictionary = {}
	for ry in range(region.y - _window, region.y + _window + 1):
		for rx in range(region.x - _window, region.x + _window + 1):
			for a: Dictionary in settlement.towns_in_region(Vector2i(rx, ry)):
				for b: Dictionary in neighbors_of(a):
					var key: Vector4i = _edge_key(a["center"], b["center"])
					if seen_edges.has(key):
						continue
					seen_edges[key] = true
					if not _edge_touches(key, low, high):
						continue
					for cell: Vector2i in _edge_path(key):
						if cell.x >= low.x and cell.x <= high.x and cell.y >= low.y and cell.y <= high.y \
								and settlement.town_at(cell).is_empty():
							cells[cell] = true
	_index[region] = cells
	return cells


## Chemin entre deux centres de villes (vide si aucune liaison possible). Même résultat dans les deux sens.
func path_between(center_a: Vector2i, center_b: Vector2i) -> Array[Vector2i]:
	return _edge_path(_edge_key(center_a, center_b))


## Centres des villes reliées à la ville de centre `center` par une route qui existe réellement.
func partners_of(center: Vector2i) -> Array[Vector2i]:
	var settlement: SettlementMap = _settlement()
	var out: Array[Vector2i] = []
	var town: Dictionary = settlement.town_at(center)
	if town.is_empty():
		return out
	var region: Vector2i = _region_of(center)
	for ry in range(region.y - _window, region.y + _window + 1):
		for rx in range(region.x - _window, region.x + _window + 1):
			for other: Dictionary in settlement.towns_in_region(Vector2i(rx, ry)):
				var other_center: Vector2i = other["center"]
				if other_center == center:
					continue
				if (_has_town(neighbors_of(town), other_center) or _has_town(neighbors_of(other), center)) \
						and not path_between(center, other_center).is_empty():
					out.append(other_center)
	return out


## Plus proches voisines d'une ville (triées par distance², x, y du centre ; limitées à max_link_distance).
func neighbors_of(town: Dictionary) -> Array:
	var center: Vector2i = town["center"]
	if _near_cache.has(center):
		return _near_cache[center]
	var settlement: SettlementMap = _settlement()
	var region: Vector2i = _region_of(center)
	var max_d2: int = _max_link_distance * _max_link_distance
	var candidates: Array = []   # [distance², x, y, ville]
	for ry in range(region.y - _neighbor_window, region.y + _neighbor_window + 1):
		for rx in range(region.x - _neighbor_window, region.x + _neighbor_window + 1):
			for other: Dictionary in settlement.towns_in_region(Vector2i(rx, ry)):
				var other_center: Vector2i = other["center"]
				if other_center == center:
					continue
				var d: Vector2i = other_center - center
				var d2: int = d.x * d.x + d.y * d.y
				if d2 <= max_d2:
					candidates.append([d2, other_center.x, other_center.y, other])
	candidates.sort_custom(_candidate_less)
	var count: int = int(_near_count_by_size.get(String(town["size_id"]), _near_count))
	var result: Array = []
	for i in mini(count, candidates.size()):
		result.append(candidates[i][3])
	_near_cache[center] = result
	return result


static func _candidate_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[2] < b[2]


static func _has_town(list: Array, center: Vector2i) -> bool:
	for t: Dictionary in list:
		if t["center"] == center:
			return true
	return false


## Clé d'arête : (centre le plus petit en x puis y, l'autre). Fixe aussi le sens du calcul : le chemin est identique dans les deux sens.
static func _edge_key(c1: Vector2i, c2: Vector2i) -> Vector4i:
	if c1.x < c2.x or (c1.x == c2.x and c1.y < c2.y):
		return Vector4i(c1.x, c1.y, c2.x, c2.y)
	return Vector4i(c2.x, c2.y, c1.x, c1.y)


## La boîte de recherche de l'arête (avec marge) recoupe-t-elle la région ?
func _edge_touches(key: Vector4i, low: Vector2i, high: Vector2i) -> bool:
	return maxi(key.x, key.z) + _margin >= low.x and mini(key.x, key.z) - _margin <= high.x \
		and maxi(key.y, key.w) + _margin >= low.y and mini(key.y, key.w) - _margin <= high.y


func _edge_path(key: Vector4i) -> Array[Vector2i]:
	if not _paths.has(key):
		_paths[key] = _find_path(Vector2i(key.x, key.y), Vector2i(key.z, key.w))
	return _paths[key]


## Empreinte des cellules de route d'une région (test de déterminisme).
func region_fingerprint(region: Vector2i) -> int:
	var cells: Dictionary = region_cells(region)
	var origin: Vector2i = region * _region_size
	var h: int = -3750763034362895579
	for y in _region_size:
		for x in _region_size:
			h = (h ^ (1 if cells.has(origin + Vector2i(x, y)) else 0)) * 1099511628211
	return h


## Mesure (µs) : villes des régions voisines (chargées si besoin), puis cellules de route de la région. Sans vider les caches.
func benchmark_region(region: Vector2i) -> Dictionary:
	var settlement: SettlementMap = _settlement()
	var runs_before: int = astar_runs
	var t0: int = Time.get_ticks_usec()
	var reach: int = _window + _neighbor_window
	for ry in range(region.y - reach, region.y + reach + 1):
		for rx in range(region.x - reach, region.x + reach + 1):
			settlement.towns_in_region(Vector2i(rx, ry))
	var t1: int = Time.get_ticks_usec()
	var cells: Dictionary = region_cells(region)
	var t2: int = Time.get_ticks_usec()
	return {"towns_us": t1 - t0, "routes_us": t2 - t1, "astar_runs": astar_runs - runs_before, "cells": cells.size()}


# --- A* ---

## Coût d'entrée dans une cellule : -1 = interdite.
func _step_cost(settlement: SettlementMap, cell: Vector2i) -> int:
	if not settlement.town_at(cell).is_empty():
		return _road_cost if settlement.town_cell_type(cell) == SettlementMap.CellType.ROAD else -1
	return _kind_cost[_world_map.cell_kind(cell)]


func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var started: int = Time.get_ticks_usec()
	astar_runs += 1
	var path: Array[Vector2i] = _search(from, to)
	astar_us += Time.get_ticks_usec() - started
	return path


func _search(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var settlement: SettlementMap = _settlement()
	var x0: int = mini(from.x, to.x) - _margin
	var y0: int = mini(from.y, to.y) - _margin
	var w: int = absi(from.x - to.x) + 1 + 2 * _margin
	var h: int = absi(from.y - to.y) + 1 + 2 * _margin
	var total: int = w * h
	var cost := PackedInt32Array()
	cost.resize(total)                 # 0 = pas encore évalué, -1 = interdit, sinon coût d'entrée
	var g := PackedInt32Array()
	g.resize(total)
	g.fill(INFINITE)
	var came := PackedInt32Array()
	came.resize(total)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(total)
	var goal_x: int = to.x - x0
	var goal_y: int = to.y - y0
	var start: int = (from.y - y0) * w + (from.x - x0)
	var goal: int = goal_y * w + goal_x
	_heap_keys.clear()
	_heap_nodes.clear()
	var seq: int = 0
	g[start] = 0
	var h0: int = (absi(from.x - to.x) + absi(from.y - to.y)) * _heuristic_cost
	_heap_push(_make_key(h0, h0, 0), start)
	var expansions: int = 0
	while not _heap_keys.is_empty() and expansions < _max_expansions:
		var node: int = _heap_pop()
		if closed[node] != 0:
			continue
		if node == goal:
			return _rebuild_path(came, start, goal, x0, y0, w)
		closed[node] = 1
		expansions += 1
		var lx: int = node % w
		@warning_ignore("integer_division")
		var ly: int = node / w
		var base_g: int = g[node]
		for dir in DIRS:
			var nx: int = lx + dir.x
			var ny: int = ly + dir.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni: int = ny * w + nx
			if closed[ni] != 0:
				continue
			var step: int = cost[ni]
			if step == 0:
				step = _step_cost(settlement, Vector2i(x0 + nx, y0 + ny))
				cost[ni] = step
			if step < 0:
				continue
			var new_g: int = base_g + step
			if new_g < g[ni]:
				g[ni] = new_g
				came[ni] = node
				seq += 1
				var hv: int = (absi(nx - goal_x) + absi(ny - goal_y)) * _heuristic_cost
				_heap_push(_make_key(new_g + hv, hv, seq), ni)
	var none: Array[Vector2i] = []
	return none


static func _make_key(f: int, h: int, seq: int) -> int:
	return (f << (SEQ_BITS + H_BITS)) | (mini(h, 65535) << SEQ_BITS) | seq


static func _rebuild_path(came: PackedInt32Array, start: int, goal: int, x0: int, y0: int, w: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var node: int = goal
	while node != -1:
		path.append(Vector2i(x0 + node % w, y0 + floori(float(node) / w)))
		if node == start:
			break
		node = came[node]
	path.reverse()
	return path


# --- Tas binaire (clé entière, nœud) ---

func _heap_push(key: int, node: int) -> void:
	var i: int = _heap_keys.size()
	_heap_keys.append(key)
	_heap_nodes.append(node)
	while i > 0:
		var parent: int = (i - 1) >> 1
		if _heap_keys[parent] <= key:
			break
		_heap_keys[i] = _heap_keys[parent]
		_heap_nodes[i] = _heap_nodes[parent]
		i = parent
	_heap_keys[i] = key
	_heap_nodes[i] = node


func _heap_pop() -> int:
	var top: int = _heap_nodes[0]
	var last: int = _heap_keys.size() - 1
	var key: int = _heap_keys[last]
	var node: int = _heap_nodes[last]
	_heap_keys.resize(last)
	_heap_nodes.resize(last)
	if last > 0:
		var i: int = 0
		while true:
			var child: int = 2 * i + 1
			if child >= last:
				break
			if child + 1 < last and _heap_keys[child + 1] < _heap_keys[child]:
				child += 1
			if _heap_keys[child] >= key:
				break
			_heap_keys[i] = _heap_keys[child]
			_heap_nodes[i] = _heap_nodes[child]
			i = child
		_heap_keys[i] = key
		_heap_nodes[i] = node
	return top
