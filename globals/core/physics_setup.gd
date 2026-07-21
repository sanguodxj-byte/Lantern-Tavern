extends Node
## 物理统一注册器（autoload: PhysicsSetup）。
## 标准化 collision_layer/mask 约定 + 为 MeshInstance 自动添加 StaticBody+BoxShape 碰撞。
## 供 tavern_structure.gd / procedural_dungeon.gd 调用，确保所有物体物理一致。

# ---- 碰撞层（bit 位）----
# bit0=1: 地形/不可互动环境（地板/墙/天花板）
# bit1=2: 玩家
# bit2=4: 敌人
# bit3=8: 可拾取物（材料/武器/盾）
# bit4=16: 可投掷物（桶/箱/被投掷敌人）
# bit5=32: 交互触发器（Area3D）
# bit6=64: 场景物体（立柱/吧台/桌子/宝箱/装饰）
# bit7=128: 投射物（箭矢/弩箭/法术弹）

const LAYER_ENVIRONMENT: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ENEMY: int = 4
const LAYER_PICKABLE: int = 8
const LAYER_THROWABLE: int = 16
const LAYER_TRIGGER: int = 32
const LAYER_SCENE_OBJECT: int = 64
const LAYER_PROJECTILE: int = 128
const LAYER_FURNITURE: int = LAYER_SCENE_OBJECT

# ---- 角色胶囊碰撞标准 ----
# 1.7m 成年男性的肩宽通常约 0.4-0.45m；游戏碰撞胶囊额外保留衣物、
# 动作摆动和操作容错，标准人形直径定为 0.5m。
const HUMANOID_COLLISION_HEIGHT := 1.7
const HUMANOID_COLLISION_WIDTH := 0.5
const HUMANOID_COLLISION_RADIUS := HUMANOID_COLLISION_WIDTH * 0.5
const CHARACTER_COLLISION_MARGIN := 0.04
const BODY_SIZE_SCALE := {
	"small": 0.5,
	"medium": 1.0,
	"large": 1.3,
	"huge": 1.75,
}

# ---- 标准掩码组合 ----
# 静态环境：仅被其他物体碰撞，不主动碰他物
const MASK_ENVIRONMENT: int = 0
# 玩家：碰撞环境+敌人+可拾取物+门/触发层+场景物体
const MASK_PLAYER: int = LAYER_ENVIRONMENT | LAYER_ENEMY | LAYER_PICKABLE | LAYER_TRIGGER | LAYER_SCENE_OBJECT
# 敌人：碰撞环境+玩家+敌人+可投掷物+门/触发层+场景物体
const MASK_ENEMY: int = LAYER_ENVIRONMENT | LAYER_PLAYER | LAYER_ENEMY | LAYER_THROWABLE | LAYER_TRIGGER | LAYER_SCENE_OBJECT
# 可拾取物：碰撞环境+场景物体+其他动态物体
const MASK_PICKABLE: int = LAYER_ENVIRONMENT | LAYER_SCENE_OBJECT | LAYER_PICKABLE | LAYER_THROWABLE
# 可投掷物：碰撞环境+敌人+玩家+门/触发层+场景物体+其他动态物体
const MASK_THROWABLE: int = LAYER_ENVIRONMENT | LAYER_ENEMY | LAYER_PLAYER | LAYER_TRIGGER | LAYER_SCENE_OBJECT | LAYER_PICKABLE | LAYER_THROWABLE
# 投射物：碰撞环境+敌人+场景物体（不碰玩家/可拾取物/触发器）
const MASK_PROJECTILE: int = LAYER_ENVIRONMENT | LAYER_ENEMY | LAYER_SCENE_OBJECT
# 选择射线：可拾取物+场景物体
const MASK_SELECTABLE: int = LAYER_PICKABLE | LAYER_SCENE_OBJECT
# 视野遮挡层：地形/墙壁+场景物体（柱子/家具等），用于敌人视野检测射线
const MASK_VISION_OBSTRUCTION: int = LAYER_ENVIRONMENT | LAYER_SCENE_OBJECT

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

## 为 CharacterBody3D 标准化碰撞层/掩码，并在缺少碰撞形状时补胶囊。
func setup_character_body(body: CharacterBody3D, layer: int, mask: int, body_size: String = "medium") -> void:
	body.collision_layer = layer
	body.collision_mask = mask
	var col := _ensure_collision_shape(body, _make_capsule_shape(body_size))
	_apply_character_capsule(col, body_size)

