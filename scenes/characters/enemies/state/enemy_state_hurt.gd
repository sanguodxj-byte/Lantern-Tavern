class_name EnemyStateHurt
extends EnemyState

func _enter_tree() -> void:
	enemy.animation_player.play("hurt")
	enemy.animation_player.animation_finished.connect(on_animation_finished)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Enemy.State.MOVING)
