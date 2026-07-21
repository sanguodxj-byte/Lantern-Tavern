class_name PlayerStateHurt
extends PlayerState

const DURATION_HURT := 200
const PUSHBACK_FORCE := 0.0

const ME := preload("res://globals/combat/milestone_effects.gd")

var time_start_hurt := Time.get_ticks_msec()

func _enter_tree() -> void:
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
	GameEvents.player_hurt.emit(player)
	if player.equipment.has_furniture():
		player.equipment.drop_furniture()
	# ARPG 实时击退：优先用 DamageResult 提供的击退力，否则用默认值
	var kb_force: float = PUSHBACK_FORCE
	if state_data.knockback_force > 0.0:
		kb_force = state_data.knockback_force
	player.pushback_force += state_data.impact_direction * kb_force
	# 里程碑被动：厚皮（CON T2）每次受击最终扣血 -2（最低 1）
	var final_damage: int = ME.apply_thick_skin(state_data.damage)
	# 里程碑被动：元素护壳（MAG T2）受法术伤害 -4（需 DamageResult 标记 is_spell，集成期暂用 false）
	# 注：当前 PlayerStateData 未携带 is_spell 标记，待 CombatBridge 扩展后接入
	player.health.take_damage(final_damage)
	_spawn_damage_number(final_damage)
	if player.health.is_dead():
		transition_state(Player.State.DYING)
	else:
		AudioManager.play("hurt", player.vocal_audio_stream_player)

func _spawn_damage_number(final_damage: int) -> void:
	if final_damage <= 0 or player == null or not player.is_inside_tree():
		return
	var is_crit := bool(state_data.is_crit) if "is_crit" in state_data else false
	FxHelper.call_deferred("create_damage_number_flags", player.global_position, final_damage, is_crit)

func _physics_process(delta: float) -> void:
	player.process_movement(delta)
	if Time.get_ticks_msec() - time_start_hurt > DURATION_HURT:
		transition_state(Player.State.MOVING)

func can_get_hurt() -> bool:
	# A hurt state is a short invulnerability window. Re-entering HURT from the
	# same hitbox window would repeatedly rebuild state nodes and feedback FX.
	return false
