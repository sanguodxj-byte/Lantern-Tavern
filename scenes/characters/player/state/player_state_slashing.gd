class_name PlayerStateSlashing
extends PlayerState

const WEAPON_CONDITION_WEAR := 2

const CB := preload("res://globals/combat/combat_bridge.gd")
const ME := preload("res://globals/combat/milestone_effects.gd")
const SPE := preload("res://globals/combat/style_passive_effects.gd")
const SLASH_ANIM := preload("res://globals/combat/combat_slash_animator.gd")
const FP_VISUAL_STATE_MACHINE := preload("res://scenes/characters/player/first_person_weapon_visual_state_machine.gd")
const REH := preload("res://globals/combat/rune_effect_hooks.gd")
const RWPH := preload("res://globals/combat/rune_word_passive_hooks.gd")
const SES := preload("res://globals/combat/status_effect_system.gd")
const PLAYER_ANIMATION_PROFILE := preload("res://globals/visual/player_animation_profile.gd")

## B3 挥砍移动限制：重武器（巨剑/斧/战锤/长矛）挥砍期间压低移动速度，轻武器不限制。
## 仅作用于本地移动积分，不改输入、不冻结敌人、不影响联机权威。
const SLASH_MOVE_MULT_HEAVY := 0.55
const SLASH_MOVE_MULT_LIGHT := 1.0
const HEAVY_SLASH_PROFILES: Array[StringName] = [&"greatsword", &"axe", &"warhammer", &"spear"]

var has_emitted_damage := false
var hitbox: Area3D = null
var hit_targets: Array[Node] = []
var time_start_slash := Time.get_ticks_msec()
var slash_duration_msec := 400
var slash_animation_name := SLASH_ANIM.ANIMATION_NAME
var weapon_placeholder: Node3D = null
var weapon_placeholder_base := Transform3D.IDENTITY
var heavy_swing_enabled := false
var heavy_swing_arc_angle_deg := 0.0

func _enter_tree() -> void:
	var weapon := player.get_active_hand_weapon_data()
	time_start_slash = Time.get_ticks_msec()
	heavy_swing_enabled = player.has_method("should_use_heavy_swing_animation") \
		and player.should_use_heavy_swing_animation()
	var animation_name := SLASH_ANIM.player_animation_name(weapon, heavy_swing_enabled)
	slash_animation_name = animation_name if player.animation_player.has_animation(animation_name) else SLASH_ANIM.ANIMATION_NAME
	slash_duration_msec = SLASH_ANIM.play(player.animation_player, slash_animation_name, SLASH_ANIM.PLAYER_SPEED_SCALE)
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("begin_weapon_release"):
		player.view_model.begin_weapon_release(
			player.view_model.resolve_melee_action(weapon, heavy_swing_enabled)
		)
	# 触发近战攻击冷却（仅近战武器走此状态）
	player.start_melee_cooldown(state_data.weapon_attack_hand)
	if player.equipment != null:
		if player.equipment.has_method("get_active_weapon_placeholder"):
			weapon_placeholder = player.equipment.get_active_weapon_placeholder()
		else:
			weapon_placeholder = player.equipment.weapon_placeholder
	if weapon_placeholder != null:
		weapon_placeholder_base = weapon_placeholder.transform
	if heavy_swing_enabled:
		var heavy_params := SPE.get_heavy_swing_params()
		heavy_swing_arc_angle_deg = float(heavy_params.get("arc_angle_deg", 0.0))
		var radius_mult := float(heavy_params.get("radius_mult", 1.0))
		hitbox = player.prepare_attack_hitbox(
			PhysicsSetup.LAYER_ENEMY | PhysicsSetup.LAYER_SCENE_OBJECT,
			radius_mult
		)
	else:
		hitbox = player.prepare_attack_hitbox(PhysicsSetup.LAYER_ENEMY | PhysicsSetup.LAYER_SCENE_OBJECT)
	player.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(delta: float) -> void:
	# B3: 重武器挥砍期间移速降低（移动积分倍率），轻武器为 1.0 不受影响。
	player.process_movement(delta, slash_move_multiplier_for(player.get_active_hand_weapon_data()))
	var slash_progress := SLASH_ANIM.progress(time_start_slash, slash_duration_msec)
	SLASH_ANIM.apply_weapon_arc(weapon_placeholder, weapon_placeholder_base, slash_progress, 1.0)
	# Visual sampling only: CombatSlashAnimator remains the authority for timing/hits.
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("sample_action"):
		player.view_model.sample_action(
			player.view_model.resolve_melee_action(
				player.get_active_hand_weapon_data(), heavy_swing_enabled
			),
			slash_progress
		)
	var is_active := SLASH_ANIM.is_player_hit_active(slash_progress)
	if hitbox != null and is_instance_valid(hitbox):
		player.set_attack_hitbox_active(hitbox, is_active)
	if is_active:
		if not has_emitted_damage:
			has_emitted_damage = true
			AudioManager.play("slash", player.action_audio_stream_player)
		_resolve_hitbox_overlaps()

