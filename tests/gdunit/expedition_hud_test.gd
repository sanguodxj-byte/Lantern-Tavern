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
