class_name World
extends Node2D
## Le monde : chunks (via ChunkManager), objets au sol, monstres, file d'actions et champ de vision.
## La carte est INFINIE et générée par chunks de façon déterministe à partir de `world_seed`
## (voir docs/WORLD_GEN.md). Le terrain n'est jamais stocké ici : on interroge le ChunkManager.
## Jalon 6a : les monstres initiaux d'un chunk sont créés par ChunkManager (SpawnGenerator) à son premier chargement ;
## un chunk déchargé met ses monstres en réserve, un chunk rechargé les restaure (voir docs/MONSTER_SPAWN.md).
## Jalon 6b : monstres endormis (bruit : make_noise), affixes. Axe vertical : le monde ne simule qu'UN étage à la fois (`get_level()`,
## ChunkManager.level) ; toutes les requêtes par case (Vector2i) portent sur cet étage, les objets au sol sont rangés par étage, les monstres
## des autres étages sont en réserve. change_level() prépare les escaliers (jalon 8).
## Jalon 6c : explosions (explode : à la mort d'un monstre EXPLODE, grenade THROW) et division des blobs (spawn_split).
## Jalon 6d : domaines de déplacement des monstres (monster_can_enter : marche, nage, eau, vol), cadavres (RAISE), renforts (SUMMON),
## bruit entendu par les monstres aveugles (BLIND_HEARING), monstres furtifs (STEALTH).
##
## Rendu en couches (de bas en haut) :
##   1. `_terrain_layer` : les chunks (sol : herbe, murs)
##   2. `_items_layer`   : objets au sol
##   3. `entities`       : arbres, joueur, monstres, triés par Y (plus bas = plus devant)
##   3b. `fx`            : particules et ondes (poussière, éclaboussures), voir Fx
##   4. `fog`            : brouillard de guerre par-dessus
##   5. `_pick_overlay`  : touches de choix de la case où ramasser
##   6. `_target_overlay`: case ciblée par le déplacement automatique (carré + points du trajet)
## Les nœuds sont positionnés sur le coin haut-gauche de leur case ; UlticaTiles applique
## les décalages de chaque sprite (personnages 32x48, arbres 96x96...).

const TILE_SIZE: int = 128
const ALERT_REARM_POINTS: float = 5.0    # secondes hors de vue (dans le brouillard) avant qu'un monstre puisse être signalé à nouveau ; 0 = dès qu'il sort de vue
const VIEW_RADIUS: int = 20              # portée de vue en cases (plein jour pour l'instant)
const MAX_MONSTERS: int = 300            # plafond global de monstres chargés (au-delà, un chunk neuf n'est pas peuplé)

# --- Explosions (jalon 6c) : rayon (cases), dégâts aux cibles, effet d'état sur le joueur. `gas` ne blesse pas : il empoisonne seulement ---
const EXPLOSIONS: Dictionary = {
	"acid": {"radius": 2, "damage": 6.0, "effect": {"id": "acid", "chance": 1.0, "duration": 5.0, "dps": 0.8, "stamina": 0.0}},
	"gas": {"radius": 2, "damage": 0.0, "effect": {"id": "poison", "chance": 1.0, "duration": 10.0, "dps": 0.4, "stamina": 0.0}},
	"fire": {"radius": 2, "damage": 8.0, "effect": {"id": "burn", "chance": 1.0, "duration": 4.0, "dps": 1.0, "stamina": 0.0}},
	"frag": {"radius": 3, "damage": 14.0, "effect": {}},
	"electric": {"radius": 2, "damage": 6.0, "effect": {"id": "", "chance": 1.0, "duration": 0.0, "dps": 0.0, "stamina": 25.0}},
}
const SPLIT_MAX_MONSTERS: int = 280      # au-delà, un blob ne se divise plus (marge sous MAX_MONSTERS)

