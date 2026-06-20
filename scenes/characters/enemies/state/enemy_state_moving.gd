class_name EnemyStateMoving
extends EnemyState

func _enter_tree() -> void:
	enemy.animation_player.play("idle")
