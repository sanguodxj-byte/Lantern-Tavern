extends GdUnitTestSuite


func test_expedition_hud_displays_pressure_and_time() -> void:
	var hud: ExpeditionHUD = load("res://scenes/ui/expedition_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()

	hud.update_pressure({
		"clock_minutes": 17 * 60,
		"threat_level": 58.0,
		"pressure_band": "leave_soon",
		"should_extract": true,
		"overtime": false,
	})

	assert_str(hud.time_label.text).is_equal("17:00 / 18:00")
	assert_str(hud.pressure_label.text).contains("差不多该撤了")
	assert_str(hud.pressure_label.text).contains("暗蚀")
	assert_bool(hud.alert_label.visible).is_true()

	hud.queue_free()


func test_expedition_hud_displays_overtime_income_loss() -> void:
	var hud: ExpeditionHUD = load("res://scenes/ui/expedition_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()

	hud.update_pressure({
		"clock_minutes": 18 * 60,
		"threat_level": 90.0,
		"pressure_band": "critical",
		"should_extract": true,
		"overtime": true,
	})

	assert_str(hud.time_label.text).is_equal("18:00 / 18:00")
	assert_str(hud.alert_label.text).contains("收入归零")
	assert_bool(hud.alert_label.visible).is_true()

	hud.queue_free()


func test_expedition_hud_gold_and_material_panels_hidden() -> void:
	# 回归测试：右侧金币/材料浮窗已移除。
	# tscn 中 visible=false + _ready() 显式设置，运行时必须保持隐藏。
	var hud: ExpeditionHUD = load("res://scenes/ui/expedition_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()

	var top_hud: Control = hud.get_node("TopHUD") as Control
	var middle_hud: Control = hud.get_node("MiddleHUD") as Control
	assert_bool(top_hud.visible).override_failure_message(
		"TopHUD(包含 Gold/Time)必须隐藏，避免与战斗 HUD 视觉冲突"
	).is_false()
	assert_bool(middle_hud.visible).override_failure_message(
		"MiddleHUD(包含 Materials/Pressure)必须隐藏，避免与战斗 HUD 视觉冲突"
	).is_false()
	# 内部子节点也应该不再可见
	var gold_label: Label = hud.get_node("TopHUD/GoldLabel") as Label
	var material_label: Label = hud.get_node("MiddleHUD/MaterialLabel") as Label
	# 子节点跟随父节点的 visible 状态；只要父节点隐藏，子节点也"不显示"
	assert_bool(gold_label.get_parent().visible).is_false()
	assert_bool(material_label.get_parent().visible).is_false()

	hud.queue_free()


func test_extraction_guidance_panel_has_stable_pixel_hud_layout() -> void:
	var hud: ExpeditionHUD = load("res://scenes/ui/expedition_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()

	var panel := hud.get_node("ExtractionPanel") as Panel
	var bar := hud.get_node("ExtractionPanel/ExtractionBar") as ProgressBar
	var skill_bar := hud.get_node("SkillBarInstance") as Control
	assert_object(panel).is_not_null()
	assert_object(bar).is_not_null()
	assert_float(panel.size.x).is_equal(360.0)
	assert_float(bar.max_value).is_equal(1.0)
	assert_int(hud.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_bool(panel.position.y + panel.size.y <= skill_bar.position.y - 12.0) \
		.override_failure_message("撤离引导面板必须稳定显示在技能栏上方且不重叠").is_true()

	hud.begin_extraction(1.5)
	hud.update_extraction_progress(0.5, 0.75)
	assert_bool(panel.visible).is_true()
	assert_float(bar.value).is_equal_approx(0.5, 0.001)
	hud.queue_free()

func test_expedition_hud_displays_floor_indicator_and_arrival_banner() -> void:
	var hud: ExpeditionHUD = load("res://scenes/ui/expedition_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()

	hud.set_floor_label("L2")
	hud.show_floor_arrival("深邃洞窟", "L2")

	assert_str(hud.floor_indicator.text).is_equal("L2")
	assert_str(hud.floor_arrival_label.text).is_equal("深邃洞窟 · L2")
	assert_bool(hud.floor_arrival_label.visible).is_true()
	assert_float(hud.floor_arrival_label.modulate.a).is_equal_approx(0.0, 0.001)
	var source := (load("res://scenes/ui/expedition_hud.gd") as GDScript).source_code
	assert_bool(source.contains("const FLOOR_HOLD_DURATION := 1.0")).is_true()
	assert_bool(source.contains("tween_interval(FLOOR_HOLD_DURATION)")).is_true()
	hud.queue_free()

func test_expedition_hud_scene_keeps_floor_controls_separate_from_hidden_resource_panels() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/ui/expedition_hud.tscn")
	assert_str(scene_source).contains("FloorIndicator")
	assert_str(scene_source).contains("FloorArrivalLabel")
	assert_str(scene_source).contains("theme_override_font_sizes/font_size = 46")
