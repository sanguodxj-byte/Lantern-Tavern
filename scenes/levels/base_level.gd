class_name BaseLevel
extends Node3D

const PLAYER_PREFAB := preload("res://scenes/characters/player/player.tscn")

@onready var player_spawn: Node3D = %PlayerSpawn

func _ready() -> void:
	if not is_procedural():
		spawn_player()

func is_procedural() -> bool:
	return false

func spawn_player() -> Player:
	var player: Player = PLAYER_PREFAB.instantiate()
	player.global_transform = player_spawn.global_transform
	add_child(player)
	# 立即注册到 GameState，确保后续系统（如怪物生成）能拿到 current_player。
	# player._ready() 中的 register_player 调用是延迟的（deferred）,
	# 如果不在 add_child 后主动注册，_spawn_dungeon_enemies 等紧随其后的
	# 逻辑会因 current_player 为旧值/null 而跳过怪物生成。
	if GameState:
		GameState.register_player(player)
		if GameState.has_method("apply_equipment_to_player"):
			GameState.apply_equipment_to_player(player)
	return player
