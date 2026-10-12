extends Node
## Autoload "GameClock" : le temps in-game.
## 1 point d'action = 1 seconde, donc 60 points = 1 minute.

const POINTS_PER_MINUTE: float = 60.0
const START_HOUR: int = 8

var elapsed_points: float = 0.0


func advance(points: float) -> void:
	elapsed_points += points
	EventBus.time_advanced.emit(points)


func get_total_minutes() -> int:
	return int(elapsed_points / POINTS_PER_MINUTE)


func get_time_string() -> String:
	var total_minutes: int = get_total_minutes() + START_HOUR * 60
	var day: int = floori(total_minutes / 1440.0) + 1
	var minutes_of_day: int = total_minutes % 1440
	var hour: int = floori(minutes_of_day / 60.0)
	var minute: int = minutes_of_day % 60
	return "Jour %d - %02d:%02d" % [day, hour, minute]
