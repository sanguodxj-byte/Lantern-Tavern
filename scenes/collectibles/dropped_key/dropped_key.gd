class_name DroppedKey
extends RigidBody3D

const ROTATION_SPEED := 10.0

@export var color: Door.KeyColor
@export var mesh: MeshInstance3D

@onready var omni_light_3d: OmniLight3D = %OmniLight3D
@onready var player_detection_area: Area3D = %PlayerDetectionArea

func _ready() -> void:
	PhysicsSetup.setup_rigidbody(self, PhysicsSetup.LAYER_PICKABLE)
	PhysicsSetup.setup_trigger(player_detection_area)
	var material := mesh.get_active_material(0).duplicate() as StandardMaterial3D
	material.albedo_color = Door.COLOR_MAP.get(color, Color.WHITE)
	material.emission_enabled = false
	mesh.set_surface_override_material(0, material)
	omni_light_3d.visible = false
	angular_velocity = Vector3.UP * ROTATION_SPEED
	player_detection_area.body_entered.connect(on_player_entered)

func on_player_entered(_body: Player) -> void:
	GameState.obtain_key(color)
	queue_free()
	
