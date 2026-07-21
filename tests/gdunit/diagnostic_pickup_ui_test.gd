extends GdUnitTestSuite
## 诊断测试：验证交互提示已统一为「物体右侧悬浮窗」，
## 在酒馆与地牢场景通用，且不再有底部 ActionPanel 提示。

# ======================================================================
# 1. 底部提示已删除（possible_action_changed / ActionPanel 不再存在）
# ======================================================================

func test_game_events_no_possible_action_signal() -> void:
	var src: String = _gd_source("res://globals/core/game_events.gd")
	assert_bool(not src.contains("signal possible_action_changed")) \
		.override_failure_message("game_events.gd 不应再定义 possible_action_changed 信号（底部提示已删除）").is_true()

func test_player_no_possible_action_emit() -> void:
	var src: String = _gd_source("res://scenes/characters/player/player.gd")
	assert_bool(not src.contains("GameEvents.possible_action_changed")) \
		.override_failure_message("player.gd 不应再发射 possible_action_changed（已合并到物体右侧悬浮窗）").is_true()

func test_ui_no_possible_action_connect() -> void:
	var src: String = _gd_source("res://scenes/ui/ui.gd")
	assert_bool(not src.contains("possible_action_changed")) \
		.override_failure_message("ui.gd 不应再连接/处理 possible_action_changed").is_true()

func test_tscn_has_no_action_panel() -> void:
	var tscn: String = _tscn_source("res://scenes/ui/ui.tscn")
	assert_bool(not tscn.contains('name="ActionPanel"')) \
		.override_failure_message("ui.tscn 不应再包含 ActionPanel 节点").is_true()
	assert_bool(not tscn.contains('name="ActionLabel"')) \
		.override_failure_message("ui.tscn 不应再包含 ActionLabel 节点").is_true()

# ======================================================================
# 2. 交互提示改为物体右侧悬浮窗（interaction_hint_changed）
# ======================================================================

func test_player_emits_interaction_hint_with_full_text() -> void:
	var src: String = _gd_source("res://scenes/characters/player/player.gd")
	assert_bool(src.contains("GameEvents.interaction_hint_changed.emit(hint_type, new_action, hint_screen_pos)")) \
		.override_failure_message("player.gd 必须通过 interaction_hint_changed 发射完整交互文本").is_true()

func test_ui_connects_interaction_hint_signal() -> void:
	var src: String = _gd_source("res://scenes/ui/ui.gd")
	assert_bool(src.contains("GameEvents.interaction_hint_changed.connect(on_interaction_hint_changed)")) \
		.override_failure_message("ui.gd 必须连接 interaction_hint_changed 信号").is_true()

# ======================================================================
# 3. 通用性：酒馆 + 地牢 都能显示悬浮窗
# ======================================================================

func test_ui_interaction_hint_not_gated_to_dungeon() -> void:
	var src: String = _gd_source("res://scenes/ui/ui.gd")
	# on_interaction_hint_changed 体内不得再出现 world_space != "dungeon" 判定
	var pos := src.find("func on_interaction_hint_changed")
	assert_int(pos).is_greater(-1)
	var end := src.find("\nfunc ", pos + 1)
	if end == -1:
		end = src.length()
	var body := src.substr(pos, end - pos)
	assert_bool(not body.contains('world_space != "dungeon"')) \
		.override_failure_message("交互提示必须通用（酒馆+地牢），on_interaction_hint_changed 不得限定 dungeon").is_true()

func test_ui_visible_in_tavern_not_only_dungeon() -> void:
	var src: String = _gd_source("res://scenes/ui/ui.gd")
	# set_world_space 必须让 UI 在酒馆也可见（不再限定 == dungeon）
	var sws_start := src.find("func set_world_space")
	assert_int(sws_start).is_greater(-1)
	var sws_end := src.find("const CHARACTER_PANEL_PREFAB", sws_start)
	if sws_end == -1:
		sws_end = src.length()
	var body := src.substr(sws_start, sws_end - sws_start)
	assert_bool(not body.contains('visible = world_space == "dungeon"')) \
		.override_failure_message("set_world_space 不得仅在地牢显示 UI（酒馆也需交互提示）").is_true()
	# 仍应在开场 intro 时隐藏
	assert_bool(body.contains('visible = world_space != "intro"')) \
		.override_failure_message("set_world_space 应在 intro 隐藏、酒馆/地牢显示 UI").is_true()

# ======================================================================
# 4. 悬浮窗定位在物体右侧（HINT_OFFSET 水平为正）
# ======================================================================

func test_hint_offset_is_right_side() -> void:
	var src: String = _gd_source("res://scenes/ui/interaction_hint_base.gd")
	assert_bool(src.contains("const HINT_OFFSET")) \
		.override_failure_message("InteractionHintBase 必须定义 HINT_OFFSET").is_true()
	# 提取 HINT_OFFSET 的 x 分量并验证为正（物体右侧）
	var start := src.find("const HINT_OFFSET")
	assert_int(start).is_greater(-1)
	var line_end := src.find("\n", start)
	var line := src.substr(start, line_end - start)
	var vec_start := line.find("Vector2(")
	assert_int(vec_start).is_greater(-1)
	var x_part := line.substr(vec_start + "Vector2(".length())
	x_part = x_part.substr(0, x_part.find(",")).strip_edges()
	var x_val := float(x_part)
	assert_float(x_val) \
		.override_failure_message("HINT_OFFSET.x 必须为正，使提示显示在物体右侧 (got %s from '%s')" % [str(x_val), line]) \
		.is_greater(0.0)

# ======================================================================
# 5. 辅助方法
# ======================================================================

static func _gd_source(path: String) -> String:
	var script := load(path) as GDScript
	if script == null:
		return ""
	return script.source_code

static func _tscn_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
