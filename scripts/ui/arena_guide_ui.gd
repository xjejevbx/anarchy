class_name ArenaGuideUI
extends CanvasLayer
## Guide de l'arène de test : petit panneau en haut à gauche qui liste les fonctionnalités à essayer, dans l'ordre.
##
## Chaque étape a un identifiant et une détection automatique :
##  - signaux d'EventBus (action_performed, menus, posture, regard, monstres repérés, journal) ;
##  - état du joueur vérifié périodiquement (nage, étage, toit masqué, effets d'état, zoom).
## Une étape cochée le reste (on peut tout tester dans n'importe quel ordre). F3 valide l'étape courante à la main
## (utile pour les essais difficiles à déclencher), F4 réinitialise le guide, F1 masque/affiche le panneau.
##
## Pour une future fonctionnalité : ajouter une entrée dans STEPS, puis la détection correspondante dans
## _on_action / _on_message / _on_* / _poll_state. Si l'essai est purement manuel, aucune détection n'est nécessaire :
## F3 suffit.

const FONT_SIZE: int = 12
const PANEL_WIDTH: float = 720.0
const LINE_HEIGHT: float = 16.0
const PANEL_MARGIN: Vector2 = Vector2(12, 12)

const COLOR_PANEL: Color = Color(0.06, 0.07, 0.09, 0.88)
const COLOR_BORDER: Color = Color(0.45, 0.5, 0.55, 0.85)
const COLOR_HEADER: Color = Color(1.0, 0.82, 0.35)
const COLOR_DONE: Color = Color(0.45, 0.9, 0.5)
const COLOR_CURRENT: Color = Color(1.0, 0.88, 0.45)
const COLOR_PENDING: Color = Color(0.62, 0.64, 0.68)
const COLOR_HINT: Color = Color(0.72, 0.75, 0.8)

# L'ordre est l'ordre conseillé du parcours. Les textes restent courts pour tenir sur deux colonnes.
const STEPS: Array = [
	{"id": "move", "text": "Se déplacer (flèches / 8-2-4-6)", "hint": "Chaque pas coûte 1 point d'action (1 s) ; l'eau coûte plus cher."},
	{"id": "wait", "text": "Attendre (5, espace ou .)", "hint": "Attendre regagne de la stamina, moins vite si vous êtes lourd."},
	{"id": "posture", "text": "Changer de posture (|)", "hint": "Marche, sprint (rapide et bruyant), accroupi (lent et discret)."},
	{"id": "attack", "text": "Attaquer un monstre au contact", "hint": "Orientez-vous vers lui et avancez : le combat de base frappe à 6 PV."},
	{"id": "kill", "text": "Tuer un monstre", "hint": "Deux zombies d'entraînement vous attendent dans l'arène de combat, au sud-est."},
	{"id": "door", "text": "Ouvrir / fermer porte ou fenêtre (o)", "hint": "Approchez-vous de la maison : porte à l'ouest, fenêtres sur les murs."},
	{"id": "ground", "text": "Voir les objets au sol (g)", "hint": "Sacs, armes improvisées et vivres entourent le départ."},
	{"id": "inventory", "text": "Ouvrir l'inventaire (i)", "hint": "Équipez, rangez, jetez : chaque action a un coût affiché avant validation."},
	{"id": "use", "text": "Utiliser un objet (u)", "hint": "Des antibiotiques sont déjà dans votre inventaire de départ (u puis Entrée)."},
	{"id": "swim", "text": "Nager en eau peu profonde", "hint": "Le bassin est à l'est : entrez par la plage de sable."},
	{"id": "deep", "text": "Nager en eau profonde", "hint": "Le centre du bassin épuise la stamina et interdit de se reposer."},
	{"id": "basement", "text": "Descendre au sous-sol (> sur un escalier)", "hint": "Escalier de descente dans la maison : roche, salle et porte intérieure."},
	{"id": "upstairs", "text": "Monter à l'étage (< sur un escalier)", "hint": "L'escalier de montée mène à l'étage supérieur de la maison."},
	{"id": "window_view", "text": "Voir l'extérieur par une fenêtre (étage)", "hint": "Au premier étage, les fenêtres montrent le sol, les toits et les arbres du dessous."},
	{"id": "roof", "text": "Entrer dans la maison (le toit se masque)", "hint": "Le toit du bâtiment où vous vous tenez disparaît ; sortez pour le revoir."},
	{"id": "bestiary", "text": "Observer le bestiaire (approche / x)", "hint": "Au sud-ouest : archétypes et capacités spéciales (armure, aura, charge, grab, garde...), tous endormis."},
	{"id": "status", "text": "Subir un effet d'état", "hint": "Morsure, poison, acide, irradiation, brûlure, engelure ou infection."},
	{"id": "explosion", "text": "Provoquer une explosion", "hint": "Grenadier zombie, chien de feu ou expérience gonflée, dans le bestiaire."},
	{"id": "minimap", "text": "Mini-carte de debug (m)", "hint": "Cases vues, monstres proches, zoom et déplacements dans la mini-carte."},
	{"id": "map", "text": "Carte du joueur (p)", "hint": "Seules les cases explorées apparaissent ; un clic pose un repère."},
	{"id": "character", "text": "Écran du personnage (c)", "hint": "Stats, état des parties du corps et onglets d'information."},
	{"id": "look", "text": "Mode regard (x ou Maj + flèche)", "hint": "Inspectez un monstre ou l'étage voisin sans déplacer le joueur."},
	{"id": "zoom", "text": "Zoomer / dézoomer (+ / -)", "hint": "Cinq niveaux de zoom, du plus large (0,125) au plus proche (0,75)."},
	{"id": "save", "text": "Sauvegarder (F5) puis recharger", "hint": "L'arène est une partie comme une autre : sauvegarde, chargement, suppression."},
]

