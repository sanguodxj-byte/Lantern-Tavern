extends Node

var current_level : BaseLevel
var current_player : Player

func register_level(level: BaseLevel) -> void:
	current_level = level

func register_player(player: Player) -> void:
	current_player = player
