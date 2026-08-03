class_name EnemyStateSlashing
extends EnemyState

const CB := preload("res://globals/combat/combat_bridge.gd")
const SLASH_ANIM := preload("res://globals/combat/combat_slash_animator.gd")
const ATTACK_PROFILE := preload("res://globals/combat/enemy_attack_profile.gd")

var has_emitted_damage := false
var hitbox: Area3D = null
var time_start_slash := Time.get_ticks_msec()
var slash_duration_msec := 440
var slash_animation_name := SLASH_ANIM.ANIMATION_NAME
var weapon_placeholder: Node3D = null
var weapon_placeholder_base := Transform3D.IDENTITY
var windup_elapsed := 0.0
var attack_windup_seconds := 0.5
var strike_started := false

## 攻击招式档案（enemy_attack_profile.gd）：动画/前摇/命中窗口/突进
var attack_profile: Dictionary = {}
var hit_start := SLASH_ANIM.ENEMY_HIT_START
var hit_end := SLASH_ANIM.ENEMY_HIT_END
var animation_speed_scale := SLASH_ANIM.ENEMY_SPEED_SCALE
var lunge_speed := 0.0
var body_sweep_rad := 0.0
var is_body_attack := false
## 身体横扫的视觉支点（非人形程序化横扫用，避免旋转物理根节点）
var _body_pivot: Node3D = null
var _body_pivot_base_yaw := 0.0

func _enter_tree() -> void:
	var weapon: WeaponData = enemy.get_attack_weapon()
	is_body_attack = enemy.attack_mode == Enemy.ATTACK_MODE_BODY or weapon == null
	_resolve_attack_profile(weapon)
	var animation_name := String(attack_profile.get("animation", ""))
	if animation_name.is_empty():
		animation_name = SLASH_ANIM.enemy_animation_name(weapon)
	slash_animation_name = animation_name if enemy.animation_player != null and enemy.animation_player.has_animation(animation_name) else SLASH_ANIM.ANIMATION_NAME
	attack_windup_seconds = maxf(float(attack_profile.get("windup", enemy.attack_windup_seconds)), 0.0)
	hit_start = float(attack_profile.get("hit_start", SLASH_ANIM.ENEMY_HIT_START))
	hit_end = float(attack_profile.get("hit_end", SLASH_ANIM.ENEMY_HIT_END))
	animation_speed_scale = float(attack_profile.get("speed_scale", SLASH_ANIM.ENEMY_SPEED_SCALE))
	lunge_speed = float(attack_profile.get("lunge", 0.0))
	body_sweep_rad = float(attack_profile.get("sweep", 0.0))
	_body_pivot = enemy.get_node_or_null("character") as Node3D
	if _body_pivot != null:
		_body_pivot_base_yaw = _body_pivot.rotation.y
	weapon_placeholder = enemy.equipment.weapon_placeholder if enemy.equipment != null else null
	if weapon_placeholder != null:
		weapon_placeholder_base = weapon_placeholder.transform
	hitbox = enemy.prepare_attack_hitbox(PhysicsSetup.LAYER_PLAYER)
	_play_windup_pose()
	if enemy.animation_player != null and not enemy.animation_player.animation_finished.is_connected(on_animation_finished):
		enemy.animation_player.animation_finished.connect(on_animation_finished)


## 解析攻击招式档案：非人形按怪物类型区分，人形按武器流派区分。
func _resolve_attack_profile(weapon: WeaponData) -> void:
	var enemy_type := enemy.get_enemy_type_id()
	attack_profile = ATTACK_PROFILE.profile_for_enemy(enemy_type, weapon, is_body_attack)


func _physics_process(delta: float) -> void:
	if not strike_started:
		windup_elapsed += delta
		var windup_progress := clampf(windup_elapsed / maxf(attack_windup_seconds, 0.001), 0.0, 1.0)
		SLASH_ANIM.apply_weapon_arc(weapon_placeholder, weapon_placeholder_base, windup_progress * hit_start, -1.0, hit_start, hit_end)
		_apply_body_sweep(windup_progress, 0.0)
		if windup_elapsed < attack_windup_seconds:
			return
		_start_strike()
	var slash_progress := SLASH_ANIM.progress(time_start_slash, slash_duration_msec)
	SLASH_ANIM.apply_weapon_arc(weapon_placeholder, weapon_placeholder_base, slash_progress, -1.0, hit_start, hit_end)
	_apply_body_sweep(0.0, slash_progress)
	var is_active := SLASH_ANIM.is_enemy_hit_active(slash_progress, hit_start, hit_end)
	if hitbox != null and is_instance_valid(hitbox):
		enemy.set_attack_hitbox_active(hitbox, is_active)
	if is_active:
		# 非人形突进招式（如史莱姆扑击）：命中窗口内朝玩家推进
		if lunge_speed > 0.0:
			_apply_lunge(delta)
		_resolve_hitbox_overlaps()
	elif slash_progress >= hit_end and not has_emitted_damage:
		has_emitted_damage = true
		AudioManager.play("slash", enemy.action_audio_stream_player)
	if slash_progress >= 1.0 and enemy.state_node == self:
		_finish_attack()

