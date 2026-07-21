extends Control
class_name TavernEquipmentPanel

const SD := preload("res://globals/combat/skill_data.gd")
const AS := preload("res://globals/combat/action_skills.gd")
const RD := preload("res://globals/combat/rune_data.gd")
const DETAIL_POPUP_SCRIPT_PATH := "res://scenes/ui/equipment_detail_popup.gd"
const PLAYER_PREVIEW_SCENE_PATH := "res://scenes/characters/player/player.tscn"
const PLAYER_MODEL_ROUTE := preload("res://scenes/characters/player/player_visual_model.tscn")
const COMBAT_STATS_SCRIPT_PATH := "res://scenes/ui/equipment_panel_combat_stats.gd"
const PLAYER_FINDER_SCRIPT_PATH := "res://scenes/ui/equipment_panel_player_finder.gd"
const VIEW_MODEL := preload("res://scenes/ui/equipment_screen_view_model.gd")
const WEAPON_PROFICIENCY_CATALOG := preload("res://globals/combat/weapon_proficiency_catalog.gd")
const SKILL_RUNTIME_SCRIPT := preload("res://globals/combat/skill_runtime.gd")
const Service := preload("res://globals/core/service.gd")
const BD := preload("res://globals/tavern/brewing_data.gd")
const SLOT_ICON_SIZE := 80
const RUNE_SLOT_ICON_SIZE := 32
const EQUIPMENT_SLOT_SIZE := Vector2(96, 96)
const INVENTORY_GRID_COLUMNS := 6
const LEFT_COLUMN_WIDTH := 640.0
const SLOT_HINT_COLOR := Color(0.94, 0.82, 0.64, 0.55)
const SLOT_FILL_NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SLOT_HINT_ASSET_VERSION := "v4"
const PREVIEW_TEXTURE := preload("res://assets/textures/ui/equipment_preview_dungeon.png")
const GENERATED_SLOT_BACKGROUND_TEXTURES := {
	"head": preload("res://assets/textures/icons/equipment/generated/slot_background_head_generated_v3.png"),
	"body": preload("res://assets/textures/icons/equipment/generated/slot_background_body_generated_v3.png"),
	"hands": preload("res://assets/textures/icons/equipment/generated/slot_background_hands_generated_v3.png"),
	"feet": preload("res://assets/textures/icons/equipment/generated/slot_background_feet_generated_v4.png"),
	"weapon": preload("res://assets/textures/icons/equipment/generated/slot_background_weapon_generated_v3.png"),
}

@onready var return_btn: Button = %ReturnBtn
@onready var slot_head: Button = %SlotHead
@onready var slot_body: Button = %SlotBody
@onready var slot_hands: Button = %SlotHands
@onready var slot_feet: Button = %SlotFeet
@onready var slot_weapon_1: Button = %SlotWeapon1
@onready var slot_weapon_2: Button = %SlotWeapon2
@onready var slot_weapon_3: Button = %SlotWeapon3
@onready var slot_weapon_4: Button = %SlotWeapon4
@onready var weapon_hand_link: Control = %WeaponHandLink
@onready var eq_viewport: SubViewport = %EqSubViewport
@onready var preview_frame: PanelContainer = %PreviewFrame
@onready var eq_camera_pivot: Node3D = %EqCameraPivot
@onready var eq_camera: Camera3D = %EqCamera3D
@onready var character_stats_text: Label = %CharacterStatsText
@onready var proficiency_text: Label = %ProficiencyText
@onready var panel_frame: PanelContainer = $PanelContainer
@onready var left_column: Control = $PanelContainer/VBoxContainer/MainLayout/LeftColumn
@onready var right_tabs: TabContainer = %RightTabs
@onready var gear_list: ItemList = %GearList
@onready var filter_all: Button = %FilterAll
@onready var filter_equipment: Button = %FilterEquipment
@onready var filter_weapons: Button = %FilterWeapons
@onready var filter_armor: Button = %FilterArmor
@onready var filter_materials: Button = %FilterMaterials
@onready var filter_runes: Button = %FilterRunes
@onready var filter_count: Label = %FilterCount
@onready var equip_selected_btn: Button = %EquipSelectedBtn
@onready var item_detail_title: Label = %ItemDetailTitle
@onready var item_detail_meta: Label = %ItemDetailMeta
@onready var item_detail_body: Label = %ItemDetailBody
@onready var item_detail_compare: Label = %ItemDetailCompare
@onready var warehouse_carried_list: ItemList = %WarehouseCarriedList
@onready var warehouse_list: ItemList = %WarehouseList
@onready var skill_slot_0: Button = %SkillSlot0
@onready var skill_slot_1: Button = %SkillSlot1
@onready var skill_slot_2: Button = %SkillSlot2
@onready var skill_slot_3: Button = %SkillSlot3
@onready var skill_slot_4: Button = %SkillSlot4
@onready var skill_slot_5: Button = %SkillSlot5
@onready var skill_slot_6: Button = %SkillSlot6
@onready var rune_warehouse_list: ItemList = %RuneWarehouseList
@onready var available_skills_list: ItemList = %AvailableSkillsList
@onready var skill_details: Label = %SkillDetails
@onready var bind_skill_btn: Button = %BindSkillBtn
@onready var unbind_skill_btn: Button = %UnbindSkillBtn

var selected_skill_id: String = ""
var selected_skill_slot: int = 0
var selected_weapon_slot: int = 0
var selected_armor_slot: String = "body"
var inventory_filter: String = VIEW_MODEL.FILTER_ALL
var weapon_slot_buttons: Array[Button] = []
var armor_slot_buttons: Dictionary = {}
var skill_slot_buttons: Array[Button] = []
var rune_slot_buttons: Array[Button] = []
var detail_popup
var DETAIL_POPUP_SCRIPT: GDScript
var PLAYER_FINDER: GDScript
var current_preview_node: Node3D = null
var _slot_icon_cache: Dictionary = {}
var WeaponRegistry: Node:
	get:
		return get_tree().root.get_node_or_null("WeaponRegistry") if get_tree() != null else null
var GameEvents: Node:
	get:
		return get_tree().root.get_node_or_null("GameEvents") if get_tree() != null else null
var GameState: Node:
	get:
		return get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
var armor_slot_ids := {
	"head": "",
	"body": "",
	"hands": "",
	"feet": "",
}

func _ready() -> void:
	resized.connect(_on_panel_resized)
	right_tabs.tab_changed.connect(_on_right_tab_changed)
	_lock_panel_frame_layout()
	_lock_left_column_layout()
	add_to_group("character_panel")
	weapon_slot_buttons = [slot_weapon_1, slot_weapon_2, slot_weapon_3, slot_weapon_4]
	armor_slot_buttons = {
		"head": slot_head,
		"body": slot_body,
		"hands": slot_hands,
		"feet": slot_feet,
	}
	skill_slot_buttons = [skill_slot_0, skill_slot_1, skill_slot_2, skill_slot_3, skill_slot_4, skill_slot_5, skill_slot_6]
	rune_slot_buttons = _collect_rune_slot_buttons()
	_prepare_skill_workspace_layout()
	_remove_internal_information_fills()
	_apply_pixel_ui_variations()
	_prepare_preview_frame()
	# Keep carried items in a square icon grid with readable names; details remain in tooltips.
	gear_list.max_columns = INVENTORY_GRID_COLUMNS
	if not _is_capture_mode():
		DETAIL_POPUP_SCRIPT = load(DETAIL_POPUP_SCRIPT_PATH) as GDScript
		PLAYER_FINDER = load(PLAYER_FINDER_SCRIPT_PATH) as GDScript
		detail_popup = DETAIL_POPUP_SCRIPT.new() if DETAIL_POPUP_SCRIPT != null else null
		if detail_popup != null:
			add_child(detail_popup)
	return_btn.pressed.connect(hide_panel)
	for i in range(weapon_slot_buttons.size()):
		weapon_slot_buttons[i].pressed.connect(func(slot_index := i): select_weapon_slot(slot_index))
	slot_head.pressed.connect(func(): select_armor_slot("head"))
	slot_body.pressed.connect(func(): select_armor_slot("body"))
	slot_hands.pressed.connect(func(): select_armor_slot("hands"))
	slot_feet.pressed.connect(func(): select_armor_slot("feet"))
	gear_list.item_activated.connect(_on_gear_item_activated)
	gear_list.item_selected.connect(_on_gear_item_selected)
	filter_all.pressed.connect(func(): set_inventory_filter(VIEW_MODEL.FILTER_ALL))
	filter_equipment.pressed.connect(func(): set_inventory_filter(VIEW_MODEL.FILTER_EQUIPMENT))
	filter_weapons.pressed.connect(func(): set_inventory_filter(VIEW_MODEL.FILTER_WEAPONS))
	filter_armor.pressed.connect(func(): set_inventory_filter(VIEW_MODEL.FILTER_ARMOR))
	filter_materials.pressed.connect(func(): set_inventory_filter(VIEW_MODEL.FILTER_MATERIALS))
	filter_runes.pressed.connect(func(): set_inventory_filter(VIEW_MODEL.FILTER_RUNES))
	equip_selected_btn.pressed.connect(_on_equip_selected_pressed)
	available_skills_list.item_selected.connect(_on_available_skill_selected)
	bind_skill_btn.pressed.connect(_on_bind_skill_pressed)
	unbind_skill_btn.pressed.connect(_on_unbind_skill_pressed)
	if not _is_capture_mode():
		_refresh_all()


