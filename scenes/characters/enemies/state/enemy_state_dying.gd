class_name EnemyStateDying
extends EnemyState

const DURATION_RAGDOLL_SIMULATION := 3.0

func _enter_tree() -> void:
	enemy.health.current_life = 0
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
	FxHelper.create_blood_fx(enemy.physical_bone_head.global_transform)	
	AudioManager.play("orc-die", enemy.vocal_audio_stream_player)
	enemy.healthbar.visible = false
	enemy.dead.emit(enemy.global_transform)
	enemy.equipment.drop_weapon()
	enemy.equipment.drop_shield()
	enemy.presence_light.visible = false
	enemy.collision_shape.disabled = true
	enemy.skeleton_simulator.active = true
	enemy.skeleton_simulator.physical_bones_start_simulation()
	enemy.physical_bone_torso.apply_impulse(state_data.impulse)
	
	# Spawn dynamic monster drop on death!
	_spawn_monster_drop()
	
	var timer := get_tree().create_timer(DURATION_RAGDOLL_SIMULATION)
	timer.timeout.connect(freeze_ragdoll)

func _spawn_monster_drop() -> void:
	var monster_drops = [
		"goblin_ear", "spider_poison_sac", "slime_jelly", "bat_wing",
		"boar_tusk", "skeleton_dust", "giant_rat_tail", "imp_horn_dust",
		"troll_blood", "zombie_flesh", "harpy_feather"
	]
	
	var drop_id = ""
	var lower_name = enemy.name.to_lower()
	if "goblin" in lower_name:
		drop_id = "goblin_ear"
	elif "spider" in lower_name:
		drop_id = "spider_poison_sac"
	elif "slime" in lower_name:
		drop_id = "slime_jelly"
	elif "kobold" in lower_name:
		drop_id = "boar_tusk"
	else:
		drop_id = monster_drops[randi() % monster_drops.size()]
		
	var mat_scene = load("res://scenes/equipment/pickable_item.tscn")
	if mat_scene:
		var item_instance = mat_scene.instantiate()
		item_instance.material_id = drop_id
		item_instance.global_position = enemy.global_position + Vector3(0, 0.4, 0)
		enemy.get_parent().add_child(item_instance)
		print("Monster defeated! Dropped material: ", drop_id)

func freeze_ragdoll() -> void:
	transition_state(Enemy.State.DEAD)

func can_die() -> bool:
	return false
