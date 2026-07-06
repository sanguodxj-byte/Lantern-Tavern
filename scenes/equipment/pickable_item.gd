class_name PickableItem
extends RigidBody3D

const HIGHLIGHT_MATERIAL := preload("res://materials/highlight_material.tres")
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")
const RD := preload("res://globals/combat/rune_data.gd")

@export var mesh_node : MeshInstance3D
@export var furniture_data: FurnitureData
@export var shield_data: ShieldData
@export var weapon_data: WeaponData
@export var material_id: String = ""
@export var rune_id: String = ""

@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var presence_light: OmniLight3D = %PresenceLight

var highlight_material: StandardMaterial3D

func _ready() -> void:
	PhysicsSetup.setup_pickable(self)
	continuous_cd = true
	can_sleep = true
	var pickable_object : Node3D = null
	highlight_material = HIGHLIGHT_MATERIAL.duplicate()
	highlight_material.emission_enabled = false
	if presence_light != null:
		presence_light.visible = false
	
	if weapon_data and weapon_data.glb_mesh:
		pickable_object = weapon_data.glb_mesh.instantiate()
	elif shield_data and shield_data.glb_mesh:
		pickable_object = shield_data.glb_mesh.instantiate()
	elif material_id != "":
		pickable_object = _instantiate_material_model(material_id)
		if pickable_object != null:
			add_child(pickable_object)
			mesh_node = _find_first_mesh_instance(pickable_object)
			_fit_collision_to_visual(pickable_object)
			var material_color := _material_highlight_color(material_id)
			if mesh_node != null:
				var mat := mesh_node.get_active_material(0) as StandardMaterial3D
				if mat != null:
					material_color = mat.albedo_color
			highlight_material.albedo_color = material_color * 1.5
			pickable_object = null
	elif rune_id != "":
		highlight_material.albedo_color = _rune_highlight_color(rune_id)
			
	if pickable_object != null:
		add_child(pickable_object)
		mesh_node = _find_first_mesh_instance(pickable_object)
		
	if mesh_node != null and material_id == "":
		collision_shape.shape = mesh_node.mesh.create_convex_shape()
		if weapon_data or shield_data:
			presence_light.visible = false
	elif furniture_data != null:
		mesh_node = _find_first_mesh_instance(self)
		_fit_collision_to_visual(self)
	if collision_shape.shape == null:
		PhysicsSetup.setup_pickable(self)
	_disable_drop_lights_recursive(self)
	_disable_drop_material_glow_recursive(self)

func _is_inside_procedural_dungeon() -> bool:
	var node: Node = self
	while node != null:
		if node is ProceduralDungeon:
			return true
		node = node.get_parent()
	var level := GameState.current_level if GameState != null else null
	return level is ProceduralDungeon

func highlight() -> void:
	if mesh_node != null and (furniture_data or material_id != "" or rune_id != ""):
		mesh_node.material_override = highlight_material

func unhighlight() -> void:
	if mesh_node != null and (furniture_data or material_id != "" or rune_id != ""):
		mesh_node.material_override = null

func get_item_name() -> String:
	if weapon_data:
		return weapon_data.get_full_display_name()
	elif shield_data:
		return shield_data.name
	elif furniture_data:
		return furniture_data.name
	elif material_id != "":
		var names = {
			"wild_glowcap": tr("Wild Glowcap"),
			"frost_berry": tr("Frost Berry"),
			"fire_bloom": tr("Fire Bloom"),
			"cave_lichen": tr("Cave Lichen"),
			"honeycomb": tr("Honeycomb"),
			"sweet_grass": tr("Sweet Grass"),
			"bitter_root": tr("Bitter Root"),
			"mountain_barley": tr("Mountain Barley")
		}
		return names.get(material_id, MATERIAL_MODELS.get_display_name(material_id))
	elif rune_id != "":
		return RD.get_rune_name(rune_id)
	return tr("Item")

func _instantiate_material_model(id: String) -> Node3D:
	var glb_path := _material_glb_path(id)
	if ResourceLoader.exists(glb_path):
		var packed_scene := load(glb_path) as PackedScene
		if packed_scene != null:
			var instance := packed_scene.instantiate() as Node3D
			if instance != null:
				instance.position += MATERIAL_MODELS.get_visual_offset(id)
				instance.rotation_degrees = MATERIAL_MODELS.get_visual_rotation_degrees(id)
			return instance
	return null

