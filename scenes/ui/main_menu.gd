extends Control
class_name MainMenu

@onready var start_btn: Button = $SidePanel/MenuVBox/StartBtn
@onready var continue_btn: Button = $SidePanel/MenuVBox/ContinueBtn
@onready var gallery_btn: Button = $SidePanel/MenuVBox/GalleryBtn
@onready var settings_btn: Button = $SidePanel/MenuVBox/SettingsBtn
@onready var lang_btn: Button = $SidePanel/MenuVBox/LangBtn
@onready var exit_btn: Button = $SidePanel/MenuVBox/ExitBtn
@onready var tutorial_choice_panel: PanelContainer = $SidePanel/TutorialChoicePanel
@onready var tutorial_title: Label = $SidePanel/TutorialChoicePanel/TutorialChoiceVBox/TutorialTitle
@onready var tutorial_desc: Label = $SidePanel/TutorialChoicePanel/TutorialChoiceVBox/TutorialDesc
@onready var start_with_tutorial_btn: Button = $SidePanel/TutorialChoicePanel/TutorialChoiceVBox/StartWithTutorialBtn
@onready var skip_tutorial_btn: Button = $SidePanel/TutorialChoicePanel/TutorialChoiceVBox/SkipTutorialBtn
@onready var back_from_tutorial_btn: Button = $SidePanel/TutorialChoicePanel/TutorialChoiceVBox/BackFromTutorialBtn

# 3D Viewport reference for the Tavern Background
@onready var viewport_container: SubViewportContainer = $TavernBackground
@onready var viewport: SubViewport = $TavernBackground/SubViewport
@onready var camera_pivot: Node3D = $TavernBackground/SubViewport/CameraPivot
@onready var camera: Camera3D = $TavernBackground/SubViewport/CameraPivot/Camera3D

var gallery_menu_open := false

const LOCALIZATION_MANAGER_SCRIPT := preload("res://globals/core/localization_manager.gd")
static var fallback_translations_registered := false

func _ready() -> void:
	_ensure_translations_registered()
	start_btn.pressed.connect(_on_start_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	gallery_btn.pressed.connect(_on_gallery_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	lang_btn.pressed.connect(_on_lang_toggle_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)
	start_with_tutorial_btn.pressed.connect(_on_start_with_tutorial_pressed)
	skip_tutorial_btn.pressed.connect(_on_skip_tutorial_pressed)
	back_from_tutorial_btn.pressed.connect(_on_back_from_tutorial_pressed)

	_setup_3d_background()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_update_button_texts()

func _update_button_texts() -> void:
	start_btn.text = tr("Start Game")
	continue_btn.text = tr("Continue")
	gallery_btn.text = tr("Gallery")
	settings_btn.text = tr("Settings")
	lang_btn.text = tr("Language: 简体中文 (CN)") if _is_chinese_locale() else tr("Language: English (EN)")
	exit_btn.text = tr("Exit Game")
	tutorial_title.text = tr("Tutorial")
	tutorial_desc.text = tr("Choose whether to play the opening tutorial before entering the tavern.")
	start_with_tutorial_btn.text = tr("Play Tutorial")
	skip_tutorial_btn.text = tr("Skip To Tavern")
	back_from_tutorial_btn.text = tr("Back")


func _ensure_translations_registered() -> void:
	var localization_manager := get_node_or_null("/root/LocalizationManager")
	if localization_manager != null:
		return
	if fallback_translations_registered:
		return

	var fallback_loader: Node = LOCALIZATION_MANAGER_SCRIPT.new()
	fallback_loader._load_translations()
	fallback_loader.free()
	fallback_translations_registered = true


func _is_chinese_locale() -> bool:
	return TranslationServer.get_locale().begins_with("zh")


func _on_lang_toggle_pressed() -> void:
	TranslationServer.set_locale("en" if _is_chinese_locale() else "zh")
	_update_button_texts()


func _process(delta: float) -> void:
	if camera_pivot:
		camera_pivot.rotate_y(0.05 * delta)

func _setup_3d_background() -> void:
	var tavern_scene_path = "res://scenes/tavern/tavern.tscn"
	if ResourceLoader.exists(tavern_scene_path):
		var tavern_scene = load(tavern_scene_path)
		var tavern_instance = tavern_scene.instantiate()
		viewport.add_child(tavern_instance)
		print("3D Tavern scene loaded as Main Menu background!")
	else:
		push_error("[MainMenu] Tavern scene not found at: " + tavern_scene_path)

func _set_tutorial_choice_visible(visible: bool) -> void:
	tutorial_choice_panel.visible = visible
	$SidePanel/MenuVBox.visible = not visible

func _on_start_pressed() -> void:
	_set_tutorial_choice_visible(true)
	start_with_tutorial_btn.grab_focus()

func _on_start_with_tutorial_pressed() -> void:
	if TavernManager:
		TavernManager.start_new_game(true)
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_skip_tutorial_pressed() -> void:
	if TavernManager:
		TavernManager.start_new_game(false)
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_back_from_tutorial_pressed() -> void:
	_set_tutorial_choice_visible(false)

func _on_continue_pressed() -> void:
	if TavernManager:
		TavernManager.continue_in_tavern()
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_gallery_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/model_viewer.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings_menu.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