var player: Player

var _view: Control
var _visible: bool = true
var _done: Dictionary = {}          # id d'étape -> true
var _elapsed: float = 0.0
var _zoom_start: int = 0


func _ready() -> void:
	layer = 16   # sous les menus (17+) et au-dessus du monde ; le HUD reste lisible
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.draw.connect(_draw_view)
	add_child(_view)
	_zoom_start = player.zoom_index if player != null else 0

	EventBus.action_performed.connect(_on_action)
	EventBus.message_logged.connect(_on_message)
	EventBus.hostile_spotted.connect(_on_hostile_spotted)
	EventBus.posture_requested.connect(_on_posture_requested)
	EventBus.inventory_requested.connect(_on_inventory_requested)
	EventBus.ground_requested.connect(_on_ground_requested)
	EventBus.ground_all_requested.connect(_on_ground_requested)
	EventBus.minimap_requested.connect(_on_minimap_requested)
	EventBus.map_requested.connect(_on_map_requested)
	EventBus.character_requested.connect(_on_character_requested)
	EventBus.look_requested.connect(_on_look_requested)
	_view.queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	_poll_state()


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.physical_keycode:
		KEY_F1:
			_visible = not _visible
			get_viewport().set_input_as_handled()
			_view.queue_redraw()
		KEY_F3:
			_validate_current()
			get_viewport().set_input_as_handled()
		KEY_F4:
			_reset()
			get_viewport().set_input_as_handled()


## État du joueur qui ne passe pas par un signal : nage, étage, toit, effets, zoom.
func _poll_state() -> void:
	if player == null or player.world == null:
		return
	var depth: int = player.swim_depth()
	if depth == TerrainDB.SWIM_SHALLOW:
		_mark("swim")
	elif depth == TerrainDB.SWIM_DEEP:
		_mark("swim")
		_mark("deep")
	var level: int = player.world.get_level()
	if level < 0:
		_mark("basement")
	elif level > 0:
		_mark("upstairs")
		if _sees_open_air(player.world):
			_mark("window_view")
	if player.world.roof_hidden_chunk != World.NO_ROOF_CHUNK:
		_mark("roof")
	if StatusEffects.summary() != "":
		_mark("status")
	if player.zoom_index != _zoom_start:
		_mark("zoom")


## Une case de vide est-elle visible ? Depuis un étage, cela signifie qu'une fenêtre (ou une ouverture) laisse
## voir l'extérieur de la surface en contrebas.
func _sees_open_air(world: World) -> bool:
	for cell: Vector2i in world.visible_cells:
		if TerrainDB.is_air(world.chunks.terrain_index(cell)):
			return true
	return false


func _on_action(action_name: String, _cost: float, _stamina_delta: float) -> void:
	match action_name:
		"Déplacement":
			_mark("move")
		"Nage":
			_mark("move")
			_mark("swim")
		"Attendre", "Flotter", "Surplace":
			_mark("wait")
		"Ouvrir", "Fermer":
			_mark("door")
		"Attaque":
			_mark("attack")
		"Inventaire":
			_mark("inventory")


