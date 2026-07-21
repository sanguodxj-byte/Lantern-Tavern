class_name EnemyStateSlashing
extends EnemyState

const CB := preload("res://globals/combat/combat_bridge.gd")
const SLASH_ANIM := preload("res://globals/combat/combat_slash_animator.gd")

var has_emitted_damage := false
var hitbox: Area3D = null
var time_start_slash := Time.get_ticks_msec()
var slash_duration_msec := 440
var slash_animation_name := SLASH_ANIM.ANIMATION_NAME
var weapon_placeholder: Node3D = null
var weapon_placeholder_base := Transform3D.IDENTITY

func _enter_tree() -> void:
	var weapon = enemy.equipment.weapon_data if enemy.equipment != null and enemy.equipment.has_weapon() else null
	var animation_name := SLASH_ANIM.enemy_animation_name(weapon)
	slash_animation_name = animation_name if enemy.animation_player.has_animation(animation_name) else SLASH_ANIM.ANIMATION_NAME
	slash_duration_msec = SLASH_ANIM.play(enemy.animation_player, slash_animation_name, SLASH_ANIM.ENEMY_SPEED_SCALE)
	weapon_placeholder = enemy.equipment.weapon_placeholder if enemy.equipment != null else null
	if weapon_placeholder != null:
		weapon_placeholder_base = weapon_placeholder.transform
	hitbox = enemy.prepare_attack_hitbox(PhysicsSetup.LAYER_PLAYER)
	enemy.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(_delta: float) -> void:
	var slash_progress := SLASH_ANIM.progress(time_start_slash, slash_duration_msec)
	SLASH_ANIM.apply_weapon_arc(weapon_placeholder, weapon_placeholder_base, slash_progress, -1.0)
	var is_active := SLASH_ANIM.is_enemy_hit_active(slash_progress)
	if hitbox != null and is_instance_valid(hitbox):
		enemy.set_attack_hitbox_active(hitbox, is_active)
	if is_active:
		_resolve_hitbox_overlaps()
	elif slash_progress >= SLASH_ANIM.ENEMY_HIT_END and not has_emitted_damage:
		has_emitted_damage = true
		AudioManager.play("slash", enemy.action_audio_stream_player)

func on_animation_finished(anim_name: String) -> void:
	if anim_name != slash_animation_name or enemy.state_node != self:
		return
	SLASH_ANIM.restore_weapon_arc(weapon_placeholder, weapon_placeholder_base)
	if hitbox != null and is_instance_valid(hitbox):
		enemy.set_attack_hitbox_active(hitbox, false)
	transition_state(Enemy.State.MOVING)

func _exit_tree() -> void:
	if hitbox != null and is_instance_valid(hitbox):
		enemy.set_attack_hitbox_active(hitbox, false)
	if enemy != null and is_instance_valid(enemy) and enemy.animation_player != null:
		if enemy.animation_player.animation_finished.is_connected(on_animation_finished):
			enemy.animation_player.animation_finished.disconnect(on_animation_finished)

func _resolve_hitbox_overlaps() -> void:
	if hitbox == null or not is_instance_valid(hitbox):
		return
	for collider in hitbox.get_overlapping_bodies():
		var player := collider as Player
		if player == null:
			continue
		var weapon = enemy.equipment.weapon_data if enemy.equipment.has_weapon() else null
		var defender_attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
		var has_shield := player.equipment.has_shield()
		var result = CB.resolve_enemy_attack(enemy, player, weapon, defender_attrs, has_shield)
		if result.hit:
			player.try_receive_hit_result(enemy, result)
			has_emitted_damage = true
		else:
			AudioManager.play("slash-miss", enemy.action_audio_stream_player)
		if hitbox != null and is_instance_valid(hitbox):
			enemy.set_attack_hitbox_active(hitbox, false)
		return

func can_get_stunned() -> bool:
	return true