# --- Domaines de déplacement (jalon 6d) : ce qu'un monstre peut traverser (PathFinder, Monster) ---
const DOMAIN_WALK: int = 0       # marche : cases praticables à pied (eau peu profonde comprise)
const DOMAIN_SWIM: int = 1       # SWIM : marche + eau profonde
const DOMAIN_AQUATIC: int = 2    # AQUATIC : l'eau seulement (peu profonde ou profonde)
const DOMAIN_FLY: int = 3        # FLY : tout sauf murs et fenêtres
const STEALTH_REVEAL_RANGE: int = 3   # STEALTH : un monstre furtif n'est visible (ni signalé) qu'à moins de N cases
const NOISE_WALK: int = 3             # le joueur qui marche (ni accroupi ni sprint) est entendu à N cases par les monstres aveugles
const NOISE_MEMORY: float = 5.0       # secondes pendant lesquelles un bruit reste « entendu »
const MAX_CORPSES: int = 200          # cadavres retenus (RAISE) ; les plus anciens disparaissent

# --- Bruit (jalon 6b) : rayon (cases) dans lequel les dormeurs se réveillent ---
const NOISE_SPRINT: int = 8              # le joueur court
const NOISE_COMBAT: int = 10             # le joueur frappe

# --- Case ciblée (déplacement automatique) ---
const TARGET_COLOR_IDLE: Color = Color(1, 1, 1, 0.95)          # case choisie, déplacement pas lancé
const TARGET_COLOR_TRAVEL: Color = Color(0.3, 1.0, 0.35, 0.95)  # déplacement automatique en cours
const TARGET_BORDER: float = 8.0
const TARGET_DOT_RADIUS: float = 12.0

var world_seed: int = 4444                  # à fixer AVANT add_child()
var seed_text: String = ""                  # seed telle que saisie (affichage / copie / sauvegarde)
var scenario: String = "default"            # scénario de départ (sauvegardé ; utilisé à la création)
var use_arena: bool = false              # true : ancienne carte fermée 60x40 (debug), à fixer AVANT add_child()
var population: float = 1.0              # multiplicateur des densités de monstres (0 = aucun), à fixer AVANT le premier chargement
var safe_centers: Array[Vector2i] = []   # cases autour desquelles aucun monstre n'apparaît (départ du joueur), voir SpawnGenerator
var chunks: ChunkManager
var player: Player
var monsters: Array[Monster] = []
var entities: Node2D
var fx: Node2D                      # calque des effets visuels (particules), au-dessus des entités, sous le brouillard
var fog: FogLayer
var ground_items: Dictionary:       # Vector2i -> Array (d'Item posés au sol) : ceux de l'ÉTAGE ACTIF
	get:
		return _ground_dict()
var pick_labels: Dictionary = {}    # Vector2i -> touche affichée (choix de la case où ramasser)
var visible_cells: Dictionary = {}  # cases actuellement visibles

var target_active: bool = false             # une case ciblée est affichée
var target_cell: Vector2i = Vector2i.ZERO
var target_path: Array[Vector2i] = []       # trajet complet (départ et arrivée inclus) ; vide = aucun chemin connu
var target_travelling: bool = false         # vrai : déplacement lancé (contour vert)

var _terrain_layer: Node2D
var _items_layer: Node2D
var _pick_overlay: Node2D
var _target_overlay: Node2D
var _hovered: Monster = null
var _corpses: Dictionary = {}           # étage (int) -> Array[Dictionary] {cell, id} : cadavres que RAISE peut relever
var noise_cell: Vector2i = Vector2i.ZERO   # dernier bruit du joueur (voir record_noise)
var noise_radius: int = 0
var noise_time: float = -1000.0
var _ground_by_level: Dictionary = {}   # étage (int) -> Dictionary Vector2i -> Array d'Item


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # sprites x4 réduits : lissage (NEAREST scintille)
	_terrain_layer = Node2D.new()
	add_child(_terrain_layer)
	_items_layer = Node2D.new()
	_items_layer.draw.connect(_draw_ground_items)
	add_child(_items_layer)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	fx = Node2D.new()
	fx.z_index = 5  # au-dessus des entités, sous le brouillard (z_index 10)
	add_child(fx)
	fog = FogLayer.new()
	fog.world = self
	fog.z_index = 10
	add_child(fog)
	_pick_overlay = Node2D.new()
	_pick_overlay.z_index = 11  # au-dessus du brouillard
	_pick_overlay.draw.connect(_draw_pick_overlay)
	add_child(_pick_overlay)
	_target_overlay = Node2D.new()
	_target_overlay.z_index = 11  # au-dessus du brouillard (ajouté après l'overlay de choix : dessiné par-dessus)
	_target_overlay.draw.connect(_draw_target_overlay)
	add_child(_target_overlay)
	chunks = ChunkManager.new()
	chunks.setup(world_seed, use_arena, _terrain_layer, entities, self)
	EventBus.time_advanced.connect(_on_time_advanced)
	EventBus.action_performed.connect(_on_player_action)


