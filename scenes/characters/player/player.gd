class_name Player
extends CharacterBody3D

const MAX_ANGLE_LOOK_UP := deg_to_rad(70)
const MAX_ANGLE_LOOK_DOWN := deg_to_rad(-70)

@export var mouse_sensitivity: float

@onready var camera: Camera3D = %Camera3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity) # PI 3.14 => 180 degrees 
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, MAX_ANGLE_LOOK_DOWN, MAX_ANGLE_LOOK_UP)