func _on_message(text: String) -> void:
	if text.contains("est mort."):
		_mark("kill")
	if text.contains("explose !"):
		_mark("explosion")
	if text.contains("antibiotiques"):
		_mark("use")
	if text.contains("Partie sauvegardée"):
		_mark("save")
	if text.contains("Vous apercevez"):
		_mark("bestiary")
	if text.contains("Vous nagez"):
		_mark("swim")
	if text.contains("Eau profonde"):
		_mark("swim")
		_mark("deep")


func _on_hostile_spotted(_monster: Node) -> void:
	_mark("bestiary")


func _on_posture_requested() -> void:
	_mark("posture")


func _on_inventory_requested() -> void:
	_mark("inventory")


func _on_ground_requested() -> void:
	_mark("ground")


func _on_minimap_requested() -> void:
	_mark("minimap")


func _on_map_requested() -> void:
	_mark("map")


func _on_character_requested() -> void:
	_mark("character")


func _on_look_requested(_direction: Vector2i) -> void:
	_mark("look")


## Valide l'étape en cours (première non cochée) : secours pour les essais manuels ou difficiles à déclencher.
func _validate_current() -> void:
	for step: Dictionary in STEPS:
		if not _done.has(String(step["id"])):
			_mark(String(step["id"]))
			return


func _mark(step_id: String) -> void:
	if _done.has(step_id):
		return
	_done[step_id] = true
	_view.queue_redraw()


func _reset() -> void:
	_done.clear()
	_zoom_start = player.zoom_index if player != null else 0
	_view.queue_redraw()


func _current_index() -> int:
	for i in STEPS.size():
		if not _done.has(String(STEPS[i]["id"])):
			return i
	return -1


func _draw_view() -> void:
	var font: Font = _view.get_theme_default_font()
	if not _visible:
		var compact := "F1 : guide de test (%d/%d)" % [_done.size(), STEPS.size()]
		_view.draw_rect(Rect2(PANEL_MARGIN, Vector2(220.0, 24.0)), Color(0.06, 0.07, 0.09, 0.7))
		_view.draw_string(font, PANEL_MARGIN + Vector2(8, 17), compact,
			HORIZONTAL_ALIGNMENT_LEFT, 210.0, FONT_SIZE, COLOR_HINT)
		return

	var rows_per_column: int = ceili(float(STEPS.size()) / 2.0)
	var panel_height: float = 38.0 + rows_per_column * LINE_HEIGHT + 26.0
	var panel := Rect2(PANEL_MARGIN, Vector2(PANEL_WIDTH, panel_height))
	_view.draw_rect(panel, COLOR_PANEL)
	_view.draw_rect(panel, COLOR_BORDER, false, 1.5)
	var header := "ARÈNE DE TEST — GUIDE  %d/%d" % [_done.size(), STEPS.size()]
	_view.draw_string(font, panel.position + Vector2(10, 21), header,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 3, COLOR_HEADER)
	_view.draw_string(font, panel.position + Vector2(panel.size.x - 240.0, 21), "F1 masquer   F3 valider   F4 réinitialiser",
		HORIZONTAL_ALIGNMENT_LEFT, 230.0, FONT_SIZE - 1, COLOR_PENDING)

	var current: int = _current_index()
	var column_width: float = (PANEL_WIDTH - 30.0) / 2.0
	for i in STEPS.size():
		var column: int = i / rows_per_column
		var row: int = i % rows_per_column
		var step: Dictionary = STEPS[i]
		var done: bool = _done.has(String(step["id"]))
		var color: Color = COLOR_DONE if done else (COLOR_CURRENT if i == current else COLOR_PENDING)
		var prefix: String = "[x] " if done else ("[>] " if i == current else "[ ] ")
		var text: String = "%s%2d. %s" % [prefix, i + 1, String(step["text"])]
		var pos := panel.position + Vector2(10.0 + column * column_width, 38.0 + row * LINE_HEIGHT)
		_view.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, column_width - 8.0, FONT_SIZE, color)

	var hint: String
	if current >= 0:
		hint = "Étape %d : %s" % [current + 1, String(STEPS[current]["hint"])]
	else:
		hint = "Toutes les étapes sont validées. F4 pour recommencer le guide."
	_view.draw_string(font, panel.position + Vector2(10, panel.size.y - 8.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 20.0, FONT_SIZE, COLOR_HINT)
