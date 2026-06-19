class_name PlayerStateMoving
extends Node

var player: Player

func _init(source_player: Player) -> void:
	player = source_player

func _physics_process(delta: float) -> void:
	var horizontal_velocity := Vector3(player.velocity.x, 0, player.velocity.z)
	if horizontal_velocity.length_squared() > 0.1 and player.is_on_floor():
		player.animation_player.play("run")
	else:
		player.animation_player.play("idle")
