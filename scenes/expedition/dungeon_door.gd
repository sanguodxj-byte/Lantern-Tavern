class_name DungeonDoor
extends StaticBody3D

signal opened
signal broken
signal pressure_action(action: String)

const KIND_STANDARD := "standard"
const KIND_BOSS := "boss"
const PRESSURE_ACTION_OPEN := "open_door"
const PRESSURE_ACTION_BREAK := "break_door"
const STANDARD_SIZE := Vector2(1.0, 2.0)
const BOSS_SIZE := Vector2(2.0, 2.0)
const VOXEL_UNIT := 1.0 / 32.0
const THICKNESS_VOXELS := 4
const THICKNESS := VOXEL_UNIT * THICKNESS_VOXELS
const SKIN_THICKNESS := 0.012
const CORE_THICKNESS := THICKNESS - SKIN_THICKNESS * 2.0
const OPEN_DURATION := 0.22

@export var interaction_name := "Door"
@export var door_kind := KIND_STANDARD
@export var max_integrity := 1
@export var open_duration := OPEN_DURATION

var current_integrity := 1
var is_open := false
var is_broken := false
var _collision_shape: CollisionShape3D = null
var _leaf_pivots: Array[Node3D] = []
var _open_tween: Tween = null


func configure(kind: String, normal_dir: Vector2i, front_material: Material, side_material: Material = null, top_material: Material = null) -> void:
	door_kind = kind
	interaction_name = "Boss Door" if door_kind == KIND_BOSS else "Door"
	max_integrity = 3 if door_kind == KIND_BOSS else 1
	current_integrity = max_integrity
	collision_layer = PhysicsSetup.LAYER_SCENE_OBJECT | PhysicsSetup.LAYER_TRIGGER
	collision_mask = PhysicsSetup.MASK_ENVIRONMENT
	set_meta("door_kind", door_kind)
	set_meta("topdown_kind", "boss_door" if door_kind == KIND_BOSS else "door")
	set_meta("voxel_unit_px", 1)
	set_meta("voxel_px_per_meter", 32)
	set_meta("door_thickness_px", THICKNESS_VOXELS)
	_build_collision(normal_dir)
	_build_visual(
		normal_dir,
		front_material,
		side_material if side_material != null else front_material,
		top_material if top_material != null else front_material
	)


func interact(source_player: Node = null) -> void:
	if is_open or is_broken:
		return
	open(source_player)


func open(_source_player: Node = null) -> void:
	if is_open or is_broken:
		return
	is_open = true
	if _collision_shape != null:
		_collision_shape.disabled = true
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	for i in range(_leaf_pivots.size()):
		var pivot := _leaf_pivots[i]
		var sign := -1.0 if i == 0 else 1.0
		_open_tween.tween_property(pivot, "rotation:y", sign * PI * 0.5, open_duration) \
			.set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_OUT)
	pressure_action.emit(PRESSURE_ACTION_OPEN)
	opened.emit()


func try_receive_hit(_source: Node = null, damage: int = 1) -> void:
	apply_damage(damage)


func try_receive_hit_result(_source: Node = null, result = null) -> void:
	var damage := 1
	if result != null:
		damage = maxi(1, int(result.get("final_damage")))
	apply_damage(damage)


func take_damage(damage: int, _source: Node = null) -> void:
	apply_damage(damage)


func apply_damage(damage: int) -> void:
	if is_open or is_broken:
		return
	current_integrity -= maxi(1, damage)
	if current_integrity <= 0:
		break_apart()


func break_apart() -> void:
	if is_broken:
		return
	is_broken = true
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	if _collision_shape != null:
		_collision_shape.disabled = true
	for pivot in _leaf_pivots:
		pivot.visible = false
	pressure_action.emit(PRESSURE_ACTION_BREAK)
	broken.emit()


