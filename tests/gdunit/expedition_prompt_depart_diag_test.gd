extends GdUnitTestSuite
## 诊断测试：验证按住 depart(T) 能否触发环形进度条填充。
## 排查"T 无法触发环形进度条进入地牢"的根因。

var _prompt: Control
var _tm_phase_before: int

func before_test() -> void:
	# 确保 TavernManager 处于白天探险阶段
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	if tm != null:
		_tm_phase_before = tm.current_phase
		tm.current_phase = tm.Phase.DAY_EXPEDITION
	# 释放可能残留的 depart 输入
	Input.action_release("depart")

func after_test() -> void:
	Input.action_release("depart")
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	if tm != null:
		tm.current_phase = _tm_phase_before
	if _prompt != null and is_instance_valid(_prompt):
		_prompt.queue_free()

func test_depart_action_exists_in_inputmap() -> void:
	assert_bool(InputMap.has_action("depart")).is_true()

func test_tavern_manager_day_phase_default_or_settable() -> void:
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	assert_object(tm).is_not_null()
	assert_int(tm.Phase.DAY_EXPEDITION).is_equal(0)

func test_prompt_is_in_tavern_day_phase_when_day() -> void:
	_prompt = load("res://scenes/ui/expedition_prompt.tscn").instantiate() as Control
	add_child(_prompt)
	assert_bool(_prompt._is_in_tavern_day_phase()).is_true()

func test_prompt_ring_fills_when_depart_held() -> void:
	_prompt = load("res://scenes/ui/expedition_prompt.tscn").instantiate() as Control
	add_child(_prompt)
	# 确保在白天阶段
	assert_bool(_prompt._is_in_tavern_day_phase()).is_true()
	# 模拟按住 depart
	Input.action_press("depart")
	# 推进若干帧（HOLD_DURATION=2.0s，每帧 ~0.016s）
	var ring_before: float = _prompt.ring.value
	for i in range(30):
		_prompt._process(0.016)
	var ring_after: float = _prompt.ring.value
	print("[DIAG] ring_before=%.4f ring_after=%.4f hold_time=%.4f" % [ring_before, ring_after, _prompt.hold_time])
	assert_float(ring_after).is_greater(ring_before)
	assert_bool(_prompt.visible).is_true()

func test_prompt_ring_resets_when_depart_released() -> void:
	_prompt = load("res://scenes/ui/expedition_prompt.tscn").instantiate() as Control
	add_child(_prompt)
	Input.action_press("depart")
	for i in range(30):
		_prompt._process(0.016)
	Input.action_release("depart")
	_prompt._process(0.016)
	print("[DIAG] after release: hold_time=%.4f ring=%.4f visible=%s" % [_prompt.hold_time, _prompt.ring.value, _prompt.visible])
	assert_float(_prompt.hold_time).is_equal(0.0)
	assert_bool(_prompt.visible).is_false()

func test_prompt_progress_complete_opens_zone_select() -> void:
	_prompt = load("res://scenes/ui/expedition_prompt.tscn").instantiate() as Control
	add_child(_prompt)
	Input.action_press("depart")
	# 持续按住超过 HOLD_DURATION
	var frames: int = int(2.0 / 0.016) + 10
	for i in range(frames):
		_prompt._process(0.016)
		if _prompt.is_complete:
			break
	print("[DIAG] is_complete=%s hold_time=%.4f" % [_prompt.is_complete, _prompt.hold_time])
	assert_bool(_prompt.is_complete).is_true()
