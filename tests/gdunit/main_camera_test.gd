extends GdUnitTestSuite

# MainCamera 相机抖动逻辑测试

func test_main_camera_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/player/main_camera.gd")).is_true()


func test_impact_duration_mapping() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	assert_int(cam.duration_map[GameEvents.ImpactIntensity.LOW]).is_equal(140)
	assert_int(cam.duration_map[GameEvents.ImpactIntensity.MEDIUM]).is_equal(200)
	assert_int(cam.duration_map[GameEvents.ImpactIntensity.HIGH]).is_equal(260)


func test_impact_intensity_mapping() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	assert_float(cam.intensity_map[GameEvents.ImpactIntensity.LOW]).is_equal(0.05)
	assert_float(cam.intensity_map[GameEvents.ImpactIntensity.MEDIUM]).is_equal(0.1)
	assert_float(cam.intensity_map[GameEvents.ImpactIntensity.HIGH]).is_equal(0.15)


func test_initial_not_shaking() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	assert_bool(cam.is_shaking).is_false()


func test_low_impact_has_lowest_values() -> void:
	var cam = auto_free(load("res://scenes/characters/player/main_camera.gd").new())
	assert_bool(cam.duration_map[GameEvents.ImpactIntensity.LOW] < cam.duration_map[GameEvents.ImpactIntensity.HIGH]).is_true()
	assert_bool(cam.intensity_map[GameEvents.ImpactIntensity.LOW] < cam.intensity_map[GameEvents.ImpactIntensity.HIGH]).is_true()
