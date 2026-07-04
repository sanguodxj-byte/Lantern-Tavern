extends Node
## 物理统一注册器（autoload: PhysicsSetup）。
## 标准化 collision_layer/mask 约定 + 为 MeshInstance 自动添加 StaticBody+BoxShape 碰撞。
## 供 tavern_structure.gd / procedural_dungeon.gd 调用，确保所有物体物理一致。

# ---- 碰撞层（bit 位）----
# bit0=1: 环境/静态物体（地板/墙/立柱/吧台/桌子/宝箱/装饰）
# bit1=2: 玩家
# bit2=4: 敌人
# bit3=8: 可拾取物（材料/武器/盾）
# bit4=16: 可投掷物（桶/箱/被投掷敌人）
# bit5=32: 交互触发器（Area3D）
# bit6=64: 家具/可抓取物

const LAYER_ENVIRONMENT: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ENEMY: int = 4
const LAYER_PICKABLE: int = 8
const LAYER_THROWABLE: int = 16
const LAYER_TRIGGER: int = 32
const LAYER_FURNITURE: int = 64

# ---- 标准掩码组合 ----
# 静态环境：仅被其他物体碰撞，不主动碰他物
const MASK_ENVIRONMENT: int = 0
# 玩家：碰撞环境+敌人+可拾取物+家具
const MASK_PLAYER: int = LAYER_ENVIRONMENT | LAYER_ENEMY | LAYER_PICKABLE | LAYER_FURNITURE
# 敌人：碰撞环境+玩家+可投掷物
const MASK_ENEMY: int = LAYER_ENVIRONMENT | LAYER_PLAYER | LAYER_THROWABLE
# 可拾取物：碰撞环境
const MASK_PICKABLE: int = LAYER_ENVIRONMENT
# 可投掷物：碰撞环境+敌人+玩家
const MASK_THROWABLE: int = LAYER_ENVIRONMENT | LAYER_ENEMY | LAYER_PLAYER

## 为 MeshInstance3D 自动添加 StaticBody3D + BoxShape3D 碰撞（基于 AABB）。
## parent: 父节点；mesh_instance: 已添加的 MeshInstance3D；layer: 碰撞层（默认环境）。
## 返回创建的 StaticBody3D。
func add_static_collision(parent: Node, mesh_instance: MeshInstance3D, layer: int = LAYER_ENVIRONMENT) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = mesh_instance.name + "Body"
	body.collision_layer = layer
	body.collision_mask = MASK_ENVIRONMENT
	body.global_transform = mesh_instance.global_transform
	# 从 mesh AABB 推导 BoxShape 尺寸
	var aabb: AABB = mesh_instance.get_aabb()
	var col := CollisionShape3D.new()
	col.name = "CollisionShape"
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	col.shape = shape
	col.position = aabb.position + aabb.size * 0.5
	body.add_child(col, true)
	parent.add_child(body, true)
	return body

## 直接用指定尺寸创建 StaticBody3D + BoxShape3D。
## parent: 父节点；pos: 全局位置；size: 碰撞箱尺寸；layer: 碰撞层。
func add_box_collision(parent: Node, pos: Vector3, size: Vector3, layer: int = LAYER_ENVIRONMENT) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "StaticBody"
	body.collision_layer = layer
	body.collision_mask = MASK_ENVIRONMENT
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col, true)
	parent.add_child(body, true)
	return body

## 为 RigidBody3D 标准化碰撞层/掩码（可投掷物用）。
func setup_rigidbody(body: RigidBody3D, layer: int = LAYER_THROWABLE) -> void:
	body.collision_layer = layer
	body.collision_mask = MASK_THROWABLE

## 获取层名（调试/测试用）
func get_layer_name(layer: int) -> String:
	match layer:
		LAYER_ENVIRONMENT: return "environment"
		LAYER_PLAYER: return "player"
		LAYER_ENEMY: return "enemy"
		LAYER_PICKABLE: return "pickable"
		LAYER_THROWABLE: return "throwable"
		LAYER_TRIGGER: return "trigger"
		LAYER_FURNITURE: return "furniture"
		_: return "unknown(%d)" % layer
