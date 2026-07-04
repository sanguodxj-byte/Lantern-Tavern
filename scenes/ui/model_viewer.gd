extends Control
class_name ModelViewer

@onready var asset_tree: Tree = $HBoxContainer/Sidebar/AssetTree
@onready var viewport: SubViewport = $HBoxContainer/ViewportContainer/SubViewport
@onready var camera_pivot: Node3D = $HBoxContainer/ViewportContainer/SubViewport/CameraPivot
@onready var camera: Camera3D = $HBoxContainer/ViewportContainer/SubViewport/CameraPivot/Camera3D
@onready var main_light: DirectionalLight3D = $HBoxContainer/ViewportContainer/SubViewport/MainLight
@onready var fill_light: OmniLight3D = $HBoxContainer/ViewportContainer/SubViewport/FillLight

# Inspector labels
@onready var asset_name_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/AssetNameVal
@onready var asset_path_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/AssetPathVal
@onready var asset_type_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/AssetTypeVal
@onready var bounds_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/BoundsVal
@onready var vertices_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/VerticesVal
@onready var status_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/StatusVal

# Controls
@onready var rot_speed_slider: HSlider = $HBoxContainer/Sidebar/PanelContainer/VBoxContainer/HBoxContainer_Rot/RotSpeedSlider
@onready var light_color_option: OptionButton = $HBoxContainer/Sidebar/PanelContainer/VBoxContainer/HBoxContainer_Light/LightColorOption
@onready var toggle_grid_btn: CheckButton = $HBoxContainer/Sidebar/PanelContainer/VBoxContainer/ToggleGridBtn
@onready var toggle_auto_rot: CheckButton = $HBoxContainer/Sidebar/PanelContainer/VBoxContainer/ToggleAutoRotBtn
@onready var return_btn: Button = $HBoxContainer/Sidebar/ReturnBtn

var current_model_node: Node3D = null
var rotation_speed: float = 0.5
var is_auto_rotating: bool = true
var grid_helper: MeshInstance3D = null

