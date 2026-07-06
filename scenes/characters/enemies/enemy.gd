class_name Enemy
extends CharacterBody3D

signal dead(death_transform: Transform3D)
signal screamed

const AIR_FRICTION := 20.0
const DURATION_RAGDOLL_SIMULATION := 3.0
const GRAVITY := 20.0
const PHYSICAL_IMPACT_COOLDOWN_MSEC := 350
const HITBOX_BUILDER := preload("res://globals/combat/combat_hitbox_builder.gd")
const CE_LIB := preload("res://globals/combat/combat_engine.gd")

@onready var action_audio_stream_player: AudioStreamPlayer3D = %ActionAudioStreamPlayer
@onready var animation_player: AnimationPlayer = $character/AnimationPlayer
@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var equipment: EquipmentComponent = %EquipmentComponent
@onready var health: HealthComponent = %HealthComponent
@onready var healthbar: Sprite3D = %Healthbar
@onready var health_indicator: StatIndicator = %HealthIndicator
@onready var nav_agent: NavigationAgent3D = %NavigationAgent3D
@onready var skeleton_simulator: PhysicalBoneSimulator3D = %PhysicalBoneSimulator3D
@onready var physical_bone_head: PhysicalBone3D = %"Physical Bone Head"
@onready var physical_bone_torso: PhysicalBone3D = %"Physical Bone Torso"
@onready var player_detection_area: Area3D = %PlayerDetectionArea
@onready var presence_light: OmniLight3D = %PresenceLight
@onready var vocal_audio_stream_player: AudioStreamPlayer3D = %VocalAudioStreamPlayer
@onready var weapon_reach_raycast: RayCast3D = %WeaponReachRaycast

@export var duration_between_attacks: int
@export var duration_stun : int
@export var player: Player
@export var speed: float
@export var is_elite: bool = false
@export var is_boss_type: bool = false
@export_enum("small", "medium", "large", "huge") var body_size: String = "medium"
## 巡逻半径（米），无玩家时在此范围内随机巡逻
@export var patrol_radius: float = 5.0

enum State {MOVING, IMPALING, DYING, DEAD, SLASHING, HURT, BLOCKING, STUNNED}

var pushback_force := Vector3.ZERO
var state: State
var state_node: EnemyState
var time_since_last_attack: int
var combat_debuffs: Dictionary = {}
var physical_impact_enabled: bool = false
var physical_impact_damage_mult: float = 1.0
var physical_impact_min_speed: float = 4.0
var physical_impact_full_speed: float = 14.0
var physical_impact_target_profile: Dictionary = {}
var _last_physical_impact_msec: int = -100000
## 出生位置，巡逻时以此为中心
var spawn_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	PhysicsSetup.setup_enemy(self)
	add_to_group("enemies")
	player_detection_area.body_entered.connect(on_player_detected)
	_apply_spawner_multipliers()
	health_indicator.refresh(health.current_life, health.max_life)
	switch_state(State.MOVING)

## 应用 DungeonSpawner 通过 meta 注入的属性倍率（hp_mult / speed_mult / dmg_mult）
func _apply_spawner_multipliers() -> void:
	if has_meta("hp_mult"):
		var hp_mult: float = float(get_meta("hp_mult", 1.0))
		health.max_life = int(health.max_life * hp_mult)
		health.current_life = health.max_life
	if has_meta("speed_mult"):
		var spd_mult: float = float(get_meta("speed_mult", 1.0))
		speed *= spd_mult
	if has_meta("is_boss_type"):
		is_boss_type = bool(get_meta("is_boss_type", false))
	if has_meta("body_size"):
		body_size = String(get_meta("body_size", "medium"))
	# 精英怪发光颜色变红、范围更大
	if is_elite and is_instance_valid(presence_light):
		presence_light.light_color = Color(1.0, 0.3, 0.2)
		presence_light.light_energy = 2.5
		presence_light.omni_range = 3.5

func _process(delta: float) -> void:
	_tick_combat_debuffs(delta)

func prepare_attack_hitbox(target_mask: int) -> Area3D:
	var attach_to := _get_active_attack_hitbox_parent()
	return HITBOX_BUILDER.ensure_hitbox(self, attach_to, _get_active_attack_reach(), target_mask)

