extends Node3D
## 远端玩家 avatar 节点（联机表现层，仅地牢范围）。
##
## 由 MultiplayerSpawner 在服务器生成、自动复制到其他客户端。
## 本节点不持有任何权威逻辑——只接收服务器下发的 player_snapshot 事件
## （经 MultiplayerSceneBridge 路由到 apply_snapshot），在 _physics_process 中本地插值平滑。
##
## 注意：MultiplayerSpawner 只复制“节点树结构 + 初始 PackedScene 状态”，
## 不会自动同步自定义属性。因此 peer_id 通过【节点名】传递（`Avatar_<peer_id>`），
## 由 bridge 在 child_entered_tree 时从名字解析，避免依赖属性同步。

## 该 avatar 对应哪个 peer（由 bridge 从节点名解析后回填，仅本地缓存用）。
var peer_id: int = 0
## 插值目标（服务器权威快照经 bridge 写入）。
var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
## 每秒插值收敛速度；值越大越“贴脸”跟手。
var interp_speed: float = 14.0

@onready var _label: Label3D = $Label3D

func _ready() -> void:
	if _label != null:
		label_text(_label, "P%d" % peer_id)

## 供 bridge 调用：服务器 player_snapshot 事件到达时设置插值目标。
func apply_snapshot(position: Vector3, yaw: float) -> void:
	target_position = position
	target_yaw = yaw

func _physics_process(delta: float) -> void:
	if is_zero_approx(interp_speed):
		global_position = target_position
		rotation.y = target_yaw
		return
	var t := min(1.0, interp_speed * delta)
	global_position = global_position.lerp(target_position, t)
	rotation.y = lerp_angle(rotation.y, target_yaw, t)

func label_text(lbl: Label3D, txt: String) -> void:
	lbl.text = txt