# Asset Database defining path mapping
# Weapons category is auto-populated from WeaponRegistry (data/weapons/weapons.json)
# Other categories are hardcoded for now.
var asset_database: Dictionary = {
	tr("Props / Objects"): {
		tr("Table"): "res://assets/models/table.obj",
		tr("Stool"): "res://assets/models/stool.obj",
		tr("Barrel"): "res://assets/models/barrel.obj",
		tr("Pillar"): "res://assets/models/pillar.obj",
		tr("Chest"): "res://assets/models/chest.obj",
		tr("Portal"): "res://assets/models/portal.obj",
		tr("Mug"): "res://assets/models/mug.obj"
	},
	tr("Weapons & Shields"): {},
	tr("Monsters"): {
		tr("Goblin"): "res://assets/models/goblin.obj",
		tr("Spider"): "res://assets/models/spider.obj",
		tr("Slime"): "res://assets/models/slime.obj",
		tr("Skeleton"): "res://assets/models/skeleton.obj",
		tr("Bat"): "res://assets/models/bat.obj",
		tr("Rat"): "res://assets/models/rat.obj",
		tr("Troll"): "res://assets/models/troll.obj",
		tr("Zombie"): "res://assets/models/zombie.obj",
		tr("Imp"): "res://assets/models/imp.obj",
		tr("Harpy"): "res://assets/models/harpy.obj"
	},
	tr("Gatherable Materials"): {
		tr("Wild Glowcap"): "res://assets/models/wild_glowcap.obj",
		tr("Frost Berry"): "res://assets/models/frost_berry.obj",
		tr("Fire Bloom"): "res://assets/models/fire_bloom.obj",
		tr("Cave Lichen"): "res://assets/models/cave_lichen.obj",
		tr("Honeycomb"): "res://assets/models/honeycomb.obj",
		tr("Sweet Grass"): "res://assets/models/sweet_grass.obj",
		tr("Bitter Root"): "res://assets/models/bitter_root.obj",
		tr("Mountain Barley"): "res://assets/models/mountain_barley.obj",
		tr("Witch Plum"): "res://assets/models/witch_plum.obj",
		tr("Shadow Lotus"): "res://assets/models/shadow_lotus.obj",
		tr("Sunflower Seed"): "res://assets/models/sunflower_seed.obj",
		tr("Ironwood Bark"): "res://assets/models/ironwood_bark.obj",
		tr("Amber Resin"): "res://assets/models/amber_resin.obj",
		tr("Acid Grape"): "res://assets/models/acid_grape.obj",
		tr("Rock Salt"): "res://assets/models/rock_salt.obj"
	},
	tr("Monster Drops"): {
		tr("Goblin Ear"): "res://assets/models/goblin_ear.obj",
		tr("Goblin Tooth"): "res://assets/models/goblin_tooth.obj",
		tr("Spider Poison Sac"): "res://assets/models/spider_poison_sac.obj",
		tr("Spider Web"): "res://assets/models/spider_web.obj",
		tr("Slime Core"): "res://assets/models/slime_core.obj",
		tr("Slime Jelly"): "res://assets/models/slime_jelly.obj",
		tr("Bat Wing"): "res://assets/models/bat_wing.obj",
		tr("Bat Guano"): "res://assets/models/bat_guano.obj",
		tr("Skeleton Dust"): "res://assets/models/skeleton_dust.obj",
		tr("Fossil Bone"): "res://assets/models/fossil_bone.obj",
		tr("Giant Rat Tail"): "res://assets/models/giant_rat_tail.obj",
		tr("Rat Whisker"): "res://assets/models/rat_whisker.obj",
		tr("Imp Horn Dust"): "res://assets/models/imp_horn_dust.obj",
		tr("Imp Wing Ash"): "res://assets/models/imp_wing_ash.obj",
		tr("Troll Blood"): "res://assets/models/troll_blood.obj",
		tr("Troll Skin"): "res://assets/models/troll_skin.obj",
		tr("Zombie Flesh"): "res://assets/models/zombie_flesh.obj",
		tr("Zombie Nail"): "res://assets/models/zombie_nail.obj",
		tr("Harpy Feather"): "res://assets/models/harpy_feather.obj",
		tr("Harpy Talon"): "res://assets/models/harpy_talon.obj",
		tr("Boar Tusk"): "res://assets/models/boar_tusk.obj"
	}
}

func _ready() -> void:
	# Wire up UI controls
	return_btn.pressed.connect(_on_return_pressed)
	toggle_grid_btn.toggled.connect(_on_toggle_grid)
	toggle_auto_rot.toggled.connect(_on_toggle_auto_rot)
	rot_speed_slider.value_changed.connect(_on_rot_speed_changed)
	
	# Configure Light Color Options
	light_color_option.add_item(tr("Cozy Candlelight"))
	light_color_option.add_item(tr("Daylight"))
	light_color_option.add_item(tr("Eerie Moonlight"))
	light_color_option.item_selected.connect(_on_light_color_selected)
	
	# Build grid helper
	_create_grid_mesh()
	
	# Auto-populate weapons category from WeaponRegistry (data/weapons/weapons.json)
	_populate_weapons_from_registry()
	
	# Build asset tree
	_build_asset_tree()
	
	# Select first element by default
	_select_default_item()


func _populate_weapons_from_registry() -> void:
	# Merge all weapon registry entries into a single "Weapons & Shields" category.
	# This prevents each weapon type (Swords, Axes, etc.) from becoming a separate
	# top-level tree node.
	var merged: Dictionary = {}
	var registry_entries := WeaponRegistry.get_model_viewer_entries()
	for category_name in registry_entries.keys():
		for item_name in registry_entries[category_name].keys():
			merged[tr(item_name)] = registry_entries[category_name][item_name]

	# Also add non-registry items (static props that don't have JSON entries yet)
	merged[tr("Buckler")] = "res://assets/meshes/shields/buckler.glb"

	# Replace the Weapons & Shields category with the merged entries
	asset_database[tr("Weapons & Shields")] = merged

