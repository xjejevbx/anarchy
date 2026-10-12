extends CanvasLayer
## HUD : heure, PV, stamina, charge, journal de messages, infobulle des monstres.

const MAX_MESSAGES: int = 6

var _label: Label
var _log_label: Label
var _tooltip: PanelContainer
var _tooltip_label: Label

var _hp: float = 0.0
var _hp_max: float = 1.0
var _stamina: float = 0.0
var _stamina_max: float = 100.0
var _penalty: float = 0.0
var _weight: float = 0.0
var _capacity: float = 1.0
var _last_action: String = ""
var _messages: Array[String] = []
var _hovered: Monster = null


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 18)
	add_child(_label)

	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 16)
	add_child(_log_label)

	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip_label = Label.new()
	_tooltip.add_child(_tooltip_label)
	add_child(_tooltip)

	EventBus.time_advanced.connect(func(_p: float) -> void: _refresh())
	EventBus.stamina_changed.connect(_on_stamina_changed)
	EventBus.load_changed.connect(_on_load_changed)
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.action_performed.connect(_on_action_performed)
	EventBus.message_logged.connect(_on_message_logged)
	EventBus.monster_hovered.connect(func(m: Node) -> void: _hovered = m as Monster)
	_refresh()


func _process(_delta: float) -> void:
	if _hovered != null and is_instance_valid(_hovered):
		_tooltip_label.text = _hovered.get_tooltip_text()
		_tooltip.position = get_viewport().get_mouse_position() + Vector2(16, 16)
		_tooltip.visible = true
	else:
		_hovered = null
		_tooltip.visible = false
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	_log_label.position = Vector2(12, viewport_height - _log_label.size.y - 12)


func _on_stamina_changed(current: float, maximum: float, time_penalty: float) -> void:
	_stamina = current
	_stamina_max = maximum
	_penalty = time_penalty
	_refresh()


func _on_load_changed(weight: float, capacity: float) -> void:
	_weight = weight
	_capacity = capacity
	_refresh()


func _on_health_changed(current: float, maximum: float) -> void:
	_hp = current
	_hp_max = maximum
	_refresh()


func _on_action_performed(action_name: String, cost: float, stamina_delta: float) -> void:
	_last_action = "%s (%.1f pts, stamina %+.2f)" % [action_name, cost, stamina_delta]


func _on_message_logged(text: String) -> void:
	_messages.append(text)
	if _messages.size() > MAX_MESSAGES:
		_messages.pop_front()
	_log_label.text = "\n".join(_messages)


func _refresh() -> void:
	var ratio: float = _weight / maxf(_capacity, 0.001)
	var load_text: String = "Charge : %.1f / %.1f kg (%d%%)" % [_weight, _capacity, roundi(ratio * 100.0)]
	if ratio > 1.0:
		load_text += "  SURCHARGE !"
	_label.text = "%s\nPV : %d / %d\nStamina : %d%%   Pénalité de temps : +%d%%\n%s\nDernière action : %s" % [
		GameClock.get_time_string(),
		ceili(_hp), int(_hp_max),
		roundi(_stamina / _stamina_max * 100.0),
		roundi(_penalty * 100.0),
		load_text,
		_last_action,
	]
