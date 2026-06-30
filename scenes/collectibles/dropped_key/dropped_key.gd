class_name DroppedKey
extends RigidBody3D

const ROTATION_SPEED := 10.0

@export var color: Door.KeyColor
@export var mesh: MeshInstance3D

@onready var omni_light_3d: OmniLight3D = %OmniLight3D
@onready var player_detection_area: Area3D = %PlayerDetectionArea

func _ready() -> void:
	var material := mesh.get_active_material(0) as StandardMaterial3D
	material.albedo_color = Door.COLOR_MAP[color]
	material.emission_enabled = true
	material.emission = Door.COLOR_MAP[color]
	material.emission_energy_multiplier = 3.0
	omni_light_3d.light_color = Door.COLOR_MAP[color]
	angular_velocity = Vector3.UP * ROTATION_SPEED
	player_detection_area.body_entered.connect(on_player_entered)

func on_player_entered(_body: Player) -> void:
	GameEvents.key_picked_up.emit(color)
	queue_free()
	
