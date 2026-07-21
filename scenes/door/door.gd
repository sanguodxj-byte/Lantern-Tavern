@tool
class_name Door
extends StaticBody3D

enum KeyColor {None, Blue, Red, Yellow, Purple}

signal opened

static var COLOR_MAP : Dictionary[KeyColor, Color] = {
	KeyColor.Blue: Color.DARK_BLUE,
	KeyColor.Red: Color.DARK_RED,
	KeyColor.Yellow: Color.DARK_GOLDENROD,
	KeyColor.Purple: Color.DARK_MAGENTA,
}

@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var collision_shape_3d: CollisionShape3D = %CollisionShape3D
@onready var frame: Node3D = %Frame
@onready var door_hinge: Node3D = $door

@export var door_color: KeyColor:
	set(new_color):
		door_color = new_color
		editor_update_key_indicator()
@export var tutorial_locked_message: String = ""
@export var tutorial_kick_prompt: String = "[F] Kick"
@export var requires_kick_to_open: bool = false
@export var editor_key_indicator: MeshInstance3D
@export var frame_mesh: MeshInstance3D

func _ready() -> void:
	if Engine.is_editor_hint():
		editor_update_key_indicator()
	else:
		_reset_closed_pose()
		frame.visible = false
		update_frame_color()


func _reset_closed_pose() -> void:
	if animation_player != null:
		animation_player.stop()
	if door_hinge != null:
		door_hinge.rotation = Vector3.ZERO
	if collision_shape_3d != null:
		collision_shape_3d.disabled = false

func interact(_source_player: Node = null) -> void:
	if tutorial_locked_message.is_empty():
		return
	# 锁定提示改走物体右侧的悬浮窗（与统一交互提示一致）
	var screen_pos := Vector2.ZERO
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam != null:
		screen_pos = cam.unproject_position(global_position)
	GameEvents.interaction_hint_changed.emit("door", tutorial_locked_message, screen_pos)

func get_kick_prompt() -> String:
	return tutorial_kick_prompt if not tutorial_kick_prompt.is_empty() else "[F] Open"

func can_open_with_kick() -> bool:
	return true

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
	opened.emit()

func update_frame_color() -> void:
	frame.hide()
		
func editor_update_key_indicator() -> void:
	if editor_key_indicator != null:
		editor_key_indicator.visible = false