## Étage actif (0 = surface, négatif = sous-sol, positif = étages).
func get_level() -> int:
	return chunks.level if chunks != null else 0


## Change d'étage (le joueur garde ses coordonnées x, y) : décharge l'ancien étage (monstres en réserve), charge le nouveau, recalcule la vue.
func change_level(new_level: int) -> void:
	if new_level == get_level():
		return
	chunks.set_level(new_level)
	_items_layer.queue_redraw()
	update_fov()


func _ground_dict() -> Dictionary:
	return _ground_dict_of(get_level())


func add_entity(node: Node2D) -> void:
	entities.add_child(node)


## --- Objets au sol ---

## Affiche la touche (1-9) sur chaque case de `labels` (Vector2i -> String) ; {} pour effacer.
func show_pick_overlay(labels: Dictionary) -> void:
	pick_labels = labels
	_pick_overlay.queue_redraw()


func _draw_pick_overlay() -> void:
	var font: Font = ThemeDB.fallback_font
	for pos: Vector2i in pick_labels:
		var cell := Rect2(Vector2(pos * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))
		_pick_overlay.draw_rect(cell, Color(0.3, 0.6, 1.0, 0.35))
		_pick_overlay.draw_rect(cell, Color(0.55, 0.8, 1.0, 0.95), false, 8.0)
		_pick_overlay.draw_string(font, cell.position + Vector2(0, 92), String(pick_labels[pos]),
			HORIZONTAL_ALIGNMENT_CENTER, TILE_SIZE, 80, Color.WHITE)


# --- Case ciblée du déplacement automatique ---

## Affiche le carré autour de `cell` et les points du trajet `path` (départ et arrivée inclus, peut être vide).
## `travelling` : le déplacement est lancé (contour vert au lieu de blanc).
func show_target(cell: Vector2i, path: Array[Vector2i], travelling: bool) -> void:
	target_active = true
	target_cell = cell
	target_path = path
	target_travelling = travelling
	_target_overlay.queue_redraw()


func clear_target() -> void:
	if not target_active:
		return
	target_active = false
	target_path = []
	target_travelling = false
	_target_overlay.queue_redraw()


func _draw_target_overlay() -> void:
	if not target_active:
		return
	var color: Color = TARGET_COLOR_TRAVEL if target_travelling else TARGET_COLOR_IDLE
	var half := Vector2(TILE_SIZE, TILE_SIZE) / 2.0
	# Points sur les cases INTERMÉDIAIRES (ni le joueur ni la case ciblée).
	for i in range(1, target_path.size() - 1):
		_target_overlay.draw_circle(Vector2(target_path[i] * TILE_SIZE) + half, TARGET_DOT_RADIUS, color)
	var inset: float = TARGET_BORDER / 2.0 + 2.0
	var square := Rect2(Vector2(target_cell * TILE_SIZE) + Vector2(inset, inset), Vector2(TILE_SIZE, TILE_SIZE) - Vector2(inset, inset) * 2.0)
	_target_overlay.draw_rect(square, color, false, TARGET_BORDER)


func get_ground_items(pos: Vector2i) -> Array:
	return _ground_dict().get(pos, [])


func add_ground_item(pos: Vector2i, item: Item) -> void:
	add_ground_item_at(get_level(), pos, item)


## Pose un objet au sol pour un étage donné (chargement d'une sauvegarde, autre étage).
func add_ground_item_at(level: int, pos: Vector2i, item: Item) -> void:
	var ground: Dictionary = _ground_dict_of(level)
	var list: Array = ground.get(pos, [])
	var merged: bool = false
	for it: Item in list:
		if it.can_merge(item):
			it.count += item.count
			merged = true
			break
	if not merged:
		list.append(item)
	ground[pos] = list
	if level == get_level():
		refresh_items()
	chunks.mark_modified_at(pos, level)


