extends GdUnitTestSuite
## 集成测试：验证酒馆场景在白天阶段正确挂载出发提示。
## 排查"T 键无法触发环形进度条"的根因。

var _tavern: Node3D
var _tm: Node
var _phase_before: int

func before_test() -> void:
	_tm = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	assert_object(_tm).is_not_null()
	_phase_before = _tm.current_phase

func after_test() -> void:
	if _tavern != null and is_instance_valid(_tavern):
		_tavern.queue_free()
	if _tm != null:
		_tm.current_phase = _phase_before

func test_tavern_mounts_expedition_prompt_in_day_phase() -> void:
	# 设置白天探险阶段
	_tm.current_phase = _tm.Phase.DAY_EXPEDITION
	# 加载酒馆场景
	_tavern = load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	assert_object(_tavern).is_not_null()
	add_child(_tavern)
	# 等待一帧让 _ready() 完成
	await await_idle_frame()
	# 检查 ExpeditionPromptLayer 是否存在
	var prompt_layer := _tavern.get_node_or_null("ExpeditionPromptLayer")
	assert_object(prompt_layer) \
		.override_failure_message("白天阶段酒馆应挂载 ExpeditionPromptLayer") \
		.is_not_null()
	# 检查提示节点是否存在
	if prompt_layer != null:
		var prompt := prompt_layer.get_child(0)
		assert_object(prompt).is_not_null()
		assert_bool(prompt is Control).is_true()
		# 检查 _is_in_tavern_day_phase 是否返回 true
		assert_bool(prompt._is_in_tavern_day_phase()) \
			.override_failure_message("_is_in_tavern_day_phase() 应在白天阶段返回 true") \
			.is_true()

func test_tavern_does_not_mount_prompt_in_night_phase() -> void:
	_tm.current_phase = _tm.Phase.NIGHT_TAVERN
	_tavern = load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(_tavern)
	await await_idle_frame()
	var prompt_layer := _tavern.get_node_or_null("ExpeditionPromptLayer")
	assert_object(prompt_layer).is_null()

func test_tavern_ready_completes_without_error() -> void:
	_tm.current_phase = _tm.Phase.DAY_EXPEDITION
	_tavern = load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(_tavern)
	await await_idle_frame()
	# 验证 _ready 完整执行（打印日志说明未崩溃）
	assert_bool(is_instance_valid(_tavern)).is_true()
	# 验证 Player 已生成
	var player := _tavern.get_node_or_null("Player")
	assert_object(player) \
		.override_failure_message("酒馆 _ready 应生成 Player 节点") \
		.is_not_null()

func test_world_load_initial_space_handles_day_expedition() -> void:
	# 验证 world.gd 的 _load_initial_space 在 DAY_EXPEDITION 阶段
	# 应进入酒馆（而非地牢），否则玩家无法触发出发提示
	var world_script := load("res://scenes/world/world.gd") as GDScript
	var source := world_script.source_code
	assert_bool(source.contains("DAY_EXPEDITION")) \
		.override_failure_message("world.gd _load_initial_space 应显式处理 DAY_EXPEDITION 阶段，否则玩家会被送入地牢而非酒馆") \
		.is_true()
	assert_bool(source.contains("tm.Phase.DAY_EXPEDITION")) \
		.override_failure_message("world.gd 应在 _load_initial_space 中检查 DAY_EXPEDITION 并加载酒馆") \
		.is_true()

func test_expedition_prompt_process_runs_in_scene_tree() -> void:
	_tm.current_phase = _tm.Phase.DAY_EXPEDITION
	_tavern = load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(_tavern)
	await await_idle_frame()
	var prompt_layer := _tavern.get_node_or_null("ExpeditionPromptLayer")
	if prompt_layer == null:
		assert_bool(false).override_failure_message("ExpeditionPromptLayer 未挂载").is_true()
		return
	var prompt: Control = prompt_layer.get_child(0) as Control
	# 检查 process_mode 是否允许 _process 运行
	assert_int(prompt.process_mode).is_not_equal(Node.PROCESS_MODE_DISABLED)
	# 手动调用 _process 验证不崩溃
	prompt._process(0.016)
	# 在未按 depart 时应不可见
	assert_bool(prompt.visible).is_false()
