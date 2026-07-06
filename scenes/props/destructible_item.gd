class_name DestructibleItem
extends Node3D

const EXPLOSION_FORCE := 5.0
const VOXEL_UNIT := 1.0 / 32.0
const PROP_ATLAS := preload("res://assets/textures/props/voxel/voxel_prop_material_atlas_32px.png")
const PROP_SHADER := preload("res://assets/shaders/dungeon_terrain.gdshader")

@export var furniture_data: FurnitureData

@onready var audio_stream_player_3d: AudioStreamPlayer3D = %AudioStreamPlayer3D

var destructible_object: Node3D = null
var _fragment_material: ShaderMaterial = null

func _ready() -> void:
	set_meta("voxel_style", "one_px_32px_per_meter")
	set_meta("voxel_unit_px", 1)
	set_meta("voxel_px_per_meter", 32)
	_ensure_fragments()

func explode() -> void:
	_ensure_fragments()
	if destructible_object == null:
		return
	var audio := audio_stream_player_3d
	if audio == null:
		audio = get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if audio != null:
		AudioManager.play("barrel-destroy", audio)
	for child in destructible_object.get_children():
		var fragment := child as RigidBody3D
		if fragment == null:
			continue
		var direction := (fragment.position + Vector3(0.0, 0.18, 0.0)).normalized()
		if direction == Vector3.ZERO:
			direction = Vector3.UP
		fragment.freeze = false
		fragment.sleeping = false
		fragment.linear_velocity = direction * EXPLOSION_FORCE
		fragment.angular_velocity = Vector3(direction.z, direction.x + 0.4, -direction.y) * 4.0
		fragment.apply_impulse(direction * EXPLOSION_FORCE, fragment.position)
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
	
	# Spawning random gatherable brewing material!
	_spawn_random_material()

func _spawn_random_material() -> void:
	var pool = [
		"wild_glowcap", "frost_berry", "fire_bloom", "cave_lichen", 
		"honeycomb", "sweet_grass", "bitter_root", "mountain_barley"
	]
	var mat_id = pool[randi() % pool.size()]
	
	# Delay load to prevent circular dependencies or scene loading conflicts during explosion physics
	var mat_scene = load("res://scenes/equipment/pickable_item.tscn")
	if mat_scene:
		var item_instance = mat_scene.instantiate()
		item_instance.material_id = mat_id
		item_instance.global_position = global_position + Vector3(0, 0.4, 0)
		var spawn_parent := get_parent()
		if spawn_parent == null:
			item_instance.queue_free()
			return
		spawn_parent.add_child(item_instance)
		print("Dungeon container exploded! Dropped material: ", mat_id)


func _ensure_fragments() -> void:
	if destructible_object != null and is_instance_valid(destructible_object):
		return
	destructible_object = get_node_or_null("VoxelFragments") as Node3D
	if destructible_object == null:
		destructible_object = _build_voxel_fragments()
		add_child(destructible_object)
	for child in destructible_object.get_children():
		var fragment := child as RigidBody3D
		if fragment == null:
			continue
		fragment.set_collision_layer_value(1, false)
		fragment.freeze = false
		fragment.sleeping = false


func _build_voxel_fragments() -> Node3D:
	var root := Node3D.new()
	root.name = "VoxelFragments"
	for i in range(9):
		var x := float((i % 3) - 1) * 7.0
		var y := float(i / 3) * 5.0 + 4.0
		var z := float(((i * 2) % 3) - 1) * 6.0
		var size := Vector3i(5 + (i % 2) * 2, 5, 5 + ((i + 1) % 2) * 2)
		root.add_child(_make_fragment("Fragment%d" % i, size, Vector3(x, y, z)))
	return root


func _make_fragment(name: String, size_px: Vector3i, center_px: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = name
	body.position = center_px * VOXEL_UNIT
	body.set_meta("voxel_generated", true)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "VoxelMesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(size_px.x), float(size_px.y), float(size_px.z)) * VOXEL_UNIT
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _get_fragment_material()
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	body.add_child(collision)
	return body


func _get_fragment_material() -> ShaderMaterial:
	if _fragment_material == null:
		_fragment_material = ShaderMaterial.new()
		_fragment_material.shader = PROP_SHADER
		_fragment_material.set_shader_parameter("atlas", PROP_ATLAS)
		_fragment_material.set_shader_parameter("tile_col_row", Vector2(1, 0))
		_fragment_material.set_shader_parameter("tile_span", Vector2(1, 1))
		_fragment_material.set_shader_parameter("atlas_grid", Vector2(4, 2))
		_fragment_material.set_shader_parameter("tile_repeat", Vector2(1, 1))
		_fragment_material.set_shader_parameter("roughness", 0.86)
		_fragment_material.set_shader_parameter("specular", 0.1)
	return _fragment_material