func remove_ground_item(pos: Vector2i, item: Item) -> void:
	var level: int = get_level()
	var ground: Dictionary = _ground_dict_of(level)
	var list: Array = ground.get(pos, [])
	list.erase(item)
	if list.is_empty():
		ground.erase(pos)
	refresh_items()
	chunks.mark_modified_at(pos, level)


## Objets au sol d'un étage (Vector2i -> Array[Item]) ; ne crée l'entrée que si nécessaire.
func _ground_dict_of(level: int) -> Dictionary:
	if not _ground_by_level.has(level):
		_ground_by_level[level] = {}
	return _ground_by_level[level]


func get_ground_items_at(level: int, pos: Vector2i) -> Array:
	return _ground_dict_of(level).get(pos, [])


## Remplace le tas d'objets d'une case (chargement d'une sauvegarde).
func set_ground_items_at(level: int, pos: Vector2i, items: Array) -> void:
	var ground: Dictionary = _ground_dict_of(level)
	if items.is_empty():
		ground.erase(pos)
	else:
		ground[pos] = items
	if level == get_level():
		refresh_items()
	chunks.mark_modified_at(pos, level)


## Tous les objets au sol d'un étage (pour la sauvegarde).
func ground_items_of_level(level: int) -> Dictionary:
	return _ground_dict_of(level)


func clear_ground_items() -> void:
	_ground_by_level.clear()
	refresh_items()


## À appeler après toute modification d'un tas d'objets au sol.
func refresh_items() -> void:
	_items_layer.queue_redraw()


# --- Terrain (délégué aux chunks) ---

## Une case hors des chunks chargés est inconnue : ni praticable, opaque.
## « Praticable » = À PIED (monstres, marche automatique) : l'eau profonde ne l'est pas, le joueur y nage (can_player_enter).
func is_walkable(pos: Vector2i) -> bool:
	return chunks.is_walkable(pos)


## Profondeur de nage de la case (TerrainDB.SWIM_NONE / SWIM_SHALLOW / SWIM_DEEP) ; SWIM_NONE si le chunk n'est pas chargé.
func swim_depth(pos: Vector2i) -> int:
	var chunk: Chunk = chunks.chunk_at(pos)
	if chunk == null:
		return TerrainDB.SWIM_NONE
	return TerrainDB.swim_depth(chunk.terrain[ChunkManager.index_of(pos)])


func is_deep_water(pos: Vector2i) -> bool:
	return swim_depth(pos) == TerrainDB.SWIM_DEEP


## Case où le JOUEUR peut entrer : praticable à pied, ou eau profonde (il nage).
func can_player_enter(pos: Vector2i) -> bool:
	return is_walkable(pos) or is_deep_water(pos)


## Eau profonde visible ou déjà vue : la marche automatique ne s'y engage que si le joueur nage déjà.
func is_known_deep_water(pos: Vector2i) -> bool:
	return is_deep_water(pos) and (visible_cells.has(pos) or is_seen(pos))


## Murs et arbres bloquent la vue.
func is_opaque(pos: Vector2i) -> bool:
	return chunks.is_opaque(pos)


func has_terrain(pos: Vector2i) -> bool:
	return chunks.has_terrain(pos)


## Portée de mêlée : cases voisines en orthogonal uniquement (cohérent avec les déplacements).
static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func is_occupied(pos: Vector2i) -> bool:
	return (player != null and player.grid_pos == pos) or get_monster_at(pos) != null


func find_path(from: Vector2i, to: Vector2i, domain: int = DOMAIN_WALK) -> Array[Vector2i]:
	return PathFinder.find(self, from, to, domain)


