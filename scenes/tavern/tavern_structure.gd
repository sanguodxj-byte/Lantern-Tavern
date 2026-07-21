@tool
class_name TavernStructure
extends Node3D

## 酒馆建筑结构保护脚本。
## 酒馆结构以 tavern.tscn 中手工编辑的 BuiltStructure 为准，禁止批量重建或合并覆盖。
##
## 碰撞体同步约定（以结构为基准）：
## - BuiltStructure 下每个结构网格(MeshInstance3D)通常配有一个同名 + "Body" 的 StaticBody3D。
## - 按"结构优先"原则，碰撞体始终以源网格的几何 AABB 重新对齐：碰撞体的 transform 直接
##   继承网格的位置/旋转/缩放，碰撞形状放在网格本地 AABB 中心、尺寸等于 AABB 尺寸。
##   因此墙体、吧台、地板、柱子等任何结构一旦被移动/旋转/缩放，碰撞箱都跟随结构。
## - 编辑器内开启实时同步：用户拖动或改尺寸后，碰撞体当帧即更新（仅在源网格变化时写回，
##   不会把未修改的碰撞体反复标脏）。场景加载时也会一次性全量对齐。
## - 缺少碰撞体的实体结构网格（如 L 形吧台旋转前挡板段）会自动补建碰撞体；装饰面
##   （天花板、Zone 标记面）通过关键字跳过，不参与自动补建。

# ---- 房间尺寸（米）----
@export var room_width: float = 13.0
@export var room_depth: float = 10.0
@export var room_height: float = 3.0
@export var room_center_x: float = 1.5
@export var room_center_z: float = -1.25
@export var wall_thickness: float = 0.3
@export var room_door_width: float = 1.5
@export var rear_door_width: float = 1.5
@export var rear_door_height: float = 2.2
@export var rear_door_center_x: float = 0.0
@export var back_hall_length: float = 4.5
@export var back_hall_width: float = 1.9
@export var back_hall_door_width: float = 1.5
@export var back_hall_center_z: float = -5.25
@export var dungeon_entry_length: float = 2.7
@export var spare_room_depth: float = 2.8
@export var bar_length: float = 3.5
@export var bar_left_x: float = 4.5
@export var warehouse_enabled: bool = true
@export var warehouse_left_x: float = -5.0
@export var warehouse_right_x: float = 3.0
@export var warehouse_south_z: float = -6.25
@export var warehouse_north_z: float = -3.55
@export var warehouse_door_center_x: float = 2.1
@export var warehouse_door_width: float = 1.5
@export var brewery_door_center_x: float = -3.4
@export var brewery_door_width: float = 1.5
@export var brewery_left_x: float = -1.0
@export var brewery_right_x: float = 3.0
@export var brewery_south_z: float = -8.7
@export var guest_entry_left_x: float = -5.0
@export var guest_entry_right_x: float = -1.0
@export var east_door_center_z: float = 0.25
@export var east_door_width: float = 2.2
@export var show_ceiling: bool = true

@export var manual_edit_generated_structure: bool = true
## 总开关：以结构网格为基准同步碰撞体（场景加载时全量对齐 + 编辑器内实时跟随）。
@export var sync_wall_collision_from_mesh: bool = true
## 为缺少碰撞体的实体结构网格自动补建 StaticBody3D（跳过装饰面关键字，如天花板/Zone）。
@export var auto_create_missing_bodies: bool = true

# 不允许自动补建碰撞体的网格名关键字（装饰面 / 标记面，本就不该有实体碰撞）。
var _skip_auto_collision_keywords := PackedStringArray(["Ceiling", "Zone"])

# ---- 材质引用（指向 scenes/tavern/materials/ 下专属材质）----
@export var floor_mat: Material = preload("res://scenes/tavern/materials/tavern_floor_mat.tres")
@export var wall_mat: Material = preload("res://scenes/tavern/materials/tavern_wall_mat.tres")
@export var ceiling_mat: Material = preload("res://scenes/tavern/materials/tavern_ceiling_mat.tres")
@export var pillar_mat: Material = preload("res://scenes/tavern/materials/tavern_pillar_mat.tres")
@export var bar_mat: Material = preload("res://scenes/tavern/materials/tavern_bar_mat.tres")

var _structure: Node3D
# 编辑器实时同步用的"源网格签名"缓存，key=网格实例 id，value=上一帧签名。
var _live_sync_cache: Dictionary = {}


func _ready() -> void:
	_structure = get_node_or_null("BuiltStructure") as Node3D
	if _structure != null:
		if sync_wall_collision_from_mesh:
			sync_wall_collision_bodies()
		return
	push_warning("TavernStructure: BuiltStructure is missing. Add or repair the exact missing nodes by hand; batch regeneration is disabled.")


func _process(_delta: float) -> void:
	# 编辑器内实时同步：用户在视口里拖动 / 旋转 / 缩放 / 改 BoxMesh 尺寸后，
	# 对应的碰撞体当帧即跟随结构更新。运行时（非编辑器）不需要持续同步，
	# 因为碰撞体已在 _ready() 时按结构对齐过了。
	if not Engine.is_editor_hint():
		return
	if not sync_wall_collision_from_mesh:
		return
	_live_sync_collision_bodies()


