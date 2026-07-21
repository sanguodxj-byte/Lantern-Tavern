extends UiScreen
class_name MainMenu

@onready var start_btn: Button = $SidePanel/MenuVBox/StartBtn
@onready var continue_btn: Button = $SidePanel/MenuVBox/ContinueBtn
@onready var gallery_btn: Button = $SidePanel/MenuVBox/GalleryBtn
@onready var settings_btn: Button = $SidePanel/MenuVBox/SettingsBtn
@onready var multiplayer_btn: Button = $SidePanel/MenuVBox/MultiplayerBtn
@onready var lang_btn: Button = $SidePanel/MenuVBox/LangBtn
@onready var exit_btn: Button = $SidePanel/MenuVBox/ExitBtn
@onready var subtitle: Label = $Subtitle
@onready var menu_header: Label = $SidePanel/MenuVBox/MenuHeader
@onready var menu_hint: Label = $SidePanel/MenuVBox/MenuHint
@onready var utility_label: Label = $SidePanel/MenuVBox/UtilityLabel
@onready var version_label: Label = $VersionLabel
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
const Service := preload("res://globals/core/service.gd")
const UI_ROUTES := preload("res://globals/ui/ui_route_catalog.gd")
static var fallback_translations_registered := false
func _ready() -> void:
	super._ready()
	_ensure_translations_registered()
	start_btn.pressed.connect(_on_start_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	gallery_btn.pressed.connect(_on_gallery_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	multiplayer_btn.pressed.connect(_on_multiplayer_pressed)
	lang_btn.pressed.connect(_on_lang_toggle_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)
	start_with_tutorial_btn.pressed.connect(_on_start_with_tutorial_pressed)
	skip_tutorial_btn.pressed.connect(_on_skip_tutorial_pressed)
	back_from_tutorial_btn.pressed.connect(_on_back_from_tutorial_pressed)

	_setup_3d_background()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_update_button_texts()
	_setup_button_hover_animations()
	_play_intro_motion()

func _update_button_texts() -> void:
	start_btn.text = tr("Start Game").strip_edges()
	continue_btn.text = tr("Continue").strip_edges()
	gallery_btn.text = tr("Gallery").strip_edges()
	settings_btn.text = tr("Settings").strip_edges()
	multiplayer_btn.text = tr("Multiplayer").strip_edges()
	lang_btn.text = tr("Language: 简体中文 (CN)").strip_edges() if _is_chinese_locale() else tr("Language: English (EN)").strip_edges()
	exit_btn.text = tr("Exit Game").strip_edges()
	subtitle.text = ""
	menu_header.text = tr("THE HEARTH AWAITS").strip_edges()
	menu_hint.text = tr("Build your legend between the warmth of the hearth and the dark below.").strip_edges()
	utility_label.text = tr("PREFERENCES").strip_edges()
	version_label.text = tr("LONE LIGHT TAVERN  •  EARLY ACCESS").strip_edges()
	tutorial_title.text = tr("Tutorial").strip_edges()
	tutorial_desc.text = tr("Choose whether to play the opening tutorial before entering the tavern.").strip_edges()
	start_with_tutorial_btn.text = tr("Play Tutorial").strip_edges()
	skip_tutorial_btn.text = tr("Skip To Tavern").strip_edges()
	back_from_tutorial_btn.text = tr("Back").strip_edges()
	
	# 根据当前语言动态加载专属的手绘像素画 LOGO 贴图，呈现极致手制大作质感
	if has_node("Title/LogoTexture"):
		if _is_chinese_locale():
			$Title/LogoTexture.texture = load("res://assets/textures/ui/title_logo_zh.png")
		else:
			$Title/LogoTexture.texture = load("res://assets/textures/ui/title_logo_en.png")

func _play_intro_motion() -> void:
	# A short, non-blocking entrance gives the menu depth without delaying input.
	$SidePanel.modulate.a = 0.0
	$SidePanel.position.x += 28.0
	
	# 设置标题缩放 Pivot 到正中心
	var title_size = $Title.size if $Title.size.x > 0 else Vector2(1080, 112)
	var subtitle_size = $Subtitle.size if $Subtitle.size.x > 0 else Vector2(1000, 38)
	$Title.pivot_offset = title_size / 2.0
	$Subtitle.pivot_offset = subtitle_size / 2.0
	
	# 标题初始状态：透明且偏大
	$Title.modulate.a = 0.0
	$Title.scale = Vector2(1.22, 1.22)
	$Subtitle.modulate.a = 0.0
	$Subtitle.scale = Vector2(1.15, 1.15)
	
	var tween := create_tween().set_parallel(true)
	
	# 侧边栏滑入
	tween.tween_property($SidePanel, "modulate:a", 1.0, 0.32)
	tween.tween_property($SidePanel, "position:x", $SidePanel.position.x - 28.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 标题砸落淡入动画 (带有 TRANS_BACK 和 EASE_OUT 的弹簧感)
	tween.tween_property($Title, "modulate:a", 1.0, 0.38)
	tween.tween_property($Title, "scale", Vector2(1.0, 1.0), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 副标题砸落淡入动画
	tween.tween_property($Subtitle, "modulate:a", 1.0, 0.42).set_delay(0.08)
	tween.tween_property($Subtitle, "scale", Vector2(1.0, 1.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.08)
	
	# 侧边栏子元素瀑布流淡入+小缩放
	var delay := 0.12
	for child in $SidePanel/MenuVBox.get_children():
		if child is Control:
			child.modulate.a = 0.0
			child.scale = Vector2(0.92, 0.92)
			var child_size = child.size if child.size.x > 0 else Vector2(388, 66)
			child.pivot_offset = child_size / 2.0
			
			var child_tween := create_tween().set_parallel(true)
			child_tween.tween_property(child, "modulate:a", 1.0, 0.26).set_delay(delay)
			child_tween.tween_property(child, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
			delay += 0.04
	
	# 启动标题立体字体的缓慢悬浮波浪摇曳动效，营造灵动的奇幻像素大作感
	var title_hover = create_tween().set_loops()
	title_hover.tween_property($Title, "position:y", 80.0 + 8.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	title_hover.tween_property($Title, "position:y", 80.0 - 8.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _setup_button_hover_animations() -> void:
	var buttons: Array[Button] = [
		start_btn,
		continue_btn,
		gallery_btn,
		settings_btn,
		multiplayer_btn,
		lang_btn,
		exit_btn,
		start_with_tutorial_btn,
		skip_tutorial_btn,
		back_from_tutorial_btn
	]
	
	for btn in buttons:
		if btn == null:
			continue
		btn.mouse_entered.connect(func(): _on_button_hover_entered(btn))
		btn.mouse_exited.connect(func(): _on_button_hover_exited(btn))

func _on_button_hover_entered(btn: Button) -> void:
	var btn_height = btn.size.y if btn.size.y > 0 else 66.0
	btn.pivot_offset = Vector2(0, btn_height / 2.0)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_button_hover_exited(btn: Button) -> void:
	var tween = create_tween().set_parallel(true)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _ensure_translations_registered() -> void:
	var localization_manager := Service.localization_manager()
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
	request_navigation(UI_ROUTES.GALLERY)

func _on_settings_pressed() -> void:
	request_navigation(UI_ROUTES.SETTINGS)

func _on_multiplayer_pressed() -> void:
	request_navigation(UI_ROUTES.MULTIPLAYER_LOBBY)

func _on_exit_pressed() -> void:
	get_tree().quit()