## Un monstre du domaine `domain` peut-il se tenir sur cette case ? Marche : praticable à pied ; nage : aussi l'eau profonde ;
## aquatique : seulement l'eau ; vol : tout terrain chargé sauf murs et fenêtres.
func monster_can_enter(pos: Vector2i, domain: int) -> bool:
	match domain:
		DOMAIN_SWIM:
			return is_walkable(pos) or is_deep_water(pos)
		DOMAIN_AQUATIC:
			return swim_depth(pos) != TerrainDB.SWIM_NONE
		DOMAIN_FLY:
			var index: int = chunks.terrain_index(pos)
			if index < 0 or TerrainDB.autotile_of(index) == "wall":
				return false
			return TerrainDB.is_walkable(index) or not TerrainDB.links_wall(index)
	return is_walkable(pos)


# --- Champ de vision ---

func is_visible_cell(pos: Vector2i) -> bool:
	return visible_cells.has(pos)


## Case praticable ET connue du joueur (visible ou déjà vue) : sert aux déplacements automatiques, qui ne « devinent » pas l'inconnu.
func is_known_walkable(pos: Vector2i) -> bool:
	return is_walkable(pos) and (visible_cells.has(pos) or is_seen(pos))


## Case déjà vue au moins une fois (mémoire de la carte).
func is_seen(pos: Vector2i) -> bool:
	return chunks.is_seen(pos)


## À appeler quand le joueur change de case (et au démarrage) : charge les chunks proches, puis calcule la vue.
func update_fov() -> void:
	if player == null:
		return
	chunks.update_around(player.grid_pos)
	visible_cells = FieldOfView.compute(self, player.grid_pos, VIEW_RADIUS)
	for cell: Vector2i in visible_cells:
		chunks.mark_seen(cell)
	fog.queue_redraw()
	_refresh_monster_visibility()


## Cache les monstres hors de vue ; signale ceux qui viennent d'apparaître.
func _refresh_monster_visibility() -> void:
	for m in monsters:
		var now_visible: bool = visible_cells.has(m.grid_pos)
		if now_visible and player != null and m.data.has_ability("STEALTH") \
				and maxi(absi(m.grid_pos.x - player.grid_pos.x), absi(m.grid_pos.y - player.grid_pos.y)) > STEALTH_REVEAL_RANGE:
			now_visible = false   # furtif : on ne le voit (ni ne le signale) qu'à moins de STEALTH_REVEAL_RANGE cases
		if now_visible and not m.visible:
			# Le message n'apparaît qu'une fois par monstre ; il revient seulement si le monstre est resté hors de vue
			# (dans le brouillard) au moins ALERT_REARM_POINTS : un monstre qui clignote en bord de vue ne spamme pas.
			if not m.spotted or GameClock.elapsed_points - m.hidden_since >= ALERT_REARM_POINTS:
				EventBus.message_logged.emit("Vous apercevez %s." % m.data.display_name)
				m.spotted = true
			EventBus.hostile_spotted.emit(m)  # arrête toujours la marche automatique
		elif not now_visible and m.visible:
			m.hidden_since = GameClock.elapsed_points
		m.visible = now_visible


# --- Monstres ---

func get_monster_at(pos: Vector2i) -> Monster:
	for m in monsters:
		if m.grid_pos == pos:
			return m
	return null


