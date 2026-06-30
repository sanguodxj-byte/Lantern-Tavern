class_name Door
extends StaticBody3D

enum KeyColor {None, Blue, Red, Yellow, Purple}

static var COLOR_MAP : Dictionary[KeyColor, Color] = {
	KeyColor.Blue: Color.DARK_BLUE,
	KeyColor.Red: Color.DARK_RED,
	KeyColor.Yellow: Color.DARK_GOLDENROD,
	KeyColor.Purple: Color.DARK_MAGENTA,
}

@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var collision_shape_3d: CollisionShape3D = %CollisionShape3D
@onready var frame: Node3D = %Frame

@export var door_color: KeyColor
@export var frame_mesh: MeshInstance3D

func _ready() -> void:
	frame.visible = door_color != KeyColor.None
	update_frame_color()

func open(source_transform: Transform3D) -> void:
	collision_shape_3d.disabled = true
	var door_forward := -global_basis.z
	var player_forward := -source_transform.basis.z
	var dot_product := door_forward.dot(player_forward)
	if dot_product > 0:
		animation_player.play("open-right")
	else:
		animation_player.play("open-left")
	frame.hide()

func update_frame_color() -> void:
	if door_color != KeyColor.None:
		var material := frame_mesh.get_surface_override_material(0).duplicate() as StandardMaterial3D
		material.albedo_color = COLOR_MAP[door_color]
		material.emission_enabled = true
		material.emission = COLOR_MAP[door_color]
		material.emission_energy_multiplier = 3.0
		frame_mesh.set_surface_override_material(0, material)
	else:
		frame.hide()
