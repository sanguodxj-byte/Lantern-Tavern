extends Control
class_name OriginSelectUi

## 出身选择界面（docs/36-出身系统与涌现式Build.md）。
## 在新游戏流程中插入主菜单"开始游戏"与"教程选择"之间。
## 玩家选择出身后，通过 origin_selected 信号通知主菜单。

const OD := preload("res://globals/combat/origin_data.gd")

## 选中出身时触发，参数为出身 id
signal origin_selected(origin_id: String)
## 返回上级菜单
signal back_requested

var _selected_origin_id: String = ""
var _card_buttons: Array = []
var _confirm_btn: Button
var _back_btn: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

## 构建出身选择 UI
func _build_ui() -> void:
	# 主面板
	var panel := PanelContainer.new()
	panel.name = "OriginPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.043, 0.035, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.78, 0.48, 0.2, 0.82)
	sb.content_margin_left = 24.0
	sb.content_margin_top = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_bottom = 24.0
	sb.corner_detail = 1
	sb.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	# 内容垂直居中：PanelContainer 子节点为 Control 时默认左上，
	# 用 CenterContainer 包裹 VBox 实现全屏居中（与主菜单面板同轴）。
	var center := CenterContainer.new()
	center.name = "OriginCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.name = "OriginVBox"
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(560, 0)
	center.add_child(vbox)

	# 标题
	var title := Label.new()
	title.name = "OriginTitle"
	title.text = tr("选择你的出身")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45, 1.0))
	vbox.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.name = "OriginSubtitle"
	subtitle.text = tr("出身决定起跑姿势，不规定终点。任何武器、流派、属性均可通过实际使用成长。")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 1.0))
	vbox.add_child(subtitle)

	# 分隔线
	vbox.add_child(HSeparator.new())

	# 出身卡片网格（2×2）
	var grid := GridContainer.new()
	grid.name = "OriginGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	vbox.add_child(grid)

	for origin_id in OD.get_all_ids():
		var origin: Dictionary = OD.get_origin(origin_id)
		var card := _build_origin_card(origin)
		grid.add_child(card)

	# 底部按钮栏
	var btn_bar := HBoxContainer.new()
	btn_bar.name = "ButtonBar"
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_bar.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_bar)

	_back_btn = Button.new()
	_back_btn.name = "BackBtn"
	_back_btn.text = tr("返回")
	_back_btn.custom_minimum_size = Vector2(140, 48)
	_back_btn.pressed.connect(_on_back_pressed)
	btn_bar.add_child(_back_btn)

	_confirm_btn = Button.new()
	_confirm_btn.name = "ConfirmBtn"
	_confirm_btn.text = tr("确认出身")
	_confirm_btn.custom_minimum_size = Vector2(180, 48)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_bar.add_child(_confirm_btn)

## 构建单个出身卡片
func _build_origin_card(origin: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Card_" + String(origin["id"])
	# 统一卡片高度（lore 文本长度差异不再导致参差）
	card.custom_minimum_size = Vector2(230, 190)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.08, 0.06, 0.92)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.48, 0.38, 0.28, 0.7)
	sb.content_margin_left = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_right = 18.0
	sb.content_margin_bottom = 14.0
	sb.corner_detail = 1
	sb.anti_aliasing = false
	card.add_theme_stylebox_override("panel", sb)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 8)
	card.add_child(card_vbox)

	# 出身名称
	var name_label := Label.new()
	name_label.text = String(origin["name"])
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45, 1.0))
	card_vbox.add_child(name_label)

	# 背景故事
	var lore_label := Label.new()
	lore_label.text = String(origin["lore"])
	lore_label.add_theme_font_size_override("font_size", 12)
	lore_label.add_theme_color_override("font_color", Color(0.72, 0.66, 0.56, 1.0))
	lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore_label.custom_minimum_size = Vector2(200, 0)
	lore_label.max_lines_visible = 3
	card_vbox.add_child(lore_label)

	# 属性偏移
	var attr_text := _format_attr_bonus(origin.get("attr_bonus", {}))
	var attr_label := Label.new()
	attr_label.text = attr_text
	attr_label.add_theme_font_size_override("font_size", 13)
	attr_label.add_theme_color_override("font_color", Color(0.9, 0.78, 0.58, 1.0))
	card_vbox.add_child(attr_label)

	# 初始武器 + 酿酒方向
	var info_label := Label.new()
	var weapon_text := tr("初始武器") + ": " + String(origin.get("starting_weapon", ""))
	var brew_text := tr("酿酒方向") + ": " + String(origin.get("brewing_direction", ""))
	info_label.text = weapon_text + "\n" + brew_text
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", Color(0.62, 0.60, 0.52, 1.0))
	card_vbox.add_child(info_label)

	# 选中按钮（贴底：占满剩余空间）
	var select_btn := Button.new()
	select_btn.text = tr("选择")
	select_btn.custom_minimum_size = Vector2(0, 36)
	select_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var origin_id := String(origin["id"])
	select_btn.pressed.connect(func(): _on_origin_card_selected(origin_id))
	select_btn.toggle_mode = true
	card_vbox.add_child(select_btn)
	_card_buttons.append({"id": origin_id, "button": select_btn, "card": card})

	return card

## 格式化属性偏移显示
func _format_attr_bonus(attr_bonus: Dictionary) -> String:
	var parts: Array = []
	var attr_names := {"str": "STR", "dex": "DEX", "mag": "MAG", "con": "CON", "agi": "AGI", "per": "PER"}
	for key in attr_names:
		if attr_bonus.has(key):
			parts.append(attr_names[key] + " +" + str(int(attr_bonus[key])))
	return " ".join(parts)

## 选中某个出身卡片
func _on_origin_card_selected(origin_id: String) -> void:
	_selected_origin_id = origin_id
	# 更新卡片高亮状态
	for entry in _card_buttons:
		var is_selected: bool = String(entry["id"]) == origin_id
		var btn: Button = entry["button"]
		btn.set_pressed(is_selected)
		_apply_card_selected_style(entry["card"], is_selected)
	# 启用确认按钮（切换为主按钮高亮样式，明确"可确认"状态）
	_confirm_btn.disabled = false
	_confirm_btn.theme_type_variation = &"PrimaryButton"


## 统一卡片选中/未选中样式：选中 = 4px 金边 + 底色微亮 + 金色外发光
func _apply_card_selected_style(card: PanelContainer, selected: bool) -> void:
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
	if sb == null:
		return
	if selected:
		sb.border_color = Color(1.0, 0.78, 0.3, 1.0)
		sb.border_width_left = 4
		sb.border_width_top = 4
		sb.border_width_right = 4
		sb.border_width_bottom = 4
		sb.bg_color = Color(0.16, 0.10, 0.07, 0.95)
		sb.shadow_color = Color(1.0, 0.78, 0.3, 0.25)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 0)
	else:
		sb.border_color = Color(0.48, 0.38, 0.28, 0.7)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.bg_color = Color(0.12, 0.08, 0.06, 0.92)
		sb.shadow_color = Color(0, 0, 0, 0)
		sb.shadow_size = 0

func _on_confirm_pressed() -> void:
	if _selected_origin_id != "":
		origin_selected.emit(_selected_origin_id)

func _on_back_pressed() -> void:
	back_requested.emit()

## 重置选中状态
func reset_selection() -> void:
	_selected_origin_id = ""
	for entry in _card_buttons:
		var btn: Button = entry["button"]
		btn.set_pressed(false)
		_apply_card_selected_style(entry["card"], false)
	_confirm_btn.disabled = true
	_confirm_btn.theme_type_variation = ""
