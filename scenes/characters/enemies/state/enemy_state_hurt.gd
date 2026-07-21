class_name EnemyStateHurt
extends EnemyState

const KNOCKBACK_FORCE := 0.0
const BPR := preload("res://globals/combat/body_part_resolver.gd")
var hurt_animation_name := "hurt"

func _enter_tree() -> void:
	enemy.health.take_damage(state_data.damage)
	_spawn_damage_number()
	var knockback := KNOCKBACK_FORCE
	if state_data.knockback_force > 0.0:
		knockback = state_data.knockback_force
	enemy.pushback_force += state_data.impact_direction * knockback
	if enemy.health.is_dead():
		AudioManager.play("hit-kill", enemy.action_audio_stream_player)
		if wants_launch(state_data):
			# 致命击退：延迟死亡，先被击飞，撞墙/落地后再四散（Barony 风格：被打飞到墙上再四散）
			var launch_data := EnemyStateData.new()
			launch_data.set_impact_direction(state_data.impact_direction)
			launch_data.set_knockback_force(state_data.knockback_force)
			# 通过 enemy.enter_launched_state 间接切换，避免直接引用 Enemy.State.LAUNCHED
			# 触发 Enemy ↔ EnemyState 循环依赖导致的枚举成员解析失败
			enemy.enter_launched_state(launch_data)
		else:
			var data := EnemyStateData.new().set_impulse(state_data.impact_direction * 120.0 + Vector3.UP * 80.0)
			transition_state(Enemy.State.DYING, data)
	else:
		AudioManager.play("slash-hit", enemy.action_audio_stream_player)
		GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.LOW)
		# physical_bone_head 仅布娃娃敌人存在；缺失时回退到 enemy.global_transform，
		# 否则对 null 访问 global_transform 会崩溃（与 EnemyStateDying._blood_transform 一致）。
		var blood_at := enemy.physical_bone_head.global_transform if enemy.physical_bone_head != null and enemy.physical_bone_head.is_inside_tree() else (enemy.global_transform if enemy.is_inside_tree() else enemy.transform)
		if enemy.is_inside_tree():
			FxHelper.call_deferred("create_blood_fx", blood_at, false)
		# 被击部位体素纹理相关：用命中点→最近骨骼→调色板色生成体素碎屑
		var impact_dir := state_data.impact_direction if "impact_direction" in state_data else Vector3.ZERO
		var enemy_position := enemy.global_position if enemy.is_inside_tree() else enemy.position
		var hit_pt := BPR.approx_hit_point(enemy_position, impact_dir)
		var skel := enemy.get_node_or_null("character/Armature/Skeleton3D")
		if skel == null:
			skel = enemy.find_child("Skeleton3D", true, false)
		var part_color := Color(0.6, 0.6, 0.6)
		if skel != null:
			part_color = BPR.resolve_part_color(enemy.name, skel, hit_pt)
		if enemy.is_inside_tree():
			FxHelper.call_deferred("create_voxel_chip", hit_pt, part_color)
	if enemy.animation_player.has_animation(hurt_animation_name):
		enemy.animation_player.play(hurt_animation_name)
		enemy.animation_player.animation_finished.connect(on_animation_finished)
	else:
		call_deferred("_finish_without_animation")

func _spawn_damage_number() -> void:
	if state_data.damage <= 0 or enemy == null or not enemy.is_inside_tree():
		return
	var is_crit := bool(state_data.is_crit) if "is_crit" in state_data else false
	FxHelper.call_deferred("create_damage_number_flags", enemy.global_position, state_data.damage, is_crit)

func _physics_process(delta: float) -> void:
	enemy.process_movement(delta)

func on_animation_finished(anim_name: String) -> void:
	if anim_name != hurt_animation_name or enemy.state_node != self:
		return
	transition_state(Enemy.State.MOVING)

func _exit_tree() -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.animation_player != null:
		if enemy.animation_player.animation_finished.is_connected(on_animation_finished):
			enemy.animation_player.animation_finished.disconnect(on_animation_finished)

func _finish_without_animation() -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.state_node == self:
		transition_state(Enemy.State.MOVING)

func can_get_hurt() -> bool:
	# Do not rebuild the hurt state for every overlapping hit during the same
	# animation window; the current state owns the hit-stun lifecycle.
	return false

## 致命击退是否延迟死亡（进入飞行态 LAUNCHED）：有击退且已死亡则延迟，否则立即死亡。
func wants_launch(state_data: EnemyStateData) -> bool:
	return state_data.knockback_force > 0.0 and enemy.health.is_dead()