func _remove_internal_information_fills() -> void:
	# Keep the parchment visible through information containers. The global
	# theme remains opaque for the rest of the game, so this screen applies the
	# transparent treatment locally at runtime after TabContainer setup.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.42, 0.27, 0.16, 0.92)
	panel_style.shadow_color = Color(0.012, 0.008, 0.016, 0.68)
	panel_style.shadow_size = 2
	for node in find_children("", "PanelContainer", true, false):
		var panel := node as PanelContainer
		if panel != null and panel != preview_frame:
			panel.add_theme_stylebox_override("panel", panel_style)
	for node in find_children("", "TabContainer", true, false):
		var tabs := node as TabContainer
		if tabs != null:
			tabs.add_theme_stylebox_override("panel", panel_style)
	for node in find_children("", "ItemList", true, false):
		var list := node as ItemList
		if list != null:
			list.add_theme_stylebox_override("panel", panel_style)


func _is_capture_mode() -> bool:
	if get_tree() == null or get_tree().root == null:
		return false
	return bool(get_tree().root.get_meta("equipment_capture_mode", false))


## 左侧装备/预览/属性栏是稳定的视觉锚点，不能随右侧 Tab 的最小宽度变化。
## 右侧内容允许扩展或压缩；左侧只保留固定的 640px 基准宽度。
func _lock_left_column_layout() -> void:
	if left_column == null:
		return
	left_column.custom_minimum_size.x = LEFT_COLUMN_WIDTH
	left_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_column.size_flags_stretch_ratio = 0.0


## 面板内容的最小宽度不能反向改变外框的 20px 内边距。
## 使用左上角锚点后，外框只跟随根节点尺寸变化，不参与内容最小尺寸回算。
func _lock_panel_frame_layout() -> void:
	if panel_frame == null or size.x <= 0.0 or size.y <= 0.0:
		return
	panel_frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel_frame.position = Vector2(20.0, 20.0)
	panel_frame.size = Vector2(maxf(0.0, size.x - 40.0), maxf(0.0, size.y - 40.0))


func _on_panel_resized() -> void:
	_lock_panel_frame_layout()


func _on_right_tab_changed(_tab_index: int) -> void:
	# TabContainer recalculates its minimum size after emitting tab_changed.
	# Defer the frame lock until that layout pass has completed.
	call_deferred("_lock_panel_frame_layout")


func _apply_pixel_ui_variations() -> void:
	for button in armor_slot_buttons.values():
		(button as Button).theme_type_variation = &"SlotButton"
	for button in weapon_slot_buttons:
		button.theme_type_variation = &"SlotButton"
	for button in skill_slot_buttons:
		button.theme_type_variation = &"SlotButton"
	for index in range(skill_slot_buttons.size()):
		var skill_slot_size := 150.0 if index < 2 else 92.0
		skill_slot_buttons[index].custom_minimum_size = Vector2(skill_slot_size, skill_slot_size)
		skill_slot_buttons[index].size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		skill_slot_buttons[index].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for button in rune_slot_buttons:
		button.theme_type_variation = &"SlotButton"
		button.custom_minimum_size = Vector2(44, 44)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	available_skills_list.icon_mode = ItemList.ICON_MODE_LEFT
	available_skills_list.fixed_icon_size = Vector2i(44, 44)
	available_skills_list.add_theme_font_size_override("font_size", 20)
	rune_warehouse_list.icon_mode = ItemList.ICON_MODE_TOP
	rune_warehouse_list.fixed_icon_size = Vector2i(72, 72)
	rune_warehouse_list.fixed_column_width = 148
	rune_warehouse_list.max_columns = 6
	rune_warehouse_list.same_column_width = true
	rune_warehouse_list.add_theme_font_size_override("font_size", 18)
	for path in [
		"%RuneWarehouseTitle",
		"PanelContainer/VBoxContainer/MainLayout/RightTabs/仓库/WarehouseLayout/CarriedPanel/CarriedBox/CarriedTitle",
		"PanelContainer/VBoxContainer/MainLayout/RightTabs/仓库/WarehouseLayout/WarehousePanel/WarehouseBox/WarehouseTitle",
	]:
		var label := get_node_or_null(path) as Label
		if label != null:
			label.theme_type_variation = &"SectionTitle"


func _prepare_skill_workspace_layout() -> void:
	var skill_tab := get_node_or_null("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能") as Control
	var skill_layout: HBoxContainer = null
	if skill_tab != null:
		skill_layout = skill_tab.get_node_or_null("SkillLayout") as HBoxContainer
	if skill_tab == null or skill_layout == null or skill_tab.get_node_or_null("SkillWorkspaceRuntime") != null:
		return
	var warehouse_panel := skill_layout.get_node_or_null("SkillPyramidPanel/SkillPyramidBox/RuneWarehousePanel") as PanelContainer
	if warehouse_panel == null:
		return
	var workspace := VBoxContainer.new()
	workspace.name = "SkillWorkspaceRuntime"
	workspace.add_theme_constant_override("separation", 12)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_tab.remove_child(skill_layout)
	skill_tab.add_child(workspace)
	workspace.add_child(skill_layout)
	skill_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_layout.size_flags_stretch_ratio = 0.9

	var warehouse_row := HBoxContainer.new()
	warehouse_row.name = "SkillWarehouseRow"
	warehouse_row.custom_minimum_size = Vector2(0, 330)
	warehouse_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	warehouse_row.size_flags_stretch_ratio = 1.1
	warehouse_row.add_theme_constant_override("separation", 12)
	workspace.add_child(warehouse_row)
	warehouse_panel.reparent(warehouse_row, false)
	warehouse_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warehouse_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL




func _prepare_preview_frame() -> void:
	if preview_frame == null:
		return
	var preview_canvas := preview_frame.get_node_or_null("PreviewCanvas") as Control
	if preview_canvas == null:
		# Older hand-authored versions keep ModelViewer directly under PreviewFrame.
		# Wrap that child at runtime so PanelContainer still has one coherent
		# canvas and the background cannot collapse behind the viewport.
		var legacy_model_viewer := preview_frame.get_node_or_null("ModelViewer") as Control
		preview_canvas = Control.new()
		preview_canvas.name = "PreviewCanvas"
		preview_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_frame.add_child(preview_canvas)
		if legacy_model_viewer != null:
			preview_frame.remove_child(legacy_model_viewer)
			preview_canvas.add_child(legacy_model_viewer)
			legacy_model_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dungeon_background := preview_canvas.get_node_or_null("DungeonBackground") as TextureRect
	if dungeon_background == null:
		dungeon_background = TextureRect.new()
		dungeon_background.name = "DungeonBackground"
		dungeon_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dungeon_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		dungeon_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dungeon_background.stretch_mode = TextureRect.STRETCH_SCALE
		preview_canvas.add_child(dungeon_background)
		preview_canvas.move_child(dungeon_background, 0)
	var model_viewer := preview_canvas.get_node_or_null("ModelViewer") as Control
	if model_viewer != null:
		model_viewer.z_index = 1
	dungeon_background.z_index = 0
	preview_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dungeon_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dungeon_background.texture = PREVIEW_TEXTURE
	var style := StyleBoxTexture.new()
	style.texture = PREVIEW_TEXTURE
	style.draw_center = true
	# This is a composed room scene, not a tile. Stretch the full image once so
	# the character stands in one coherent dungeon instead of repeated texture
	# patches.
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.content_margin_left = 10.0
	style.content_margin_top = 10.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 10.0
	preview_frame.add_theme_stylebox_override("panel", style)

func show_panel() -> void:
	_refresh_all()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func hide_panel() -> void:
	hide_detail_popup()
	visible = false
	if get_tree() != null and not get_tree().paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		hide_panel()

func _refresh_all() -> void:
	_sync_warehouse_tab_visibility()
	_refresh_equipment_slots()
	_refresh_character_summary()
	_refresh_preview()
	_refresh_items()
	_refresh_warehouse()
	_refresh_skill_rune_warehouse()
	_refresh_skill_slots()
	_refresh_available_skills()

func _refresh_equipment_slots() -> void:
	_prepare_equipment_slot_buttons()
	_refresh_armor_slot_button("head", tr("头部"))
	_refresh_armor_slot_button("body", tr("身体"))
	_refresh_armor_slot_button("hands", tr("手部"))
	_refresh_armor_slot_button("feet", tr("脚部"))
	var eq := _get_player_equipment()
	var two_hand_slot := _two_hand_group_slot_index(eq)
	weapon_hand_link.visible = two_hand_slot < 0
	if two_hand_slot == 1:
		# The visible combined button is always the leading hand slot. Keep the
		# logical source index separately so replacing it still targets slot 1.
		selected_weapon_slot = 0
	for i in range(weapon_slot_buttons.size()):
		var button := weapon_slot_buttons[i]
		if button == null:
			continue
		if two_hand_slot >= 0 and i == 1:
			button.visible = false
			button.disabled = true
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			continue
		button.visible = true
		button.disabled = false
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.custom_minimum_size = EQUIPMENT_SLOT_SIZE
		var data_index := two_hand_slot if two_hand_slot >= 0 and i == 0 else i
		var icon: Texture2D = _empty_slot_icon("weapon", data_index)
		var item_label := tr("空")
		if eq != null:
			var slot_data: Variant = eq.get_weapon_slot_data(data_index)
			if slot_data != null:
				icon = _slot_icon_for_weapon_data(slot_data)
				item_label = _equipment_display_name(slot_data)
		button.text = ""
		button.button_pressed = i == selected_weapon_slot
		button.tooltip_text = tr("手持槽 %d\n%s") % [data_index + 1, item_label]
		button.icon = icon
		if two_hand_slot >= 0 and i == 0:
			button.custom_minimum_size = Vector2(EQUIPMENT_SLOT_SIZE.x, EQUIPMENT_SLOT_SIZE.y * 2.0 + 6.0)
			button.tooltip_text = tr("双手占用主手与副手\n%s") % item_label


