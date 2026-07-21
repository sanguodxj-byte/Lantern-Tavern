extends GdUnitTestSuite
## 交互提示悬浮窗系统测试
## 验证基类、子类、GameEvents 信号、player.gd 集成的完整链路

# ============================================================
# 1. 基类 InteractionHintBase 测试
# ============================================================

func test_base_class_exists_and_extends_panel() -> void:
	var script := load("res://scenes/ui/interaction_hint_base.gd") as GDScript
	assert_object(script).is_not_null()
	# InteractionHintBase 继承 PanelContainer
	var instance: InteractionHintBase = script.new()
	add_child(instance)
	assert_bool(instance is PanelContainer).is_true()
	instance.queue_free()
	await await_idle_frame()

func test_base_class_has_show_and_hide_methods() -> void:
	var script := load("res://scenes/ui/interaction_hint_base.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func show_hint(")) \
		.override_failure_message("基类必须定义 show_hint 方法").is_true()
	assert_bool(source.contains("func hide_hint(")) \
		.override_failure_message("基类必须定义 hide_hint 方法").is_true()

func test_base_class_hide_is_instant() -> void:
	var script := load("res://scenes/ui/interaction_hint_base.gd") as GDScript
	var source := script.source_code
	# hide_hint 中不应有 tween 动画，应直接设置 visible = false
	var hide_func_start := source.find("func hide_hint()")
	assert_int(hide_func_start).is_greater(-1)
	var hide_func_end := source.find("\nfunc ", hide_func_start + 1)
	if hide_func_end == -1:
		hide_func_end = source.length()
	var hide_func := source.substr(hide_func_start, hide_func_end - hide_func_start)
	assert_bool(not hide_func.contains("tween_property")) \
		.override_failure_message("hide_hint 必须立即隐藏，不能有渐隐动画").is_true()
	assert_bool(hide_func.contains("visible = false")) \
		.override_failure_message("hide_hint 必须设置 visible = false").is_true()

func test_base_class_positions_near_screen_pos() -> void:
	var script := load("res://scenes/ui/interaction_hint_base.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _position_near(")) \
		.override_failure_message("基类必须定义 _position_near 方法").is_true()
	assert_bool(source.contains("clampf")) \
		.override_failure_message("基类必须使用 clampf 钳制到视口范围").is_true()

func test_base_class_has_fade_in() -> void:
	var script := load("res://scenes/ui/interaction_hint_base.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _play_fade_in(")) \
		.override_failure_message("基类必须有淡入动画方法").is_true()
	assert_bool(source.contains("FADE_IN_DURATION")) \
		.override_failure_message("基类必须定义淡入时长常量").is_true()

# ============================================================
# 2. 子类 PickupHint 测试
# ============================================================

func test_pickup_hint_extends_base() -> void:
	var script := load("res://scenes/ui/pickup_hint.gd") as GDScript
	assert_object(script).is_not_null()
	var base := script.get_base_script()
	assert_object(base).is_not_null()
	assert_str(base.resource_path).contains("interaction_hint_base")

func test_pickup_hint_has_show_for_item() -> void:
	var script := load("res://scenes/ui/pickup_hint.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func show_for_item(")) \
		.override_failure_message("PickupHint 必须定义 show_for_item 方法").is_true()

func test_pickup_hint_text_contains_pick_up_and_item_name() -> void:
	var hint: PickupHint = load("res://scenes/ui/pickup_hint.gd").new()
	add_child(hint)
	# 完整交互文本由 player.gd 构建后原样传入
	hint.show_for_item("[E] Pick Up Short Sword", Vector2(100, 100))
	await await_idle_frame()
	assert_bool(hint.visible).is_true()
	# 文本应包含 [E] 和物品名
	var label: Label = hint.get_child(0).get_child(0)
	assert_str(label.text).contains("[E]")
	assert_str(label.text).contains("Short Sword")
	hint.queue_free()

func test_pickup_hint_empty_name_shows_item() -> void:
	var hint: PickupHint = load("res://scenes/ui/pickup_hint.gd").new()
	add_child(hint)
	hint.show_for_item("[E] Pick Up", Vector2(100, 100))
	await await_idle_frame()
	assert_bool(hint.visible).is_true()
	var label: Label = hint.get_child(0).get_child(0)
	assert_str(label.text).contains("[E]")
	hint.queue_free()

