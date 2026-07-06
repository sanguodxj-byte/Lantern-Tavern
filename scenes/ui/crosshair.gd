class_name Crosshair
extends Control

## 像素风准心（屏幕正中央）。
## 弓/弩瞄准时显示，投掷时也显示。
## 命中敌人时变红提供反馈。

const COL_DEFAULT := Color(1.0, 1.0, 1.0, 0.85)
const COL_TARGETING := Color(1.0, 0.25, 0.15, 0.95)
const COL_AIMING := Color(0.3, 1.0, 0.4, 0.9)

@export var arm_length: float = 8.0
@export var arm_thickness: float = 2.0
@export var center_gap: float = 3.0

var _is_targeting: bool = false
var _is_aiming: bool = false
var _player: Node = null
var _scan_timer: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func _process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer >= 0.1:
		_scan_timer = 0.0
		_update_state()
	queue_redraw()

func _update_state() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			return
	# 瞄准状态
	if "is_weapon_aiming" in _player:
		_is_aiming = _player.is_weapon_aiming
	else:
		_is_aiming = false
	# 射线检测是否命中敌人
	_is_targeting = _check_targeting_enemy()

func _check_targeting_enemy() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var cam = _player.get("camera") if "camera" in _player else null
	if cam == null or not is_instance_valid(cam):
		return false
	var camera: Camera3D = cam as Camera3D
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z.normalized()
	var to := from + forward * 60.0
	var space := camera.get_world_3d()
	if space == null:
		return false
	var ds := space.direct_space_state
	if ds == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	query.collision_mask = PhysicsSetup.LAYER_ENEMY
	var result := ds.intersect_ray(query)
	return not result.is_empty()

func _find_player() -> Node:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.get("current_player") and is_instance_valid(gs.get("current_player")):
		return gs.current_player
	return null

func _draw() -> void:
	var c := size / 2.0
	# 坐标取整，确保锐利像素渲染
	var cx: int = int(c.x)
	var cy: int = int(c.y)
	var color: Color = COL_DEFAULT
	if _is_targeting:
		color = COL_TARGETING
	elif _is_aiming:
		color = COL_AIMING
	# 十字准心：上下左右四条臂，中间留空隙（全部整数坐标）
	var t: int = int(arm_thickness)
	var l: int = int(arm_length)
	var g: int = int(center_gap)
	# 上
	draw_rect(Rect2(cx - t / 2, cy - g - l, t, l), color, true)
	# 下
	draw_rect(Rect2(cx - t / 2, cy + g, t, l), color, true)
	# 左
	draw_rect(Rect2(cx - g - l, cy - t / 2, l, t), color, true)
	# 右
	draw_rect(Rect2(cx + g, cy - t / 2, l, t), color, true)
	# 中心点（瞄准时显示，2x2 像素方块）
	if _is_aiming:
		draw_rect(Rect2(cx - 1, cy - 1, 2, 2), color, true)

## 外部设置玩家引用（供测试用）
func set_player(p: Node) -> void:
	_player = p
