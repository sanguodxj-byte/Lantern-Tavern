class_name EnemyState
extends Node

signal transition_requested(new_state: Enemy.State, source_data: EnemyStateData)

var enemy: Enemy
var state_data: EnemyStateData

func _init(source_enemy: Enemy, source_data: EnemyStateData = EnemyStateData.new()) -> void:
	enemy = source_enemy
	state_data = source_data

func transition_state(new_state: Enemy.State, source_data: EnemyStateData = EnemyStateData.new()) -> void:
	transition_requested.emit(new_state, source_data)

func can_get_stunned() -> bool:
	return false

func can_get_hurt() -> bool:
	return false

func can_die() -> bool:
	return true