func on_animation_finished(anim_name: String) -> void:
	if anim_name != slash_animation_name or player.state_node != self:
		return
	SLASH_ANIM.restore_weapon_arc(weapon_placeholder, weapon_placeholder_base)
	if player.view_model != null and is_instance_valid(player.view_model):
		if player.view_model.has_method("finish_weapon_release"):
			player.view_model.finish_weapon_release()
		elif player.view_model.has_method("stop_action"):
			player.view_model.stop_action(true)
	if hitbox != null and is_instance_valid(hitbox):
		player.set_attack_hitbox_active(hitbox, false)
	if player != null and is_instance_valid(player) and player.animation_player != null:
		if player.animation_player.animation_finished.is_connected(on_animation_finished):
			player.animation_player.animation_finished.disconnect(on_animation_finished)
	transition_state(Player.State.MOVING)

func _exit_tree() -> void:
	if player != null and player.view_model != null and is_instance_valid(player.view_model):
		if player.view_model.has_method("get_visual_weapon_state") and player.view_model.has_method("cancel_weapon_hold"):
			if player.view_model.get_visual_weapon_state() == FP_VISUAL_STATE_MACHINE.State.RELEASING:
				player.view_model.cancel_weapon_hold()
		if player.view_model.has_method("stop_action"):
			player.view_model.stop_action(true)
	if hitbox != null and is_instance_valid(hitbox):
		player.set_attack_hitbox_active(hitbox, false)

func _resolve_hitbox_overlaps() -> void:
	if hitbox == null or not is_instance_valid(hitbox):
		return
	for collider in hitbox.get_overlapping_bodies():
		var body := collider as Node
		if body == null or hit_targets.has(body):
			continue
		if not _is_inside_heavy_swing_arc(body):
			continue
		hit_targets.append(body)
		var enemy := body as Enemy
		if enemy != null:
			_resolve_enemy_hit(enemy)
		elif collider != null and collider.has_method("try_receive_hit"):
			player.equipment.apply_weapon_damage(WEAPON_CONDITION_WEAR)
			var cm := _charge_multiplier()
			body.try_receive_hit(player, int(round(1 * cm)))
			has_emitted_damage = true

func _is_inside_heavy_swing_arc(body: Node) -> bool:
	if not heavy_swing_enabled or heavy_swing_arc_angle_deg <= 0.0 or not body is Node3D:
		return true
	var offset := (body as Node3D).global_position - player.global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.0001:
		return true
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return true
	var angle := rad_to_deg(acos(clampf(forward.normalized().dot(offset.normalized()), -1.0, 1.0)))
	return angle <= heavy_swing_arc_angle_deg * 0.5

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
	var style_ctx: Dictionary = player.get_style_context() if player.has_method("get_style_context") else {}
	var result = CB.resolve_player_attack(player, enemy, weapon, main_type, off_type, attrs, level, is_back, {}, style_ctx)
	# 伤害倍率组合（一次挥砍仅消费一次，避免对多敌重复叠加）：
	#   近战蓄力 ×1.0~2.0（doc21 #1）  ×  完美格挡·增伤 ×1.5（doc21 #6）  ×  残影 ×1.3（doc21 #7）
	# 完美格挡 / 残影 buff 仅在本次攻击命中成功时消费，miss 不消耗（留待下次命中）
	var dmg_mult := _charge_multiplier()
	if result.hit:
		if player.consume_perfect_block_buff():
			dmg_mult *= player.PERFECT_BLOCK_BUFF_MULT
		if player.consume_sidestep_buff():
			dmg_mult *= player.SIDESTEP_BUFF_MULT
	if dmg_mult != 1.0:
		result.final_damage = int(round(result.final_damage * dmg_mult))
		result.knockback_force = result.knockback_force * dmg_mult
	if result.hit:
		player.equipment.apply_weapon_damage(WEAPON_CONDITION_WEAR)
		# 符文之语伤害倍率与状态效果受击增伤
		var rune_mult := RWPH.get_outgoing_damage_mult(player, enemy) * SES.get_incoming_damage_mult(enemy)
		if rune_mult != 1.0:
			result.final_damage = maxi(1, int(round(float(result.final_damage) * rune_mult)))
		enemy.try_receive_hit_result(player, result)
		# 触发符文机制与符文之语被动
		var hit_pos: Vector3 = enemy.global_position
		REH.on_player_hit_enemy(player, enemy, hit_pos, int(result.final_damage))
		RWPH.on_player_hit_enemy(player, enemy, hit_pos, int(result.final_damage))
		# 检查敌人是否因本次命中死亡
		var ehealth = enemy.get("health")
		if ehealth != null and is_instance_valid(ehealth) and int(ehealth.get("current_life")) <= 0:
			RWPH.on_enemy_killed(player, enemy, hit_pos)
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

func _get_off_hand_type() -> String:
	if state_data.weapon_attack_hand == "secondary" and player.can_dual_wield_attack_with_active_equipment():
		return CB.get_weapon_class(player.get_active_hand_weapon_data())
	return "shield" if player.equipment.has_shield() else ""

## 本次挥砍的蓄力伤害倍率（未装备蓄力被动则为 1.0，无增伤）
func _charge_multiplier() -> float:
	return player.get_melee_charge_multiplier(state_data.weapon_charge_ratio)

## B3 挥砍移动系数：重武器（巨剑/斧/战锤/长矛）挥砍期间压低移速（0.55），
## 轻武器与空手不限制（1.0）。纯函数便于测试，不访问节点树。
static func slash_move_multiplier_for(weapon: Variant) -> float:
	if weapon != null and PLAYER_ANIMATION_PROFILE.profile_for_weapon(weapon) in HEAVY_SLASH_PROFILES:
		return SLASH_MOVE_MULT_HEAVY
	return SLASH_MOVE_MULT_LIGHT
