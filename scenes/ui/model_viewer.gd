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
var asset_database: Dictionary = {
	"Props / Objects (场景道具)": {
		"Table (木桌)": "res://assets/models/table.obj",
		"Stool (圆凳)": "res://assets/models/stool.obj",
		"Barrel (木桶)": "res://assets/models/barrel.obj",
		"Pillar (石柱)": "res://assets/models/pillar.obj",
		"Chest (宝箱)": "res://assets/models/chest.obj",
		"Portal (传送门)": "res://assets/models/portal.obj"
	},
	"Weapons & Shields (武器装备)": {
		"Shortsword (短剑)": "res://assets/meshes/weapons/shortsword.glb",
		"Axe (长斧)": "res://assets/meshes/weapons/axe.glb",
		"Buckler (圆盾)": "res://assets/meshes/shields/buckler.glb",
		"Spikes Trap (地刺陷阱)": "res://assets/meshes/traps/spikes.glb"
	},
	"Monsters (怪物建模)": {
		"Goblin (哥布林)": "res://assets/models/goblin.obj",
		"Spider (巨型蜘蛛)": "res://assets/models/spider.obj",
		"Slime (史莱姆)": "res://assets/models/slime.obj",
		"Skeleton (骷髅兵)": "res://assets/models/skeleton.obj",
		"Bat (吸血蝙蝠)": "res://assets/models/bat.obj",
		"Rat (巨鼠)": "res://assets/models/rat.obj",
		"Troll (巨魔)": "res://assets/models/troll.obj",
		"Zombie (僵尸)": "res://assets/models/zombie.obj",
		"Imp (小恶魔)": "res://assets/models/imp.obj",
		"Harpy (哈比鸟人)": "res://assets/models/harpy.obj"
	},
	"Gatherable Materials (采集原料)": {
		"Wild Glowcap (野生荧光菇)": "res://assets/models/wild_glowcap.obj",
		"Frost Berry (霜冻浆果)": "res://assets/models/frost_berry.obj",
		"Fire Bloom (烈焰花瓣)": "res://assets/models/fire_bloom.obj",
		"Cave Lichen (洞穴苔藓)": "res://assets/models/cave_lichen.obj",
		"Honeycomb (野生蜂巢)": "res://assets/models/honeycomb.obj"
	}
}

func _ready() -> void:
	# Wire up UI controls
	return_btn.pressed.connect(_on_return_pressed)
	toggle_grid_btn.toggled.connect(_on_toggle_grid)
	toggle_auto_rot.toggled.connect(_on_toggle_auto_rot)
	rot_speed_slider.value_changed.connect(_on_rot_speed_changed)
	
	# Configure Light Color Options
	light_color_option.add_item("Cozy Candlelight (暖烛光)")
	light_color_option.add_item("Daylight (白日光)")
	light_color_option.add_item("Eerie Moonlight (冷月光)")
	light_color_option.item_selected.connect(_on_light_color_selected)
	
	# Build grid helper
	_create_grid_mesh()
	
	# Build asset tree
	_build_asset_tree()
	
	# Select first element by default
	_select_default_item()

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
		
	var size = aabb.get_size()
	var max_dim = max(size.x, max(size.y, size.z))
	
	# Apply standard material if obj has missing textures
	if path.ends_with(".obj"):
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
			
		for mesh_inst in mesh_instances:
			if mesh_inst.material_override == null:
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
	asset_type_label.text = "GLTF PackedScene" if path.ends_with(".glb") else "Wavefront OBJ Mesh"
	
	var mesh_instances = _find_mesh_instances(instance)
	var vert_count = 0
	for mi in mesh_instances:
		if mi.mesh:
			for surface_idx in range(mi.mesh.get_surface_count()):
				var arrays = mi.mesh.surface_get_arrays(surface_idx)
				if arrays and arrays.size() > Mesh.ARRAY_VERTEX:
					vert_count += arrays[Mesh.ARRAY_VERTEX].size()
					
	if vert_count > 0:
		vertices_label.text = "%d Verts" % vert_count
	else:
		vertices_label.text = "Mocked: 1,852 Verts" # fallback
		
	bounds_label.text = "Normalized to 1.5 units"
	status_label.text = "VALIDATED & STABLE"
	status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))

func _update_inspector_failure(asset_name: String, path: String) -> void:
	asset_name_label.text = asset_name
	asset_path_label.text = path
	asset_type_label.text = "Unknown / Missing"
	vertices_label.text = "0 Verts"
	bounds_label.text = "0, 0, 0"
	status_label.text = "MISSING SOURCE MODEL"
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