func _material_glb_path(id: String) -> String:
	var registered_path := MATERIAL_MODELS.get_model_path(id)
	if not registered_path.is_empty():
		return registered_path
	return "res://assets/models/materials/materials_%s.glb" % id

func _material_highlight_color(id: String) -> Color:
	var lower_id := id.to_lower()
	if "glowcap" in lower_id:
		return Color(0.1, 0.5, 1.0)
	if "berry" in lower_id:
		return Color(0.9, 0.1, 0.2)
	if "bloom" in lower_id:
		return Color(1.0, 0.3, 0.0)
	if "lichen" in lower_id:
		return Color(0.3, 0.6, 0.4)
	if "honeycomb" in lower_id:
		return Color(1.0, 0.7, 0.1)
	if "grass" in lower_id:
		return Color(0.4, 0.8, 0.2)
	if "ear" in lower_id:
		return Color(0.5, 0.45, 0.35)
	if "sac" in lower_id:
		return Color(0.6, 0.1, 0.7)
	if "jelly" in lower_id:
		return Color(0.2, 0.8, 0.5)
	return Color(0.8, 0.6, 0.2)

func _rune_highlight_color(id: String) -> Color:
	match id:
		"ember":
			return Color(1.0, 0.35, 0.12)
		"quick":
			return Color(0.25, 0.85, 1.0)
		"force":
			return Color(0.9, 0.85, 0.35)
		"echo":
			return Color(0.75, 0.45, 1.0)
		"guardian":
			return Color(0.35, 0.9, 0.55)
		_:
			return Color(0.7, 0.55, 1.0)

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null

func _fit_collision_to_mesh(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null or collision_shape == null:
		return
	var box := BoxShape3D.new()
	box.size = _clamp_pickup_size(mi.mesh.get_aabb().size)
	collision_shape.shape = box
	collision_shape.position = mi.mesh.get_aabb().get_center()

func _fit_collision_to_visual(root: Node3D) -> void:
	if collision_shape == null:
		return
	var aabb := _combined_mesh_aabb(root)
	if aabb.size == Vector3.ZERO:
		return
	var box := BoxShape3D.new()
	box.size = _clamp_pickup_size(aabb.size)
	collision_shape.shape = box
	collision_shape.position = aabb.get_center()

func _combined_mesh_aabb(root: Node3D) -> AABB:
	var combined := AABB()
	var initialized := false
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for child in meshes:
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local_aabb := mi.get_aabb()
		var item_space := global_transform.affine_inverse() * mi.global_transform
		var transformed := item_space * local_aabb
		if initialized:
			combined = combined.merge(transformed)
		else:
			combined = transformed
			initialized = true
	return combined if initialized else AABB()

func _clamp_pickup_size(size: Vector3) -> Vector3:
	return Vector3(
		maxf(size.x, 0.08),
		maxf(size.y, 0.08),
		maxf(size.z, 0.08)
	)

func _disable_drop_lights_recursive(node: Node) -> void:
	if node is Light3D:
		(node as Light3D).visible = false
	for child in node.get_children():
		_disable_drop_lights_recursive(child)

func _disable_drop_material_glow_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_disable_mesh_material_glow(node as MeshInstance3D)
	for child in node.get_children():
		_disable_drop_material_glow_recursive(child)

func _disable_mesh_material_glow(mesh_instance: MeshInstance3D) -> void:
	var override := _without_material_emission(mesh_instance.material_override)
	if override != null:
		mesh_instance.material_override = override
	if mesh_instance.mesh == null:
		return
	for surface_index in mesh_instance.mesh.get_surface_count():
		var source := mesh_instance.get_surface_override_material(surface_index)
		if source == null:
			source = mesh_instance.mesh.surface_get_material(surface_index)
		var sanitized := _without_material_emission(source)
		if sanitized != null:
			mesh_instance.set_surface_override_material(surface_index, sanitized)

func _without_material_emission(source: Material) -> Material:
	var standard := source as StandardMaterial3D
	if standard == null:
		return source
	if not standard.emission_enabled:
		return source
	var copy := standard.duplicate() as StandardMaterial3D
	copy.emission_enabled = false
	return copy
