class_name Enemy
extends CharacterBody3D

signal dead(death_transform: Transform3D)
signal screamed

const AIR_FRICTION := 20.0
const DURATION_RAGDOLL_SIMULATION := 3.0
const GRAVITY := 20.0

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

enum State {MOVING, IMPALING, DYING, DEAD, SLASHING, HURT, BLOCKING, STUNNED}

var pushback_force := Vector3.ZERO
var state: State
var state_node: EnemyState
var time_since_last_attack: int

func _ready() -> void:
	player_detection_area.body_entered.connect(on_player_detected)
	health_indicator.refresh(health.current_life, health.max_life)
	switch_state(State.MOVING)
	
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
	if player == null or not equipment.has_shield() or state_node.can_get_hurt():
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
	if player == null or not equipment.has_shield() or state_node.can_get_hurt():
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
	# ARPG 秒数眩晕：若 result.stun_duration > 0，进入 STUNNED 状态
	if player == null or not equipment.has_shield() or state_node.can_get_hurt():
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
	move_and_slide()

func process_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

func process_pushback(delta: float) -> void:
	pushback_force = pushback_force.move_toward(Vector3.ZERO, delta * AIR_FRICTION)
	velocity += pushback_force

func on_player_detected(body: Player) -> void:
	player = body

func take_acid_damage() -> void:
	if state_node.can_die():
		switch_state(State.DYING)
		
func take_spike_damage(_spikes_trap: SpikesTrap) -> void:
	if state_node.can_die():
		AudioManager.play("spikes", action_audio_stream_player)
		switch_state(State.DYING)
