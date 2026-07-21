extends GdUnitTestSuite
## 端到端集成测试：验证主菜单 → 酒馆 → 睡眠 → 白天 → T键出发的完整流程。
## 覆盖"跳过教程"、"继续游戏"两条路径，以及主菜单背景视口不干扰。

var _tm: Node
var _phase_before: int
var _tutorial_active_before: bool

func before_test() -> void:
	_tm = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	assert_object(_tm).is_not_null()
	_phase_before = _tm.current_phase
	_tutorial_active_before = _tm.tutorial_active
	Input.action_release("depart")

func after_test() -> void:
	Input.action_release("depart")
	if _tm != null:
		_tm.current_phase = _phase_before
		_tm.tutorial_active = _tutorial_active_before

# ============================================================
# 路径 1：主菜单"跳过教程" → 酒馆(夜晚) → 睡眠 → 酒馆(白天) → T键
# ============================================================

func test_skip_tutorial_night_tavern_has_no_prompt() -> void:
	# 模拟 start_new_game(false) 后的状态
	_tm.current_phase = _tm.Phase.NIGHT_TAVERN
	_tm.tutorial_active = false
	_tm.tutorial_completed = true
	# 加载酒馆
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	# 夜晚阶段不应挂载出发提示
	var prompt_layer := tavern.get_node_or_null("ExpeditionPromptLayer")
	assert_object(prompt_layer) \
		.override_failure_message("夜晚阶段酒馆不应挂载出发提示") \
		.is_null()
	tavern.queue_free()

func test_skip_tutorial_day_tavern_mounts_prompt_after_sleep() -> void:
	# 模拟 start_new_game(false) → 夜晚 → start_next_day() → 白天
	_tm.current_phase = _tm.Phase.DAY_EXPEDITION
	_tm.tutorial_active = false
	_tm.tutorial_completed = true
	# 加载酒馆（模拟睡眠后重新进入白天酒馆）
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	# 白天阶段应挂载出发提示
	var prompt_layer := tavern.get_node_or_null("ExpeditionPromptLayer")
	assert_object(prompt_layer) \
		.override_failure_message("白天阶段酒馆应挂载 ExpeditionPromptLayer") \
		.is_not_null()
	tavern.queue_free()

func test_skip_tutorial_full_flow_t_key_works() -> void:
	# === 步骤 1：夜晚酒馆（模拟"跳过教程"后进入） ===
	_tm.current_phase = _tm.Phase.NIGHT_TAVERN
	_tm.tutorial_active = false
	_tm.tutorial_completed = true
	var tavern_night := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern_night)
	await await_idle_frame()
	# 验证夜晚无出发提示
	assert_object(tavern_night.get_node_or_null("ExpeditionPromptLayer")).is_null()
	# 夜晚阶段无出发提示节点 → T 键自然不会有任何响应
	# 释放夜晚酒馆
	tavern_night.queue_free()
	await await_idle_frame()

	# === 步骤 2：模拟睡眠 → 白天酒馆 ===
	_tm.current_phase = _tm.Phase.DAY_EXPEDITION
	var tavern_day := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern_day)
	await await_idle_frame()
	# 验证白天挂载了出发提示
	var prompt_layer := tavern_day.get_node_or_null("ExpeditionPromptLayer")
	assert_object(prompt_layer) \
		.override_failure_message("睡眠后白天酒馆应挂载出发提示") \
		.is_not_null()

	# === 步骤 3：模拟按住 T 键 ===
	var prompt: Control = prompt_layer.get_child(0) as Control
	assert_bool(prompt._is_in_tavern_day_phase()) \
		.override_failure_message("_is_in_tavern_day_phase 应在白天阶段返回 true") \
		.is_true()
	# 按住 T 键 30 帧（约 0.48s），环形进度条应填充
	Input.action_press("depart")
	var ring_before: float = prompt.ring.value
	for i in range(30):
		prompt._process(0.016)
	var ring_after: float = prompt.ring.value
	print("[FLOW] skip_tutorial: ring_before=%.4f ring_after=%.4f" % [ring_before, ring_after])
	assert_float(ring_after).is_greater(ring_before)
	assert_bool(prompt.visible).is_true()

	# === 步骤 4：持续按住直到完成 ===
	var frames: int = int(2.0 / 0.016) + 10
	for i in range(frames):
		prompt._process(0.016)
		if prompt.is_complete:
			break
	print("[FLOW] skip_tutorial: is_complete=%s hold_time=%.4f" % [prompt.is_complete, prompt.hold_time])
	assert_bool(prompt.is_complete) \
		.override_failure_message("按住 T 键 2 秒后出发提示应完成") \
		.is_true()

	Input.action_release("depart")
	tavern_day.queue_free()

# ============================================================
# 路径 2：主菜单"继续游戏" → 酒馆(夜晚) → 睡眠 → 酒馆(白天) → T键
# ============================================================

