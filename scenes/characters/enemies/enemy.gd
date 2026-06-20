class_name Enemy
extends CharacterBody3D

const DURATION_RAGDOLL_SIMULATION := 3.0

@onready var animation_player: AnimationPlayer = $character/AnimationPlayer

@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var equipment: EquipmentComponent = %EquipmentComponent
@onready var skeleton_simulator: PhysicalBoneSimulator3D = %PhysicalBoneSimulator3D
@onready var physical_bone_torso: PhysicalBone3D = %"Physical Bone Torso"

enum State {MOVING, IMPALING, DYING, DEAD}

var state: State
var state_node: EnemyState

func _ready() -> void:
	switch_state(State.MOVING)

func switch_state(new_state: State, data: EnemyStateData = EnemyStateData.new()) -> void:
	if state_node != null:
		state_node.queue_free()
	var state_map := {
		State.DEAD: EnemyStateDead,
		State.DYING: EnemyStateDying,
		State.IMPALING: EnemyStateImpaling,
		State.MOVING: EnemyStateMoving,
	}
	state_node = state_map[new_state].new(self, data)
	state_node.transition_requested.connect(switch_state)
	state_node.name = "State: " + State.keys()[new_state]
	state = new_state
	add_child(state_node)

func impale(thrown_item: ThrownItem, item_basis: Basis) -> void:
	var state_data := EnemyStateData.new().set_thrown_item(thrown_item).set_thrown_item_basis(item_basis)
	switch_state(State.IMPALING, state_data)
