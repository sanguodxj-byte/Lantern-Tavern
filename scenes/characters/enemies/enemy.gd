class_name Enemy
extends CharacterBody3D

signal screamed

const AIR_FRICTION := 20.0
const DURATION_RAGDOLL_SIMULATION := 3.0
const GRAVITY := 20.0

@onready var animation_player: AnimationPlayer = $character/AnimationPlayer
@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var equipment: EquipmentComponent = %EquipmentComponent
@onready var health: HealthComponent = %HealthComponent
@onready var nav_agent: NavigationAgent3D = %NavigationAgent3D
@onready var skeleton_simulator: PhysicalBoneSimulator3D = %PhysicalBoneSimulator3D
@onready var physical_bone_torso: PhysicalBone3D = %"Physical Bone Torso"
@onready var player_detection_area: Area3D = %PlayerDetectionArea
@onready var weapon_reach_raycast: RayCast3D = %WeaponReachRaycast

@export var duration_between_attacks: int
@export var player: Player
@export var speed: float

enum State {MOVING, IMPALING, DYING, DEAD, SLASHING, HURT}

var pushback_force := Vector3.ZERO
var state: State
var state_node: EnemyState
var time_since_last_attack: int

func _ready() -> void:
	player_detection_area.body_entered.connect(on_player_detected)
	switch_state(State.MOVING)
	
func switch_state(new_state: State, data: EnemyStateData = EnemyStateData.new()) -> void:
	if state_node != null:
		state_node.queue_free()
	var state_map := {
		State.DEAD: EnemyStateDead,
		State.DYING: EnemyStateDying,
		State.HURT: EnemyStateHurt,
		State.IMPALING: EnemyStateImpaling,
		State.MOVING: EnemyStateMoving,
		State.SLASHING: EnemyStateSlashing,
	}
	state_node = state_map[new_state].new(self, data)
	state_node.transition_requested.connect(switch_state)
	state_node.name = "State: " + State.keys()[new_state]
	state = new_state
	add_child(state_node)

func impale(thrown_item: ThrownItem, item_basis: Basis) -> void:
	var state_data := EnemyStateData.new().set_thrown_item(thrown_item).set_thrown_item_basis(item_basis)
	screamed.emit()
	switch_state(State.IMPALING, state_data)

func has_registered_player() -> bool:
	return player != null and is_instance_valid(player)

func is_player_within_reach() -> bool:
	if has_registered_player() and equipment.has_weapon():
		return weapon_reach_raycast.is_colliding()
	return false

func try_receive_hit(source_player: Player, damage: int) -> void:
	player = source_player
	screamed.emit()
	var hit_direction := source_player.global_position.direction_to(global_position).normalized()
	switch_state(State.HURT, EnemyStateData.new().set_damage(damage).set_impact_direction(hit_direction))

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
