extends GdUnitTestSuite

# MainCamera 相机抖动逻辑测试

func test_main_camera_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/player/main_camera.gd")).is_true()


func test_impact_duration_mapping() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	assert_int(cam.duration_map[GameEvents.ImpactIntensity.LOW]).is_equal(70)
	assert_int(cam.duration_map[GameEvents.ImpactIntensity.MEDIUM]).is_equal(110)
	assert_int(cam.duration_map[GameEvents.ImpactIntensity.HIGH]).is_equal(160)


func test_impact_intensity_mapping() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	assert_float(cam.intensity_map[GameEvents.ImpactIntensity.LOW]).is_equal(0.015)
	assert_float(cam.intensity_map[GameEvents.ImpactIntensity.MEDIUM]).is_equal(0.035)
	assert_float(cam.intensity_map[GameEvents.ImpactIntensity.HIGH]).is_equal(0.06)


func test_initial_not_shaking() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	assert_bool(cam.is_shaking).is_false()


func test_low_impact_has_lowest_values() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	assert_bool(cam.duration_map[GameEvents.ImpactIntensity.LOW] < cam.duration_map[GameEvents.ImpactIntensity.HIGH]).is_true()
	assert_bool(cam.intensity_map[GameEvents.ImpactIntensity.LOW] < cam.intensity_map[GameEvents.ImpactIntensity.HIGH]).is_true()


# ── B2 命中冲击（Hit Impact）──

func test_hit_impact_listens_to_player_hit_enemy_signal() -> void:
	var script := load("res://scenes/characters/player/main_camera.gd") as GDScript
	assert_str(script.source_code).contains("player_hit_enemy.connect")
	assert_str(script.source_code).contains("func _on_player_hit_enemy(")


func test_hit_impact_amplitude_within_0_5_to_1_5_degrees() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	# docs/task.md: 默认关闭或限制在约 0.5°..1.5°
	assert_float(cam.IMPACT_PITCH_DEG).is_greater_equal(0.5)
	assert_float(cam.IMPACT_PITCH_DEG).is_less_equal(1.5)
	assert_float(cam.IMPACT_CRIT_PITCH_DEG).is_greater_equal(0.5)
	assert_float(cam.IMPACT_CRIT_PITCH_DEG).is_less_equal(1.5)
	assert_float(cam.IMPACT_CRIT_PITCH_DEG).is_greater(cam.IMPACT_PITCH_DEG)


func test_hit_impact_applies_transient_pitch_and_returns_to_baseline() -> void:
	Settings.camera_impact_enabled = true
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	add_child(cam)
	var base_rotation: float = float(cam.rotation_degrees.x)
	cam._on_player_hit_enemy({"is_crit": false})
	assert_float(cam._impact_pitch_deg).is_greater(0.0)
	# 逐帧推进，冲击应施加后又衰减回基线
	var advanced := 0.0
	while advanced < cam.IMPACT_RECOVER_SEC * 2.0:
		cam._update_hit_impact(1.0 / 60.0)
		advanced += 1.0 / 60.0
	assert_float(cam._impact_pitch_deg).is_equal_approx(0.0, 0.001)
	assert_float(cam.rotation_degrees.x).is_equal_approx(base_rotation, 0.001)


func test_hit_impact_disabled_setting_skips_pitch() -> void:
	Settings.camera_impact_enabled = false
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	cam._on_player_hit_enemy({"is_crit": false})
	# 关闭镜头冲击时不得施加任何俯仰偏移
	assert_float(cam._impact_pitch_deg).is_equal_approx(0.0, 0.001)
	Settings.camera_impact_enabled = true


func test_crit_hit_uses_stronger_impact() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	cam._on_player_hit_enemy({"is_crit": true})
	assert_float(cam._impact_pitch_deg).is_equal_approx(cam.IMPACT_CRIT_PITCH_DEG, 0.001)