func set_attack_hitbox_active(hitbox: Area3D, active: bool) -> void:
	HITBOX_BUILDER.set_active(hitbox, active)

func _get_active_attack_hitbox_parent() -> Node3D:
	if equipment == null or equipment.weapon_placeholder == null:
		return null
	if equipment.weapon_placeholder.get_child_count() == 0:
		return null
	return equipment.weapon_placeholder.get_child(0) as Node3D

func _get_active_attack_reach() -> float:
	if weapon_reach_raycast != null:
		return maxf(absf(weapon_reach_raycast.target_position.z), 0.8)
	var weapon := equipment.weapon_data if equipment != null and equipment.has_weapon() else null
	return maxf(weapon.reach, 0.8) if weapon != null else 1.2
	
func switch_state(new_state: State, data: EnemyStateData = EnemyStateData.new()) -> void:
	if state_node != null:
		state_node.queue_free()
	var state_map := {
		State.BLOCKING: EnemyStateBlocking,
		State.DEAD: EnemyStateDead,
		State.DYING: EnemyStateDying,
		State.HURT: EnemyStateHurt,
		State.IMPALING: EnemyStateImpaling,
		State.MOVING: EnemyStateMoving,
		State.SLASHING: EnemyStateSlashing,
		State.STUNNED: EnemyStateStunned,
	}
	state_node = state_map[new_state].new(self, data)
	state_node.transition_requested.connect(switch_state)
	state_node.name = "State: " + State.keys()[new_state]
	state = new_state
	add_child(state_node)

func impale(thrown_item: ThrownItem, item_basis: Basis) -> void:
	var state_data := EnemyStateData.new().set_thrown_item(thrown_item).set_thrown_item_basis(item_basis)
	if state_node.can_get_hurt():
		switch_state(State.IMPALING, state_data)
	else:
		var hit_direction := thrown_item.global_position.direction_to(global_position)
		state_data.set_impact_direction(hit_direction)
		switch_state(State.BLOCKING, state_data)
	screamed.emit()

func try_receive_furniture_impact(thrown_item: ThrownItem) -> void:
	if equipment.has_shield():
		equipment.drop_shield()
		var hit_direction := thrown_item.global_position.direction_to(global_position)
		var data := EnemyStateData.new().set_impact_direction(hit_direction).set_knockback_force(2.5)
		switch_state(State.STUNNED, data)
	else:
		switch_state(State.DYING)

func try_receive_thrown_enemy_impact(source_enemy: Enemy, source_player: Player = null) -> void:
	if source_player != null:
		player = source_player
	screamed.emit()
	var hit_direction := source_enemy.global_position.direction_to(global_position) if source_enemy != null else Vector3.ZERO
	var data := EnemyStateData.new().set_damage(6).set_impact_direction(hit_direction).set_knockback_force(5.0)
	if equipment.has_shield():
		equipment.drop_shield()
		switch_state(State.STUNNED, data)
	else:
		switch_state(State.HURT, data)

func has_registered_player() -> bool:
	return player != null and is_instance_valid(player)

func is_player_within_reach() -> bool:
	if has_registered_player() and equipment.has_weapon():
		return weapon_reach_raycast.is_colliding()
	return false

func try_receive_hit(source_player: Player, damage: int) -> void:
	player = source_player
	screamed.emit()
	var hit_direction := source_player.global_position.direction_to(global_position)
	var data := EnemyStateData.new().set_damage(damage).set_impact_direction(hit_direction)
	if state_node.can_get_hurt():
		switch_state(State.HURT, data)
	else:
		switch_state(State.BLOCKING, data)

