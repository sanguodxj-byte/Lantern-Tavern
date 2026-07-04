class_name EnemyStateSlashing
extends EnemyState

const TIME_EMIT_DAMAGE := 200

const CB := preload("res://globals/combat_bridge.gd")

var has_emitted_damage := false
var time_start_slash := Time.get_ticks_msec()

func _enter_tree() -> void:
	enemy.animation_player.play("slash")
	enemy.animation_player.animation_finished.connect(on_animation_finished)

func _process(_delta: float) -> void:
	var time_elapsed := Time.get_ticks_msec() - time_start_slash
	if not has_emitted_damage and time_elapsed > TIME_EMIT_DAMAGE:
		has_emitted_damage = true
		if enemy.weapon_reach_raycast.is_colliding():
			var player := enemy.weapon_reach_raycast.get_collider() as Player
			if player != null:
				# ARPG 战斗结算：通过 CombatBridge 调用 CombatEngine.resolve_attack
				# 替换原硬编码 weapon_data.get_damage_dealt()
				var weapon = enemy.equipment.weapon_data if enemy.equipment.has_weapon() else null
				var defender_attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
				var has_shield := player.equipment.has_shield()
				var result = CB.resolve_enemy_attack(enemy, player, weapon, defender_attrs, has_shield)
				if result.hit:
					player.try_receive_hit_result(enemy, result)
				else:
					AudioManager.play("slash-miss", enemy.action_audio_stream_player)
			else:
				AudioManager.play("slash", enemy.action_audio_stream_player)
		else:
			AudioManager.play("slash", enemy.action_audio_stream_player)


func on_animation_finished(_anim_name: String) -> void:
	transition_state(Enemy.State.MOVING)

func can_get_stunned() -> bool:
	return true