func _weapon_slot_occupies_both_hands(data: Variant) -> bool:
	if data == null:
		return false
	var hands := String(data.hands).to_lower()
	var attack_type := String(data.attack_type).to_lower()
	var weapon_class := String(data.weapon_class).to_lower()
	if hands == "two_hand" or attack_type in ["ranged", "spell"]:
		return true
	if weapon_class in ["two_hand", "longbow", "crossbow", "wand", "grimoire"]:
		return true
	return "two_hand" in data.tags


func _two_hand_group_slot_index(eq: Node) -> int:
	if eq == null or not eq.has_method("get_weapon_slot_data"):
		return -1
	for index in [0, 1]:
		if _weapon_slot_occupies_both_hands(eq.get_weapon_slot_data(index)):
			return index
	return -1


func _normalise_weapon_slot_index(slot_index: int) -> int:
	var clamped := clampi(slot_index, 0, weapon_slot_buttons.size() - 1)
	if clamped > 1:
		return clamped
	var two_hand_slot := _two_hand_group_slot_index(_get_player_equipment())
	if two_hand_slot == 1:
		return 1
	if two_hand_slot == 0:
		return 0
	return clamped


func _weapon_slot_data_index_for_visual(slot_index: int) -> int:
	var clamped := clampi(slot_index, 0, weapon_slot_buttons.size() - 1)
	if clamped == 0:
		var two_hand_slot := _two_hand_group_slot_index(_get_player_equipment())
		if two_hand_slot >= 0:
			return two_hand_slot
	return clamped

func _refresh_items() -> void:
	gear_list.clear()
	_append_materials_to_list(gear_list, _get_carried_inventory(), "items", inventory_filter)
	_append_runes_to_list(gear_list, _get_carried_rune_inventory(), "items", inventory_filter)
	_append_equipment_to_list(gear_list, inventory_filter)
	if gear_list.item_count == 0:
		gear_list.add_item(tr("随身物品为空"))
		gear_list.set_item_disabled(0, true)
	filter_count.text = "%s · %d件" % [VIEW_MODEL.filter_label(inventory_filter), gear_list.item_count if gear_list.item_count > 0 and gear_list.get_item_metadata(0) != null else 0]
	_update_inventory_filter_buttons()
	_clear_selected_item_detail()

func _append_equipment_to_list(list: ItemList, filter_id: String = "") -> void:
	var equipment_inventory := _get_carried_equipment_inventory()
	for raw_id in equipment_inventory.keys():
		var equipment_id := String(raw_id)
		var amount := int(equipment_inventory.get(equipment_id, 0))
		if amount <= 0:
			continue
		var meta: Dictionary = WeaponRegistry.get_entry_meta(equipment_id)
		if meta.is_empty():
			continue
		var category := String(meta.get("category", ""))
		var item_type := "armor" if _is_armor_category(category) else "weapon"
		if not VIEW_MODEL.accepts_filter(item_type, filter_id):
			continue
		# 获取实际 WeaponData 以显示含词缀的名称
		var display_name: String = WeaponRegistry.get_display_name(equipment_id)
		var weapon_data: WeaponData = null
		var gs := Service.game_state()
		if gs != null and gs.has_method("get_carried_equipment_instance"):
			weapon_data = gs.get_carried_equipment_instance(equipment_id)
		if weapon_data == null:
			weapon_data = WeaponRegistry.get_weapon_data(equipment_id)
		if weapon_data != null and weapon_data.has_method("get_full_display_name"):
			display_name = String(weapon_data.get_full_display_name())
		var quality_label := ""
		if weapon_data != null and not weapon_data.affixes.is_empty():
			quality_label = WeaponData.get_affix_quality_label(weapon_data.affixes)
		var quality_tier := VIEW_MODEL.quality_tier_for(item_type, quality_label)
		var inventory_label := _format_inventory_label(display_name)
		if display_name.find(" · ") < 0:
			var quality_display := quality_label if not quality_label.is_empty() else VIEW_MODEL.quality_label_for_tier(quality_tier)
			if not quality_display.is_empty():
				inventory_label += "\n" + quality_display
		var idx: int = list.add_item("\n", _icon_for_equipment_id(equipment_id))
		list.set_item_metadata(idx, {
			"type": item_type,
			"id": equipment_id,
			"category": category,
			"amount": amount,
			"data": weapon_data,
			"quality_label": quality_label,
			"quality_tier": quality_tier,
			"_inventory_label": inventory_label,
		})
		# tooltip 包含含词缀名称、品质标签和词缀效果
		var tooltip_parts: Array[String] = []
		tooltip_parts.append("%s x%d" % [display_name, amount])
		if weapon_data != null and not weapon_data.affixes.is_empty():
			var tooltip_quality_label := WeaponData.get_affix_quality_label(weapon_data.affixes)
			if not tooltip_quality_label.is_empty():
				tooltip_parts.append("[%s]" % tooltip_quality_label)
			for affix_line in WeaponData.get_affix_detail_lines(weapon_data.affixes):
				tooltip_parts.append(affix_line)
		list.set_item_tooltip(idx, "\n".join(tooltip_parts))

func _refresh_warehouse() -> void:
	warehouse_carried_list.clear()
	warehouse_list.clear()
	_append_materials_to_list(warehouse_carried_list, _get_carried_inventory(), "items")
	_append_runes_to_list(warehouse_carried_list, _get_carried_rune_inventory(), "items")
	_append_materials_to_list(warehouse_list, _get_warehouse_inventory(), "warehouse")
	_append_runes_to_list(warehouse_list, _get_warehouse_rune_inventory(), "warehouse")
	if warehouse_carried_list.item_count == 0:
		warehouse_carried_list.add_item(tr("随身物品为空"))
		warehouse_carried_list.set_item_disabled(0, true)
	if warehouse_list.item_count == 0:
		warehouse_list.add_item(tr("仓库为空"))
		warehouse_list.set_item_disabled(0, true)

func _refresh_skill_rune_warehouse() -> void:
	if rune_warehouse_list == null:
		return
	rune_warehouse_list.clear()
	_append_runes_to_list(rune_warehouse_list, _combined_owned_rune_inventory(), "rune_warehouse")
	if rune_warehouse_list.item_count == 0:
		rune_warehouse_list.add_item(tr("符文为空"))
		rune_warehouse_list.set_item_disabled(0, true)

func _append_materials_to_list(list: ItemList, inventory: Dictionary, source: String, filter_id: String = "") -> void:
	for item_id in inventory.keys():
		var amount: int = int(inventory[item_id])
		if amount <= 0:
			continue
		if not VIEW_MODEL.accepts_filter("material", filter_id):
			continue
		var item_name := _get_material_name(item_id)
		var idx: int = list.add_item("\n", DETAIL_POPUP_SCRIPT.icon_for_material(item_id))
		list.set_item_metadata(idx, {"type": "material", "id": item_id, "source": source, "amount": amount, "quality_tier": "", "_inventory_label": _format_inventory_label(item_name)})
		list.set_item_tooltip(idx, "%s x%d" % [_get_material_name(item_id), amount])

func _append_runes_to_list(list: ItemList, inventory: Dictionary, source: String, filter_id: String = "") -> void:
	for rune_id in inventory.keys():
		var amount: int = int(inventory[rune_id])
		if amount <= 0:
			continue
		if not VIEW_MODEL.accepts_filter("rune", filter_id):
			continue
		var id := String(rune_id)
		var rune_name := RD.get_rune_name(id)
		var rune_icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_rune(id)
		var native_icon := null if list == rune_warehouse_list else rune_icon
		var idx: int = list.add_item("\n", native_icon)
		var rune := RD.get_rune(id)
		var rune_tier := VIEW_MODEL.quality_tier_for("rune", "", String(rune.get("rarity", "common")))
		var rune_label := _format_inventory_label(rune_name) + "\n" + VIEW_MODEL.quality_label_for_tier(rune_tier)
		list.set_item_metadata(idx, {"type": "rune", "id": id, "source": source, "amount": amount, "quality_tier": rune_tier, "_inventory_label": rune_label, "_inventory_icon": rune_icon})
		list.set_item_tooltip(idx, "%s x%d" % [RD.get_rune_name(id), amount])

func _combined_owned_rune_inventory() -> Dictionary:
	var combined: Dictionary = {}
	for inventory in [_get_carried_rune_inventory(), _get_warehouse_rune_inventory()]:
		for raw_id in inventory.keys():
			var rune_id := String(raw_id)
			combined[rune_id] = int(combined.get(rune_id, 0)) + int(inventory[raw_id])
	return combined


func _format_inventory_label(display_name: String) -> String:
	var separator := display_name.find(" · ")
	if separator > 0:
		return "%s\n%s" % [display_name.substr(0, separator), display_name.substr(separator + 3)]
	return display_name

func select_weapon_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= 4:
		return false
	selected_weapon_slot = _normalise_weapon_slot_index(slot_index)
	_refresh_equipment_slots()
	return true

func select_armor_slot(slot_name: String) -> bool:
	if not armor_slot_ids.has(slot_name):
		return false
	selected_armor_slot = slot_name
	_refresh_equipment_slots()
	return true