func find_free_cell_near(origin: Vector2i) -> Vector2i:
	for r in range(0, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var p: Vector2i = origin + Vector2i(dx, dy)
				if is_walkable(p) and not is_occupied(p):
					return p
	return origin


## Crée le nœud d'un monstre sur `cell` (sans vérification) ; il reste caché jusqu'au prochain calcul de vue.
func _create_monster(data: MonsterData, cell: Vector2i) -> Monster:
	var m := Monster.new()
	m.data = data
	m.world = self
	m.hp = data.max_hp
	m.grid_pos = cell
	m.home_cell = cell
	m.z = get_level()
	m.next_action_time = GameClock.elapsed_points
	m.hidden_since = GameClock.elapsed_points
	m.visible = false  # update_fov() décidera
	entities.add_child(m)
	monsters.append(m)
	chunks.mark_modified_at(cell, get_level())
	return m


func spawn_monster(data: MonsterData, near: Vector2i) -> Monster:
	var m: Monster = _create_monster(data, find_free_cell_near(near))
	_refresh_monster_visibility()
	return m


## Monstre initial d'un chunk (SpawnGenerator : {monster, cell, facing, state, affixes}). Null si la case n'est plus libre.
## Pas de recalcul de la visibilité ici : update_fov() (ou le prochain déplacement du joueur) s'en charge.
func spawn_monster_at(entry: Dictionary) -> Monster:
	var cell: Vector2i = entry["cell"]
	var data: MonsterData = MonsterDB.create(String(entry["monster"]), entry.get("affixes", []))
	if not monster_can_enter(cell, Monster.domain_of(data)) or is_occupied(cell):
		return null
	var m: Monster = _create_monster(data, cell)
	m.facing = entry.get("facing", m.facing)
	m.state = _valid_state(String(entry.get("state", "idle")), m.data)
	m.ambient = bool(entry.get("ambient", false))
	return m


## Crée un monstre `monster_id` sur la case libre la plus proche de `origin` (rayon `radius`, cases praticables à pied), en chasse du joueur si
## `hunting`. Null s'il n'y a pas de place ou si le plafond de monstres est atteint (SUMMON, RAISE).
func spawn_near(origin: Vector2i, monster_id: String, radius: int, hunting: bool) -> Monster:
	if monsters.size() >= SPLIT_MAX_MONSTERS:
		return null
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell: Vector2i = origin + Vector2i(dx, dy)
				if is_walkable(cell) and not is_occupied(cell) and swim_depth(cell) == TerrainDB.SWIM_NONE:
					return _spawn_hunter(monster_id, cell, hunting)
	return null


## Crée un monstre sur une case précise (si elle est libre et praticable à pied).
func spawn_at_cell(monster_id: String, cell: Vector2i, hunting: bool) -> Monster:
	if monsters.size() >= SPLIT_MAX_MONSTERS or not is_walkable(cell) or is_occupied(cell):
		return null
	return _spawn_hunter(monster_id, cell, hunting)


func _spawn_hunter(monster_id: String, cell: Vector2i, hunting: bool) -> Monster:
	var m: Monster = _create_monster(MonsterDB.create(monster_id), cell)
	if hunting and player != null:
		m.has_target = true
		m.target_cell = player.grid_pos
	_refresh_monster_visibility()
	return m


# --- Cadavres (RAISE) ---

func add_corpse(cell: Vector2i, monster_id: String) -> void:
	var level: int = get_level()
	if not _corpses.has(level):
		_corpses[level] = []
	var list: Array = _corpses[level]
	list.append({"cell": cell, "id": monster_id})
	while list.size() > MAX_CORPSES:
		list.pop_front()


## Retire et renvoie le cadavre le plus proche de `origin` à moins de `reach` cases ({cell, id}), {} s'il n'y en a pas.
func take_corpse_near(origin: Vector2i, reach: int) -> Dictionary:
	var list: Array = _corpses.get(get_level(), [])
	var best: int = -1
	var best_distance: int = reach + 1
	for i in list.size():
		var cell: Vector2i = (list[i] as Dictionary)["cell"]
		var distance: int = maxi(absi(cell.x - origin.x), absi(cell.y - origin.y))
		if distance < best_distance:
			best_distance = distance
			best = i
	if best < 0:
		return {}
	var corpse: Dictionary = list[best]
	list.remove_at(best)
	return corpse


# --- Bruit entendu (BLIND_HEARING) ---

## Mémorise le dernier bruit du joueur (sans réveiller personne : voir make_noise pour les dormeurs).
func record_noise(origin: Vector2i, radius: int) -> void:
	noise_cell = origin
	noise_radius = radius
	noise_time = GameClock.elapsed_points


## Un monstre en `cell` entend-il le dernier bruit du joueur (encore récent et assez proche) ?
func hears_noise(cell: Vector2i) -> bool:
	return GameClock.elapsed_points - noise_time <= NOISE_MEMORY \
		and maxi(absi(cell.x - noise_cell.x), absi(cell.y - noise_cell.y)) <= noise_radius


## « sleep » est refusé pour un monstre qui ne dort jamais (garde, enragé).
func _valid_state(state: String, data: MonsterData) -> String:
	if state == "sleep" and (data.never_sleeps or data.abilities.has("GUARD")):
		return "idle"
	return state


## Rend vie à un monstre mis en réserve par Monster.to_dict() quand son chunk est rechargé.
## Les cases et directions sont relues en Vector2i (en mémoire) ou en tableaux (JSON).
func restore_monster(entry: Dictionary) -> Monster:
	var data: MonsterData = MonsterDB.create(String(entry["id"]), entry.get("affixes", []))
	var cell: Vector2i = cell_from_data(entry.get("cell", []))
	var m: Monster = _create_monster(data, cell)
	m.home_cell = cell_from_data(entry.get("home", cell), cell)
	m.state = _valid_state(String(entry.get("state", "idle")), data)
	m.hp = float(entry.get("hp", data.max_hp))
	m.stamina = float(entry.get("stamina", Player.STAMINA_MAX))
	m.facing = cell_from_data(entry.get("facing", m.facing), m.facing)
	if not Monster.RING.has(m.facing):
		m.facing = Vector2i(0, 1)
	m.spotted = bool(entry.get("spotted", false))
	m.generation = int(entry.get("generation", 0))
	m.next_action_time = float(entry.get("next_action_time", m.next_action_time))
	m.has_target = bool(entry.get("has_target", false))
	m.target_cell = cell_from_data(entry.get("target_cell", cell), cell)
	m.hidden_since = float(entry.get("hidden_since", m.hidden_since))
	m._ranged_ready_at = float(entry.get("ranged_ready_at", 0.0))
	m._scream_ready_at = float(entry.get("scream_ready_at", 0.0))
	m._last_hurt = float(entry.get("last_hurt", -1000.0))
	m._regen_clock = float(entry.get("regen_clock", 0.0))
	m._rush_ready_at = float(entry.get("rush_ready_at", 0.0))
	m._attack_bonus = float(entry.get("attack_bonus", 1.0))
	m.ambient = bool(entry.get("ambient", false))
	return m


## Case ou direction relue depuis un Vector2i (réserve en mémoire) ou un tableau [x, y] (JSON).
static func cell_from_data(value: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


## Explosion de type `kind` (clé d'EXPLOSIONS) en `origin`. `radius` < 0 : le rayon du type. Blesse le joueur et les monstres dans le rayon
## (sauf `source`, qui explose : c'est à l'appelant de le retirer) ; un monstre tué est retiré (il peut exploser à son tour).
func explode(origin: Vector2i, radius: int, kind: String, source: Monster) -> void:
	var def: Dictionary = EXPLOSIONS.get(kind, {})
	if def.is_empty():
		return
	var reach: int = int(def["radius"]) if radius < 0 else radius
	var damage: float = float(def["damage"])
	if source != null and radius < 0:
		EventBus.message_logged.emit("%s explose !" % source.data.display_name)
	if player != null and not player.dead and maxi(absi(player.grid_pos.x - origin.x), absi(player.grid_pos.y - origin.y)) <= reach:
		var part: String = BodyPartDB.pick(MonsterData.ZONES_HUMANOID, randf())
		if damage > 0.0:
			EventBus.message_logged.emit("L'explosion vous touche (%s) : -%d PV." % [BodyPartDB.name_of(part), int(damage)])
			player.take_damage(damage, part)
		var effect: Dictionary = def["effect"]
		if not effect.is_empty() and not player.dead:
			StatusEffects.apply(player, effect, part)
	if damage <= 0.0:
		return
	for m: Monster in monsters.duplicate():
		if m != source and maxi(absi(m.grid_pos.x - origin.x), absi(m.grid_pos.y - origin.y)) <= reach:
			if m.take_damage(damage):
				remove_monster(m)


## Un blob qui se divise : crée un monstre du même type (mêmes affixes) sur une case voisine libre, avec `hp_value` PV. Faux s'il n'y a pas de place.
func spawn_split(parent: Monster, hp_value: float) -> bool:
	if monsters.size() >= SPLIT_MAX_MONSTERS:
		return false
	var offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for offset: Vector2i in offsets:
		var cell: Vector2i = parent.grid_pos + offset
		if not is_walkable(cell) or is_occupied(cell) or swim_depth(cell) != TerrainDB.SWIM_NONE:
			continue
		var child: Monster = _create_monster(MonsterDB.create(parent.data.id, parent.data.affixes), cell)
		child.hp = minf(hp_value, child.data.max_hp)
		child.generation = parent.generation + 1
		child.facing = parent.facing
		child.has_target = parent.has_target
		child.target_cell = parent.target_cell
		_refresh_monster_visibility()
		return true
	return false


## Réveille les dormeurs (sauf les embuscades, qui n'écoutent que de près) à moins de `radius` cases de `origin`.
func make_noise(origin: Vector2i, radius: int) -> void:
	record_noise(origin, radius)
	for m: Monster in monsters:
		if m.state == "sleep" and not m.data.abilities.has("AMBUSH") \
				and maxi(absi(m.grid_pos.x - origin.x), absi(m.grid_pos.y - origin.y)) <= radius:
			m.wake()


## Le joueur fait du bruit quand il frappe ou qu'il court (le signal d'action ne dit rien de plus : player.gd reste inchangé).
func _on_player_action(action_name: String, _cost: float, _stamina_delta: float) -> void:
	if player == null:
		return
	if action_name == "Attaque":
		make_noise(player.grid_pos, NOISE_COMBAT)
	elif action_name == "Déplacement" and player.posture == Player.Posture.SPRINT:
		make_noise(player.grid_pos, NOISE_SPRINT)
	elif action_name == "Déplacement" and player.posture == Player.Posture.WALK:
		record_noise(player.grid_pos, NOISE_WALK)   # entendu des monstres aveugles, mais ne réveille pas les dormeurs


func remove_monster(m: Monster) -> void:
	monsters.erase(m)
	if _hovered == m:
		_hovered = null
		EventBus.monster_hovered.emit(null)
	chunks.mark_modified_at(m.grid_pos, m.z)
	m.queue_free()


## Fait agir tous les monstres dont le moment d'action est arrivé, dans l'ordre chronologique.
func _on_time_advanced(_points: float) -> void:
	if player == null:
		return
	var guard: int = 0
	while guard < 500 and not player.dead:
		var next_monster: Monster = null
		for m in monsters:
			if m.next_action_time <= GameClock.elapsed_points:
				if next_monster == null or m.next_action_time < next_monster.next_action_time:
					next_monster = m
		if next_monster == null:
			break
		var cost: float = next_monster.take_turn()
		next_monster.next_action_time += maxf(cost, 0.1)
		guard += 1
	_refresh_monster_visibility()


func _process(_delta: float) -> void:
	chunks.process_queue()  # génération étalée des chunks lointains
	var cell := Vector2i((get_global_mouse_position() / TILE_SIZE).floor())
	var under_mouse: Monster = get_monster_at(cell)
	if under_mouse != null and not under_mouse.visible:
		under_mouse = null  # on n'infobulle pas ce qu'on ne voit pas
	if under_mouse != _hovered:
		_hovered = under_mouse
		EventBus.monster_hovered.emit(under_mouse)


# --- Rendu des objets au sol ---

## Objets au sol : sprite du dernier objet posé ; petit repère blanc s'il y en a plusieurs.
func _draw_ground_items() -> void:
	var ground: Dictionary = _ground_dict()
	for pos: Vector2i in ground:
		var list: Array = ground[pos]
		if list.is_empty():
			continue
		var origin := Vector2(pos * TILE_SIZE)
		var top := list[list.size() - 1] as Item
		var sprite: String = UlticaTiles.pick_sprite(top.tile_id(), "fg", 0)
		var box := Rect2(origin, Vector2(TILE_SIZE, TILE_SIZE))
		if not UlticaTiles.draw_icon(_items_layer, sprite, box):
			_items_layer.draw_rect(Rect2(origin + Vector2(40, 40), Vector2(48, 48)), Color(0.85, 0.7, 0.3))  # repli
		if list.size() > 1:
			_items_layer.draw_rect(Rect2(origin + Vector2(TILE_SIZE - 28, TILE_SIZE - 28), Vector2(20, 20)), Color.WHITE)
