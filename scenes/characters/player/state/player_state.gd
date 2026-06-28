class_name PlayerState
extends Node

signal transition_requested(new_state: Player.State, source_data: PlayerStateData)

var state_data: PlayerStateData
var player: Player

func _init(source_player: Player, source_data: PlayerStateData = PlayerStateData.new()) -> void:
	player = source_player
	state_data = source_data

func transition_state(new_state: Player.State, source_data: PlayerStateData = PlayerStateData.new()) -> void:
	transition_requested.emit(new_state, source_data)

func can_get_hurt() -> bool:
	return true

func can_die() -> bool:
	return true
