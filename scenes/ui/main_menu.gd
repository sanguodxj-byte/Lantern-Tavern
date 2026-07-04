extends Control
class_name MainMenu

@onready var start_btn: Button = $SidePanel/MenuVBox/StartBtn
@onready var continue_btn: Button = $SidePanel/MenuVBox/ContinueBtn
@onready var gallery_btn: Button = $SidePanel/MenuVBox/GalleryBtn
@onready var settings_btn: Button = $SidePanel/MenuVBox/SettingsBtn
@onready var exit_btn: Button = $SidePanel/MenuVBox/ExitBtn

# 3D Viewport reference for the Tavern Background
@onready var viewport_container: SubViewportContainer = $TavernBackground
@onready var viewport: SubViewport = $TavernBackground/SubViewport
@onready var camera_pivot: Node3D = $TavernBackground/SubViewport/CameraPivot
@onready var camera: Camera3D = $TavernBackground/SubViewport/CameraPivot/Camera3D

var gallery_menu_open := false

func _ready() -> void:
	start_btn.pressed.connect(_on_start_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	gallery_btn.pressed.connect(_on_gallery_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)

	_setup_3d_background()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_update_button_texts()

func _update_button_texts() -> void:
	start_btn.text = tr("[S]tart Game")
	continue_btn.text = tr("[C]ontinue")
	gallery_btn.text = tr("[G]allery")
	settings_btn.text = tr("Settin[g]s")
	exit_btn.text = tr("E[x]it Game")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S: _on_start_pressed()
			KEY_C: _on_continue_pressed()
			KEY_G: _on_gallery_pressed()
			KEY_X: _on_exit_pressed()


func _process(delta: float) -> void:
	if camera_pivot:
		camera_pivot.rotate_y(0.05 * delta)

func _setup_3d_background() -> void:
	var tavern_scene_path = "res://scenes/tavern/tavern.tscn"
	if ResourceLoader.exists(tavern_scene_path):
		var tavern_scene = load(tavern_scene_path)
		var tavern_instance = tavern_scene.instantiate()
		viewport.add_child(tavern_instance)
		print("3D Tavern scene dynamically loaded as Main Menu background!")
	else:
		print("Tavern scene not found, instantiating fallback cozy 3D tavern props...")
		_spawn_fallback_cozy_tavern()

func _spawn_fallback_cozy_tavern() -> void:
	var light = OmniLight3D.new()
	light.position = Vector3(0, 2.5, 0)
	light.omni_range = 10.0
	light.omni_attenuation = 1.0
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 2.0
	viewport.add_child(light)
	
	var table_mesh_path = "res://assets/models/table.obj"
	var table_mat_path = "res://materials/table_mat.tres"
	if ResourceLoader.exists(table_mesh_path):
			var table = MeshInstance3D.new()
			table.mesh = load(table_mesh_path)
			if ResourceLoader.exists(table_mat_path):
				table.material_override = load(table_mat_path)
			table.position = Vector3(0, 0, 0)
			viewport.add_child(table)
			
			var stool_mesh_path = "res://assets/models/stool.obj"
			var stool_mat_path = "res://materials/stool_mat.tres"
			if ResourceLoader.exists(stool_mesh_path):
				var stool_offsets = [Vector3(-0.8, 0, 0), Vector3(0.8, 0, 0), Vector3(0, 0, -0.8)]
				for offset in stool_offsets:
					var stool = MeshInstance3D.new()
					stool.mesh = load(stool_mesh_path)
					if ResourceLoader.exists(stool_mat_path):
						stool.material_override = load(stool_mat_path)
					stool.position = offset
					viewport.add_child(stool)

func _on_start_pressed() -> void:
	if TavernManager:
		TavernManager.gold = 100
		TavernManager.inventory.clear()
	# 开始游戏：主界面 UI 退出，进入酒馆场景（不直接跳地牢）
	# 玩家在酒馆内按住 F 触发环形进度条进入地牢探险
	get_tree().change_scene_to_file("res://scenes/tavern/tavern.tscn")

func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/tavern_ui.tscn")

func _on_gallery_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/model_viewer.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_panel.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
