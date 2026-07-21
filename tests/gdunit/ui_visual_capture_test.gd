extends GdUnitTestSuite

const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const TAVERN_UI_SCENE := preload("res://scenes/ui/tavern_ui.tscn")
const EQUIPMENT_SCENE := preload("res://scenes/ui/tavern_equipment_panel.tscn")
const COMBAT_HUD_SCENE := preload("res://scenes/ui/combat_hud.tscn")
const EXPEDITION_HUD_SCENE := preload("res://scenes/ui/expedition_hud.tscn")
const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")
const CAPTURE_DIR := "res://reports/ui_audit"
const CAPTURE_PREFIX := "after"

var _original_window_size := Vector2i.ZERO


func before() -> void:
	_original_window_size = DisplayServer.window_get_size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))


func after() -> void:
	DisplayServer.window_set_size(_original_window_size)


func test_capture_current_project_ui() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await _wait_frames(8)

	await _capture_main_menu()
	await _capture_tavern_management()
	await _capture_equipment(false)
	await _capture_equipment(true)
	await _capture_combat_hud()


func _capture_main_menu() -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as Control
	add_child(menu)
	await _wait_frames(220)
	for tween in get_tree().get_processed_tweens():
		tween.kill()
	_force_controls_visible(menu)
	(menu.get_node("SidePanel") as Control).modulate.a = 1.0
	(menu.get_node("SidePanel/MenuVBox") as Control).visible = true
	_seed_main_menu(menu)
	await _wait_frames(2)
	_save_viewport("main_menu")
	await _remove_capture_node(menu)


func _capture_tavern_management() -> void:
	var stage := _create_stage(Color(0.025, 0.026, 0.030, 1.0))
	var tavern_ui := TAVERN_UI_SCENE.instantiate() as Control
	stage.add_child(tavern_ui)
	tavern_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _wait_frames(12)
	tavern_ui.get_node("Title").text = "孤灯酒馆 · 夜间经营"
	tavern_ui.get_node("ControlPanel/StatusLabel").text = "顾客 3/4  ·  金币 286  ·  今日声望 +12"
	_seed_tavern_management(tavern_ui)
	await _wait_frames(4)
	_save_viewport("tavern_management")
	await _remove_capture_node(stage)


func _capture_equipment(show_skills: bool) -> void:
	var stage := _create_stage(Color(0.028, 0.029, 0.032, 1.0))
	var panel := EQUIPMENT_SCENE.instantiate() as Control
	stage.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.visible = true
	await _wait_frames(16)

	var tabs := panel.get_node("%RightTabs") as TabContainer
	if show_skills:
		tabs.current_tab = 1
		_seed_skill_panel(panel)
	else:
		tabs.current_tab = 0
		_seed_equipment_panel(panel)
	await _wait_frames(6)
	_save_viewport("skills" if show_skills else "equipment")
	await _remove_capture_node(stage)


func _capture_combat_hud() -> void:
	var stage := _create_stage(Color(0.035, 0.037, 0.043, 1.0))
	var backdrop := MAIN_MENU_SCENE.instantiate() as Control
	stage.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for hidden_path in ["SidePanel", "Subtitle", "VersionLabel", "Title"]:
		(backdrop.get_node(hidden_path) as Control).visible = false

	var combat_hud := COMBAT_HUD_SCENE.instantiate() as CanvasLayer
	var expedition_hud := EXPEDITION_HUD_SCENE.instantiate() as Control
	var mock_player := Node3D.new()
	mock_player.name = "CapturePlayer"
	mock_player.position = Vector3.ZERO
	stage.add_child(mock_player)
	add_child(combat_hud)
	stage.add_child(expedition_hud)
	expedition_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _wait_frames(12)

	combat_hud.hp_bar.set_values(78, 100)
	combat_hud.mp_bar.set_values(42, 70)
	combat_hud.update_pressure({
		"clock_minutes": 17 * 60 + 24,
		"threat_level": 64.0,
		"pressure_band": "leave_soon",
	})
	combat_hud.combat_log.push_entry("哥布林斥候受到 18 点斩击伤害", Color(0.96, 0.78, 0.46))
	combat_hud.combat_log.push_entry("你获得了：发光菌帽 ×2", Color(0.58, 0.82, 0.68))
	combat_hud.combat_log.push_entry("暗蚀正在加深……", Color(0.72, 0.74, 0.78))
	combat_hud.minimap.set_grid_data([
		[2, 2, 2, 2, 2, 2, 2],
		[2, 1, 1, 1, 0, 0, 2],
		[2, 1, 1, 1, 1, 1, 2],
		[2, 0, 1, 1, 1, 1, 2],
		[2, 0, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 2],
		[2, 2, 2, 2, 2, 2, 2],
	], Vector3(-10.5, 0.0, -10.5), 3.0)
	combat_hud.minimap.set_player(mock_player)
	for x in range(7):
		for y in range(7):
			combat_hud.minimap.mark_cell_explored(x, y)

	expedition_hud.update_player_hp(78, 100)
	expedition_hud.collected_materials = {"glowcap": 2, "ore": 3}
	expedition_hud.call("_update_hud")
	await _wait_frames(8)
	_save_viewport("combat_hud")

	remove_child(combat_hud)
	combat_hud.queue_free()
	await _remove_capture_node(stage)