## 程序化身体横扫（如巨龙挥爪）：蓄力向一侧侧摆（windup 阶段），
## 命中窗口内挥过中线到另一侧，收势回正。rig 动画较弱时补偿横扫视觉。
func _apply_body_sweep(windup_progress: float, slash_progress: float) -> void:
	if body_sweep_rad <= 0.001 or _body_pivot == null:
		return
	var sweep := body_sweep_rad
	var yaw := _body_pivot_base_yaw
	if slash_progress <= 0.001:
		# 蓄力：从回正侧摆到 -sweep
		yaw = _body_pivot_base_yaw + lerpf(0.0, -sweep, clampf(windup_progress, 0.0, 1.0))
	else:
		# 挥击：从 -sweep 经中线挥到 +sweep，收势回正
		var strike := clampf((slash_progress - hit_start) / maxf(hit_end - hit_start, 0.01), 0.0, 1.0)
		var recover := clampf((slash_progress - hit_end) / maxf(1.0 - hit_end, 0.01), 0.0, 1.0)
		if slash_progress < hit_start:
			yaw = _body_pivot_base_yaw + lerpf(-sweep, 0.0, strike)
		elif slash_progress <= hit_end:
			yaw = _body_pivot_base_yaw + lerpf(-sweep, sweep, strike)
		else:
			yaw = _body_pivot_base_yaw + lerpf(sweep, 0.0, recover)
	_body_pivot.rotation.y = yaw

## 突进：朝已登记玩家方向推进（仅攻击窗口内，避免穿墙）。
func _apply_lunge(delta: float) -> void:
	if not enemy.has_registered_player() or not is_instance_valid(enemy.player):
		return
	var to_player := enemy.player.global_position - enemy.global_position
	to_player.y = 0.0
	if to_player.length_squared() <= 0.0001:
		return
	var direction := to_player.normalized()
	enemy.global_position += direction * lunge_speed * delta

func _play_windup_pose() -> void:
	if enemy.animation_player == null:
		return
	# 非人形身体攻击用待机姿态蓄力，人形武器攻击保持持械姿态
	if is_body_attack:
		if enemy.animation_player.has_animation("idle"):
			enemy.animation_player.play("idle", SLASH_ANIM.BLEND_SEC)
		return
	var pose := "hold_weapon" if enemy.animation_player.has_animation("hold_weapon") else "idle"
	enemy.animation_player.play(pose, SLASH_ANIM.BLEND_SEC)

func _start_strike() -> void:
	if strike_started:
		return
	strike_started = true
	SLASH_ANIM.restore_weapon_arc(weapon_placeholder, weapon_placeholder_base)
	time_start_slash = Time.get_ticks_msec()
	slash_duration_msec = SLASH_ANIM.play(enemy.animation_player, slash_animation_name, animation_speed_scale)

func _finish_attack() -> void:
	SLASH_ANIM.restore_weapon_arc(weapon_placeholder, weapon_placeholder_base)
	_restore_body_pivot()
	if hitbox != null and is_instance_valid(hitbox):
		enemy.set_attack_hitbox_active(hitbox, false)
	if enemy.state_node == self:
		transition_state(Enemy.State.MOVING)

func _restore_body_pivot() -> void:
	if _body_pivot != null and is_instance_valid(_body_pivot):
		_body_pivot.rotation.y = _body_pivot_base_yaw

func on_animation_finished(anim_name: String) -> void:
	if not strike_started or anim_name != slash_animation_name or enemy.state_node != self:
		return
	_finish_attack()

func _exit_tree() -> void:
	_restore_body_pivot()
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
		var weapon: WeaponData = enemy.get_attack_weapon()
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