func configure_selected_weapon_slot(weapon_id: String) -> bool:
	var eq := _get_player_equipment()
	if eq == null:
		return false
	var weapon: WeaponData = WeaponRegistry.get_weapon_data(weapon_id)
	if weapon == null:
		return false
	var target_slot := _normalise_weapon_slot_index(selected_weapon_slot)
	var existing_two_hand_slot := _two_hand_group_slot_index(eq)
	var displaced_two_hand_id := ""
	if existing_two_hand_slot >= 0 and target_slot <= 1 and not _weapon_slot_occupies_both_hands(weapon):
		# Replacing a merged two-hand group with a one-hand weapon starts a new
		# main-hand layout. Do not leave the old two-hand item hidden in slot 2.
		target_slot = 0
		if existing_two_hand_slot != target_slot:
			var displaced_two_hand: Variant = eq.get_weapon_slot_data(existing_two_hand_slot)
			displaced_two_hand_id = String(displaced_two_hand.id) if displaced_two_hand != null and "id" in displaced_two_hand else ""
	if _weapon_slot_occupies_both_hands(weapon):
		# Two-hand, ranged, and spell weapons always use the canonical leading
		# hand slot so the UI and the equipment component share one invariant.
		target_slot = 0
	var previous: Variant = eq.get_weapon_slot_data(target_slot)
	var previous_id := String(previous.id) if previous != null and "id" in previous else ""
	if previous_id == weapon_id:
		_clear_two_hand_companion_slot(eq, target_slot, weapon)
		var activated: bool = eq.activate_weapon_slot(target_slot) if eq.has_method("activate_weapon_slot") else true
		if activated:
			_apply_equipment_changed(eq)
		return activated
	if not _consume_carried_equipment(weapon_id):
		return false
	if not displaced_two_hand_id.is_empty():
		eq.configure_weapon_slot(existing_two_hand_slot, null, false)
	var ok: bool = eq.configure_weapon_slot(target_slot, weapon, true)
	if ok:
		_return_carried_equipment(previous_id)
		_return_carried_equipment(displaced_two_hand_id)
		_clear_two_hand_companion_slot(eq, target_slot, weapon)
		_apply_equipment_changed(eq)
	else:
		_return_carried_equipment(weapon_id)
		_return_carried_equipment(displaced_two_hand_id)
	return ok


func _clear_two_hand_companion_slot(eq: Node, target_slot: int, weapon: WeaponData) -> void:
	if eq == null or not _weapon_slot_occupies_both_hands(weapon) or target_slot > 1:
		return
	var companion_slot := 1 if target_slot == 0 else 0
	var companion: Variant = eq.get_weapon_slot_data(companion_slot)
	if companion == null:
		return
	eq.configure_weapon_slot(companion_slot, null, false)
	var companion_id := String(companion.id) if "id" in companion else ""
	_return_carried_equipment(companion_id)

func configure_armor_slot(slot_name: String, armor_id: String) -> bool:
	if not armor_slot_ids.has(slot_name):
		return false
	var meta: Dictionary = WeaponRegistry.get_entry_meta(armor_id)
	var category: String = meta.get("category", "")
	if not _is_armor_category(category):
		return false
	var armor: WeaponData = WeaponRegistry.get_weapon_data(armor_id)
	var eq := _get_player_equipment()
	if eq == null:
		return false
	var previous: Variant = eq.get_armor_slot_data(slot_name)
	var previous_id := String(previous.id) if previous != null and "id" in previous else ""
	if previous_id == armor_id:
		return true
	if not _consume_carried_equipment(armor_id):
		return false
	if not eq.configure_armor_slot(slot_name, armor):
		_return_carried_equipment(armor_id)
		return false
	_return_carried_equipment(previous_id)
	armor_slot_ids[slot_name] = armor_id
	_apply_equipment_changed(eq)
	return true

func _apply_equipment_changed(eq: Node) -> void:
	if eq != null:
		var gs := Service.game_state()
		if gs != null and gs.has_method("save_equipment_from_player"):
			gs.save_equipment_from_player(_get_current_player())
		if eq.has_method("show_weapon"):
			eq.show_weapon()
		if eq.has_method("show_shield"):
			eq.show_shield()
		if "weapon_data" in eq:
			GameEvents.weapon_changed.emit(eq.weapon_data)
		if eq.has_method("get_active_shield_data"):
			GameEvents.shield_changed.emit(eq.get_active_shield_data())
	_refresh_equipment_slots()
	_refresh_character_summary()
	_refresh_items()
	_refresh_warehouse()
	call_deferred("_refresh_preview")
	_ensure_mouse_visible()

func _on_gear_item_activated(index: int) -> void:
	var meta = gear_list.get_item_metadata(index)
	_equip_gear_metadata(meta)

func _on_gear_item_selected(index: int) -> void:
	var meta = gear_list.get_item_metadata(index)
	_refresh_selected_item_detail(meta)
	if typeof(meta) == TYPE_DICTIONARY and (meta.get("type", "") == "weapon" or meta.get("type", "") == "armor"):
		_refresh_preview(String(meta.get("id", "")))
	else:
		_refresh_preview()

func _on_equip_selected_pressed() -> void:
	var selected := gear_list.get_selected_items()
	if selected.is_empty():
		return
	var meta = gear_list.get_item_metadata(selected[0])
	_equip_gear_metadata(meta)

func set_inventory_filter(filter_id: String) -> void:
	if filter_id not in [VIEW_MODEL.FILTER_ALL, VIEW_MODEL.FILTER_EQUIPMENT, VIEW_MODEL.FILTER_WEAPONS, VIEW_MODEL.FILTER_ARMOR, VIEW_MODEL.FILTER_MATERIALS, VIEW_MODEL.FILTER_RUNES]:
		return
	inventory_filter = filter_id
	_refresh_items()

func _update_inventory_filter_buttons() -> void:
	var buttons := {
		VIEW_MODEL.FILTER_ALL: filter_all,
		VIEW_MODEL.FILTER_EQUIPMENT: filter_equipment,
		VIEW_MODEL.FILTER_WEAPONS: filter_weapons,
		VIEW_MODEL.FILTER_ARMOR: filter_armor,
		VIEW_MODEL.FILTER_MATERIALS: filter_materials,
		VIEW_MODEL.FILTER_RUNES: filter_runes,
	}
	for filter_id in buttons:
		var button: Button = buttons[filter_id]
		button.button_pressed = filter_id == inventory_filter

func _clear_selected_item_detail() -> void:
	item_detail_title.text = "选择物品"
	item_detail_meta.text = "物品详情"
	item_detail_body.text = "点击物品查看属性、词缀和装备效果。"
	item_detail_compare.text = ""
	equip_selected_btn.text = "装备到当前槽"
	equip_selected_btn.disabled = true

func _refresh_selected_item_detail(meta: Variant) -> void:
	if typeof(meta) != TYPE_DICTIONARY or String(meta.get("type", "")).is_empty():
		_clear_selected_item_detail()
		return
	var item_type := String(meta.get("type", ""))
	var item_id := String(meta.get("id", ""))
	var amount := int(meta.get("amount", 1))
	var detail: Dictionary = {}
	match item_type:
		"weapon", "armor":
			detail = DETAIL_POPUP_SCRIPT.detail_for_equipment_id(item_id)
		"material":
			detail = DETAIL_POPUP_SCRIPT.detail_for_material_id(item_id, amount)
		"rune":
			detail = DETAIL_POPUP_SCRIPT.detail_for_rune_id(item_id, amount)
	if detail.is_empty():
		_clear_selected_item_detail()
		return
	item_detail_title.text = String(detail.get("title", "物品"))
	item_detail_meta.text = String(detail.get("category", ""))
	var detail_lines: Array[String] = []
	for line in detail.get("lines", []):
		detail_lines.append(String(line))
	var description := String(detail.get("description", ""))
	if not description.is_empty():
		detail_lines.append(description)
	item_detail_body.text = "\n".join(detail_lines)
	var equippable := item_type == "weapon" or item_type == "armor"
	item_detail_compare.text = ""
	if equippable:
		var candidate_data = meta.get("data", null)
		if candidate_data == null:
			candidate_data = WeaponRegistry.get_weapon_data(item_id)
		var equipped_data = _selected_equipped_data(item_type, candidate_data)
		item_detail_compare.text = VIEW_MODEL.format_comparison(VIEW_MODEL.build_equipment_comparison(candidate_data, equipped_data))
	equip_selected_btn.text = "装备到当前槽" if equippable else "仅供查看"
	equip_selected_btn.disabled = not equippable

func _selected_equipped_data(item_type: String, candidate_data: Variant) -> Variant:
	var eq := _get_player_equipment()
	if eq == null:
		return null
	if item_type == "weapon":
		return eq.get_weapon_slot_data(selected_weapon_slot)
	var armor_slot := String(candidate_data.armor_slot) if candidate_data != null and "armor_slot" in candidate_data and not String(candidate_data.armor_slot).is_empty() else selected_armor_slot
	return eq.get_armor_slot_data(armor_slot)

func _equip_gear_metadata(meta: Variant) -> void:
	if typeof(meta) != TYPE_DICTIONARY:
		return
	match meta.get("type", ""):
		"weapon":
			configure_selected_weapon_slot(String(meta.get("id", "")))
		"armor":
			var armor_data: WeaponData = WeaponRegistry.get_weapon_data(String(meta.get("id", "")))
			var target_slot: String = armor_data.armor_slot if armor_data != null and not armor_data.armor_slot.is_empty() else selected_armor_slot
			configure_armor_slot(target_slot, String(meta.get("id", "")))

func _refresh_skill_slots() -> void:
	var sr: Node = _get_skill_runtime()
	for i in range(7):
		var bound: String = sr.get_slot_skill(i) if sr != null else ""
		var label: String = _slot_label(i)
		var selected_marker := " *" if i == selected_skill_slot else ""
		var skill_name := tr(bound) if bound != "" else tr("空")
		if i >= 0 and i < skill_slot_buttons.size():
			skill_slot_buttons[i].text = "%s%s\n%s" % [label, selected_marker, skill_name]
	_refresh_rune_slots()

