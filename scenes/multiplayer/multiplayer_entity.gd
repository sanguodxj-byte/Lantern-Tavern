extends Node3D
## 远端实体复制节点（联机表现层）：敌人 / 宝箱 / 门 / 掉落的客户端可见表示。
##
## 由 MultiplayerSceneBridge 经显式 RPC（authority→call_remote）生成与更新；
## 只接收服务器下发的 entity_spawned / entity_snapshot / entity_despawned 事件并插值/更新，
## 不持有任何权威战斗/掉落逻辑（服务器权威）。
##
## 不声明 class_name：避免 headless 类注册 / .uid 同步问题；经 preload 引用。

## 该实体对应哪个 entity_id（由 bridge 从事件回填，命名 Entity_<id> 便于调试）。
var entity_id: int = 0
## 实体类别：enemy / chest / door / loot（决定外观与标签）。
var kind: String = "enemy"
## 插值目标（服务器权威快照经 bridge 写入）。
var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
## 每秒插值收敛速度。
var interp_speed: float = 12.0
## 当前/最大生命（服务器权威；仅 enemy 使用）。
var hp: int = 0
var max_hp: int = 0

@onready var _name_label: Label3D = $NameLabel
@onready var _hp_label: Label3D = $HpLabel

func _ready() -> void:
	if _name_label != null:
		_name_label.text = kind
	_refresh_hp()

## 供 bridge 调用：entity_spawned 事件到达时初始化（位置/HP/标签）。
func apply_spawn(data: Dictionary) -> void:
	kind = String(data.get("kind", "enemy"))
	entity_id = int(data.get("entity_id", entity_id))
	target_position = data.get("position", Vector3.ZERO)
	global_position = target_position
	hp = int(data.get("current_life", 0))
	max_hp = int(data.get("max_life", 0))
	if _name_label != null:
		_name_label.text = String(data.get("label", kind))
	_refresh_hp()

## 供 bridge 调用：entity_snapshot 事件到达时更新（HP/位置）。
func apply_snapshot(data: Dictionary) -> void:
	if data.has("position"):
		target_position = data["position"]
	if data.has("current_life"):
		hp = int(data["current_life"])
	if data.has("max_life"):
		max_hp = int(data["max_life"])
	_refresh_hp()

func apply_despawn() -> void:
	queue_free()

func _physics_process(delta: float) -> void:
	if is_zero_approx(interp_speed):
		global_position = target_position
	else:
		var t := min(1.0, interp_speed * delta)
		global_position = global_position.lerp(target_position, t)

func _refresh_hp() -> void:
	if _hp_label != null:
		if max_hp > 0:
			_hp_label.text = "%d/%d" % [hp, max_hp]
		else:
			_hp_label.text = ""
