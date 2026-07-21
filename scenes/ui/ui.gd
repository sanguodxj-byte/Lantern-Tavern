class_name UI
extends CanvasLayer

const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")
const PICKUP_HINT_SCRIPT := preload("res://scenes/ui/pickup_hint.gd")
const INTERACT_HINT_SCRIPT := preload("res://scenes/ui/interact_hint.gd")

@onready var subtitle_label: Label = %SubtitleLabel
@onready var tutorial_hint_label: Label = %TutorialHintLabel
@onready var death_screen: ColorRect = %DeathScreen
@onready var death_label: Label = %DeathScreen.get_node("Label")
@onready var hurt_vignette: Panel = %HurtVignette

var world_space: String = "dungeon"
var item_detail_popup
var death_tween: Tween = null
var hurt_flash_tween: Tween = null
var _pickup_hint: PickupHint
var _interact_hint: InteractHint
var _current_hint_type: String = ""

## 受击闪红：边缘 vignette 峰值透明度 / 时长
const HURT_FLASH_PEAK_A := 0.92
const HURT_FLASH_IN_SEC := 0.05
const HURT_FLASH_OUT_SEC := 0.22

func _ready() -> void:
	item_detail_popup = DETAIL_POPUP_SCRIPT.new()
	add_child(item_detail_popup)
	GameEvents.player_hurt.connect(on_player_hurt)
	GameEvents.player_dead.connect(on_player_dead)
	GameEvents.level_restarted.connect(on_level_restart)
	GameEvents.item_detail_changed.connect(on_item_detail_changed)
	GameEvents.subtitle_changed.connect(on_subtitle_changed)
	GameEvents.tutorial_hint_changed.connect(on_tutorial_hint_changed)
	GameEvents.interaction_hint_changed.connect(on_interaction_hint_changed)
	_setup_interaction_hints()
	
func on_player_hurt(_player: Player = null) -> void:
	# intro 过场不闪；酒馆/地牢战斗受击均闪红
	if world_space == "intro":
		return
	play_hurt_flash()


## 受击全屏边缘闪红（可被连续受击打断并重播）
func play_hurt_flash() -> void:
	if not is_instance_valid(hurt_vignette):
		return
	if hurt_flash_tween != null and hurt_flash_tween.is_valid():
		hurt_flash_tween.kill()
	hurt_vignette.modulate.a = 0.0
	hurt_flash_tween = create_tween()
	hurt_flash_tween.tween_property(hurt_vignette, "modulate:a", HURT_FLASH_PEAK_A, HURT_FLASH_IN_SEC)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hurt_flash_tween.tween_property(hurt_vignette, "modulate:a", 0.0, HURT_FLASH_OUT_SEC)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func on_player_dead() -> void:
	if is_instance_valid(death_label):
		death_label.text = tr("YOU DIED") + "\n\n" + tr("PRESS R TO RESTART")
	if death_tween != null and death_tween.is_valid():
		death_tween.kill()
	death_tween = create_tween()
	death_tween.tween_property(death_screen, "modulate", Color.WHITE, 0.5)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)

func on_level_restart() -> void:
	if hurt_flash_tween != null and hurt_flash_tween.is_valid():
		hurt_flash_tween.kill()
		hurt_flash_tween = null
	if is_instance_valid(hurt_vignette):
		hurt_vignette.modulate.a = 0.0
	death_screen.modulate = Color.TRANSPARENT

## 创建交互悬浮窗实例（拾取 + 交互共用基类 InteractionHintBase）
func _setup_interaction_hints() -> void:
	_pickup_hint = PICKUP_HINT_SCRIPT.new()
	_pickup_hint.visible = false
	add_child(_pickup_hint)
	_interact_hint = INTERACT_HINT_SCRIPT.new()
	_interact_hint.visible = false
	add_child(_interact_hint)

## 响应交互悬浮窗信号：根据类型显示对应悬浮窗，空类型立即隐藏所有。
## 在酒馆与地牢场景通用（不再限定 dungeon）。
func on_interaction_hint_changed(hint_type: String, text: String, screen_position: Vector2) -> void:
	# 类型未变化且仍可见时仅更新位置
	if hint_type == _current_hint_type and hint_type != "":
		_show_hint_by_type(hint_type, text, screen_position)
		return
	# 类型变化：先隐藏旧的，再显示新的
	_hide_all_hints()
	_current_hint_type = hint_type
	if hint_type == "":
		return
	_show_hint_by_type(hint_type, text, screen_position)

func _show_hint_by_type(hint_type: String, text: String, screen_position: Vector2) -> void:
	match hint_type:
		"pickup":
			# 可拾取物：详情悬浮窗已占据物体右侧的原 hint 位，
			# 拾取提示关闭自动定位，由下方 _position_pickup_hint_below_popup 放到详情正下方。
			var popup_visible: bool = item_detail_popup != null and is_instance_valid(item_detail_popup) and item_detail_popup.visible
			_pickup_hint.show_for_item(text, screen_position, not popup_visible)
			if popup_visible:
				_position_pickup_hint_below_popup()
		"interact", "chest", "door":
			_interact_hint.show_for_object(text, screen_position)

