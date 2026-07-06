class_name PlayerStateSlashing
extends PlayerState

const WEAPON_CONDITION_WEAR := 2
const ATTR_EXP_PER_HIT := 5
const PROFICIENCY_PER_HIT := 1

const CB := preload("res://globals/combat/combat_bridge.gd")
const ME := preload("res://globals/combat/milestone_effects.gd")
const SLASH_ANIM := preload("res://globals/combat/combat_slash_animator.gd")

var has_emitted_damage := false
var hitbox: Area3D = null
var hit_targets: Array[Node] = []
var time_start_slash := Time.get_ticks_msec()
var slash_duration_msec := 400
var weapon_placeholder: Node3D = null
var weapon_placeholder_base := Transform3D.IDENTITY

func _enter_tree() -> void:
	var weapon := player.get_active_hand_weapon_data()
	var animation_name := SLASH_ANIM.player_animation_name(weapon)
	slash_duration_msec = SLASH_ANIM.play(player.animation_player, animation_name, SLASH_ANIM.PLAYER_SPEED_SCALE)
	weapon_placeholder = player.equipment.weapon_placeholder if player.equipment != null else null
	if weapon_placeholder != null:
		weapon_placeholder_base = weapon_placeholder.transform
	hitbox = player.prepare_attack_hitbox(PhysicsSetup.LAYER_ENEMY | PhysicsSetup.LAYER_SCENE_OBJECT)
	player.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(delta: float) -> void:
	player.process_movement(delta)
	var slash_progress := SLASH_ANIM.progress(time_start_slash, slash_duration_msec)
	SLASH_ANIM.apply_weapon_arc(weapon_placeholder, weapon_placeholder_base, slash_progress)
	# 同步第一人称视图模型挥砍弧线
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("apply_slash_arc"):
		player.view_model.apply_slash_arc(slash_progress)
	var is_active := SLASH_ANIM.is_player_hit_active(slash_progress)
	if hitbox != null and is_instance_valid(hitbox):
		player.set_attack_hitbox_active(hitbox, is_active)
	if is_active:
		_resolve_hitbox_overlaps()
	elif slash_progress >= SLASH_ANIM.PLAYER_HIT_END and not has_emitted_damage:
		has_emitted_damage = true
		AudioManager.play("slash", player.action_audio_stream_player)

func on_animation_finished(_anim_name: String) -> void:
	SLASH_ANIM.restore_weapon_arc(weapon_placeholder, weapon_placeholder_base)
	# 恢复视图模型到默认位置
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("restore_transform"):
		player.view_model.restore_transform()
	if hitbox != null and is_instance_valid(hitbox):
		player.set_attack_hitbox_active(hitbox, false)
	transition_state(Player.State.MOVING)

func _exit_tree() -> void:
	if hitbox != null and is_instance_valid(hitbox):
		player.set_attack_hitbox_active(hitbox, false)

func _resolve_hitbox_overlaps() -> void:
	if hitbox == null or not is_instance_valid(hitbox):
		return
	for collider in hitbox.get_overlapping_bodies():
		var body := collider as Node
		if body == null or hit_targets.has(body):
			continue
		hit_targets.append(body)
		var enemy := body as Enemy
		if enemy != null:
			_resolve_enemy_hit(enemy)
		elif collider != null and collider.has_method("try_receive_hit"):
			player.equipment.apply_weapon_damage(WEAPON_CONDITION_WEAR)
			body.try_receive_hit(player, 1)
			has_emitted_damage = true

func _resolve_enemy_hit(enemy: Enemy) -> void:
	var weapon = player.get_active_hand_weapon_data()
	var attrs := _get_player_attrs()
	var level := _get_player_level()
	var main_type := CB.get_weapon_class(weapon)
	var off_type := _get_off_hand_type()
	var atk_forward := -player.global_transform.basis.z.normalized()
	var def_forward := -enemy.global_transform.basis.z.normalized()
	var is_back := CB.is_backstab(atk_forward, def_forward)
	if ME.negate_flank_bonus():
		is_back = false
	var result = CB.resolve_player_attack(player, enemy, weapon, main_type, off_type, attrs, level, is_back)
	if result.hit:
		player.equipment.apply_weapon_damage(WEAPON_CONDITION_WEAR)
		enemy.try_receive_hit_result(player, result)
		_accumulate_combat_exp(CB.get_weapon_proficiency_key(weapon), result.attack_type)
		has_emitted_damage = true
	else:
		AudioManager.play("slash-miss", player.action_audio_stream_player)

func _get_player_attrs() -> Dictionary:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		return ap.get_player_attrs()
	return {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}

func _get_player_level() -> int:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		return ap.get_level()
	return 1

func _accumulate_combat_exp(proficiency_key: String, attack_type: String) -> void:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap == null:
		return
	match attack_type:
		"melee":
			ap.accumulate_attr("str", ATTR_EXP_PER_HIT)
		"ranged":
			ap.accumulate_attr("dex", ATTR_EXP_PER_HIT)
		"spell":
			ap.accumulate_attr("mag", ATTR_EXP_PER_HIT)
		_:
			ap.accumulate_attr("str", ATTR_EXP_PER_HIT)
	ap.accumulate_proficiency(proficiency_key if proficiency_key != "" else "unarmed", PROFICIENCY_PER_HIT)
	ap.check_skill_unlocks()

func _get_off_hand_type() -> String:
	if state_data.weapon_attack_hand == "secondary" and player.can_dual_wield_attack_with_active_equipment():
		return CB.get_weapon_class(player.get_active_hand_weapon_data())
	return "shield" if player.equipment.has_shield() else ""