## ARPG 战斗结算入口：接受 CombatEngine.DamageResult（含向量击退/秒眩晕/最终伤害）
## 由 CombatBridge.resolve_player_attack 产出，替换原 try_receive_hit 的硬编码 damage
func try_receive_hit_result(source_player: Player, result) -> void:
	player = source_player
	screamed.emit()
	var hit_direction := source_player.global_position.direction_to(global_position)
	# 若 result 含向量击退冲量，优先使用其方向
	var impact_dir := hit_direction
	if result.knockback_impulse != Vector3.ZERO:
		impact_dir = result.knockback_impulse.normalized()
	var data := EnemyStateData.new()
	data.set_damage(result.final_damage)
	data.set_impact_direction(impact_dir)
	# ARPG 实时击退力（米/秒），由 DamageResult.knockback_force 提供
	data.set_knockback_force(result.knockback_force)
	physical_impact_enabled = bool(result.physical_impact_enabled)
	physical_impact_damage_mult = float(result.physical_impact_damage_mult)
	physical_impact_min_speed = float(result.physical_impact_min_speed)
	physical_impact_full_speed = float(result.physical_impact_full_speed)
	physical_impact_target_profile = get_physical_impact_target_profile()
	# 动作控制版：格挡由状态机判定（can_get_hurt = false → BLOCKING 状态），
	# 不再有概率格挡投骰。格挡反馈由 EnemyStateBlocking._enter_tree 播放。
	# 穿透格挡的攻击（ignores_block）无视格挡状态，直接造成伤害。
	# ARPG 秒数眩晕：若 result.stun_duration > 0，进入 STUNNED 状态
	if state_node.can_get_hurt() or result.ignores_block:
		if result.stun_duration > 0.0 and state_node.can_get_stunned():
			# 临时改写 duration_stun 为秒数对应的毫秒（EnemyStateStunned 用 Time.get_ticks_msec 比对）
			# 策划案 ARPG 化：stun_duration 单位为秒，转毫秒供现有计时逻辑使用
			duration_stun = int(result.stun_duration * 1000.0)
			switch_state(State.STUNNED, data)
		else:
			switch_state(State.HURT, data)
	else:
		switch_state(State.BLOCKING, data)

func try_receive_kick(source_player: Player) -> void:
	player = source_player
	screamed.emit()
	var hit_direction := source_player.global_position.direction_to(global_position)
	var data := EnemyStateData.new().set_impact_direction(hit_direction)
	if state_node.can_get_stunned() or not equipment.has_shield():
		if state == State.STUNNED:
			data.set_knockback_force(2.5)
		switch_state(State.STUNNED, data)
	else:
		switch_state(State.BLOCKING, data)

func try_stun() -> void:
	if state_node.can_get_stunned():
		switch_state(State.STUNNED)

func process_movement(delta: float) -> void:
	process_gravity(delta)
	process_pushback(delta)
	var impact_velocity := velocity
	move_and_slide()
	_check_physical_impact_damage(impact_velocity)
	_check_thrown_enemy_collision()

func process_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

func process_pushback(delta: float) -> void:
	pushback_force = pushback_force.move_toward(Vector3.ZERO, delta * AIR_FRICTION)
	velocity += pushback_force

func _check_thrown_enemy_collision() -> void:
	if not has_meta("is_thrown") or bool(get_meta("thrown_enemy_collision_resolved", false)):
		return
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		var body := collision.get_collider()
		if body is Enemy and body != self:
			set_meta("thrown_enemy_collision_resolved", true)
			call_deferred("_resolve_thrown_enemy_collision", body)
			return
	if velocity.length() < 0.5:
		_clear_thrown_enemy_meta()

func _resolve_thrown_enemy_collision(body: Node) -> void:
	if not is_instance_valid(self):
		return
	var source_player := get_meta("throw_source_player", null) as Player
	_clear_thrown_enemy_meta()
	if body is Enemy and is_instance_valid(body):
		(body as Enemy).try_receive_thrown_enemy_impact(self, source_player)

func _clear_thrown_enemy_meta() -> void:
	for key in ["is_thrown", "throw_velocity", "throw_source_player", "thrown_enemy_collision_resolved"]:
		if has_meta(key):
			remove_meta(key)

func _check_physical_impact_damage(impact_velocity: Vector3) -> void:
	if not physical_impact_enabled:
		return
	if Time.get_ticks_msec() - _last_physical_impact_msec < PHYSICAL_IMPACT_COOLDOWN_MSEC:
		return
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		var body := collision.get_collider()
		if not _is_physical_impact_collider(body):
			continue
		var normal := collision.get_normal()
		if normal.y > 0.65:
			continue
		var incoming_speed := maxf(impact_velocity.dot(-normal), 0.0)
		var damage := CE_LIB.compute_physical_impact_damage(
			health.max_life,
			incoming_speed,
			physical_impact_min_speed,
			physical_impact_full_speed,
			physical_impact_damage_mult,
			physical_impact_target_profile
		)
		if damage <= 0:
			continue
		_last_physical_impact_msec = Time.get_ticks_msec()
		_apply_physical_impact_damage(damage, normal)
		return

