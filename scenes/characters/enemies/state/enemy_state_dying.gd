class_name EnemyStateDying
extends EnemyState

const DURATION_RAGDOLL_SIMULATION := 3.0
const DROP_BURST_STRENGTH := 3.5
const RD := preload("res://globals/combat/rune_data.gd")

## 死亡物理副作用是否已延迟调度（供回归测试断言“进入 DYING 不立即执行物理操作”）。
var _death_effects_deferred := false
## 延迟的死亡物理副作用是否已真正执行。
var _death_effects_started := false
var _dead_signal_emitted := false

func _enter_tree() -> void:
	enemy.health.current_life = 0
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
	if enemy != null and enemy.is_inside_tree():
		FxHelper.call_deferred("create_blood_fx", _blood_transform())
	AudioManager.play("orc-die", enemy.vocal_audio_stream_player)
	if enemy.is_inside_tree():
		call_deferred("_emit_dead_signal", enemy.global_transform)
	# 死亡物理副作用（布娃娃模拟启动 / 冲量 / 关闭碰撞 / 掉落物）必须延迟到物理步骤之外执行。
	# 否则在 _physics_process 内同步进入 DYING（普攻击杀、击飞落地、穿刺、陷阱致死）会
	# 在物理引擎步进期间执行 physical_bones_start_simulation / apply_impulse / add_child(RigidBody)，
	# 导致引擎死锁（游戏卡死）。与 enemy.gd 中踢击致死的 call_deferred("_deferred_switch_to_dying") 修复一致。
	_death_effects_deferred = true
	call_deferred("_begin_death_effects")
	var timer := get_tree().create_timer(DURATION_RAGDOLL_SIMULATION)
	timer.timeout.connect(freeze_ragdoll)

## 延迟执行的死亡物理副作用。在物理步骤结束后运行，避免物理引擎死锁。
func _begin_death_effects() -> void:
	if not is_instance_valid(enemy) or enemy.state_node != self:
		return
	if _death_effects_started:
		return
	# Set this before mutating physics/scene state. Multiple deferred callbacks
	# can otherwise enter the same death side effects in one frame.
	_death_effects_started = true
	if enemy.collision_shape != null:
		enemy.collision_shape.disabled = true
	if enemy.equipment != null:
		enemy.equipment.drop_weapon()
		enemy.equipment.drop_shield()
	# 死亡碎裂效果：优先使用 VoxelRagdoll（体素碎裂），skeleton_simulator 仅作回退。
	# 体素怪物使用 _rig.glb（单蒙皮网格），骨骼布娃娃无效（PhysicalBone3D collision_layer=0，
	# 蒙皮网格不跟随骨骼），故所有敌人均走 VoxelRagdoll 路径。
	# headless 无 GPU/物理上下文，跳过碎裂模拟避免引擎崩溃。
	if enemy.voxel_ragdoll != null:
		var dir := state_data.impact_direction if state_data != null else Vector3.ZERO
		var strength := 3.0
		if state_data != null and state_data.impulse != Vector3.ZERO:
			strength = maxf(state_data.impulse.length() * 0.02, 2.0)
		if not _is_headless():
			enemy._death_ragdoll_active = true
			enemy.voxel_ragdoll.activate(enemy.get_node_or_null("character"), dir, strength)
	elif enemy.skeleton_simulator != null:
		if not _is_headless():
			enemy.skeleton_simulator.active = true
			enemy.skeleton_simulator.physical_bones_start_simulation()
			if enemy.physical_bone_torso != null and state_data != null and state_data.impulse != Vector3.ZERO:
				enemy.physical_bone_torso.apply_impulse(state_data.impulse)
	# Spawn dynamic monster drop on death!
	_spawn_monster_drop()

func _emit_dead_signal(death_transform: Transform3D) -> void:
	if _dead_signal_emitted or enemy == null or not is_instance_valid(enemy):
		return
	_dead_signal_emitted = true
	enemy.dead.emit(death_transform)

## 可靠的 headless 检测。--headless 会被引擎从 OS.get_cmdline_args() 消费掉，
## OS.has_feature("headless") 在 gdUnit 上下文返回 false，唯有 DisplayServer 名称可靠。
func _is_headless() -> bool:
	return OS.has_feature("headless") or DisplayServer.get_name() == "headless"

