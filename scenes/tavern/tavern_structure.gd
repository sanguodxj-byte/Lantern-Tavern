@tool
class_name TavernStructure
extends Node3D

## 酒馆建筑结构生成器（@tool 模式编辑器内可见）。
## 动态构建地板/墙体/天花板/立柱/吧台骨架，使用酒馆专属材质。
## 所有尺寸常量化，便于设计师在检查器里直接调整而无需手摆网格。

# ---- 房间尺寸（米）----
@export var room_width: float = 15.0
@export var room_depth: float = 15.0
@export var room_height: float = 3.2
@export var wall_thickness: float = 0.3

# ---- 材质引用（指向 scenes/tavern/materials/ 下专属材质）----
@export var floor_mat: Material = preload("res://scenes/tavern/materials/tavern_floor_mat.tres")
@export var wall_mat: Material = preload("res://scenes/tavern/materials/tavern_wall_mat.tres")
@export var ceiling_mat: Material = preload("res://scenes/tavern/materials/tavern_ceiling_mat.tres")
@export var pillar_mat: Material = preload("res://scenes/tavern/materials/tavern_pillar_mat.tres")
@export var bar_mat: Material = preload("res://scenes/tavern/materials/tavern_bar_mat.tres")

var _structure: Node3D

func _ready() -> void:
	_build()

func _build() -> void:
	_clear_existing()
	_structure = Node3D.new()
	_structure.name = "BuiltStructure"
	add_child(_structure, true)
	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_pillars()
	_build_bar_counter()

func _clear_existing() -> void:
	if _structure != null and is_instance_valid(_structure):
		_structure.queue_free()
		_structure = null

func _build_floor() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(room_width, 0.2, room_depth)
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = mesh
	mi.material_override = floor_mat
	mi.position = Vector3(0, -0.1, 0)
	_structure.add_child(mi, true)
	# 碰撞体
	var body := StaticBody3D.new()
	body.name = "FloorBody"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	col.shape = shape
	body.add_child(col, true)
	body.position = mi.position
	_structure.add_child(body, true)

func _build_walls() -> void:
	var h := room_height
	# 北墙 (z = -depth/2)
	_add_wall("WallNorth", Vector3(room_width, h, wall_thickness), Vector3(0, h/2, -room_depth/2 - wall_thickness/2))
	# 南墙
	_add_wall("WallSouth", Vector3(room_width, h, wall_thickness), Vector3(0, h/2, room_depth/2 + wall_thickness/2))
	# 东墙
	_add_wall("WallEast", Vector3(wall_thickness, h, room_depth), Vector3(room_width/2 + wall_thickness/2, h/2, 0))
	# 西墙
	_add_wall("WallWest", Vector3(wall_thickness, h, room_depth), Vector3(-room_width/2 - wall_thickness/2, h/2, 0))

func _add_wall(wall_name: String, sz: Vector3, pos: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.name = wall_name
	mi.mesh = mesh
	mi.material_override = wall_mat
	mi.position = pos
	_structure.add_child(mi, true)
	# 墙体碰撞
	var body := StaticBody3D.new()
	body.name = wall_name + "Body"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	body.add_child(col, true)
	body.position = pos
	_structure.add_child(body, true)

func _build_ceiling() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(room_width, 0.2, room_depth)
	var mi := MeshInstance3D.new()
	mi.name = "Ceiling"
	mi.mesh = mesh
	mi.material_override = ceiling_mat
	mi.position = Vector3(0, room_height, 0)
	_structure.add_child(mi, true)

func _build_pillars() -> void:
	# 四角立柱，距墙 1.5m
	var offsets := [
		Vector3(-room_width/2 + 1.5, 0, -room_depth/2 + 1.5),
		Vector3( room_width/2 - 1.5, 0, -room_depth/2 + 1.5),
		Vector3(-room_width/2 + 1.5, 0,  room_depth/2 - 1.5),
		Vector3( room_width/2 - 1.5, 0,  room_depth/2 - 1.5),
	]
	var i := 0
	for off in offsets:
		i += 1
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.8, room_height, 0.8)
		var mi := MeshInstance3D.new()
		mi.name = "Pillar%d" % i
		mi.mesh = mesh
		mi.material_override = pillar_mat
		mi.position = Vector3(off.x, room_height/2, off.z)
		_structure.add_child(mi, true)
		# 立柱碰撞体
		_add_box_collision(mi.name + "Body", mi.position, mesh.size)

func _build_bar_counter() -> void:
	# 吧台沿北墙铺设：台面 + 前挡板
	var bar_len := room_width - 4.0  # 留 2m 出入口
	# 台面
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(bar_len, 0.15, 1.2)
	var top := MeshInstance3D.new()
	top.name = "BarTop"
	top.mesh = top_mesh
	top.material_override = bar_mat
	top.position = Vector3(0, 1.1, -room_depth/2 + 0.9)
	_structure.add_child(top, true)
	# 台面碰撞体
	_add_box_collision("BarTopBody", top.position, top_mesh.size)
	# 前挡板
	var front_mesh := BoxMesh.new()
	front_mesh.size = Vector3(bar_len, 1.0, 0.15)
	var front := MeshInstance3D.new()
	front.name = "BarFront"
	front.mesh = front_mesh
	front.material_override = pillar_mat
	front.position = Vector3(0, 0.5, -room_depth/2 + 1.5)
	_structure.add_child(front, true)
	# 前挡板碰撞体
	_add_box_collision("BarFrontBody", front.position, front_mesh.size)

## 统一创建 StaticBody3D + BoxShape3D 碰撞（环境层）
func _add_box_collision(body_name: String, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1  # 环境层
	body.collision_mask = 0
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col, true)
	_structure.add_child(body, true)

# 编辑器内属性变化时重建
func _set(_p: StringName, _v: Variant) -> bool:
	if Engine.is_editor_hint():
		_build()
	return false
