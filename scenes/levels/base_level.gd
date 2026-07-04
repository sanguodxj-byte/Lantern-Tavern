class_name BaseLevel
extends Node3D

const PLAYER_PREFAB := preload("res://scenes/characters/player/player.tscn")

@onready var player_spawn: Node3D = %PlayerSpawn

func _ready() -> void:
	if not is_procedural():
		spawn_player()

func is_procedural() -> bool:
	return false

func spawn_player() -> void:
	var player: Player = PLAYER_PREFAB.instantiate()
	player.global_transform = player_spawn.global_transform
	add_child(player)