func _hide_all_hints() -> void:
	if _pickup_hint != null and is_instance_valid(_pickup_hint):
		_pickup_hint.hide_hint()
	if _interact_hint != null and is_instance_valid(_interact_hint):
		_interact_hint.hide_hint()
	_current_hint_type = ""

func on_item_detail_changed(detail: Dictionary, screen_position: Vector2 = Vector2.ZERO) -> void:
	if item_detail_popup == null:
		return
	if detail.is_empty():
		item_detail_popup.hide_detail()
		return
	# 详情悬浮窗取代交互提示的位置：显示在物体右侧（与交互提示同一锚点）
	var anchor := screen_position
	if anchor == Vector2.ZERO:
		anchor = get_viewport().get_visible_rect().size * Vector2(0.62, 0.55)
	item_detail_popup.show_detail(detail, anchor)
	# 弹窗显示后，若当前是拾取提示，把它放到弹窗正下方
	if _current_hint_type == "pickup":
		_position_pickup_hint_below_popup()

## 把拾取提示定位到详情悬浮窗正下方（详情悬浮窗已占据物体右侧的原 hint 位）。
## 详情弹窗为同步定位，故此处可直接读取其 global_position / size。
func _position_pickup_hint_below_popup() -> void:
	if _pickup_hint == null or not is_instance_valid(_pickup_hint) or not _pickup_hint.visible:
		return
	if item_detail_popup == null or not is_instance_valid(item_detail_popup) or not item_detail_popup.visible:
		return
	# 同步刷新拾取提示尺寸，确保读取到的 height 反映当前文本
	_pickup_hint.reset_size()
	var below: Vector2 = item_detail_popup.global_position + Vector2(0.0, item_detail_popup.size.y + 6.0)
	var vp := get_viewport().get_visible_rect().size
	below.x = clampf(below.x, 12.0, maxf(12.0, vp.x - _pickup_hint.size.x - 12.0))
	below.y = clampf(below.y, 12.0, maxf(12.0, vp.y - _pickup_hint.size.y - 12.0))
	_pickup_hint.global_position = below

func on_subtitle_changed(text: String) -> void:
	subtitle_label.visible = not text.is_empty()
	subtitle_label.text = text

func on_tutorial_hint_changed(text: String) -> void:
	tutorial_hint_label.visible = not text.is_empty()
	tutorial_hint_label.text = text

func set_world_space(space: String) -> void:
	world_space = space
	# 交互 / 字幕 / 教程 / 装备检视等通用 UI 在酒馆与地牢都显示，
	# 仅开场 intro 隐藏（避免遮挡过场）。战斗向 HUD（血量/护盾/武器/小地图）
	# 已统一收口到 CombatHUD 并在所有空间显示，UI 层不再重复绘制。
	visible = world_space != "intro"
	if visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# 每次场景切换时重置所有临时 UI 状态
	# 修复：死亡 → 遣送酒馆 → 重新进入地牢时，死亡屏幕等残留状态未清理
	if death_tween != null and death_tween.is_valid():
		death_tween.kill()
		death_tween = null
	if hurt_flash_tween != null and hurt_flash_tween.is_valid():
		hurt_flash_tween.kill()
		hurt_flash_tween = null
	if is_instance_valid(death_screen):
		death_screen.modulate = Color.TRANSPARENT
	if is_instance_valid(hurt_vignette):
		hurt_vignette.modulate.a = 0.0
	# 隐藏所有交互悬浮窗
	_hide_all_hints()
	if is_instance_valid(subtitle_label):
		subtitle_label.visible = false
	if is_instance_valid(tutorial_hint_label):
		tutorial_hint_label.visible = false
	# 关闭可能打开的装备面板
	if character_panel_instance != null and is_instance_valid(character_panel_instance) and character_panel_instance.visible:
		character_panel_instance.hide_panel()

const CHARACTER_PANEL_PREFAB := preload("res://scenes/ui/tavern_equipment_panel.tscn")
var character_panel_instance: TavernEquipmentPanel = null

func _input(event: InputEvent) -> void:
	if world_space != "dungeon":
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		# Consume the event to prevent propagation
		get_viewport().set_input_as_handled()
		toggle_character_panel()

func toggle_character_panel() -> void:
	if death_screen and death_screen.modulate.a > 0.5:
		return # Cannot open inventory while dead
		
	if not character_panel_instance:
		character_panel_instance = CHARACTER_PANEL_PREFAB.instantiate() as TavernEquipmentPanel
		character_panel_instance.visible = false
		add_child(character_panel_instance)
		
	if character_panel_instance.visible:
		character_panel_instance.hide_panel()
	else:
		character_panel_instance.show_panel()