func _is_physical_impact_collider(body: Object) -> bool:
	if body == null or body == self:
		return false
	if body is Player or body is Enemy:
		return false
	return body is StaticBody3D or body is AnimatableBody3D or body is RigidBody3D or body is CharacterBody3D

func _apply_physical_impact_damage(damage: int, normal: Vector3) -> void:
	health.take_damage(damage)
	health_indicator.refresh(health.current_life, health.max_life)
	physical_impact_enabled = false
	if health.is_dead() and state_node.can_die():
		var impact_dir := -normal.normalized()
		var data := EnemyStateData.new().set_impulse(impact_dir * 120.0 + Vector3.UP * 80.0)
		switch_state(State.DYING, data)

func get_physical_impact_target_profile() -> Dictionary:
	var rank_mult := 1.0
	if is_boss_type or bool(get_meta("is_boss", false)) or bool(get_meta("is_boss_type", false)):
		rank_mult = 0.65
	elif is_elite or bool(get_meta("is_elite", false)):
		rank_mult = 0.85
	var size_profile := _body_size_impact_profile()
	return {
		"rank": "boss" if rank_mult < 0.7 else ("elite" if rank_mult < 1.0 else "normal"),
		"body_size": body_size,
		"impact_damage_taken_mult": rank_mult * float(size_profile.get("impact_damage_taken_mult", 1.0)),
		"impact_min_speed_add": float(size_profile.get("impact_min_speed_add", 0.0)),
	}

func _body_size_impact_profile() -> Dictionary:
	match body_size:
		"small":
			return {"impact_damage_taken_mult": 1.10, "impact_min_speed_add": -0.5}
		"large":
			return {"impact_damage_taken_mult": 0.80, "impact_min_speed_add": 1.0}
		"huge":
			return {"impact_damage_taken_mult": 0.60, "impact_min_speed_add": 2.0}
		_:
			return {"impact_damage_taken_mult": 1.0, "impact_min_speed_add": 0.0}

func apply_combat_debuff(debuff_type: String, duration_sec: float, value: Variant) -> void:
	if debuff_type == "" or duration_sec <= 0.0:
		return
	combat_debuffs[debuff_type] = {"remaining": duration_sec, "value": value}

func get_combat_speed_multiplier() -> float:
	var mult := float(get_meta("environment_activity_mult", 1.0))
	for debuff_type in combat_debuffs.keys():
		var value = combat_debuffs[debuff_type].get("value", 0)
		match debuff_type:
			"slow", "ground_ice":
				mult *= 1.0 - float(value) / 100.0
			"slow_and_haste":
				if typeof(value) == TYPE_DICTIONARY:
					mult *= 1.0 - float(value.get("slow_target", 0.0)) / 100.0
			"root_and_dmg_down":
				if typeof(value) == TYPE_DICTIONARY and bool(value.get("root", false)):
					mult = 0.0
	return maxf(mult, 0.0)

func get_combat_defense_penalty() -> int:
	if not combat_debuffs.has("def_down"):
		return 0
	return int(combat_debuffs["def_down"].get("value", 0))

func get_combat_evade_penalty() -> float:
	if not combat_debuffs.has("evade_down"):
		return 0.0
	return float(combat_debuffs["evade_down"].get("value", 0.0))

func _tick_combat_debuffs(delta: float) -> void:
	for debuff_type in combat_debuffs.keys():
		var debuff: Dictionary = combat_debuffs[debuff_type]
		var remaining := float(debuff.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			combat_debuffs.erase(debuff_type)
		else:
			debuff["remaining"] = remaining
			combat_debuffs[debuff_type] = debuff

func on_player_detected(body: Player) -> void:
	player = body

func take_acid_damage() -> void:
	if state_node.can_die():
		switch_state(State.DYING)
		
func take_spike_damage(_spikes_trap: SpikesTrap) -> void:
	if state_node.can_die():
		AudioManager.play("spikes", action_audio_stream_player)
		switch_state(State.DYING)