func test_continue_game_full_flow_t_key_works() -> void:
	# === 步骤 1：夜晚酒馆（模拟"继续游戏"后进入） ===
	# continue_in_tavern() 设置 current_phase = NIGHT_TAVERN
	_tm.current_phase = _tm.Phase.NIGHT_TAVERN
	var tavern_night := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern_night)
	await await_idle_frame()
	assert_object(tavern_night.get_node_or_null("ExpeditionPromptLayer")).is_null()
	tavern_night.queue_free()
	await await_idle_frame()

	# === 步骤 2：模拟睡眠 → 白天酒馆 ===
	_tm.current_phase = _tm.Phase.DAY_EXPEDITION
	var tavern_day := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern_day)
	await await_idle_frame()
	var prompt_layer := tavern_day.get_node_or_null("ExpeditionPromptLayer")
	assert_object(prompt_layer) \
		.override_failure_message("继续游戏→睡眠后白天酒馆应挂载出发提示") \
		.is_not_null()

	# === 步骤 3：模拟按住 T 键 ===
	var prompt: Control = prompt_layer.get_child(0) as Control
	Input.action_press("depart")
	for i in range(30):
		prompt._process(0.016)
	assert_bool(prompt.visible).is_true()
	assert_float(prompt.ring.value).is_greater(0.0)

	# === 步骤 4：持续按住直到完成 ===
	var frames: int = int(2.0 / 0.016) + 10
	for i in range(frames):
		prompt._process(0.016)
		if prompt.is_complete:
			break
	print("[FLOW] continue_game: is_complete=%s hold_time=%.4f" % [prompt.is_complete, prompt.hold_time])
	assert_bool(prompt.is_complete).is_true()

	Input.action_release("depart")
	tavern_day.queue_free()

# ============================================================
# 验证：主菜单背景视口不挂载出发提示
# ============================================================

func test_main_menu_background_tavern_has_no_prompt() -> void:
	# 即使 current_phase 是 DAY_EXPEDITION（默认值），主菜单背景视口也不应挂载出发提示
	_tm.current_phase = _tm.Phase.DAY_EXPEDITION
	# 加载主菜单
	var menu := load("res://scenes/ui/main_menu.tscn").instantiate() as Control
	assert_object(menu).is_not_null()
	add_child(menu)
	await await_idle_frame()
	await await_idle_frame()  # 额外等待一帧让背景酒馆 _ready 完成
	# 查找 SubViewport 中的背景酒馆
	var viewport := menu.get_node_or_null("TavernBackground/SubViewport")
	if viewport == null:
		# 如果主菜单没有背景视口结构，跳过
		menu.queue_free()
		return
	# SubViewport 的子节点应该是酒馆实例
	var bg_tavern: Node = null
	for child in viewport.get_children():
		if child is Node3D:
			bg_tavern = child
			break
	if bg_tavern == null:
		menu.queue_free()
		return
	# 验证背景酒馆没有挂载出发提示
	var prompt_layer := bg_tavern.get_node_or_null("ExpeditionPromptLayer")
	assert_object(prompt_layer) \
		.override_failure_message("主菜单背景视口中的酒馆不应挂载出发提示，否则会抢占 T 键输入") \
		.is_null()
	# 验证背景酒馆也没有挂载装备面板
	var eq_layer := bg_tavern.get_node_or_null("TavernEquipmentLayer")
	assert_object(eq_layer) \
		.override_failure_message("主菜单背景视口中的酒馆不应挂载装备面板") \
		.is_null()
	menu.queue_free()

# ============================================================
# 验证：depart 输入动作已注册且映射到 T 键
# ============================================================

func test_depart_action_registered_and_mapped_to_t() -> void:
	assert_bool(InputMap.has_action("depart")).is_true()
	var events: Array = InputMap.action_get_events("depart")
	assert_bool(events.size() > 0).is_true()
	var has_t_key: bool = false
	for event in events:
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.physical_keycode == KEY_T:
				has_t_key = true
				break
	assert_bool(has_t_key) \
		.override_failure_message("depart 动作应映射到 T 键 (physical_keycode=84)") \
		.is_true()

# ============================================================
# 验证：world.gd 在 DAY_EXPEDITION 阶段加载酒馆而非地牢
# ============================================================

func test_world_loads_tavern_in_day_expedition() -> void:
	var world_script := load("res://scenes/world/world.gd") as GDScript
	var source := world_script.source_code
	assert_bool(source.contains("DAY_EXPEDITION")) \
		.override_failure_message("world.gd _load_initial_space 应处理 DAY_EXPEDITION 阶段") \
		.is_true()
	assert_bool(source.contains("transition_to_tavern()")) \
		.override_failure_message("world.gd 应在 DAY_EXPEDITION 时加载酒馆") \
		.is_true()

# ============================================================
# 验证：tavern_manager_node 在 SubViewport 中不挂载 UI
# ============================================================

func test_tavern_node_skips_ui_in_subviewport() -> void:
	var script := load("res://scenes/tavern/tavern_manager_node.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("SubViewport")) \
		.override_failure_message("tavern_manager_node 应检查 SubViewport 以避免主菜单背景挂载 UI") \
		.is_true()
