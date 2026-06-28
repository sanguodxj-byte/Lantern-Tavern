class_name World
extends Node3D

const LEVELS := [preload("res://scenes/levels/level_01_welcome.tscn")]

var current_level_index := 0
var current_loaded_level : BaseLevel = null

func _ready() -> void:
	GameEvents.level_restarted.connect(on_level_restarted)
	load_level(current_level_index)

func on_level_restarted() -> void:
	load_level(current_level_index)

func load_level(index: int) -> void:
	if current_loaded_level != null:
		current_loaded_level.queue_free()
	if LEVELS.size() > index:
		current_loaded_level = LEVELS[index].instantiate()
		GameState.register_level(current_loaded_level)
		add_child(current_loaded_level)
