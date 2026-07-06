class_name EnemyStateDying
extends EnemyState

const DURATION_RAGDOLL_SIMULATION := 3.0
const RD := preload("res://globals/combat/rune_data.gd")

func _enter_tree() -> void:
	enemy.health.current_life = 0
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
	FxHelper.create_blood_fx(_blood_transform())
	AudioManager.play("orc-die", enemy.vocal_audio_stream_player)
	if enemy.healthbar != null:
		enemy.healthbar.visible = false
	enemy.dead.emit(enemy.global_transform)
	if enemy.equipment != null:
		enemy.equipment.drop_weapon()
		enemy.equipment.drop_shield()
	if enemy.presence_light != null:
		enemy.presence_light.visible = false
	if enemy.collision_shape != null:
		enemy.collision_shape.disabled = true
	if enemy.skeleton_simulator != null:
		enemy.skeleton_simulator.active = true
		enemy.skeleton_simulator.physical_bones_start_simulation()
	if enemy.physical_bone_torso != null and state_data != null:
		enemy.physical_bone_torso.apply_impulse(state_data.impulse)
	
	# Spawn dynamic monster drop on death!
	_spawn_monster_drop()
	
	var timer := get_tree().create_timer(DURATION_RAGDOLL_SIMULATION)
	timer.timeout.connect(freeze_ragdoll)

func _spawn_monster_drop() -> void:
	# 掉落表以体素模型怪物为准（7 种）
	var monster_drops = [
		"goblin_ear", "giant_rat_tail", "skeleton_dust", "slime_jelly",
		"troll_blood", "soul_gem", "dragon_scale"
	]
	
	var drop_id = ""
	var lower_name = enemy.name.to_lower()
	if "goblin" in lower_name:
		drop_id = "goblin_ear"
	elif "rat" in lower_name:
		drop_id = "giant_rat_tail"
	elif "skeleton" in lower_name:
		drop_id = "skeleton_dust"
	elif "slime" in lower_name:
		drop_id = "slime_jelly"
	elif "troll" in lower_name:
		drop_id = "troll_blood"
	elif "necrolord" in lower_name:
		drop_id = "soul_gem"
	elif "dragon" in lower_name:
		drop_id = "dragon_scale"
	else:
		drop_id = monster_drops[randi() % monster_drops.size()]
		
	var mat_scene = load("res://scenes/equipment/pickable_item.tscn")
	if mat_scene and enemy != null and enemy.get_parent() != null:
		var item_instance = mat_scene.instantiate()
		item_instance.material_id = drop_id
		_place_drop_before_add(item_instance, _drop_position() + Vector3(0, 0.4, 0))
		enemy.get_parent().add_child(item_instance)
		print("Monster defeated! Dropped material: ", drop_id)
	
	# 精英/Boss 额外掉落材料和符文
	if _is_elite_enemy():
		_spawn_elite_bonus_drop()

func freeze_ragdoll() -> void:
	transition_state(Enemy.State.DEAD)

func can_die() -> bool:
	return false

func can_get_hurt() -> bool:
	return false

func _blood_transform() -> Transform3D:
	if enemy != null and enemy.physical_bone_head != null:
		return enemy.physical_bone_head.global_transform
	return enemy.global_transform if enemy != null else Transform3D.IDENTITY

## 精英怪额外掉落：100% 掉落额外材料 + 符文
func _spawn_elite_bonus_drop() -> void:
	var bonus_drops = ["troll_blood", "soul_gem", "dragon_scale", "shadow_lotus", "fire_bloom"]
	var drop_id = bonus_drops[randi() % bonus_drops.size()]
	var mat_scene = load("res://scenes/equipment/pickable_item.tscn")
	if mat_scene and enemy != null and enemy.get_parent() != null:
		var item_instance = mat_scene.instantiate()
		item_instance.material_id = drop_id
		# 随机偏移避免与主掉落重叠
		var offset := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		_place_drop_before_add(item_instance, _drop_position() + Vector3(0, 0.4, 0) + offset)
		enemy.get_parent().add_child(item_instance)
		print("[Elite] Bonus drop: ", drop_id)
		var rune := RD.roll_rune("boss" if _is_boss_enemy() else "elite")
		if not rune.is_empty():
			var rune_item = mat_scene.instantiate()
			rune_item.rune_id = String(rune.get("id", ""))
			var rune_offset := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
			_place_drop_before_add(rune_item, _drop_position() + Vector3(0, 0.4, 0) + rune_offset)
			enemy.get_parent().add_child(rune_item)
			print("[Elite] Rune drop: ", rune_item.rune_id)


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