func setup_player(body: CharacterBody3D) -> void:
	setup_character_body(body, LAYER_PLAYER, MASK_PLAYER, "medium")

func setup_enemy(body: CharacterBody3D) -> void:
	setup_character_body(body, LAYER_ENEMY, MASK_ENEMY, _read_body_size(body))

func get_body_size_scale(body_size: String) -> float:
	return float(BODY_SIZE_SCALE.get(body_size, BODY_SIZE_SCALE["medium"]))

func get_character_capsule_height(body_size: String = "medium") -> float:
	return HUMANOID_COLLISION_HEIGHT * get_body_size_scale(body_size)

func get_character_capsule_radius(body_size: String = "medium") -> float:
	return HUMANOID_COLLISION_RADIUS * get_body_size_scale(body_size)

## 为可拾取物标准化碰撞层/掩码，并补默认盒碰撞。
func setup_pickable(body: PhysicsBody3D) -> void:
	body.collision_layer = LAYER_PICKABLE
	body.collision_mask = MASK_PICKABLE
	_ensure_collision_shape(body, _make_box_shape(Vector3(0.35, 0.35, 0.35)))

## 为 RigidBody3D 标准化碰撞层/掩码（可投掷物用）。
func setup_rigidbody(body: RigidBody3D, layer: int = LAYER_THROWABLE) -> void:
	body.collision_layer = layer
	match layer:
		LAYER_PICKABLE:
			body.collision_mask = MASK_PICKABLE
		LAYER_PROJECTILE:
			body.collision_mask = MASK_PROJECTILE
		_:
			body.collision_mask = MASK_THROWABLE
	_ensure_collision_shape(body, _make_box_shape(Vector3(0.35, 0.35, 0.35)))

## 为投射物 RigidBody3D 标准化碰撞层/掩码 + 连续碰撞检测。
func setup_projectile(body: RigidBody3D) -> void:
	body.collision_layer = LAYER_PROJECTILE
	body.collision_mask = MASK_PROJECTILE
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 4
	_ensure_collision_shape(body, _make_box_shape(Vector3(0.15, 0.15, 0.4)))

func setup_trigger(area: Area3D, mask: int = LAYER_PLAYER) -> void:
	area.collision_layer = LAYER_TRIGGER
	area.collision_mask = mask
	_ensure_collision_shape(area, _make_sphere_shape(1.0))

## 获取层名（调试/测试用）
func get_layer_name(layer: int) -> String:
	match layer:
		LAYER_ENVIRONMENT: return "environment"
		LAYER_PLAYER: return "player"
		LAYER_ENEMY: return "enemy"
		LAYER_PICKABLE: return "pickable"
		LAYER_THROWABLE: return "throwable"
		LAYER_TRIGGER: return "trigger"
		LAYER_SCENE_OBJECT: return "scene_object"
		LAYER_PROJECTILE: return "projectile"
		_: return "unknown(%d)" % layer

func _ensure_collision_shape(body: CollisionObject3D, fallback_shape: Shape3D) -> CollisionShape3D:
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node != null:
			if shape_node.shape == null:
				shape_node.shape = fallback_shape
			return shape_node
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = fallback_shape
	if fallback_shape is CapsuleShape3D:
		col.position = Vector3(0, 0.85, 0)
	body.add_child(col, true)
	return col

func _make_capsule_shape(body_size: String = "medium") -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = get_character_capsule_radius(body_size)
	shape.height = get_character_capsule_height(body_size)
	shape.margin = CHARACTER_COLLISION_MARGIN
	return shape

func _apply_character_capsule(col: CollisionShape3D, body_size: String) -> void:
	var capsule := col.shape as CapsuleShape3D
	if capsule == null:
		capsule = _make_capsule_shape(body_size)
		col.shape = capsule
	capsule.radius = get_character_capsule_radius(body_size)
	capsule.height = get_character_capsule_height(body_size)
	capsule.margin = CHARACTER_COLLISION_MARGIN
	col.position = Vector3(0, capsule.height * 0.5, 0)

func _read_body_size(body: CharacterBody3D) -> String:
	if body.has_meta("body_size"):
		return String(body.get_meta("body_size"))
	var exported_value: Variant = body.get("body_size")
	if exported_value is String and exported_value != "":
		return exported_value
	return "medium"

func _make_box_shape(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape

func _make_sphere_shape(radius: float) -> SphereShape3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return shape
