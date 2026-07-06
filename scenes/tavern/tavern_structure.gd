@tool
class_name TavernStructure
extends Node3D

## 酒馆建筑结构保护脚本。
## 酒馆结构以 tavern.tscn 中手工编辑的 BuiltStructure 为准，禁止批量重建或合并覆盖。

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
@export var show_ceiling: bool = false

@export var manual_edit_generated_structure: bool = true
@export var sync_wall_collision_from_mesh: bool = true

# ---- 材质引用（指向 scenes/tavern/materials/ 下专属材质）----
@export var floor_mat: Material = preload("res://scenes/tavern/materials/tavern_floor_mat.tres")
@export var wall_mat: Material = preload("res://scenes/tavern/materials/tavern_wall_mat.tres")
@export var ceiling_mat: Material = preload("res://scenes/tavern/materials/tavern_ceiling_mat.tres")
@export var pillar_mat: Material = preload("res://scenes/tavern/materials/tavern_pillar_mat.tres")
@export var bar_mat: Material = preload("res://scenes/tavern/materials/tavern_bar_mat.tres")

var _structure: Node3D


func _ready() -> void:
	_structure = get_node_or_null("BuiltStructure") as Node3D
	if _structure != null:
		if sync_wall_collision_from_mesh:
			sync_wall_collision_bodies()
		return
	push_warning("TavernStructure: BuiltStructure is missing. Add or repair the exact missing nodes by hand; batch regeneration is disabled.")


func get_built_structure() -> Node3D:
	return _structure if _structure != null else get_node_or_null("BuiltStructure") as Node3D


func has_manual_built_structure() -> bool:
	return get_built_structure() != null


func sync_wall_collision_bodies() -> void:
	var built := get_built_structure()
	if built == null:
		return
	for child in built.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or not _is_wall_collision_source(mesh_instance):
			continue
		_sync_collision_body_to_mesh(built, mesh_instance)


func _is_wall_collision_source(mesh_instance: MeshInstance3D) -> bool:
	var node_name := String(mesh_instance.name)
	if node_name.ends_with("Body"):
		return false
	if not (node_name.contains("Wall") or node_name.contains("Lintel")):
		return false
	return mesh_instance.mesh is BoxMesh


func _sync_collision_body_to_mesh(built: Node3D, mesh_instance: MeshInstance3D) -> void:
	var body_name := "%sBody" % mesh_instance.name
	var body := built.get_node_or_null(body_name) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = body_name
		body.collision_mask = 0
		built.add_child(body)
		if Engine.is_editor_hint():
			body.owner = owner

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

	var bounds := _mesh_aabb_in_parent_space(mesh_instance)
	body.transform = Transform3D(Basis.IDENTITY, bounds.position + bounds.size * 0.5)
	shape_node.transform = Transform3D.IDENTITY
	box_shape.size = bounds.size


func _mesh_aabb_in_parent_space(mesh_instance: MeshInstance3D) -> AABB:
	var local := mesh_instance.get_aabb()
	var initialized := false
	var result := AABB()
	for corner in _aabb_corners(local):
		var point: Vector3 = mesh_instance.transform * corner
		if initialized:
			result = result.expand(point)
		else:
			result = AABB(point, Vector3.ZERO)
			initialized = true
	return result


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var min_v := aabb.position
	var max_v := aabb.position + aabb.size
	return [
		Vector3(min_v.x, min_v.y, min_v.z),
		Vector3(max_v.x, min_v.y, min_v.z),
		Vector3(min_v.x, max_v.y, min_v.z),
		Vector3(max_v.x, max_v.y, min_v.z),
		Vector3(min_v.x, min_v.y, max_v.z),
		Vector3(max_v.x, min_v.y, max_v.z),
		Vector3(min_v.x, max_v.y, max_v.z),
		Vector3(max_v.x, max_v.y, max_v.z),
	]