# ============================================================
# 3. 子类 InteractHint 测试
# ============================================================

func test_interact_hint_extends_base() -> void:
	var script := load("res://scenes/ui/interact_hint.gd") as GDScript
	assert_object(script).is_not_null()
	var base := script.get_base_script()
	assert_object(base).is_not_null()
	assert_str(base.resource_path).contains("interaction_hint_base")

func test_interact_hint_has_show_for_object() -> void:
	var script := load("res://scenes/ui/interact_hint.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func show_for_object(")) \
		.override_failure_message("InteractHint 必须定义 show_for_object 方法").is_true()

func test_interact_hint_text_contains_interact_and_name() -> void:
	var hint: InteractHint = load("res://scenes/ui/interact_hint.gd").new()
	add_child(hint)
	# 完整交互文本由 player.gd 构建后原样传入
	hint.show_for_object("[E] Interact Barrel", Vector2(200, 200))
	await await_idle_frame()
	assert_bool(hint.visible).is_true()
	var label: Label = hint.get_child(0).get_child(0)
	assert_str(label.text).contains("[E]")
	assert_str(label.text).contains("Barrel")
	hint.queue_free()

func test_interact_hint_displays_multiline_progress_text() -> void:
	# 宝箱/门等富文本（含进度、动作提示）也应完整显示在物体右侧悬浮窗
	var hint: InteractHint = load("res://scenes/ui/interact_hint.gd").new()
	add_child(hint)
	hint.show_for_object("Chest\nHold [E] to Open (5s)", Vector2(300, 300))
	await await_idle_frame()
	assert_bool(hint.visible).is_true()
	var label: Label = hint.get_child(0).get_child(0)
	assert_str(label.text).contains("Chest")
	assert_str(label.text).contains("Hold [E] to Open (5s)")
	hint.queue_free()

# ============================================================
# 4. 共用基类验证
# ============================================================

func test_both_subclasses_share_same_base() -> void:
	var pickup_script := load("res://scenes/ui/pickup_hint.gd") as GDScript
	var interact_script := load("res://scenes/ui/interact_hint.gd") as GDScript
	var pickup_base := pickup_script.get_base_script().resource_path
	var interact_base := interact_script.get_base_script().resource_path
	assert_str(pickup_base).is_equal(interact_base)
	assert_str(pickup_base).contains("interaction_hint_base")

func test_both_subclasses_inherit_show_hint_and_hide_hint() -> void:
	var pickup: PickupHint = load("res://scenes/ui/pickup_hint.gd").new()
	add_child(pickup)
	assert_bool(pickup.has_method("show_hint")).is_true()
	assert_bool(pickup.has_method("hide_hint")).is_true()
	pickup.queue_free()

	var interact: InteractHint = load("res://scenes/ui/interact_hint.gd").new()
	add_child(interact)
	assert_bool(interact.has_method("show_hint")).is_true()
	assert_bool(interact.has_method("hide_hint")).is_true()
	interact.queue_free()

# ============================================================
# 5. GameEvents 信号验证
# ============================================================

func test_game_events_has_interaction_hint_signal() -> void:
	var script := load("res://globals/core/game_events.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("signal interaction_hint_changed")) \
		.override_failure_message("GameEvents 必须定义 interaction_hint_changed 信号").is_true()

func test_signal_has_three_params() -> void:
	var script := load("res://globals/core/game_events.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("signal interaction_hint_changed(hint_type: String, text: String, screen_position: Vector2)")) \
		.override_failure_message("interaction_hint_changed 信号必须有 hint_type, text, screen_position 三个参数").is_true()

# ============================================================
# 6. player.gd 集成验证
# ============================================================

func test_player_emits_interaction_hint_signal() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("GameEvents.interaction_hint_changed.emit")) \
		.override_failure_message("player.gd 必须发射 interaction_hint_changed 信号").is_true()

func test_player_sets_hint_type_for_pickable() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains('hint_type = "pickup"')) \
		.override_failure_message("指向 PickableItem 时 hint_type 应为 'pickup'").is_true()

func test_player_sets_hint_type_for_interact() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains('hint_type = "interact"')) \
		.override_failure_message("指向可交互物体时 hint_type 应为 'interact'").is_true()

