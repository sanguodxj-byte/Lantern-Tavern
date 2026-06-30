extends Node

var current_keys : Dictionary[Door.KeyColor, bool] = {}
var current_level : BaseLevel
var current_player : Player

func has_key(color: Door.KeyColor) -> bool:
	return current_keys.get(color, false)

func use_key(color: Door.KeyColor) -> void:
	current_keys[color] = false
	GameEvents.current_keys_changed.emit(color)

func obtain_key(color: Door.KeyColor) -> void:
	current_keys[color] = true
	GameEvents.current_keys_changed.emit(color)

func register_level(level: BaseLevel) -> void:
	current_level = level
	current_keys = {}

func register_player(player: Player) -> void:
	current_player = player
