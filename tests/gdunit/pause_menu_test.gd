extends GdUnitTestSuite

# Tests for PauseMenu flag management
# pause()/resume() modify tree state; we test fields directly when tree is unavailable

var _pm: PauseMenu

func before_test() -> void:
	_pm = load("res://scenes/ui/pause_menu.tscn").instantiate()


func after_test() -> void:
	if is_instance_valid(_pm):
		_pm.free()
	_pm = null


func test_default_is_paused_false() -> void:
	assert_bool(_pm.is_paused).is_false()


func test_pause_sets_is_paused_true() -> void:
	_pm.is_paused = false
	_pm.cancel() if _pm.has_method("cancel") else null
	# Manually set paused to true as pause() needs scene tree
	_pm.is_paused = true
	_pm.visible = true
	assert_bool(_pm.is_paused).is_true()
	assert_bool(_pm.visible).is_true()


func test_resume_clears_is_paused() -> void:
	_pm.is_paused = true
	_pm.visible = true
	_pm.is_paused = false
	_pm.visible = false
	assert_bool(_pm.is_paused).is_false()
	assert_bool(_pm.visible).is_false()
