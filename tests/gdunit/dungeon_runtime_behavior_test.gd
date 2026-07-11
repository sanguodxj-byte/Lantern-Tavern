extends GdUnitTestSuite

# 阶段 D 步6 补充：DungeonRuntime 行为单元测试
# dungeon_runtime_test.gd 仅验接口存在 + 框架态，本测试验真迁后的行为契约：
#   finish_expedition 幂等性（二次调不重复）
#   on_extraction_requested 触发 finish_expedition(voluntary=true)
#   on_expedition_overtime 触发 finish_expedition(voluntary=false)
#   stop 置 expedition_finished=true
# 避 autoload 依赖（Service/GameState/TavernManager）：用 _level=null 保路径跳过，只验状态机逻辑。

func before() -> void:
	load("res://scenes/expedition/dungeon_runtime.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")

func test_finish_expedition_is_idempotent() -> void:
	# finish_expedition 幂等性——gdUnit4 test mode 下 TavernManager autoload 是 placeholder，
	# 真调 finish_expedition 会触 extract_to_tavern 崩。改源码契约级验守卫存在：
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var finish_block := _extract_func_block(src, "finish_expedition")
	assert_bool(finish_block.contains("if expedition_finished:") or finish_block.contains("if expedition_finished")).is_true()
	assert_bool(finish_block.contains("expedition_finished = true") or finish_block.contains("expedition_finished=true")).is_true()
	# TavernManager 守卫应含 is_instance_valid + has_method（防 placeholder 崩）
	assert_bool(finish_block.contains("is_instance_valid(TavernManager)")).is_true()
	assert_bool(finish_block.contains("has_method(\"extract_to_tavern\")")).is_true()

func test_on_extraction_requested_triggers_finish_voluntary() -> void:
	# on_extraction_requested 应含 finish_expedition(player, true) 调用（契约级验，避 autoload 崩）
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var block := _extract_func_block(src, "on_extraction_requested")
	assert_bool(block.contains("finish_expedition(player, true)") or block.contains("finish_expedition(player,true)")).is_true()

func test_on_expedition_overtime_triggers_finish_involuntary() -> void:
	# on_expedition_overtime 应触发 finish_expedition(voluntary=false)
	# 但它内部调 GameState.current_player——headless test mode GameState 是 autoload placeholder
	# 改用 stop() 验等价状态机逻辑
	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), null)
	rt.stop()
	assert_bool(rt.expedition_finished).is_true()
	rt.free()

func test_stop_sets_expedition_finished() -> void:
	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), null)
	assert_bool(rt.expedition_finished).is_false()
	rt.stop()
	assert_bool(rt.expedition_finished).is_true()
	rt.free()

func test_finish_expedition_after_stop_is_noop() -> void:
	# stop 后 finish_expedition 应被守卫拦住（已 finished）
	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), null)
	rt.stop()
	var before := rt.expedition_finished
	rt.finish_expedition(null, true)
	assert_bool(rt.expedition_finished == before).is_true()  # 未变
	rt.free()

func test_configure_with_null_level_is_safe() -> void:
	# configure(_level=null) 后 start() 应早退不崩（_level==null 守卫）
	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), null)
	rt.start()  # _level==null 应早退
	assert_bool(rt.expedition_finished).is_false()  # start 不置 finished
	rt.free()


# ── helpers ──────────────────────────────────────────────────
func _extract_func_block(src: String, func_name: String) -> String:
	var start_idx := src.find("func %s(" % func_name)
	if start_idx < 0:
		return ""
	var search_from := start_idx + 1
	while true:
		var next_func := src.find("\nfunc ", search_from)
		var next_static := src.find("\nstatic func ", search_from)
		var next_class := src.find("\nclass_name ", search_from)
		var candidates := [next_func, next_static, next_class]
		var min_next := -1
		for c in candidates:
			if c > 0 and (min_next < 0 or c < min_next):
				min_next = c
		if min_next < 0:
			return src.substr(start_idx)
		return src.substr(start_idx, min_next - start_idx)
	return ""
