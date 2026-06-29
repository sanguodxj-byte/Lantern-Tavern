class_name PlayerStateDying
extends PlayerState

func _enter_tree() -> void:
	player.equipment.drop_shield()
	player.equipment.drop_weapon()
	AudioManager.play("player-death", player.vocal_audio_stream_player)
	GameEvents.player_dead.emit()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		GameEvents.level_restarted.emit()

func can_get_hurt() -> bool:
	return false

func can_die() -> bool:
	return false