func _build_collision(normal_dir: Vector2i) -> void:
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	var size := BOSS_SIZE if door_kind == KIND_BOSS else STANDARD_SIZE
	if normal_dir.x != 0:
		shape.size = Vector3(THICKNESS, size.y, size.x)
	else:
		shape.size = Vector3(size.x, size.y, THICKNESS)
	_collision_shape.shape = shape
	_collision_shape.position = Vector3(0, size.y * 0.5, 0)
	add_child(_collision_shape)


func _build_visual(normal_dir: Vector2i, front_material: Material, side_material: Material, top_material: Material) -> void:
	_leaf_pivots.clear()
	var size := BOSS_SIZE if door_kind == KIND_BOSS else STANDARD_SIZE
	var width_axis := Vector3(0, 0, 1) if normal_dir.x != 0 else Vector3(1, 0, 0)
	if door_kind == KIND_BOSS:
		_add_leaf("LeftLeaf", width_axis, -size.x * 0.5, size.x * 0.25, size.x * 0.5, size.y, normal_dir, front_material, side_material, top_material)
		_add_leaf("RightLeaf", width_axis, size.x * 0.5, -size.x * 0.25, size.x * 0.5, size.y, normal_dir, front_material, side_material, top_material)
	else:
		var pivot := Node3D.new()
		pivot.name = "LeafPivot"
		pivot.position = -width_axis * (size.x * 0.5)
		add_child(pivot)
		_leaf_pivots.append(pivot)
		_add_leaf_mesh(pivot, "Leaf", width_axis * (size.x * 0.5), size.x, size.y, normal_dir, front_material, side_material, top_material)


func _add_leaf(name: String, width_axis: Vector3, pivot_offset: float, mesh_offset: float, width: float, height: float, normal_dir: Vector2i, front_material: Material, side_material: Material, top_material: Material) -> void:
	var pivot := Node3D.new()
	pivot.name = name + "Pivot"
	pivot.position = width_axis * pivot_offset
	add_child(pivot)
	_leaf_pivots.append(pivot)
	_add_leaf_mesh(pivot, name, width_axis * mesh_offset, width, height, normal_dir, front_material, side_material, top_material)


func _add_leaf_mesh(parent: Node3D, name: String, local_pos: Vector3, width: float, height: float, normal_dir: Vector2i, front_material: Material, side_material: Material, top_material: Material) -> void:
	var normal := Vector3(float(normal_dir.x), 0.0, float(normal_dir.y))
	var center := local_pos + Vector3(0, height * 0.5, 0)
	_add_leaf_box(parent, name + "Front", _leaf_face_size(width, height, normal_dir, SKIN_THICKNESS), center + normal * (THICKNESS * 0.5 - SKIN_THICKNESS * 0.5), front_material)
	_add_leaf_box(parent, name + "Back", _leaf_face_size(width, height, normal_dir, SKIN_THICKNESS), center - normal * (THICKNESS * 0.5 - SKIN_THICKNESS * 0.5), front_material)
	_add_leaf_box(parent, name + "Side", _leaf_face_size(width, height, normal_dir, CORE_THICKNESS), center, side_material)
	_add_leaf_box(parent, name + "Top", _leaf_top_size(width, normal_dir), local_pos + Vector3(0, height + SKIN_THICKNESS * 0.5, 0), top_material)


func _leaf_face_size(width: float, height: float, normal_dir: Vector2i, depth: float) -> Vector3:
	if normal_dir.x != 0:
		return Vector3(depth, height, width)
	return Vector3(width, height, depth)


func _leaf_top_size(width: float, normal_dir: Vector2i) -> Vector3:
	if normal_dir.x != 0:
		return Vector3(THICKNESS, SKIN_THICKNESS, width)
	return Vector3(width, SKIN_THICKNESS, THICKNESS)


func _add_leaf_box(parent: Node3D, name: String, size: Vector3, local_pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = local_pos
	parent.add_child(mesh)
	return mesh