## 在 Inspector 里把此开关勾选一次（会自动复位），即按当前结构全量对齐碰撞体。
## 日常编辑无需手动触发：编辑器内实时同步已覆盖"改完即同步"。
@export var resync_collision_now: bool = false:
	set(value):
		resync_collision_now = false
		if sync_wall_collision_from_mesh:
			sync_all_structure_collision_bodies()


func get_built_structure() -> Node3D:
	return _structure if _structure != null else get_node_or_null("BuiltStructure") as Node3D


func has_manual_built_structure() -> bool:
	return get_built_structure() != null


## 以结构网格为基准，把所有（已存在或按需补建的）碰撞体对齐到对应网格。
## 兼容旧调用名 sync_wall_collision_bodies()。
func sync_wall_collision_bodies() -> void:
	_sync_all_structure_collision_bodies()


## 同 sync_wall_collision_bodies()，语义更明确的别名。
func sync_all_structure_collision_bodies() -> void:
	_sync_all_structure_collision_bodies()


func _sync_all_structure_collision_bodies() -> void:
	var built := get_built_structure()
	if built == null:
		return
	_live_sync_cache.clear()
	for child in built.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or not _is_collision_source(mesh_instance):
			continue
		_sync_one(mesh_instance)
		_live_sync_cache[mesh_instance.get_instance_id()] = _mesh_signature(mesh_instance)


## 仅当某个源网格相对上一帧发生变化时才写回其碰撞体（避免把未修改的碰撞体反复标脏）。
func _live_sync_collision_bodies() -> void:
	var built := get_built_structure()
	if built == null:
		return
	for child in built.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or not _is_collision_source(mesh_instance):
			continue
		var sig := _mesh_signature(mesh_instance)
		if _live_sync_cache.get(mesh_instance.get_instance_id(), "") == sig:
			continue
		_sync_one(mesh_instance)
		_live_sync_cache[mesh_instance.get_instance_id()] = sig


## 任何直接挂在 BuiltStructure 下的结构网格都是碰撞源，除了已带 "Body" 后缀的碰撞体自身。
func _is_collision_source(mesh_instance: MeshInstance3D) -> bool:
	var node_name := String(mesh_instance.name)
	return not node_name.ends_with("Body")


func _should_auto_create(mesh_instance: MeshInstance3D) -> bool:
	if not auto_create_missing_bodies:
		return false
	if not (mesh_instance.mesh is BoxMesh):
		# 仅对实体盒体补建碰撞，避免给非实体（平面标记等）误加碰撞。
		return false
	var node_name := String(mesh_instance.name)
	for kw in _skip_auto_collision_keywords:
		if node_name.contains(kw):
			return false
	return true


func _paired_body_name(mesh_instance: MeshInstance3D) -> String:
	return "%sBody" % mesh_instance.name


## 同步单个源网格对应的碰撞体：已存在则更新，缺失且允许自动补建则创建。
func _sync_one(mesh_instance: MeshInstance3D) -> void:
	var built := get_built_structure()
	var body_name := _paired_body_name(mesh_instance)
	var body := built.get_node_or_null(body_name) as StaticBody3D
	if body == null:
		if not _should_auto_create(mesh_instance):
			return
		body = StaticBody3D.new()
		body.name = body_name
		body.collision_mask = 0
		built.add_child(body)
		if Engine.is_editor_hint():
			body.owner = owner
	_sync_collision_body_to_mesh(body, mesh_instance)


## 以源网格几何为基准对齐碰撞体：
## - body.transform 直接继承网格 transform（位置 / 旋转 / 缩放全部跟随）；
## - 碰撞形状放在网格"本地 AABB"中心，尺寸等于本地 AABB 尺寸。
## 这样旋转过的结构（如 L 形吧台前挡板）也能得到正确朝向的碰撞盒。
func _sync_collision_body_to_mesh(body: StaticBody3D, mesh_instance: MeshInstance3D) -> void:
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		body.add_child(shape_node)
		if Engine.is_editor_hint():
			shape_node.owner = owner

	var box_shape := shape_node.shape as BoxShape3D
	if box_shape == null:
		box_shape = BoxShape3D.new()
		shape_node.shape = box_shape

	var local_aabb := mesh_instance.get_aabb()
	# 把网格变换拆成「旋转 + 位移」赋给碰撞体（碰撞体保持轴对齐、仅跟随旋转），
	# 把缩放烘焙进碰撞形状的尺寸与本地位置。否则缩放网格会把缩放写进 StaticBody
	# 的 basis（非单位阵），既违背"轴对齐碰撞"约定，又会让世界尺寸/中心被双重缩放。
	var mesh_basis: Basis = mesh_instance.transform.basis
	var scale_vec := mesh_basis.get_scale()
	var rot_basis := mesh_basis.orthonormalized()
	body.transform = Transform3D(rot_basis, mesh_instance.transform.origin)
	shape_node.transform = Transform3D.IDENTITY
	shape_node.position = (local_aabb.position + local_aabb.size * 0.5) * scale_vec
	box_shape.size = local_aabb.size * scale_vec


## 源网格签名：transform 或几何 AABB 变化即视为"需要重新同步"。
func _mesh_signature(mesh_instance: MeshInstance3D) -> String:
	return "%s|%s" % [mesh_instance.transform, mesh_instance.get_aabb()]
