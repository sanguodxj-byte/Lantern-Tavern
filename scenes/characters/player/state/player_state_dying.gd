class_name PlayerStateDying
extends PlayerState

func _enter_tree() -> void:
	GameState.handle_expedition_failure(player)
	AudioManager.play("player-death", player.vocal_audio_stream_player)
	GameEvents.player_dead.emit()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		# 死亡遣送酒馆：按设计文档 §1.2，玩家在酒馆躺椅上醒来，进入当晚经营期。
		# extract_to_tavern 会切换 phase 为 NIGHT_TAVERN 并加载酒馆空间。
		var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
		if tm != null and tm.has_method("extract_to_tavern"):
			tm.extract_to_tavern()
		else:
			GameEvents.level_restarted.emit()

func can_get_hurt() -> bool:
	return false

func can_die() -> bool:
	return false