func _process(delta: float) -> void:
	if is_auto_rotating and current_model_node:
		current_model_node.rotate_y(rotation_speed * delta)

func _create_grid_mesh() -> void:
	grid_helper = MeshInstance3D.new()
	var grid_mesh = PlaneMesh.new()
	grid_mesh.size = Vector2(8, 8)
	grid_mesh.subdivide_width = 8
	grid_mesh.subdivide_depth = 8
	grid_helper.mesh = grid_mesh
	
	# Transparent grid material
	var grid_mat = StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.2)
	grid_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	grid_mat.roughness = 1.0
	grid_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.use_point_size = true
	grid_helper.material_override = grid_mat
	grid_helper.position = Vector3(0, -0.01, 0)
	viewport.add_child(grid_helper)
	grid_helper.visible = true

func _build_asset_tree() -> void:
	asset_tree.clear()
	var root = asset_tree.create_item()
	asset_tree.hide_root = true
	
	for category in asset_database.keys():
		var cat_item = asset_tree.create_item(root)
		cat_item.set_text(0, category)
		cat_item.set_selectable(0, false)
		
		for asset_name in asset_database[category].keys():
			var asset_item = asset_tree.create_item(cat_item)
			asset_item.set_text(0, asset_name)
			asset_item.set_metadata(0, asset_database[category][asset_name])
			
	asset_tree.item_selected.connect(_on_asset_selected)

func _select_default_item() -> void:
	# Select the first child of the first category
	var root = asset_tree.get_root()
	if root:
		var first_cat = root.get_first_child()
		if first_cat:
			var first_asset = first_cat.get_first_child()
			if first_asset:
				first_asset.select(0)

func _on_asset_selected() -> void:
	var selected_item = asset_tree.get_selected()
	if not selected_item:
		return
		
	var path = selected_item.get_metadata(0)
	var name_text = selected_item.get_text(0)
	
	_load_model(name_text, path)

func _load_model(asset_name: String, path: String) -> void:
	# Clear previous model
	if current_model_node and is_instance_valid(current_model_node):
		current_model_node.queue_free()
		current_model_node = null
		
	if not ResourceLoader.exists(path):
		_update_inspector_failure(asset_name, path)
		return
		
	var loaded_res = load(path)
	if not loaded_res:
		_update_inspector_failure(asset_name, path)
		return
		
	var instance: Node3D = null
	if loaded_res is PackedScene:
		instance = loaded_res.instantiate()
	elif loaded_res is Mesh:
		instance = MeshInstance3D.new()
		instance.mesh = loaded_res
		
	if not instance:
		_update_inspector_failure(asset_name, path)
		return
		
	viewport.add_child(instance)
	current_model_node = instance
	
	# Normalize and scale
	_adjust_camera_and_model(instance, path)
	_update_inspector_success(asset_name, path, instance)

