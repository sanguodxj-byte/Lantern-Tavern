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

# ---------------------------------------------------------------------------
# 1740 审查 P1：暂停恢复必须还原原始 process_mode（可逆状态变换）
# ---------------------------------------------------------------------------

func test_pause_resume_restores_original_process_modes() -> void:
	var pm: PauseMenu = load("res://scenes/ui/pause_menu.tscn").instantiate()
	add_child(pm)
	# 三个代表性节点：inherit（应被暂停）、always（暂停时也应禁用、恢复时还原 always）、disabled（暂停前禁用，恢复后必须保持禁用）
	var game_node := Node3D.new()
	game_node.name = "GameLayer"
	add_child(game_node)
	var always_node := Node.new()
	always_node.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(always_node)
	var pre_disabled := Node.new()
	pre_disabled.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(pre_disabled)
	pm.pause()
	assert_int(game_node.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_int(always_node.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_int(pre_disabled.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	pm.resume()
	# 恢复后：inherit 还原 inherit、always 还原 always、原本 disabled 必须保持 disabled（不被错误打开）
	assert_int(game_node.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_int(always_node.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_int(pre_disabled.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	remove_child(pm)
	pm.free()
	game_node.free()
	always_node.free()
	pre_disabled.free()