func _refresh_rune_slots() -> void:
	var sr: Node = _get_skill_runtime()
	for button in rune_slot_buttons:
		var skill_index: int = int(button.get("skill_slot_index"))
		var socket_index: int = int(button.get("rune_socket_index"))
		var capacity := _rune_slot_capacity(skill_index)
		button.visible = socket_index < capacity
		button.disabled = not button.visible
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if not button.visible:
			continue
		var runes: Array = sr.get_slot_runes(skill_index) if sr != null and sr.has_method("get_slot_runes") else []
		if socket_index < runes.size():
			var rune_id := String(runes[socket_index])
			button.text = ""
			button.icon = _scaled_rune_slot_icon(DETAIL_POPUP_SCRIPT.icon_for_rune(rune_id))
			button.tooltip_text = RD.get_rune_name(rune_id)
		else:
			button.text = "-"
			button.icon = null
			button.tooltip_text = ""

func _refresh_available_skills() -> void:
	available_skills_list.clear()
	for skill in AS.SKILLS:
		_add_available_skill(skill)
	var ap: Node = _get_attr_panel()
	for skill in SD.SKILLS:
		if ap != null and ap.has_skill(skill["id"]):
			_add_available_skill(skill)
	if available_skills_list.item_count > 0:
		available_skills_list.select(0)
		_on_available_skill_selected(0)

func _add_available_skill(skill: Dictionary) -> void:
	var label := String(skill.get("name", skill.get("id", "技能")))
	var icon := _skill_icon_for(String(skill.get("id", "")))
	var idx: int = available_skills_list.add_item(label, icon)
	available_skills_list.set_item_metadata(idx, skill)
	available_skills_list.set_item_tooltip(idx, "%s\n%s" % [skill.get("type", "技能"), skill.get("desc", "")])

func _skill_icon_for(skill_id: String) -> Texture2D:
	if skill_id.is_empty():
		return null
	var icons: Node = Engine.get_main_loop().root.get_node_or_null("SkillIcons")
	if icons != null and icons.has_method("get_icon"):
		return icons.get_icon(skill_id) as Texture2D
	return null

func _on_available_skill_selected(index: int) -> void:
	var skill: Dictionary = available_skills_list.get_item_metadata(index)
	selected_skill_id = skill.get("id", "")
	skill_details.text = "%s\nCD: %.1fs\n%s" % [
		skill.get("name", selected_skill_id),
		float(skill.get("cooldown", 0.0)),
		skill.get("desc", "")
	]

func select_skill_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= 7:
		return false
	selected_skill_slot = slot_index
	var sr: Node = _get_skill_runtime()
	var bound: String = sr.get_slot_skill(slot_index) if sr != null else ""
	if bound != "":
		selected_skill_id = bound
		var skill: Dictionary = AS.get_skill_by_id(bound)
		if skill.is_empty():
			skill = SD.get_skill_by_id(bound)
		skill_details.text = "%s\n%s" % [tr(skill.get("name", bound)), tr(skill.get("desc", ""))]
	else:
		skill_details.text = tr("%s\n空") % _slot_label(slot_index)
	_refresh_skill_slots()
	return true

func _on_bind_skill_pressed() -> void:
	if selected_skill_id == "":
		return
	if not configure_skill_slot(selected_skill_slot, selected_skill_id):
		skill_details.text = tr("无法绑定到该槽位")

func _on_unbind_skill_pressed() -> void:
	configure_skill_slot(selected_skill_slot, "")

func configure_skill_slot(slot_index: int, skill_id: String) -> bool:
	var sr: Node = _get_skill_runtime()
	if sr == null:
		return false
	var ok: bool = sr.bind_skill(slot_index, skill_id)
	if ok:
		_refresh_skill_slots()
		select_skill_slot(slot_index)
	return ok

func configure_skill_slot_rune(slot_index: int, rune_id: String) -> bool:
	var sr: Node = _get_skill_runtime()
	if sr == null or not sr.has_method("socket_rune"):
		return false
	var ok: bool = sr.socket_rune(slot_index, rune_id)
	if ok:
		_consume_rune_from_inventory(rune_id)
		_refresh_items()
		_refresh_warehouse()
		_refresh_skill_rune_warehouse()
		_refresh_skill_slots()
		select_skill_slot(slot_index)
	return ok

func collect_drag_payload(source: String) -> Dictionary:
	var list: ItemList = _list_for_source(source)
	if list == null:
		return {}
	for index in list.get_selected_items():
		var meta = list.get_item_metadata(index)
		if typeof(meta) == TYPE_DICTIONARY and (meta.get("type", "") == "weapon" or meta.get("type", "") == "armor"):
			return {
				"kind": "equipment",
				"id": String(meta.get("id", "")),
				"category": String(meta.get("category", "")),
				"count": int(meta.get("amount", 1)),
			}
	var ids: Array[String] = []
	var rune_ids: Array[String] = []
	for index in list.get_selected_items():
		var meta = list.get_item_metadata(index)
		if typeof(meta) == TYPE_DICTIONARY and meta.get("type", "") == "material":
			ids.append(String(meta["id"]))
		elif typeof(meta) == TYPE_DICTIONARY and meta.get("type", "") == "rune":
			rune_ids.append(String(meta["id"]))
	if ids.is_empty() and rune_ids.is_empty():
		return {}
	if not ids.is_empty() and rune_ids.is_empty():
		return {"kind": "inventory_materials", "source": source, "ids": ids, "count": ids.size()}
	if ids.is_empty() and not rune_ids.is_empty():
		return {"kind": "inventory_runes", "source": source, "rune_ids": rune_ids, "count": rune_ids.size()}
	return {"kind": "inventory_stacks", "source": source, "ids": ids, "rune_ids": rune_ids, "count": ids.size() + rune_ids.size()}

