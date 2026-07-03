class_name PickableItem
extends StaticBody3D

const GLOW_MATERIAL := preload("res://materials/glow_material.tres")
const HIGHLIGHT_MATERIAL := preload("res://materials/highlight_material.tres")

@export var mesh_node : MeshInstance3D
@export var furniture_data: FurnitureData
@export var shield_data: ShieldData
@export var weapon_data: WeaponData
@export var material_id: String = ""

@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var presence_light: OmniLight3D = %PresenceLight

var glow_material: StandardMaterial3D
var highlight_material: StandardMaterial3D

func _ready() -> void:
	var pickable_object : Node3D = null
	highlight_material = HIGHLIGHT_MATERIAL.duplicate()
	glow_material = GLOW_MATERIAL.duplicate()
	
	if weapon_data:
		pickable_object = weapon_data.glb_mesh.instantiate()
	elif shield_data:
		pickable_object = shield_data.glb_mesh.instantiate()
	elif material_id != "":
		# Spawn custom brewing material from OBJ model
		var obj_path = "res://assets/models/%s.obj" % material_id
		if ResourceLoader.exists(obj_path):
			var mesh_res = load(obj_path)
			var mi = MeshInstance3D.new()
			mi.mesh = mesh_res
			
			# Add a nice material
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.8, 0.6, 0.2) # Default Amber Warm
			mat.roughness = 0.5
			
			var lower_id = material_id.to_lower()
			if "glowcap" in lower_id:
				mat.albedo_color = Color(0.1, 0.5, 1.0)
				mat.emission_enabled = true
				mat.emission = Color(0.05, 0.2, 0.5)
			elif "berry" in lower_id:
				mat.albedo_color = Color(0.9, 0.1, 0.2)
			elif "bloom" in lower_id:
				mat.albedo_color = Color(1.0, 0.3, 0.0)
				mat.emission_enabled = true
				mat.emission = Color(0.3, 0.1, 0.0)
			elif "lichen" in lower_id:
				mat.albedo_color = Color(0.3, 0.6, 0.4)
			elif "honeycomb" in lower_id:
				mat.albedo_color = Color(1.0, 0.7, 0.1)
			elif "grass" in lower_id:
				mat.albedo_color = Color(0.4, 0.8, 0.2)
			elif "ear" in lower_id:
				mat.albedo_color = Color(0.5, 0.45, 0.35)
			elif "sac" in lower_id:
				mat.albedo_color = Color(0.6, 0.1, 0.7)
			elif "jelly" in lower_id:
				mat.albedo_color = Color(0.2, 0.8, 0.5)
				mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.8
				
			mi.material_override = mat
			add_child(mi)
			mesh_node = mi
			
			# Setup standard collision box for tiny collectable items
			var box = BoxShape3D.new()
			box.size = Vector3(0.4, 0.4, 0.4)
			collision_shape.shape = box
			
			# Highlight material override for materials
			highlight_material.albedo_color = mat.albedo_color * 1.5
			
	if pickable_object != null:
		add_child(pickable_object)
		mesh_node = pickable_object.get_child(0) as MeshInstance3D
		
	if mesh_node != null and material_id == "":
		collision_shape.shape = mesh_node.mesh.create_convex_shape()
		if weapon_data or shield_data:
			presence_light.visible = false
			mesh_node.material_override = glow_material

func highlight() -> void:
	if furniture_data or material_id != "":
		mesh_node.material_override = highlight_material

func unhighlight() -> void:
	if furniture_data or material_id != "":
		mesh_node.material_override = null