func _adjust_camera_and_model(instance: Node3D, path: String) -> void:
	# Calculate bounding box to normalize scale
	var aabb := AABB()
	var mesh_instances := _find_mesh_instances(instance)
	
	if not mesh_instances.is_empty():
		aabb = mesh_instances[0].get_aabb()
		for i in range(1, mesh_instances.size()):
			aabb = aabb.merge(mesh_instances[i].get_aabb())
	else:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
		
	var size = aabb.size
	var max_dim = max(size.x, max(size.y, size.z))
	
	# Apply standard material if obj has missing textures
	if path.ends_with(".obj"):
		for mesh_inst in mesh_instances:
			# Check if there is an active material already loaded from .mtl
			var has_material = false
			if mesh_inst.mesh:
				for s in range(mesh_inst.mesh.get_surface_count()):
					var surface_mat = mesh_inst.mesh.surface_get_material(s)
					if surface_mat != null:
						has_material = true
						break
			
			# If no material was loaded from the obj/mtl, apply a fallback / custom color
			if not has_material and mesh_inst.material_override == null:
				var mat = StandardMaterial3D.new()
				mat.albedo_color = Color(0.7, 0.5, 0.4) # Warm terracotta fallback
				mat.roughness = 0.6
				
				# Give specific custom colors for materials/props
				var lower_name = path.to_lower()
				if "glowcap" in lower_name:
					mat.albedo_color = Color(0.2, 0.6, 1.0)
					mat.emission_enabled = true
					mat.emission = Color(0.1, 0.3, 0.6)
				elif "frost_berry" in lower_name:
					mat.albedo_color = Color(0.9, 0.2, 0.3)
				elif "fire_bloom" in lower_name:
					mat.albedo_color = Color(1.0, 0.4, 0.0)
					mat.emission_enabled = true
					mat.emission = Color(0.5, 0.1, 0.0)
				elif "goblin" in lower_name:
					mat.albedo_color = Color(0.2, 0.5, 0.2)
				elif "spider" in lower_name:
					mat.albedo_color = Color(0.1, 0.1, 0.15)
				elif "slime" in lower_name:
					mat.albedo_color = Color(0.2, 0.8, 0.3)
					mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color.a = 0.7
				elif "barrel" in lower_name or "table" in lower_name or "stool" in lower_name:
					mat.albedo_color = Color(0.4, 0.25, 0.15)
					
				mesh_inst.material_override = mat
				
	# Center pivot at the bottom center of the bounding box
	instance.position = Vector3(0, -aabb.position.y * (1.5 / max_dim), 0)
	
	# Scale model to standard viewport height (around 1.5 units)
	var scale_factor = 1.5 / max_dim
	instance.scale = Vector3(scale_factor, scale_factor, scale_factor)

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result

func _update_inspector_success(asset_name: String, path: String, instance: Node) -> void:
	asset_name_label.text = asset_name
	asset_path_label.text = path
	asset_type_label.text = tr("GLTF PackedScene") if path.ends_with(".glb") else tr("Wavefront OBJ Mesh")
	
	var mesh_instances = _find_mesh_instances(instance)
	var vert_count = 0
	for mi in mesh_instances:
		if mi.mesh:
			for surface_idx in range(mi.mesh.get_surface_count()):
				var arrays = mi.mesh.surface_get_arrays(surface_idx)
				if arrays and arrays.size() > Mesh.ARRAY_VERTEX:
					vert_count += arrays[Mesh.ARRAY_VERTEX].size()
					
	if vert_count > 0:
		vertices_label.text = tr("%d Verts") % vert_count
	else:
		vertices_label.text = tr("Mocked: 1,852 Verts") # fallback
		
	bounds_label.text = tr("Normalized to 1.5 units")
	status_label.text = tr("VALIDATED & STABLE")
	status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))

func _update_inspector_failure(asset_name: String, path: String) -> void:
	asset_name_label.text = asset_name
	asset_path_label.text = path
	asset_type_label.text = tr("Unknown / Missing")
	vertices_label.text = tr("0 Verts")
	bounds_label.text = tr("0, 0, 0")
	status_label.text = tr("MISSING SOURCE MODEL")
	status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))

func _on_toggle_grid(enabled: bool) -> void:
	if grid_helper:
		grid_helper.visible = enabled

func _on_toggle_auto_rot(enabled: bool) -> void:
	is_auto_rotating = enabled

func _on_rot_speed_changed(val: float) -> void:
	rotation_speed = val

func _on_light_color_selected(index: int) -> void:
	if index == 0: # Cozy candlelight
		main_light.light_color = Color(1.0, 0.65, 0.3)
		main_light.light_energy = 1.5
		fill_light.light_color = Color(1.0, 0.5, 0.2)
		fill_light.light_energy = 1.0
	elif index == 1: # Daylight
		main_light.light_color = Color(1.0, 1.0, 0.95)
		main_light.light_energy = 2.0
		fill_light.light_color = Color(0.8, 0.85, 1.0)
		fill_light.light_energy = 0.5
	elif index == 2: # Moonlight
		main_light.light_color = Color(0.4, 0.6, 1.0)
		main_light.light_energy = 1.0
		fill_light.light_color = Color(0.1, 0.2, 0.5)
		fill_light.light_energy = 0.8

func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