func _spawn_monster_drop() -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	# 掉落优先走 DungeonSpawner roster（enemy_base_type meta）
	var drop_id := ""
	if enemy != null and enemy.has_meta("enemy_base_type"):
		var base_type := String(enemy.get_meta("enemy_base_type"))
		var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
		if spawner != null and spawner.has_method("get_drop_id"):
			drop_id = String(spawner.call("get_drop_id", base_type))
	if drop_id.is_empty():
		var lower_name = enemy.name.to_lower() if enemy != null else ""
		if "goblin" in lower_name or "orc" in lower_name or "hobgoblin" in lower_name or "bandit" in lower_name or "cultist" in lower_name:
			drop_id = "goblin_ear"
		elif "rat" in lower_name or "gnoll" in lower_name or "werewolf" in lower_name:
			drop_id = "giant_rat_tail"
		elif "skeleton" in lower_name or "wight" in lower_name or "ghoul" in lower_name or "armor" in lower_name or "duergar" in lower_name or "gargoyle" in lower_name:
			drop_id = "skeleton_dust"
		elif "slime" in lower_name or "fungal" in lower_name or "myconid" in lower_name or "lizard" in lower_name or "troglodyte" in lower_name:
			drop_id = "slime_jelly"
		elif "troll" in lower_name or "bugbear" in lower_name or "minotaur" in lower_name:
			drop_id = "troll_blood"
		elif "necrolord" in lower_name or "vampire" in lower_name or "mummy" in lower_name or "shadow" in lower_name or "elf" in lower_name or "drow" in lower_name or "oni" in lower_name or "elemental" in lower_name or "golem" in lower_name:
			drop_id = "soul_gem"
		elif "dragon" in lower_name or "harpy" in lower_name:
			drop_id = "dragon_scale"
		else:
			var monster_drops = [
				"goblin_ear", "giant_rat_tail", "skeleton_dust", "slime_jelly",
				"troll_blood", "soul_gem", "dragon_scale"
			]
			drop_id = monster_drops[randi() % monster_drops.size()]
		
	var mat_scene = load("res://scenes/equipment/pickable_item.tscn")
	if mat_scene and enemy.get_parent() != null and enemy.get_parent().is_inside_tree():
		var item_instance = mat_scene.instantiate()
		item_instance.material_id = drop_id
		_place_drop_before_add(item_instance, _drop_position() + Vector3(0, 0.4, 0))
		enemy.get_parent().add_child(item_instance)
		print("Monster defeated! Dropped material: ", drop_id)
		# Barony 风格：死亡爆出，带物理冲量（向外+向上翻滚）
		if item_instance.has_method("pop_out"):
			item_instance.pop_out(_drop_position(), DROP_BURST_STRENGTH)
	
	# 精英/Boss 额外掉落材料和符文
	if _is_elite_enemy():
		_spawn_elite_bonus_drop()

func freeze_ragdoll() -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.state_node != self:
		return
	transition_state(Enemy.State.DEAD)

func can_die() -> bool:
	return false

func can_get_hurt() -> bool:
	return false

func _blood_transform() -> Transform3D:
	if enemy != null and enemy.physical_bone_head != null and enemy.physical_bone_head.is_inside_tree():
		return enemy.physical_bone_head.global_transform
	if enemy != null and enemy.is_inside_tree():
		return enemy.global_transform
	return enemy.transform if enemy != null else Transform3D.IDENTITY

## 精英怪额外掉落：100% 掉落额外材料 + 符文
func _spawn_elite_bonus_drop() -> void:
	var bonus_drops = ["troll_blood", "soul_gem", "dragon_scale", "shadow_lotus", "fire_bloom"]
	var drop_id = bonus_drops[randi() % bonus_drops.size()]
	var mat_scene = load("res://scenes/equipment/pickable_item.tscn")
	if mat_scene and enemy.get_parent() != null and enemy.get_parent().is_inside_tree():
		var item_instance = mat_scene.instantiate()
		item_instance.material_id = drop_id
		# 随机偏移避免与主掉落重叠
		var offset := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		_place_drop_before_add(item_instance, _drop_position() + Vector3(0, 0.4, 0) + offset)
		enemy.get_parent().add_child(item_instance)
		print("[Elite] Bonus drop: ", drop_id)
		if item_instance.has_method("pop_out"):
			item_instance.pop_out(_drop_position(), DROP_BURST_STRENGTH)
		var rune := RD.roll_rune("boss" if _is_boss_enemy() else "elite")
		if not rune.is_empty():
			var rune_item = mat_scene.instantiate()
			rune_item.rune_id = String(rune.get("id", ""))
			var rune_offset := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
			_place_drop_before_add(rune_item, _drop_position() + Vector3(0, 0.4, 0) + rune_offset)
			enemy.get_parent().add_child(rune_item)
			print("[Elite] Rune drop: ", rune_item.rune_id)
			if rune_item.has_method("pop_out"):
				rune_item.pop_out(_drop_position(), DROP_BURST_STRENGTH)


func _drop_position() -> Vector3:
	if enemy == null:
		return Vector3.ZERO
	if enemy.is_inside_tree():
		return enemy.global_position
	return enemy.position


func _place_drop_before_add(item_instance: Node3D, world_position: Vector3) -> void:
	var parent := enemy.get_parent()
	if parent is Node3D:
		item_instance.position = (parent as Node3D).to_local(world_position)
	else:
		item_instance.position = world_position

func _is_elite_enemy() -> bool:
	if enemy == null:
		return false
	if "is_elite" in enemy and bool(enemy.is_elite):
		return true
	return enemy.get_meta("is_elite", false)

func _is_boss_enemy() -> bool:
	if enemy == null:
		return false
	if "is_boss_type" in enemy and bool(enemy.is_boss_type):
		return true
	return enemy.get_meta("is_boss_type", false) or enemy.get_meta("is_boss", false)