func test_player_sets_hint_type_for_chest() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains('hint_type = "chest"')) \
		.override_failure_message("指向宝箱时 hint_type 应为 'chest'").is_true()

func test_player_sets_hint_type_for_door() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains('hint_type = "door"')) \
		.override_failure_message("指向门时 hint_type 应为 'door'").is_true()

func test_player_computes_screen_position() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_get_raycast_screen_position")) \
		.override_failure_message("player.gd 必须定义 _get_raycast_screen_position 方法").is_true()
	assert_bool(source.contains("camera.unproject_position")) \
		.override_failure_message("必须使用 camera.unproject_position 计算屏幕坐标").is_true()

func test_player_emits_empty_hint_when_no_target() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	# 当没有射线碰撞时，hint_type 应为空字符串
	# 验证 hint_type 初始值为空
	assert_bool(source.contains('var hint_type := ""')) \
		.override_failure_message("hint_type 初始值必须为空字符串").is_true()

# ============================================================
# 7. ui.gd 集成验证
# ============================================================

func test_ui_connects_interaction_hint_signal() -> void:
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("GameEvents.interaction_hint_changed.connect(on_interaction_hint_changed)")) \
		.override_failure_message("ui.gd 必须连接 interaction_hint_changed 信号").is_true()

func test_ui_creates_hint_instances() -> void:
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_setup_interaction_hints")) \
		.override_failure_message("ui.gd 必须定义 _setup_interaction_hints 方法").is_true()
	assert_bool(source.contains("PICKUP_HINT_SCRIPT")) \
		.override_failure_message("ui.gd 必须预加载 PickupHint 脚本").is_true()
	assert_bool(source.contains("INTERACT_HINT_SCRIPT")) \
		.override_failure_message("ui.gd 必须预加载 InteractHint 脚本").is_true()

func test_ui_has_hide_all_hints() -> void:
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _hide_all_hints")) \
		.override_failure_message("ui.gd 必须定义 _hide_all_hints 方法").is_true()

func test_ui_hides_hints_on_scene_change() -> void:
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	# set_world_space 中应调用 _hide_all_hints
	var sws_start := source.find("func set_world_space")
	assert_int(sws_start).is_greater(-1)
	var sws_end := source.find("\nfunc ", sws_start + 1)
	if sws_end == -1:
		sws_end = source.length()
	var sws_func := source.substr(sws_start, sws_end - sws_start)
	assert_bool(sws_func.contains("_hide_all_hints()")) \
		.override_failure_message("set_world_space 必须调用 _hide_all_hints 清理悬浮窗").is_true()

# ============================================================
# 8. 运行时行为验证
# ============================================================

func test_hide_hint_makes_invisible_immediately() -> void:
	var hint: InteractionHintBase = load("res://scenes/ui/interaction_hint_base.gd").new()
	add_child(hint)
	hint.show_hint("Test", Vector2(100, 100))
	await await_idle_frame()
	assert_bool(hint.visible).is_true()
	# 立即隐藏
	hint.hide_hint()
	assert_bool(hint.visible).is_false()
	# 无需等待帧，应已不可见
	hint.queue_free()

func test_show_hint_with_empty_text_hides() -> void:
	var hint: InteractionHintBase = load("res://scenes/ui/interaction_hint_base.gd").new()
	add_child(hint)
	hint.show_hint("", Vector2(100, 100))
	assert_bool(hint.visible).is_false()
	hint.queue_free()

func test_pickup_hint_then_interact_hint_switch() -> void:
	# 模拟从指向拾取物切换到指向交互物
	var pickup: PickupHint = load("res://scenes/ui/pickup_hint.gd").new()
	var interact: InteractHint = load("res://scenes/ui/interact_hint.gd").new()
	add_child(pickup)
	add_child(interact)
	# 先显示拾取提示
	pickup.show_for_item("Sword", Vector2(100, 100))
	await await_idle_frame()
	assert_bool(pickup.visible).is_true()
	assert_bool(interact.visible).is_false()
	# 切换到交互提示
	pickup.hide_hint()
	interact.show_for_object("Barrel", Vector2(200, 200))
	await await_idle_frame()
	assert_bool(pickup.visible).is_false()
	assert_bool(interact.visible).is_true()
	pickup.queue_free()
	interact.queue_free()
