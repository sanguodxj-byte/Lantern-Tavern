extends SceneTree

## Deterministic equipment-screen capture.
## Uses an isolated SubViewport so UI evidence does not depend on the desktop
## window viewport, which is unavailable in headless runs.

const EQUIPMENT_SCENE := preload("res://scenes/ui/tavern_equipment_panel.tscn")
const PLAYER_MODEL_ROUTE := preload("res://scenes/characters/player/player_visual_model.tscn")
const SIZE := Vector2i(1920, 1080)

var capture_skills := false
var capture_proficiency := false
var output_path := "res://reports/ui_audit/after_equipment.png"

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--skills":
			capture_skills = true
			output_path = "res://reports/ui_audit/after_skills_v2.png"
		elif argument == "--proficiency":
			capture_proficiency = true
			output_path = "res://reports/ui_audit/after_proficiency.png"
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/ui_audit"))
	var viewport := SubViewport.new()
	viewport.name = "EquipmentCaptureViewport"
	viewport.size = SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	root.set_meta("equipment_capture_mode", true)

	var stage := ColorRect.new()
	stage.color = Color(0.018, 0.019, 0.021, 1.0)
	stage.size = Vector2(SIZE)
	viewport.add_child(stage)

	var panel := EQUIPMENT_SCENE.instantiate() as Control
	panel.visible = true
	viewport.add_child(panel)
	# Capture uses an explicit top-left anchored root. The production scene is
	# full-rect, but a direct Control child of a SubViewport can recalculate that
	# anchor differently after a TabContainer page changes its minimum size.
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2.ZERO
	panel.size = Vector2(SIZE)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	_apply_skill_workspace_layout(panel)
	# Capture mode intentionally skips the full runtime bootstrap, so explicitly
	# run the lightweight equipment-slot refresh to render empty-slot hints.
	panel.call("_refresh_equipment_slots")
	var tabs := panel.get_node("%RightTabs") as TabContainer
	if capture_skills:
		tabs.current_tab = 1
		_seed_skills(panel)
	else:
		tabs.current_tab = 0
		_seed_equipment(panel)
	var stats_panel := panel.find_child("StatsPanel", true, false) as TabContainer
	if capture_proficiency and stats_panel != null:
		stats_panel.current_tab = 1
	_seed_preview_model(panel)
	await process_frame
	await process_frame
	await process_frame
	if capture_skills:
		_seed_skills(panel)
	else:
		_seed_equipment(panel)
	if capture_proficiency and stats_panel != null:
		stats_panel.current_tab = 1
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("[EquipmentCapture] isolated viewport returned an empty image")
		quit(1)
		return
	var error := image.save_png(output_path)
	if error != OK:
		printerr("[EquipmentCapture] failed to save %s: %d" % [output_path, error])
		quit(1)
		return
	print("[EquipmentCapture] wrote %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
	viewport.queue_free()
	quit(0)

func _seed_equipment(panel: Control) -> void:
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
		var index := gear_list.add_item("\n", icon)
		var item_type := "material" if int(fixture[2]) > 1 else "weapon"
		if String(fixture[0]).contains("甲"):
			item_type = "armor"
		gear_list.set_item_metadata(index, {
			"amount": int(fixture[2]),
			"type": item_type,
			"id": String(fixture[0]),
			"quality_tier": _fixture_quality_tier(String(fixture[0]), item_type),
			"_inventory_label": String(fixture[0]),
		})
		gear_list.set_item_tooltip(index, String(fixture[0]))
	gear_list.select(0)
	panel.get_node("%CharacterStatsText").text = "等级 8\n力量 STR 5\n生命 78 / 100\n敏捷 DEX 5\n攻击 24–31\n体质 CON 5\n护甲 16\n智力 MAG 5\n闪避 8%\n灵巧 AGI 5\n暴击 12%\n感知 PER 5"
	panel.get_node("%ProficiencyText").text = "剑 42\n匕首 35\n斧 28\n锤 24\n枪 31\n弓 26\n弩 22\n法杖 29\n魔导书 18\n盾牌 31"
	panel.get_node("%ItemDetailTitle").text = "精制短剑"
	panel.get_node("%ItemDetailMeta").text = "武器 · 优良"
	panel.get_node("%ItemDetailBody").text = "攻击 24–31\n距离 1.2m\n耐久 720/800\n适用于主手与副手"
	panel.get_node("%ItemDetailCompare").text = "属性对比  攻击 +6  ·  距离 +0.2  ·  耐久 +120"
	panel.get_node("%FilterCount").text = "全部 · %d件" % fixtures.size()

func _fixture_quality_tier(label: String, item_type: String) -> String:
	if item_type == "material":
		return ""
	if label.contains("稀有"):
		return "rare"
	if label.contains("优良"):
		return "uncommon"
	return "common"

func _seed_preview_model(panel: Control) -> void:
	var viewport := panel.get_node("%EqSubViewport") as SubViewport
	var model := PLAYER_MODEL_ROUTE.instantiate() as Node3D
	if model == null:
		return
	viewport.add_child(model)
	model.position = Vector3(0, -0.85, 0)
	model.rotation = Vector3(0, deg_to_rad(215), 0)

func _seed_skills(panel: Control) -> void:
	var available := panel.find_child("AvailableSkillsList", true, false) as ItemList
	available.clear()
	var icons: Node = root.get_node_or_null("SkillIcons")
	var fixtures := [
		["旋风斩", "主动 · 武器技能", "res://assets/textures/icons/skills/skill_e6978b_e99cb7_e6969c.png"],
		["盾牌猛击", "主动 · 盾牌技能", ""],
		["余烬附魔", "主动 · 法术技能", ""],
		["战斗专注", "被动 · 属性技能", ""],
		["猎人直觉", "被动 · 属性技能", ""],
	]
	for fixture in fixtures:
		var icon: Texture2D = icons.get_icon(String(fixture[0])) if icons != null and icons.has_method("get_icon") else null
		var index := available.add_item(String(fixture[0]), icon)
		available.set_item_metadata(index, {"id": String(fixture[0]), "name": String(fixture[0]), "type": String(fixture[1])})
		available.set_item_tooltip(index, "拖拽到技能槽位进行装备")
	available.select(0)

	var rune_warehouse := panel.find_child("RuneWarehouseList", true, false) as ItemList
	rune_warehouse.clear()
	for rune_fixture in [["ember", "余烬符文"], ["quick", "迅捷符文"], ["force", "冲击符文"], ["surge", "奔涌符文"], ["echo", "回响符文"], ["guardian", "守护符文"]]:
		var rune_icon := load("res://assets/textures/icons/runes/%s.png" % rune_fixture[0]) as Texture2D
		var rune_index := rune_warehouse.add_item("\n", null)
		rune_warehouse.set_item_metadata(rune_index, {"type": "rune", "id": String(rune_fixture[0]), "amount": 2, "quality_tier": "common", "_inventory_label": String(rune_fixture[1]), "_inventory_icon": rune_icon})
		rune_warehouse.set_item_tooltip(rune_index, "%s ×2" % rune_fixture[1])

	(panel.find_child("SkillDetails", true, false) as Label).text = "旋风斩\n主动 · 武器技能\n\n横扫近身敌人，造成 135% 武器伤害。\n冷却：6.0 秒\n消耗：18 法力"
	for i in range(7):
		var slot := panel.find_child("SkillSlot%d" % i, true, false) as Button
		slot.text = ["F *\n旋风斩", "G\n盾牌猛击", "坚韧", "反击", "洞察", "空", "空"][i]
		var skill_slot_size := 150.0 if i < 2 else 92.0
		slot.custom_minimum_size = Vector2(skill_slot_size, skill_slot_size)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for slot_path in ["%RuneSlot0_0", "%RuneSlot0_1", "%RuneSlot0_2", "%RuneSlot1_0", "%RuneSlot1_1", "%RuneSlot1_2"]:
		var rune_slot := panel.find_child(slot_path.trim_prefix("%"), true, false) as Button
		rune_slot.text = "-"
	(panel.find_child("CharacterStatsText", true, false) as Label).text = "等级 8\n力量 STR 5\n生命 78 / 100\n敏捷 DEX 5\n攻击 24–31\n体质 CON 5\n护甲 16\n智力 MAG 5\n闪避 8%\n灵巧 AGI 5\n暴击 12%\n感知 PER 5"
	(panel.find_child("ProficiencyText", true, false) as Label).text = "剑 42\n匕首 35\n斧 28\n锤 24\n枪 31\n弓 26\n弩 22\n法杖 29\n魔导书 18\n盾牌 31"

func _apply_skill_workspace_layout(panel: Control) -> void:
	var skill_tab := panel.get_node_or_null("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能") as Control
	var skill_layout: HBoxContainer = null
	if skill_tab != null:
		skill_layout = skill_tab.get_node_or_null("SkillLayout") as HBoxContainer
	if skill_tab == null or skill_layout == null or skill_tab.get_node_or_null("SkillWorkspaceCapture") != null:
		return
	var warehouse_panel := skill_layout.get_node_or_null("SkillPyramidPanel/SkillPyramidBox/RuneWarehousePanel") as PanelContainer
	if warehouse_panel == null:
		return
	var workspace := VBoxContainer.new()
	workspace.name = "SkillWorkspaceCapture"
	workspace.add_theme_constant_override("separation", 12)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_tab.remove_child(skill_layout)
	skill_tab.add_child(workspace)
	workspace.add_child(skill_layout)
	skill_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_layout.size_flags_stretch_ratio = 0.9
	var warehouse_row := HBoxContainer.new()
	warehouse_row.name = "SkillWarehouseRowCapture"
	warehouse_row.custom_minimum_size = Vector2(0, 330)
	warehouse_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	warehouse_row.size_flags_stretch_ratio = 1.1
	workspace.add_child(warehouse_row)
	warehouse_panel.reparent(warehouse_row, false)
	warehouse_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warehouse_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