func can_drop_inventory_data(target: String, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var kind := String(data.get("kind", ""))
	if kind == "equipment":
		return target == "items" or target == "warehouse"
	return (kind == "inventory_materials" or kind == "inventory_runes" or kind == "inventory_stacks") \
		and data.get("source", "") != target \
		and (target == "items" or target == "warehouse") \
		and (not _uses_warehouse(String(data.get("source", "")), target) or _is_warehouse_available())

func drop_inventory_data(target: String, data: Variant) -> void:
	if not can_drop_inventory_data(target, data):
		return
	var kind := String(data.get("kind", ""))
	if kind == "equipment":
		_unequip_to_inventory(data)
		return
	transfer_inventory_items(String(data["source"]), target, data.get("ids", []), data.get("rune_ids", []))

func collect_equipment_slot_drag_payload(slot_kind: String, slot_index: int, armor_slot: String) -> Dictionary:
	var eq := _get_player_equipment()
	if eq == null:
		return {}
	match slot_kind:
		"weapon":
			var w_data: Variant = eq.get_weapon_slot_data(_weapon_slot_data_index_for_visual(slot_index))
			if w_data == null:
				return {}
			return {
				"kind": "equipment",
				"id": String(w_data.id),
				"category": String(w_data.equipment_category),
				"count": 1,
				"source_slot_kind": "weapon",
				"source_slot_index": _weapon_slot_data_index_for_visual(slot_index),
			}
		"armor":
			var a_data: Variant = eq.get_armor_slot_data(armor_slot)
			if a_data == null:
				return {}
			return {
				"kind": "equipment",
				"id": String(a_data.id),
				"category": String(a_data.equipment_category),
				"count": 1,
				"source_slot_kind": "armor",
				"source_armor_slot": armor_slot,
			}
	return {}

func _unequip_to_inventory(data: Variant) -> void:
	var eq := _get_player_equipment()
	if eq == null:
		return
	var equipment_id := String(data.get("id", ""))
	if equipment_id.is_empty():
		return
	var source_slot_kind := String(data.get("source_slot_kind", ""))
	match source_slot_kind:
		"weapon":
			var slot_index := int(data.get("source_slot_index", -1))
			if slot_index < 0 or slot_index >= 4:
				return
			var slot_data: Variant = eq.get_weapon_slot_data(slot_index)
			if slot_data == null or String(slot_data.id) != equipment_id:
				return
			eq.configure_weapon_slot(slot_index, null, slot_index == eq.active_weapon_slot)
		"armor":
			var armor_slot := String(data.get("source_armor_slot", ""))
			if not armor_slot_ids.has(armor_slot):
				return
			var slot_data: Variant = eq.get_armor_slot_data(armor_slot)
			if slot_data == null or String(slot_data.id) != equipment_id:
				return
			eq.configure_armor_slot(armor_slot, null)
			armor_slot_ids[armor_slot] = ""
		_:
			return
	_return_carried_equipment(equipment_id)
	_apply_equipment_changed(eq)
	_ensure_mouse_visible()

func can_drop_equipment_slot_data(slot_kind: String, slot_index: int, armor_slot: String, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("kind", "") != "equipment":
		return false
	var category: String = data.get("category", "")
	match slot_kind:
		"weapon":
			if slot_index < 0 or slot_index >= 4 or not _is_hand_category(category):
				return false
			var source_slot_kind := String(data.get("source_slot_kind", ""))
			if source_slot_kind == "weapon":
				var eq := _get_player_equipment()
				if eq != null:
					var source_index := int(data.get("source_slot_index", -1))
					var target_index := _weapon_slot_data_index_for_visual(slot_index)
					var source_data: Variant = eq.get_weapon_slot_data(source_index)
					var target_data: Variant = eq.get_weapon_slot_data(target_index)
					if _weapon_slot_occupies_both_hands(source_data) or _weapon_slot_occupies_both_hands(target_data):
						return false
			return true
		"armor":
			return armor_slot_ids.has(armor_slot) and _is_armor_category(category)
	return false

func drop_equipment_slot_data(slot_kind: String, slot_index: int, armor_slot: String, data: Variant) -> void:
	if not can_drop_equipment_slot_data(slot_kind, slot_index, armor_slot, data):
		_ensure_mouse_visible()
		return
	var equipment_id: String = data.get("id", "")
	var source_slot_kind := String(data.get("source_slot_kind", ""))
	var target_weapon_index := _weapon_slot_data_index_for_visual(slot_index) if slot_kind == "weapon" else slot_index
	# 同槽位拖放直接忽略
	if source_slot_kind == slot_kind:
		if slot_kind == "weapon" and int(data.get("source_slot_index", -1)) == target_weapon_index:
			_ensure_mouse_visible()
			return
		if slot_kind == "armor" and String(data.get("source_armor_slot", "")) == armor_slot:
			_ensure_mouse_visible()
			return
	# 同类槽位间拖拽：直接交换，不经过背包
	if source_slot_kind != "" and source_slot_kind == slot_kind:
		_swap_equipment_slots(data, slot_kind, slot_index, armor_slot)
		_ensure_mouse_visible()
		return
	# 从不同类槽位拖来时先卸下放入背包，再从背包装备到目标槽
	if source_slot_kind != "":
		_unequip_to_inventory(data)
	match slot_kind:
		"weapon":
			select_weapon_slot(slot_index)
			configure_selected_weapon_slot(equipment_id)
		"armor":
			configure_armor_slot(armor_slot, equipment_id)
	_ensure_mouse_visible()

func _swap_equipment_slots(data: Variant, target_kind: String, target_index: int, target_armor_slot: String) -> void:
	var eq := _get_player_equipment()
	if eq == null:
		return
	match target_kind:
		"weapon":
			var source_index := int(data.get("source_slot_index", -1))
			if source_index < 0 or source_index >= 4:
				return
			var source_data: Variant = eq.get_weapon_slot_data(source_index)
			var target_data: Variant = eq.get_weapon_slot_data(_weapon_slot_data_index_for_visual(target_index))
			if _weapon_slot_occupies_both_hands(source_data) or _weapon_slot_occupies_both_hands(target_data):
				# A merged two-hand group is removed through the inventory path, not
				# exchanged with a single visual button. This prevents an invalid
				# hidden companion slot from being created by drag-and-drop.
				return
			var was_source_active: bool = source_index == int(eq.active_weapon_slot)
			eq.configure_weapon_slot(source_index, target_data, false)
			eq.configure_weapon_slot(target_index, source_data, was_source_active)
		"armor":
			var source_armor := String(data.get("source_armor_slot", ""))
			if not armor_slot_ids.has(source_armor) or not armor_slot_ids.has(target_armor_slot):
				return
			var source_data: Variant = eq.get_armor_slot_data(source_armor)
			var target_data: Variant = eq.get_armor_slot_data(target_armor_slot)
			eq.configure_armor_slot(source_armor, target_data)
			eq.configure_armor_slot(target_armor_slot, source_data)
			armor_slot_ids[source_armor] = String(target_data.id) if target_data != null else ""
			armor_slot_ids[target_armor_slot] = String(source_data.id) if source_data != null else ""
	_apply_equipment_changed(eq)

func _ensure_mouse_visible() -> void:
	if visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func collect_skill_drag_payload(source: String) -> Dictionary:
	match source:
		"available_skills":
			if available_skills_list.get_selected_items().is_empty():
				return {}
			var skill: Dictionary = available_skills_list.get_item_metadata(available_skills_list.get_selected_items()[0])
			return {"kind": "skill", "id": String(skill.get("id", "")), "count": 1}
		"skill_slots":
			return collect_skill_slot_drag_payload(selected_skill_slot)
	return {}

func collect_skill_slot_drag_payload(slot_index: int) -> Dictionary:
	var sr: Node = _get_skill_runtime()
	var bound: String = sr.get_slot_skill(slot_index) if sr != null else ""
	if bound == "":
		return {}
	return {"kind": "skill", "id": bound, "source_slot": slot_index, "count": 1}

func can_drop_skill_slot_data(slot_index: int, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var kind := String(data.get("kind", ""))
	if kind == "skill":
		return _can_bind_skill_to_slot(slot_index, String(data.get("id", "")))
	if kind == "rune" or kind == "inventory_runes":
		var rune_id := String(data.get("id", ""))
		if rune_id.is_empty():
			var ids: Array = data.get("rune_ids", [])
			rune_id = String(ids[0]) if not ids.is_empty() else ""
		return _can_socket_rune_to_slot(slot_index, rune_id)
	return false

func drop_skill_slot_data(slot_index: int, data: Variant) -> void:
	if not can_drop_skill_slot_data(slot_index, data):
		return
	var kind := String(data.get("kind", ""))
	if kind == "skill":
		configure_skill_slot(slot_index, String(data.get("id", "")))
	elif kind == "rune":
		configure_skill_slot_rune(slot_index, String(data.get("id", "")))
	elif kind == "inventory_runes":
		for raw_id in data.get("rune_ids", []):
			if not configure_skill_slot_rune(slot_index, String(raw_id)):
				break

func can_drop_rune_socket_data(slot_index: int, rune_socket_index: int, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if rune_socket_index < 0 or rune_socket_index >= _rune_slot_capacity(slot_index):
		return false
	var sr: Node = _get_skill_runtime()
	var runes: Array = sr.get_slot_runes(slot_index) if sr != null and sr.has_method("get_slot_runes") else []
	if rune_socket_index < runes.size():
		return false
	return can_drop_skill_slot_data(slot_index, data)

func drop_rune_socket_data(slot_index: int, rune_socket_index: int, data: Variant) -> void:
	if can_drop_rune_socket_data(slot_index, rune_socket_index, data):
		drop_skill_slot_data(slot_index, data)

func show_inventory_item_detail(source: String, item_index: int, screen_position: Vector2) -> void:
	var list := _list_for_source(source)
	if list == null or item_index < 0 or item_index >= list.item_count:
		hide_detail_popup()
		return
	var meta = list.get_item_metadata(item_index)
	if typeof(meta) != TYPE_DICTIONARY:
		hide_detail_popup()
		return
	match String(meta.get("type", "")):
		"weapon", "armor":
			var instance_data = meta.get("data", null)
			if instance_data != null:
				detail_popup.show_for_weapon_data(instance_data, screen_position)
			else:
				detail_popup.show_for_equipment_id(String(meta.get("id", "")), screen_position)
		"material":
			detail_popup.show_for_material_id(String(meta.get("id", "")), int(meta.get("amount", 1)), screen_position)
		"rune":
			detail_popup.show_for_rune_id(String(meta.get("id", "")), int(meta.get("amount", 1)), screen_position)
		_:
			hide_detail_popup()

func show_equipment_slot_detail(slot_kind: String, slot_index: int, armor_slot: String, screen_position: Vector2) -> void:
	var eq := _get_player_equipment()
	if eq == null:
		hide_detail_popup()
		return
	match slot_kind:
		"weapon":
			detail_popup.show_for_weapon_data(eq.get_weapon_slot_data(_weapon_slot_data_index_for_visual(slot_index)), screen_position)
		"armor":
			detail_popup.show_for_weapon_data(eq.get_armor_slot_data(armor_slot), screen_position)
		_:
			hide_detail_popup()

func hide_detail_popup() -> void:
	if detail_popup != null:
		detail_popup.hide_detail()

func transfer_materials(source: String, target: String, item_ids: Array) -> Dictionary:
	var source_inv: Dictionary = _inventory_for_source(source)
	var target_inv: Dictionary = _inventory_for_source(target)
	var moved: Dictionary = move_items_between(source_inv, target_inv, item_ids, target == "items", GameState.MATERIAL_SPACE_PER_ITEM)
	_refresh_items()
	_refresh_warehouse()
	_refresh_skill_rune_warehouse()
	return moved

func transfer_inventory_items(source: String, target: String, material_ids: Array, rune_ids: Array) -> Dictionary:
	var moved := {
		"materials": move_items_between(_inventory_for_source(source), _inventory_for_source(target), material_ids, target == "items", GameState.MATERIAL_SPACE_PER_ITEM),
		"runes": move_items_between(_rune_inventory_for_source(source), _rune_inventory_for_source(target), rune_ids, target == "items", GameState.RUNE_SPACE_PER_ITEM),
	}
	_refresh_items()
	_refresh_warehouse()
	_refresh_skill_rune_warehouse()
	return moved

func move_items_between(source_inv: Dictionary, target_inv: Dictionary, item_ids: Array, target_is_carried: bool = false, space_per_item: int = 1) -> Dictionary:
	var moved: Dictionary = {}
	for raw_id in item_ids:
		var item_id: String = String(raw_id)
		var amount: int = int(source_inv.get(item_id, 0))
		if amount <= 0:
			continue
		if target_is_carried and not _can_add_carried_stack(amount, space_per_item):
			continue
		target_inv[item_id] = int(target_inv.get(item_id, 0)) + amount
		source_inv.erase(item_id)
		moved[item_id] = amount
	return moved

func _refresh_armor_slot_button(slot_name: String, display_name: String) -> void:
	var button: Button = armor_slot_buttons.get(slot_name, null)
	if button == null:
		return
	var marker := " *" if selected_armor_slot == slot_name else ""
	var item_label := tr("空")
	button.icon = _empty_slot_icon(slot_name)
	var eq := _get_player_equipment()
	var slot_data = eq.get_armor_slot_data(slot_name) if eq != null else null
	if slot_data != null:
		armor_slot_ids[slot_name] = slot_data.id
		button.icon = _slot_icon_for_weapon_data(slot_data)
		item_label = _equipment_display_name(slot_data)
	else:
		armor_slot_ids[slot_name] = ""
		var equipment_id: String = armor_slot_ids.get(slot_name, "")
		if not equipment_id.is_empty():
			button.icon = _slot_icon_for_equipment_id(equipment_id)
			item_label = WeaponRegistry.get_display_name(equipment_id)
	button.text = ""
	button.button_pressed = selected_armor_slot == slot_name
	button.tooltip_text = "%s%s\n%s" % [display_name, marker, item_label]

func _refresh_character_summary() -> void:
	if character_stats_text == null or proficiency_text == null:
		return
	var player := _get_current_player()
	var eq := _get_player_equipment()
	var ap := _get_attr_panel()
	var attrs: Dictionary = ap.get_player_attrs() if ap != null and ap.has_method("get_player_attrs") else {
		"str": 5, "dex": 5, "mag": 5, "con": 5, "agi": 5, "per": 5,
	}
	var level := int(ap.get_level()) if ap != null and ap.has_method("get_level") else 1
	var life_text := "—"
	if player != null and "health" in player and player.health != null:
		life_text = "%d / %d" % [player.health.current_life, player.health.max_life]
	var weapon = eq.weapon_data if eq != null and "weapon_data" in eq else null
	var attack_text := "%d–%d" % [weapon.damage_min, weapon.damage_max] if weapon != null else "—"
	var armor_value := int(attrs.get("con", 0))
	if eq != null and eq.has_method("get_armor_defense"):
		armor_value += int(eq.get_armor_defense())
	var evade_text := "%.0f%%" % ap.compute_evade_rate() if ap != null and ap.has_method("compute_evade_rate") else "—"
	var crit_text := "%.0f%%" % ap.compute_crit_rate() if ap != null and ap.has_method("compute_crit_rate") else "—"
	# StatsVisual alternates entries into left/right columns. Keep combat readouts
	# on the left and the six canonical attributes on the right.
	var stats_lines: Array[String] = [
		"等级 %d" % level, "力量 STR %d" % int(attrs.get("str", 0)),
		"生命 %s" % life_text, "敏捷 DEX %d" % int(attrs.get("dex", 0)),
		"攻击 %s" % attack_text, "体质 CON %d" % int(attrs.get("con", 0)),
		"护甲 %d" % armor_value, "智力 MAG %d" % int(attrs.get("mag", 0)),
		"闪避 %s" % evade_text, "灵巧 AGI %d" % int(attrs.get("agi", 0)),
		"暴击 %s" % crit_text, "感知 PER %d" % int(attrs.get("per", 0)),
	]
	if stats_lines.is_empty():
		stats_lines.append(tr("未找到实机角色"))
	character_stats_text.text = "\n".join(stats_lines)

	var prof_lines: Array[String] = []
	if ap != null and "weapon_proficiency" in ap:
		var prof: Dictionary = ap.weapon_proficiency
		for entry in WEAPON_PROFICIENCY_CATALOG.entries():
			var key := String(entry["key"])
			prof_lines.append("%s %d" % [tr(String(entry["label"])), WEAPON_PROFICIENCY_CATALOG.value_for(prof, key)])
	if prof_lines.is_empty():
		prof_lines.append(tr("暂无熟练度记录"))
	proficiency_text.text = "\n".join(prof_lines)

func _refresh_preview(preview_equipment_id: String = "") -> void:
	if eq_viewport == null:
		return
	var preview_hand_data: WeaponData = null
	var eq := _get_player_equipment()
	if eq != null:
		preview_hand_data = eq.weapon_data if "weapon_data" in eq else null
	if not preview_equipment_id.is_empty():
		var data: WeaponData = WeaponRegistry.get_weapon_data(preview_equipment_id)
		if data != null and _is_hand_category(data.equipment_category):
			preview_hand_data = data
	_spawn_preview_character(preview_hand_data)

func _clear_preview() -> void:
	if current_preview_node != null and is_instance_valid(current_preview_node):
		current_preview_node.queue_free()
	current_preview_node = null

func _spawn_preview_character(hand_data: WeaponData = null) -> void:
	_clear_preview()
	var preview_scene := load(PLAYER_PREVIEW_SCENE_PATH) as PackedScene
	var preview_player: Node3D = preview_scene.instantiate() as Node3D if preview_scene != null else null
	if preview_player == null:
		_spawn_fallback_preview_model()
		return
	preview_player.set_meta("equipment_preview", true)
	eq_viewport.add_child(preview_player)
	current_preview_node = preview_player
	preview_player.position = Vector3(0, -0.85, 0)
	preview_player.rotation = Vector3(0, deg_to_rad(215), 0)
	preview_player.set_process(false)
	preview_player.set_physics_process(false)
	preview_player.set_process_input(false)
	preview_player.set_process_unhandled_input(false)
	preview_player.movement_input_enabled = false
	preview_player.interaction_input_enabled = false
	preview_player.combat_input_enabled = false
	if preview_player.equipment != null:
		preview_player.equipment.is_linked_to_ui = false
		if hand_data != null:
			preview_player.equipment.configure_weapon_slot(0, hand_data, true)
	if preview_player.camera != null:
		preview_player.camera.queue_free()
	for path in ["%SelectRaycast", "%KickRaycast", "%WeaponReachRaycast"]:
		var ray_node := preview_player.get_node_or_null(NodePath(path))
		if ray_node != null:
			ray_node.queue_free()
	var collision := preview_player.get_node_or_null("CollisionShape3D")
	if collision != null:
		collision.queue_free()
	if preview_player.animation_player != null and preview_player.animation_player.has_animation("idle"):
		preview_player.animation_player.play("idle")

func _spawn_fallback_preview_model() -> void:
	var fallback := PLAYER_MODEL_ROUTE.instantiate() as Node3D
	if fallback == null:
		return
	fallback.set_meta("equipment_preview_fallback", true)
	eq_viewport.add_child(fallback)
	current_preview_node = fallback
	fallback.position = Vector3(0, -0.85, 0)
	fallback.rotation = Vector3(0, deg_to_rad(215), 0)

func _prepare_equipment_slot_buttons() -> void:
	for slot_kind in armor_slot_buttons:
		_prepare_icon_button(armor_slot_buttons[slot_kind], slot_kind)
	for button in weapon_slot_buttons:
		_prepare_icon_button(button, "weapon")

func _prepare_icon_button(button: Button, slot_kind: String) -> void:
	if button == null:
		return
	button.custom_minimum_size = EQUIPMENT_SLOT_SIZE
	button.toggle_mode = true
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _empty_slot_icon(slot_kind: String, _variant: int = 0) -> Texture2D:
	# 使用 Button 原生 icon 绘制浅色实心剪影，避免额外 TextureRect 被按钮主题背景遮挡。
	var key := "empty_hint_%s_%s" % [SLOT_HINT_ASSET_VERSION, slot_kind]
	var cached: Variant = _slot_icon_cache.get(key)
	if cached is Texture2D:
		return cached
	var source := GENERATED_SLOT_BACKGROUND_TEXTURES.get(slot_kind, GENERATED_SLOT_BACKGROUND_TEXTURES["weapon"]) as Texture2D
	if source == null:
		return null
	var image := source.get_image()
	image.convert(Image.FORMAT_RGBA8)
	image = _build_solid_slot_hint_image(image)
	var hint := ImageTexture.create_from_image(image)
	_slot_icon_cache[key] = hint
	return hint


func _build_solid_slot_hint_image(source_image: Image) -> Image:
	var image := source_image.duplicate()
	var width: int = image.get_width()
	var height: int = image.get_height()
	var boundary := PackedByteArray()
	boundary.resize(width * height)
	for y in range(height):
		for x in range(width):
			boundary[y * width + x] = 1 if _slot_hint_boundary_pixel(image, x, y) else 0

	# Flood-fill the matte from the canvas edge. Pixels not reached by that fill
	# are inside the silhouette and become the solid role hint.
	var exterior := PackedByteArray()
	exterior.resize(width * height)
	var queue: Array[Vector2i] = []
	for x in range(width):
		_queue_slot_hint_exterior(Vector2i(x, 0), width, height, boundary, exterior, queue)
		_queue_slot_hint_exterior(Vector2i(x, height - 1), width, height, boundary, exterior, queue)
	for y in range(height):
		_queue_slot_hint_exterior(Vector2i(0, y), width, height, boundary, exterior, queue)
		_queue_slot_hint_exterior(Vector2i(width - 1, y), width, height, boundary, exterior, queue)
	var queue_index: int = 0
	while queue_index < queue.size():
		var point := queue[queue_index]
		queue_index += 1
		for offset in SLOT_FILL_NEIGHBORS:
			_queue_slot_hint_exterior(point + offset, width, height, boundary, exterior, queue)

	for y in range(height):
		for x in range(width):
			var index: int = y * width + x
			if boundary[index] == 1 or exterior[index] == 0:
				image.set_pixel(x, y, SLOT_HINT_COLOR)
			else:
				image.set_pixel(x, y, Color.TRANSPARENT)
	return image


func _slot_hint_boundary_pixel(image: Image, x: int, y: int) -> bool:
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var sample_x := x + offset_x
			var sample_y := y + offset_y
			if sample_x < 0 or sample_x >= image.get_width() or sample_y < 0 or sample_y >= image.get_height():
				continue
			var pixel := image.get_pixel(sample_x, sample_y)
			if pixel.a > 0.01 and maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.10:
				return true
	return false


func _queue_slot_hint_exterior(point: Vector2i, width: int, height: int, boundary: PackedByteArray, exterior: PackedByteArray, queue: Array[Vector2i]) -> void:
	if point.x < 0 or point.x >= width or point.y < 0 or point.y >= height:
		return
	var index: int = point.y * width + point.x
	if boundary[index] == 1 or exterior[index] == 1:
		return
	exterior[index] = 1
	queue.append(point)

func _build_combat_stat_lines(player: Node, eq: Node, ap: Node) -> Array[String]:
	var combat_stats_script := load(COMBAT_STATS_SCRIPT_PATH) as GDScript
	return combat_stats_script.build_stat_lines(player, eq, ap) if combat_stats_script != null else []

func _equipment_display_name(data) -> String:
	if data == null:
		return tr("空")
	# 优先使用含词缀前缀的完整显示名
	if data.has_method("get_full_display_name"):
		var full := String(data.get_full_display_name())
		if not full.is_empty():
			return full
	if "name_zh" in data and not String(data.name_zh).is_empty():
		return String(data.name_zh)
	if "name" in data:
		return String(data.name)
	return tr("装备")

func _is_armor_category(category: String) -> bool:
	return category.begins_with("armor")

func _is_hand_category(category: String) -> bool:
	return category == "weapons" or category == "shields"

func _can_bind_skill_to_slot(slot_index: int, skill_id: String) -> bool:
	var sr: Node = _get_skill_runtime()
	if sr == null or slot_index < 0 or slot_index >= 7 or skill_id == "":
		return false
	var slot_type: int = sr.get_slot_type(slot_index)
	match slot_type:
		SKILL_RUNTIME_SCRIPT.SlotType.F_ACTION, SKILL_RUNTIME_SCRIPT.SlotType.G_WEAPON:
			if not AS.get_skill_by_id(skill_id).is_empty():
				return true
			var active_skill: Dictionary = SD.get_skill_by_id(skill_id)
			return not active_skill.is_empty() and active_skill.get("type", "") == "active" and _attr_panel_has_skill(skill_id)
		SKILL_RUNTIME_SCRIPT.SlotType.PASSIVE:
			var passive_skill: Dictionary = SD.get_skill_by_id(skill_id)
			return not passive_skill.is_empty() and passive_skill.get("type", "") == "passive" and _attr_panel_has_skill(skill_id)
	return false

func _can_socket_rune_to_slot(slot_index: int, rune_id: String) -> bool:
	var sr: Node = _get_skill_runtime()
	if sr == null or not sr.has_method("get_slot_runes"):
		return false
	if slot_index < 0 or slot_index >= 7 or rune_id.is_empty() or not RD.has_rune(rune_id):
		return false
	if sr.get_slot_skill(slot_index) == "":
		return false
	var runes: Array = sr.get_slot_runes(slot_index)
	return runes.size() < _rune_slot_capacity(slot_index)

func _attr_panel_has_skill(skill_id: String) -> bool:
	var ap: Node = _get_attr_panel()
	return ap != null and ap.has_method("has_skill") and ap.has_skill(skill_id)

func _list_for_source(source: String) -> ItemList:
	match source:
		"items":
			if right_tabs.current_tab == 2:
				return warehouse_carried_list
			return gear_list
		"warehouse":
			return warehouse_list
		"rune_warehouse":
			return rune_warehouse_list
	return null

func _inventory_for_source(source: String) -> Dictionary:
	match source:
		"items":
			return _get_carried_inventory()
		"warehouse":
			return _get_warehouse_inventory()
	return {}

func _rune_inventory_for_source(source: String) -> Dictionary:
	match source:
		"items":
			return _get_carried_rune_inventory()
		"warehouse":
			return _get_warehouse_rune_inventory()
	return {}

func _get_carried_inventory() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_materials" in gs:
		return gs.carried_materials
	return {}

func _get_carried_rune_inventory() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_runes" in gs:
		return gs.carried_runes
	return {}

func _get_carried_equipment_inventory() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_equipment" in gs:
		return gs.carried_equipment
	return {}

func _get_warehouse_inventory() -> Dictionary:
	var tm: Node = Service.tavern_manager()
	if tm != null and "materials_inventory" in tm:
		return tm.materials_inventory
	return {}

func _get_warehouse_rune_inventory() -> Dictionary:
	var tm: Node = Service.tavern_manager()
	if tm != null and "runes_inventory" in tm:
		return tm.runes_inventory
	return {}

func _consume_rune_from_inventory(rune_id: String) -> bool:
	for inventory in [_get_carried_rune_inventory(), _get_warehouse_rune_inventory()]:
		var amount := int(inventory.get(rune_id, 0))
		if amount <= 0:
			continue
		if amount > 1:
			inventory[rune_id] = amount - 1
		else:
			inventory.erase(rune_id)
		return true
	return false

func _consume_carried_equipment(equipment_id: String) -> bool:
	var gs: Node = Service.game_state()
	if gs == null or not gs.has_method("remove_carried_equipment"):
		return false
	return gs.remove_carried_equipment(equipment_id, 1)

func _return_carried_equipment(equipment_id: String) -> void:
	if equipment_id.is_empty():
		return
	var gs: Node = Service.game_state()
	if gs != null and gs.has_method("add_carried_equipment"):
		gs.add_carried_equipment(equipment_id, 1)

func _can_add_carried_stack(amount: int, space_per_item: int) -> bool:
	var gs: Node = Service.game_state()
	if gs == null or not gs.has_method("can_add_carried_space"):
		return false
	return gs.can_add_carried_space(amount * space_per_item)

func _uses_warehouse(source: String, target: String) -> bool:
	return source == "warehouse" or target == "warehouse"

func _sync_warehouse_tab_visibility() -> void:
	if right_tabs == null or right_tabs.get_tab_count() <= 2:
		return
	var available := _is_warehouse_available()
	right_tabs.set_tab_hidden(2, not available)
	right_tabs.set_tab_disabled(2, not available)
	if not available and right_tabs.current_tab == 2:
		right_tabs.current_tab = 0

func _is_warehouse_available() -> bool:
	var node: Node = self
	while node != null:
		if "current_space" in node:
			return String(node.get("current_space")) == "tavern"
		node = node.get_parent()
	var gs := Service.game_state()
	if gs != null and "current_level" in gs:
		var level = gs.current_level
		if level != null and is_instance_valid(level):
			if String(level.name).to_lower().contains("tavern"):
				return true
	var tm := Service.tavern_manager()
	if tm != null and "current_phase" in tm:
		return int(tm.current_phase) == 1
	return false

func _get_material_name(item_id: String) -> String:
	# 与图鉴/拾取物同一解析链（BrewingData → MaterialModelRegistry → 本地化）
	return BD.get_material_name(item_id)

func _icon_for_equipment_id(equipment_id: String) -> Texture2D:
	return DETAIL_POPUP_SCRIPT.icon_for_equipment_id(equipment_id)

func _icon_for_weapon_data(data: WeaponData) -> Texture2D:
	if data == null:
		return null
	return DETAIL_POPUP_SCRIPT.icon_for_equipment_id(data.id)

func _slot_icon_for_equipment_id(equipment_id: String) -> Texture2D:
	return _scaled_slot_icon(_icon_for_equipment_id(equipment_id))

func _slot_icon_for_weapon_data(data: WeaponData) -> Texture2D:
	return _scaled_slot_icon(_icon_for_weapon_data(data))

func _scaled_slot_icon(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cache_key := texture.get_rid().get_id()
	if _slot_icon_cache.has(cache_key):
		return _slot_icon_cache[cache_key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate()
	image.resize(SLOT_ICON_SIZE, SLOT_ICON_SIZE, Image.INTERPOLATE_NEAREST)
	var scaled := ImageTexture.create_from_image(image)
	_slot_icon_cache[cache_key] = scaled
	return scaled

func _scaled_rune_slot_icon(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cache_key := "rune_%s" % texture.get_rid().get_id()
	if _slot_icon_cache.has(cache_key):
		return _slot_icon_cache[cache_key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image.resize(RUNE_SLOT_ICON_SIZE, RUNE_SLOT_ICON_SIZE, Image.INTERPOLATE_NEAREST)
	var scaled := ImageTexture.create_from_image(image)
	_slot_icon_cache[cache_key] = scaled
	return scaled

func _collect_rune_slot_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for node in find_children("RuneSlot*", "Button", true, false):
		if "skill_slot_index" in node and "rune_socket_index" in node:
			buttons.append(node as Button)
	buttons.sort_custom(func(a: Button, b: Button) -> bool:
		var a_slot: int = int(a.get("skill_slot_index"))
		var b_slot: int = int(b.get("skill_slot_index"))
		if a_slot == b_slot:
			return int(a.get("rune_socket_index")) < int(b.get("rune_socket_index"))
		return a_slot < b_slot
	)
	return buttons

func _rune_slot_capacity(slot_index: int) -> int:
	var sr: Node = _get_skill_runtime()
	if sr != null and sr.has_method("get_rune_capacity"):
		return int(sr.get_rune_capacity(slot_index))
	return 2 if slot_index >= 2 else SKILL_RUNTIME_SCRIPT.MAX_RUNES_PER_SLOT

func _get_player_equipment() -> Node:
	var player := _get_current_player()
	if player != null and "equipment" in player and player.equipment != null:
		return player.equipment
	return null

func _get_current_player() -> Node:
	return PLAYER_FINDER.get_current_player() if PLAYER_FINDER != null else null

func _slot_label(slot_index: int) -> String:
	match slot_index:
		0:
			return tr("F 主动槽")
		1:
			return tr("G 主动槽")
		_:
			return tr("被动槽 %d") % (slot_index - 1)

func _format_slot_runes(runes: Array) -> String:
	if runes.is_empty():
		return ""
	var names: Array[String] = []
	for raw_id in runes:
		names.append(RD.get_rune_name(String(raw_id)))
	return tr("\n符文: %s") % " / ".join(names)

func _get_skill_runtime() -> Node:
	return Service.skill_runtime()

func _get_attr_panel() -> Node:
	return Service.attr_panel()