func _seed_equipment_panel(panel: Control) -> void:
	var gear_list := panel.get_node("%GearList") as ItemList
	gear_list.clear()
	var fixtures := [
		["精制短剑\n优良", "res://assets/textures/icons/equipment/weapons_shortsword.png", 1],
		["旅者圆盾\n普通", "res://assets/textures/icons/equipment/weapons_shield.png", 1],
		["锁链甲\n磨损", "res://assets/textures/icons/equipment/armor_chain_armor.png", 1],
		["余烬法杖\n稀有", "res://assets/textures/icons/equipment/weapons_staff.png", 1],
		["发光菌帽", "res://assets/textures/icons/materials/glowshroom.png", 8],
		["黑麦根", "res://assets/textures/icons/materials/black_rye_root.png", 5],
		["紫晶碎片", "res://assets/textures/icons/materials/quartz_dust.png", 3],
		["巨鼠尾", "res://assets/textures/icons/materials/giant_rat_tail.png", 2],
		["灵魂宝石", "res://assets/textures/icons/materials/soul_gem.png", 2],
		["地牢苔藓", "res://assets/textures/icons/materials/dungeon_moss.png", 6],
	]
	for fixture in fixtures:
		var icon := load(String(fixture[1])) as Texture2D
		if String(fixture[0]) == "灵魂宝石":
			icon = DETAIL_POPUP_SCRIPT.icon_for_material("soul_gem")
		var index := gear_list.add_item("\n", icon)
		gear_list.set_item_metadata(index, {"amount": int(fixture[2]), "type": "fixture", "id": String(fixture[0]), "_inventory_label": String(fixture[0])})
		gear_list.set_item_tooltip(index, String(fixture[0]))
	gear_list.select(0)
	panel.call("_on_gear_item_selected", 0)
	panel.get_node("%CharacterStatsText").text = "等级 8\n生命 78 / 100\n攻击 24–31\n护甲 16\n闪避 8%\n暴击 12%"
	panel.get_node("%ProficiencyText").text = "剑 42\n匕首 35\n斧 28\n锤 24\n枪 31\n弓 26\n弩 22\n法杖 29\n魔导书 18\n盾牌 31"


func _seed_main_menu(menu: Control) -> void:
	var labels := {
		"SidePanel/MenuVBox/MenuHeader": "炉火在此静候",
		"SidePanel/MenuVBox/MenuHint": "经营你的酒馆，并深入黑暗地牢。",
		"SidePanel/MenuVBox/UtilityLabel": "偏好设置",
		"SidePanel/MenuVBox/StartBtn": "开始游戏",
		"SidePanel/MenuVBox/ContinueBtn": "继续冒险",
		"SidePanel/MenuVBox/GalleryBtn": "藏品图鉴",
		"SidePanel/MenuVBox/SettingsBtn": "游戏设置",
		"SidePanel/MenuVBox/MultiplayerBtn": "多人游戏",
		"SidePanel/MenuVBox/LangBtn": "语言：简体中文",
		"SidePanel/MenuVBox/ExitBtn": "离开游戏",
	}
	for path in labels:
		var control := menu.get_node(path) as Control
		control.set("text", labels[path])
		control.modulate = Color.WHITE
		control.self_modulate = Color.WHITE


func _seed_tavern_management(tavern_ui: Control) -> void:
	var orders := tavern_ui.get_node("OrderPanel/ScrollContainer/OrderList") as VBoxContainer
	var inventory := tavern_ui.get_node("InventoryPanel/ScrollContainer/InventoryList") as ItemList
	for child in orders.get_children():
		orders.remove_child(child)
		child.queue_free()
	inventory.clear()
	for order_text in [
		"01  矿工奥托    黑麦烈酒 ×1    报酬 38G",
		"02  猎人弥拉    发光菌汤 ×2    报酬 54G",
		"03  旅商伊森    紫晶药酒 ×1    报酬 71G",
	]:
		var order := Button.new()
		order.text = order_text
		order.alignment = HORIZONTAL_ALIGNMENT_LEFT
		order.custom_minimum_size.y = 72.0
		order.theme_type_variation = &"SlotButton"
		orders.add_child(order)
	for material_text in [
		"发光菌帽        8      [常见]",
		"黑麦根          5      [常见]",
		"紫晶碎片        3      [稀有]",
		"巨鼠尾          2      [材料]",
	]:
		inventory.add_item(material_text)
		if material_text.contains("紫晶"):
			inventory.set_item_custom_fg_color(inventory.item_count - 1, Color(0.78, 0.80, 0.84))


func _seed_skill_panel(panel: Control) -> void:
	var available := panel.get_node("%AvailableSkillsList") as ItemList
	available.clear()
	for skill_name in ["旋风斩", "盾牌猛击", "余烬附魔", "战斗专注", "猎人直觉"]:
		available.add_item(skill_name)
	available.select(0)
	panel.get_node("%SkillDetails").text = "旋风斩\n主动 · 武器技能\n\n横扫近身敌人，造成 135% 武器伤害。\n冷却：6.0 秒\n消耗：18 法力"
	for i in range(7):
		var slot := panel.get_node("%%SkillSlot%d" % i) as Button
		slot.text = ["F 旋风斩", "G 盾牌猛击", "坚韧", "反击", "洞察", "空", "空"][i]


func _create_stage(background_color: Color) -> Control:
	var stage := Control.new()
	stage.name = "CaptureStage"
	add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = background_color
	stage.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return stage


func _force_controls_visible(root: Node) -> void:
	for child in root.find_children("*", "Control", true, false):
		if child is Control:
			child.modulate.a = 1.0
			child.scale = Vector2.ONE


func _save_viewport(name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	assert_object(image).is_not_null()
	assert_int(image.save_png("%s/%s_%s.png" % [CAPTURE_DIR, CAPTURE_PREFIX, name])).is_equal(OK)
	assert_bool(image.get_width() >= 1600).is_true()
	assert_bool(image.get_height() >= 900).is_true()


func _remove_capture_node(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()
	await _wait_frames(3)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
