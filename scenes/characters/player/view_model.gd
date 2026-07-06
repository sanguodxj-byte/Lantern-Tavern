class_name ViewModel
extends Node3D

## 第一人称武器视图模型。
## 挂在摄像机下方，自动跟随摄像机位置/旋转。
## 武器前端出现在视野内，并跟随攻击/射击/瞄准动作摆动。
## 监听 GameEvents.weapon_changed 信号自动同步武器模型。

const SLASH_ANIM := preload("res://globals/combat/combat_slash_animator.gd")

## 摄像机渲染层（仅第 1 层），确保武器模型被摄像机渲染
const VIEW_MODEL_RENDER_LAYER := 1

## 默认持武器位置（相对于摄像机），右下前方
@export var view_position: Vector3 = Vector3(0.30, -0.28, -0.55)
## 默认持武器旋转（度），轻微倾斜以展示武器侧面
@export var view_rotation_degrees: Vector3 = Vector3(-12.0, 18.0, 0.0)
## 瞄准时位置（居中靠近摄像机）
@export var aim_position: Vector3 = Vector3(0.0, -0.20, -0.48)
## 瞄准时旋转（度）
@export var aim_rotation_degrees: Vector3 = Vector3(-5.0, 0.0, 0.0)

@onready var weapon_holder: Node3D = $WeaponHolder

var _base_transform: Transform3D
var _current_weapon_node: Node3D = null

func _ready() -> void:
	_reset_base()
	# 监听武器变更信号，自动同步视图模型武器模型
	# 使用 get_tree() 安全获取 GameEvents autoload
	var tree := get_tree()
	if tree != null:
		var ge := tree.root.get_node_or_null("GameEvents")
		if ge != null and ge.has_signal("weapon_changed"):
			ge.connect("weapon_changed", _on_weapon_changed)

func _reset_base() -> void:
	var rot := Basis.from_euler(Vector3(
		deg_to_rad(view_rotation_degrees.x),
		deg_to_rad(view_rotation_degrees.y),
		deg_to_rad(view_rotation_degrees.z)
	))
	_base_transform = Transform3D(rot, view_position)
	weapon_holder.transform = _base_transform

func _on_weapon_changed(weapon_data: Variant) -> void:
	set_weapon(weapon_data as WeaponData)

## 设置武器模型（装备武器时由信号自动调用，也可手动调用）
func set_weapon(weapon_data: WeaponData) -> void:
	clear_weapon()
	if weapon_data == null or weapon_data.glb_mesh == null:
		return
	# 盾牌不在主手视图模型中显示
	if weapon_data.item_tag == "shield" or weapon_data.weapon_class == "shield":
		return
	_current_weapon_node = weapon_data.glb_mesh.instantiate()
	weapon_holder.add_child(_current_weapon_node)
	# 显式将武器网格设到第 1 渲染层，确保被摄像机（cull_mask=1）渲染
	_set_render_layer_recursive(_current_weapon_node, VIEW_MODEL_RENDER_LAYER)

## 清除武器模型（卸下武器时由信号自动调用）
func clear_weapon() -> void:
	if _current_weapon_node != null and is_instance_valid(_current_weapon_node):
		_current_weapon_node.queue_free()
	_current_weapon_node = null

## 递归设置节点及其所有子节点的渲染层
func _set_render_layer_recursive(node: Node, layer: int) -> void:
	if node is GeometryInstance3D:
		node.layers = layer
	for child in node.get_children():
		_set_render_layer_recursive(child, layer)

## 获取当前基础变换（供外部状态脚本读取）
func get_base_transform() -> Transform3D:
	return _base_transform

## 应用挥砍弧线动画（与 CombatSlashAnimator.apply_weapon_arc 相同的弧线逻辑）
func apply_slash_arc(progress_value: float, side: float = 1.0) -> void:
	var windup := clampf(progress_value / SLASH_ANIM.PLAYER_HIT_START, 0.0, 1.0)
	var strike := clampf((progress_value - SLASH_ANIM.PLAYER_HIT_START) / maxf(SLASH_ANIM.PLAYER_HIT_END - SLASH_ANIM.PLAYER_HIT_START, 0.01), 0.0, 1.0)
	var recover := clampf((progress_value - SLASH_ANIM.PLAYER_HIT_END) / maxf(1.0 - SLASH_ANIM.PLAYER_HIT_END, 0.01), 0.0, 1.0)
	var roll := lerpf(-SLASH_ANIM.ARC_ROLL_RAD, SLASH_ANIM.ARC_ROLL_RAD, strike) * side
	var yaw := lerpf(-SLASH_ANIM.ARC_YAW_RAD, SLASH_ANIM.ARC_YAW_RAD, strike) * side
	if progress_value < SLASH_ANIM.PLAYER_HIT_START:
		roll = lerpf(0.0, -SLASH_ANIM.ARC_ROLL_RAD, windup) * side
		yaw = lerpf(0.0, -SLASH_ANIM.ARC_YAW_RAD, windup) * side
	elif progress_value > SLASH_ANIM.PLAYER_HIT_END:
		roll = lerpf(SLASH_ANIM.ARC_ROLL_RAD, 0.0, recover) * side
		yaw = lerpf(SLASH_ANIM.ARC_YAW_RAD, 0.0, recover) * side
	var offset := Vector3(0.0, 0.0, -sin(progress_value * PI) * SLASH_ANIM.ARC_FORWARD_OFFSET)
	var arc := Transform3D(Basis.from_euler(Vector3(0.0, yaw, roll)), offset)
	weapon_holder.transform = _base_transform * arc

## 恢复到默认位置（挥砍结束后调用）
func restore_transform() -> void:
	weapon_holder.transform = _base_transform

## 应用射击后坐力（射击时调用）
func apply_recoil() -> void:
	var recoil_pos := _base_transform.origin + Vector3(0.0, 0.02, 0.10)
	var recoil_rot := _base_transform.basis.get_euler() + Vector3(deg_to_rad(-8.0), 0.0, 0.0)
	var recoil_transform := Transform3D(Basis.from_euler(recoil_rot), recoil_pos)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(weapon_holder, "transform", recoil_transform, 0.04)
	tween.tween_property(weapon_holder, "transform", _base_transform, 0.12)

## 设置瞄准状态（右键瞄准时调用，武器移到屏幕中央）
func set_aiming(enabled: bool) -> void:
	var target_pos := aim_position if enabled else view_position
	var target_rot_deg := aim_rotation_degrees if enabled else view_rotation_degrees
	var target_rot := Basis.from_euler(Vector3(
		deg_to_rad(target_rot_deg.x),
		deg_to_rad(target_rot_deg.y),
		deg_to_rad(target_rot_deg.z)
	))
	var target := Transform3D(target_rot, target_pos)
	_base_transform = target
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(weapon_holder, "transform", target, 0.15)
