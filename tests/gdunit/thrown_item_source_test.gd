extends GdUnitTestSuite

## 投掷物碎裂/卡死修复回归测试
## 验证：
##   1. ThrownItem 有 source 字段，排除与投掷源的碰撞
##   2. on_body_entered 忽略 source
##   3. throw_furniture 设置 source
##   4. _spawn_dropped_weapon 设置 source
##   5. PlayerStateThrowing 延迟投出 + 动画结束后恢复武器可见性

# ── ThrownItem source 字段与碰撞排除 ──────────────────────────

func test_thrown_item_has_source_field() -> void:
	var source := (load("res://scenes/equipment/thrown_item.gd") as GDScript).source_code
	assert_bool(source.contains("var source: CollisionObject3D")) \
		.override_failure_message("ThrownItem 必须有 source 字段用于排除自碰撞").is_true()


func test_thrown_item_ready_adds_collision_exception() -> void:
	var source := (load("res://scenes/equipment/thrown_item.gd") as GDScript).source_code
	assert_bool(source.contains("add_collision_exception_with(source)")) \
		.override_failure_message("ThrownItem._ready 必须调用 add_collision_exception_with(source)").is_true()


func test_thrown_item_on_body_entered_ignores_source() -> void:
	var source_code := (load("res://scenes/equipment/thrown_item.gd") as GDScript).source_code
	var func_start := source_code.find("func on_body_entered")
	assert_int(func_start).is_greater(-1)
	var func_end := source_code.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source_code.length()
	var func_body := source_code.substr(func_start, func_end - func_start)
	# on_body_entered 必须在设置 has_resolved_collision 之前检查 body == source
	assert_bool(func_body.contains("body == source")) \
		.override_failure_message("on_body_entered 必须忽略 source 碰撞").is_true()
	# body == source 的检查必须在 has_resolved_collision 检查之前
	var source_check_pos := func_body.find("body == source")
	var resolved_check_pos := func_body.find("has_resolved_collision")
	assert_bool(source_check_pos < resolved_check_pos) \
		.override_failure_message("source 检查必须在 has_resolved_collision 检查之前，避免消耗碰撞标志").is_true()


# ── EquipmentComponent throw_furniture 设置 source ────────────

func test_throw_furniture_sets_source() -> void:
	var source := (load("res://scenes/characters/component/equipment_component.gd") as GDScript).source_code
	var func_start := source.find("func throw_furniture")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("thrown_item.source")) \
		.override_failure_message("throw_furniture 必须设置 thrown_item.source").is_true()
	assert_bool(func_body.contains("get_parent() as CollisionObject3D")) \
		.override_failure_message("source 应设为 get_parent() as CollisionObject3D").is_true()


func test_spawn_dropped_weapon_sets_source() -> void:
	var source := (load("res://scenes/characters/component/equipment_component.gd") as GDScript).source_code
	var func_start := source.find("func _spawn_dropped_weapon")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("thrown_item.source")) \
		.override_failure_message("_spawn_dropped_weapon 必须设置 thrown_item.source").is_true()


# ── throw_furniture 不再立即 show_weapon ─────────────────────

func test_throw_furniture_does_not_show_weapon() -> void:
	var source := (load("res://scenes/characters/component/equipment_component.gd") as GDScript).source_code
	var func_start := source.find("func throw_furniture")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# throw_furniture 不应直接调用 show_weapon/show_shield（由调用方决定）
	assert_bool(not func_body.contains("show_weapon()")) \
		.override_failure_message("throw_furniture 不应直接调用 show_weapon()，应由调用方决定").is_true()
	assert_bool(not func_body.contains("show_shield()")) \
		.override_failure_message("throw_furniture 不应直接调用 show_shield()，应由调用方决定").is_true()


func test_drop_furniture_restores_weapon_visibility() -> void:
	var source := (load("res://scenes/characters/component/equipment_component.gd") as GDScript).source_code
	var func_start := source.find("func drop_furniture")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# drop_furniture 应恢复武器可见性
	assert_bool(func_body.contains("show_weapon()")) \
		.override_failure_message("drop_furniture 应调用 show_weapon() 恢复武器可见性").is_true()
	assert_bool(func_body.contains("show_shield()")) \
		.override_failure_message("drop_furniture 应调用 show_shield() 恢复护盾可见性").is_true()


# ── PlayerStateThrowing 延迟投出 + 动画后恢复武器 ─────────────

func test_throwing_state_delays_furniture_throw() -> void:
	var source := (load("res://scenes/characters/player/state/player_state_throwing.gd") as GDScript).source_code
	# 不应在 _enter_tree 中立即调用 throw_furniture
	var enter_start := source.find("func _enter_tree")
	var enter_end := source.find("\nfunc ", enter_start + 1)
	var enter_body := source.substr(enter_start, enter_end - enter_start)
	assert_bool(not enter_body.contains("throw_furniture()")) \
		.override_failure_message("_enter_tree 不应立即调用 throw_furniture()，应延迟到动画释放点").is_true()
	# 应在 _physics_process 中计时后调用
	var phys_start := source.find("func _physics_process")
	var phys_end := source.find("\nfunc ", phys_start + 1)
	var phys_body := source.substr(phys_start, phys_end - phys_start)
	assert_bool(phys_body.contains("throw_furniture()")) \
		.override_failure_message("_physics_process 应在计时到达后调用 throw_furniture()").is_true()
	assert_bool(phys_body.contains("FURNITURE_RELEASE_DELAY")) \
		.override_failure_message("应使用 FURNITURE_RELEASE_DELAY 常量控制释放时机").is_true()


func test_throwing_state_has_release_delay_constant() -> void:
	var source := (load("res://scenes/characters/player/state/player_state_throwing.gd") as GDScript).source_code
	assert_bool(source.contains("FURNITURE_RELEASE_DELAY")) \
		.override_failure_message("PlayerStateThrowing 必须有 FURNITURE_RELEASE_DELAY 常量").is_true()


func test_throwing_state_restores_weapon_after_animation() -> void:
	var source := (load("res://scenes/characters/player/state/player_state_throwing.gd") as GDScript).source_code
	var func_start := source.find("func on_animation_finished")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# 动画结束后应恢复武器可见性
	assert_bool(func_body.contains("show_weapon()")) \
		.override_failure_message("on_animation_finished 应在动画结束后恢复武器可见性").is_true()
	assert_bool(func_body.contains("show_shield()")) \
		.override_failure_message("on_animation_finished 应在动画结束后恢复护盾可见性").is_true()
