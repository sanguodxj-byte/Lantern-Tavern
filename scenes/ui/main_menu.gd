extends Control
class_name MainMenu

@onready var start_button: Button = $MarginContainer/VBoxContainer/StartButton
@onready var classic_button: Button = $MarginContainer/VBoxContainer/ClassicButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/SettingsButton
@onready var model_viewer_button: Button = $MarginContainer/VBoxContainer/ModelViewerButton
@onready var character_log_button: Button = $MarginContainer/VBoxContainer/CharacterLogButton
@onready var exit_button: Button = $MarginContainer/VBoxContainer/ExitButton
@onready var lang_toggle: Button = $MarginContainer/VBoxContainer/LangToggle

# 3D Viewport reference for the Tavern Background
@onready var viewport_container: SubViewportContainer = $TavernBackground
@onready var viewport: SubViewport = $TavernBackground/SubViewport
@onready var camera_pivot: Node3D = $TavernBackground/SubViewport/CameraPivot
@onready var camera: Camera3D = $TavernBackground/SubViewport/CameraPivot/Camera3D

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	classic_button.pressed.connect(_on_classic_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	model_viewer_button.pressed.connect(_on_model_viewer_pressed)
	character_log_button.pressed.connect(_on_character_log_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	lang_toggle.pressed.connect(_on_lang_toggle_pressed)
	
	_update_lang_label()
	_setup_3d_background()

func _process(delta: float) -> void:
	# Slowly rotate the camera pivot to create a cozy, dynamic panning effect of the 3D Tavern
	if camera_pivot:
		camera_pivot.rotate_y(0.05 * delta)

func _setup_3d_background() -> void:
	# Dynamically spawn the 3D Tavern scene inside the SubViewport if available
	# This avoids missing scene crashes while keeping the main menu fully responsive and stunning
	var tavern_scene_path = "res://scenes/tavern/tavern.tscn"
	if ResourceLoader.exists(tavern_scene_path):
		var tavern_scene = load(tavern_scene_path)
		var tavern_instance = tavern_scene.instantiate()
		viewport.add_child(tavern_instance)
		print("3D Tavern scene dynamically loaded as Main Menu background!")
	else:
		# Fallback: create mock meshes (barrels, table, stools) to ensure a gorgeous preview in sandbox
		print("Tavern scene not found, instantiating fallback cozy 3D tavern props...")
		_spawn_fallback_cozy_tavern()

func _spawn_fallback_cozy_tavern() -> void:
	# Create a central light
	var light = OmniLight3D.new()
	light.position = Vector3(0, 2.5, 0)
	light.omni_range = 10.0
	light.omni_attenuation = 1.0
	light.light_color = Color(1.0, 0.65, 0.3) # Warm candle glow
	light.light_energy = 2.0
	viewport.add_child(light)
	
	# Instantiate our procedurally generated PBR Table and Stools
	var table_mesh_path = "res://assets/models/table.obj"
	var table_mat_path = "res://materials/table_mat.tres"
	if ResourceLoader.exists(table_mesh_path):
		var table = MeshInstance3D.new()
		table.mesh = load(table_mesh_path)
		if ResourceLoader.exists(table_mat_path):
			table.material_override = load(table_mat_path)
		table.position = Vector3(0, 0, 0)
		viewport.add_child(table)
		
		# Surround table with stools
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
		TavernManager.inventory.clear() # Clear materials
		TavernManager.enter_phase(TavernManager.Phase.DAY_EXPEDITION)
	else:
		get_tree().change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")

func _on_classic_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_settings_pressed() -> void:
	# Redirect settings button to the Tavern Brewing Phase Board to give it direct access
	if TavernManager:
		TavernManager.enter_phase(TavernManager.Phase.NIGHT_TAVERN)
	else:
		get_tree().change_scene_to_file("res://scenes/ui/tavern_ui.tscn")

func _on_model_viewer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/model_viewer.tscn")

func _on_character_log_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_panel.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_lang_toggle_pressed() -> void:
	var current_locale = TranslationServer.get_locale()
	if current_locale.begins_with("zh"):
		TranslationServer.set_locale("en")
	else:
		TranslationServer.set_locale("zh")
	_update_lang_label()

func _update_lang_label() -> void:
	var current_locale = TranslationServer.get_locale()
	if current_locale.begins_with("zh"):
		lang_toggle.text = "Language: 简体中文 (CN)"
	else:
		lang_toggle.text = "Language: English (EN)"
