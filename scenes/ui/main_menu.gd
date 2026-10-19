extends UiScreen
class_name MainMenu

@onready var start_btn: Button = $SidePanel/MenuVBox/StartBtn
@onready var continue_btn: Button = $SidePanel/MenuVBox/ContinueBtn
@onready var gallery_btn: Button = $SidePanel/MenuVBox/GalleryBtn
@onready var settings_btn: Button = $SidePanel/MenuVBox/SettingsBtn
@onready var multiplayer_btn: Button = $SidePanel/MenuVBox/MultiplayerBtn
@onready var lang_btn: Button = $SidePanel/MenuVBox/LangBtn
@onready var exit_btn: Button = $SidePanel/MenuVBox/ExitBtn
@onready var subtitle: Label = $SidePanel/MenuVBox/Subtitle
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
var _hover_tweens: Dictionary = {}
var _title_hover_tween: Tween = null

const MAIN_MENU_COMPACT_HEIGHT := 820.0
const MAIN_MENU_COMPACT_PANEL_HEIGHT := 684.0
const MAIN_MENU_REGULAR_PANEL_HEIGHT := 1000.0

const Service := preload("res://globals/core/service.gd")
const UI_ROUTES := preload("res://globals/ui/ui_route_catalog.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const ORIGIN_SELECT_UI_SCRIPT := preload("res://scenes/ui/origin_select_ui.gd")
const SAVE_LOAD_PANEL_SCENE := preload("res://scenes/ui/save_load_panel.tscn")

## 出身选择界面实例（新游戏流程中动态创建）
var _origin_select_ui: Control
## 存档/读档面板实例（"继续"按钮动态创建，LOAD 模式）
var _save_load_panel: Control
## 玩家在出身选择界面选定的出身 id，待教程选择确认后传入 start_new_game
var _pending_origin_id: String = ""

func _ready() -> void:
	super._ready()
	# E2（1327 审查）：单一本地化引导——主菜单只订阅 initialized 信号刷新文本，
	# 不再 new 临时 loader 兜底（消除启动时序分叉）。
	var localization_manager := Service.localization_manager()
	if localization_manager != null and localization_manager.has_signal("initialized"):
		localization_manager.initialized.connect(_on_localization_initialized)
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
	_update_continue_state()
	_apply_responsive_layout()
	resized.connect(_apply_responsive_layout)
	_setup_button_hover_animations()
	_setup_focus_navigation()
	_play_intro_motion()
	_setup_origin_select_ui()
	call_deferred("_focus_first_available_button")

func _update_button_texts() -> void:
	start_btn.text = tr("Start Game").strip_edges()
	continue_btn.text = tr("Continue").strip_edges()
	gallery_btn.text = tr("Gallery").strip_edges()
	settings_btn.text = tr("Settings").strip_edges()
	multiplayer_btn.text = tr("Multiplayer").strip_edges()
	lang_btn.text = tr("Language: 简体中文 (CN)").strip_edges() if _is_chinese_locale() else tr("Language: English (EN)").strip_edges()
	exit_btn.text = tr("Exit Game").strip_edges()
	subtitle.text = tr("A TAVERNKEEPER'S DESCENT").strip_edges()
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
	if has_node("SidePanel/MenuVBox/Title/LogoTexture"):
		if _is_chinese_locale():
			$SidePanel/MenuVBox/Title/LogoTexture.texture = load("res://assets/textures/ui/title_logo_zh.png")
		else:
			$SidePanel/MenuVBox/Title/LogoTexture.texture = load("res://assets/textures/ui/title_logo_en.png")


func _apply_responsive_layout() -> void:
	var compact := size.y < MAIN_MENU_COMPACT_HEIGHT
	var side_panel := $SidePanel as Control
	var menu_box := $SidePanel/MenuVBox as VBoxContainer
	var panel_height := MAIN_MENU_COMPACT_PANEL_HEIGHT if compact else minf(MAIN_MENU_REGULAR_PANEL_HEIGHT, size.y - 72.0)
	side_panel.offset_top = -panel_height
	menu_box.offset_top = 20.0 if compact else 28.0
	menu_box.add_theme_constant_override("separation", 4 if compact else 8)
	menu_hint.visible = not compact
	menu_header.visible = not compact
	# 紧凑布局下隐藏标题区，节省面板空间
	$SidePanel/MenuVBox/Title.visible = not compact
	$SidePanel/MenuVBox/Subtitle.visible = not compact
	$SidePanel/PanelAccent.offset_top = 20.0 if compact else 28.0
	for button in [start_btn, continue_btn, gallery_btn, settings_btn, multiplayer_btn, exit_btn]:
		button.custom_minimum_size.y = 56.0 if compact else 60.0
		button.add_theme_font_size_override("font_size", 28 if compact else 32)
	lang_btn.custom_minimum_size.y = 50.0 if compact else 54.0
	lang_btn.add_theme_font_size_override("font_size", 24 if compact else 28)


func _play_intro_motion() -> void:
	# A short, non-blocking entrance gives the menu depth without delaying input.
	$SidePanel.modulate.a = 0.0
	$SidePanel.position.x += 28.0
	
	# 设置标题缩放 Pivot 到正中心
	var title := $SidePanel/MenuVBox/Title
	var subtitle := $SidePanel/MenuVBox/Subtitle
	var title_size = title.size if title.size.x > 0 else Vector2(400, 104)
	var subtitle_size = subtitle.size if subtitle.size.x > 0 else Vector2(400, 30)
	title.pivot_offset = title_size / 2.0
	subtitle.pivot_offset = subtitle_size / 2.0
	
	# 标题初始状态：透明且偏大
	title.modulate.a = 0.0
	title.scale = Vector2(1.22, 1.22)
	subtitle.modulate.a = 0.0
	subtitle.scale = Vector2(1.15, 1.15)
	
	var tween := create_tween().set_parallel(true)
	
	# 侧边栏滑入
	tween.tween_property($SidePanel, "modulate:a", 1.0, 0.32)
	tween.tween_property($SidePanel, "position:x", $SidePanel.position.x - 28.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 标题砸落淡入动画 (带有 TRANS_BACK 和 EASE_OUT 的弹簧感)
	tween.tween_property(title, "modulate:a", 1.0, 0.38)
	tween.tween_property(title, "scale", Vector2(1.0, 1.0), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 副标题砸落淡入动画
	tween.tween_property(subtitle, "modulate:a", 1.0, 0.42).set_delay(0.08)
	tween.tween_property(subtitle, "scale", Vector2(1.0, 1.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.08)
	
	# 侧边栏子元素瀑布流淡入+小缩放（标题/副标题已有专属动画，跳过避免竞争）
	var delay := 0.12
	for child in $SidePanel/MenuVBox.get_children():
		if child is Control and child != title and child != subtitle:
			child.modulate.a = 0.0
			child.scale = Vector2(0.92, 0.92)
			var child_size = child.size if child.size.x > 0 else Vector2(388, 66)
			child.pivot_offset = child_size / 2.0
			
			var child_tween := create_tween().set_parallel(true)
			child_tween.tween_property(child, "modulate:a", 1.0, 0.26).set_delay(delay)
			child_tween.tween_property(child, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
			delay += 0.04
	
	# 标题只做低幅、慢节奏呼吸，避免持续大幅漂浮影响品牌稳定感。
	if _title_hover_tween != null and _title_hover_tween.is_valid():
		_title_hover_tween.kill()
	var title_base_y: float = float(title.position.y)
	_title_hover_tween = create_tween().set_loops()
	_title_hover_tween.tween_property(title, "position:y", title_base_y + 3.0, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_hover_tween.tween_property(title, "position:y", title_base_y - 3.0, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

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
	if btn.disabled:
		return
	var btn_height: float = btn.size.y if btn.size.y > 0 else 66.0
	btn.pivot_offset = Vector2(0, btn_height / 2.0)
	_kill_hover_tween(btn)
	var tween := create_tween().set_parallel(true)
	_hover_tweens[btn] = tween
	tween.tween_property(btn, "scale", Vector2(1.025, 1.025), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_button_hover_exited(btn: Button) -> void:
	_kill_hover_tween(btn)
	var tween := create_tween().set_parallel(true)
	_hover_tweens[btn] = tween
	tween.tween_property(btn, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _kill_hover_tween(btn: Button) -> void:
	var existing: Tween = _hover_tweens.get(btn, null)
	if existing != null and existing.is_valid():
		existing.kill()
	_hover_tweens.erase(btn)


func _setup_focus_navigation() -> void:
	var primary_buttons: Array[Button] = [
		start_btn,
		continue_btn,
		gallery_btn,
		settings_btn,
		multiplayer_btn,
		lang_btn,
		exit_btn,
	]
	for index in range(primary_buttons.size()):
		var button := primary_buttons[index]
		button.focus_mode = Control.FOCUS_ALL
		button.focus_neighbor_top = button.get_path_to(primary_buttons[posmod(index - 1, primary_buttons.size())])
		button.focus_neighbor_bottom = button.get_path_to(primary_buttons[(index + 1) % primary_buttons.size()])
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path()
	var tutorial_buttons: Array[Button] = [start_with_tutorial_btn, skip_tutorial_btn, back_from_tutorial_btn]
	for index in range(tutorial_buttons.size()):
		var button := tutorial_buttons[index]
		button.focus_mode = Control.FOCUS_ALL
		button.focus_neighbor_top = button.get_path_to(tutorial_buttons[posmod(index - 1, tutorial_buttons.size())])
		button.focus_neighbor_bottom = button.get_path_to(tutorial_buttons[(index + 1) % tutorial_buttons.size()])


func _focus_first_available_button() -> void:
	if start_btn != null and is_instance_valid(start_btn):
		start_btn.grab_focus()


func _update_continue_state() -> void:
	var save_manager := get_tree().root.get_node_or_null("SaveManager") if get_tree() != null else null
	var has_any_save := false
	if save_manager != null and save_manager.has_method("has_save"):
		for slot_index in range(3):
			if save_manager.has_save(slot_index):
				has_any_save = true
				break
	continue_btn.disabled = not has_any_save
	continue_btn.tooltip_text = "" if has_any_save else tr("No saved adventure found.").strip_edges()

## E2（1327 审查）：LocalizationManager 引导完成后刷新文本（晚初始化场景）。
func _on_localization_initialized() -> void:
	_update_button_texts()


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
		# 同步全局像素着色开关到主菜单 3D 背景。
		# 酒馆场景内嵌 ShaderMaterial 的 pixel_lighting_enabled 默认为 1.0，
		# 不调用 apply_to_tree 会导致关闭像素着色后主菜单背景仍显示 toon 光照。
		VOXEL_LIGHTING.apply_to_tree(tavern_instance, true)
		print("3D Tavern scene loaded as Main Menu background!")
	else:
		push_error("[MainMenu] Tavern scene not found at: " + tavern_scene_path)

func _set_tutorial_choice_visible(visible: bool) -> void:
	tutorial_choice_panel.visible = visible
	$SidePanel/MenuVBox.visible = not visible
	if visible:
		start_with_tutorial_btn.grab_focus()
	else:
		start_btn.grab_focus()

func _on_start_pressed() -> void:
	_pending_origin_id = ""
	_set_origin_select_visible(true)

func _on_start_with_tutorial_pressed() -> void:
	if TavernManager:
		TavernManager.start_new_game(true, _pending_origin_id)
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_skip_tutorial_pressed() -> void:
	if TavernManager:
		TavernManager.start_new_game(false, _pending_origin_id)
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_back_from_tutorial_pressed() -> void:
	_set_tutorial_choice_visible(false)
	_set_origin_select_visible(true)


## 创建并挂载出身选择界面，连接信号。
func _setup_origin_select_ui() -> void:
	_origin_select_ui = ORIGIN_SELECT_UI_SCRIPT.new()
	_origin_select_ui.name = "OriginSelectUI"
	_origin_select_ui.origin_selected.connect(_on_origin_selected)
	_origin_select_ui.back_requested.connect(_on_origin_back_requested)
	add_child(_origin_select_ui)
	_origin_select_ui.visible = false


## 切换出身选择界面可见性。显示时隐藏侧边栏菜单与教程面板，并重置选中状态。
func _set_origin_select_visible(vis: bool) -> void:
	if _origin_select_ui == null:
		return
	_origin_select_ui.visible = vis
	if vis:
		_origin_select_ui.reset_selection()
		tutorial_choice_panel.visible = false
		$SidePanel/MenuVBox.visible = false
	else:
		$SidePanel/MenuVBox.visible = true
		start_btn.grab_focus()


## 出身确认后进入教程选择步骤。
func _on_origin_selected(origin_id: String) -> void:
	_pending_origin_id = origin_id
	_set_origin_select_visible(false)
	_set_tutorial_choice_visible(true)
	start_with_tutorial_btn.grab_focus()


## 返回主菜单。
func _on_origin_back_requested() -> void:
	_set_origin_select_visible(false)


func _on_cancel_input() -> void:
	# ESC/TAB 退出当前叠加层；按优先级处理出身选择 → 教程选择。
	if _origin_select_ui != null and _origin_select_ui.visible:
		_on_origin_back_requested()
		return
	if tutorial_choice_panel.visible:
		_on_back_from_tutorial_pressed()

func _on_continue_pressed() -> void:
	# P0-1（0804）："继续"必须先让玩家选择存档槽位并成功加载，才进入酒馆。
	# 加载失败（损坏/空槽）停留在面板，绝不直接切场景。
	_show_save_load_panel(true)

## 创建/显示存档读档面板。load_mode=true 时以 LOAD 模式打开（"继续"流程）。
func _show_save_load_panel(load_mode: bool) -> void:
	if _save_load_panel == null:
		_save_load_panel = SAVE_LOAD_PANEL_SCENE.instantiate()
		_save_load_panel.name = "SaveLoadPanelOverlay"
		add_child(_save_load_panel)
		_save_load_panel.slot_action_completed.connect(_on_save_slot_action)
		_save_load_panel.back_pressed.connect(_on_save_load_back)
	_save_load_panel.set_mode(SaveLoadPanel.Mode.LOAD if load_mode else SaveLoadPanel.Mode.SAVE)
	_save_load_panel.visible = true
	_save_load_panel.move_to_front()
	_save_load_panel.refresh()

func _on_save_slot_action(action: String, slot_index: int) -> void:
	if action != "load":
		return
	if _save_load_panel != null:
		_save_load_panel.visible = false
	if TavernManager:
		TavernManager.continue_in_tavern()
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_save_load_back() -> void:
	if _save_load_panel != null:
		_save_load_panel.visible = false

func _on_gallery_pressed() -> void:
	request_navigation(UI_ROUTES.GALLERY)

func _on_settings_pressed() -> void:
	request_navigation(UI_ROUTES.SETTINGS)

func _on_multiplayer_pressed() -> void:
	request_navigation(UI_ROUTES.MULTIPLAYER_LOBBY)

func _on_exit_pressed() -> void:
	get_tree().quit()
