class_name Player
extends CharacterBody3D

const MAX_ANGLE_LOOK_UP := deg_to_rad(70)
const MAX_ANGLE_LOOK_DOWN := deg_to_rad(-70)

@export var acceleration: float
@export var jump_force: float
@export var gravity: float
@export var mouse_sensitivity: float
@export var run_speed: float
@export var walk_speed: float

@onready var animation_player: AnimationPlayer = $character/AnimationPlayer
@onready var camera: Camera3D = %MainCamera
@onready var kick_raycast: RayCast3D = %KickRaycast
@onready var equipment: EquipmentComponent = %EquipmentComponent
@onready var health: HealthComponent = %HealthComponent
@onready var select_raycast: RayCast3D = %SelectRaycast
@onready var weapon_reach_raycast: RayCast3D = %WeaponReachRaycast

enum State {MOVING, PICKING_UP, THROWING, SLASHING, KICKING, BLOCKING}

var current_pickable_focused_item : PickableItem = null
var input_dir := Vector2.ZERO
var state: State
var state_node: PlayerState

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.register_player(self)
	switch_state(State.MOVING)

func _process(_delta: float) -> void:
	input_dir = Input.get_vector("strafe_left", "strafe_right", "backward", "forward")

	#if Input.is_action_just_pressed("kick"):
		#GameEvents.player_hurt.emit(self)

func _physics_process(_delta: float) -> void:
	check_jump_input()
	process_gravity()
	move_and_slide()
	check_for_selection()

func process_movement(delta: float) -> void:
	var input_3d_space := Vector3(input_dir.x, 0, -input_dir.y)
	var target_speed := run_speed if Input.is_action_pressed("run") else walk_speed
	var desired_velocity := transform.basis * input_3d_space * target_speed
	if input_3d_space == Vector3.ZERO:
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity) # PI 3.14 => 180 degrees 
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, MAX_ANGLE_LOOK_DOWN, MAX_ANGLE_LOOK_UP)

func switch_state(new_state: State) -> void:
	if state_node != null:
		state_node.queue_free()
	var state_map := {
		State.BLOCKING: PlayerStateBlocking,
		State.KICKING: PlayerStateKicking,
		State.MOVING: PlayerStateMoving,
		State.PICKING_UP: PlayerStatePickingUp,
		State.SLASHING: PlayerStateSlashing,
		State.THROWING: PlayerStateThrowing,
	}
	state_node = state_map[new_state].new(self)
	state_node.transition_requested.connect(switch_state)
	state_node.name = "State: " + State.keys()[new_state]
	state = new_state
	add_child(state_node)

func check_jump_input() -> void:
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_force

func process_gravity() -> void:
	if not is_on_floor():
		velocity.y -= gravity

func check_for_selection() -> void:
	var target_node: Node = null
	if select_raycast.is_colliding():
		var collider := select_raycast.get_collider()
		if collider is PickableItem:
			target_node = collider
	if target_node != current_pickable_focused_item:
		if current_pickable_focused_item:
			current_pickable_focused_item.unhighlight()
		current_pickable_focused_item = target_node
		if current_pickable_focused_item is PickableItem:
			current_pickable_focused_item.highlight()
			
func can_pickup_object() -> bool:
	return current_pickable_focused_item != null

func take_acid_damage() -> void:
	print("ouch")
