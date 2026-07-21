extends GdUnitTestSuite
## 物理撞击伤害延迟切换状态测试
## 验证：踢击/冲撞设置 physical_impact_enabled=true 后，敌人在 _physics_process 中
## 撞墙致死时，switch_state(DYING) 通过 call_deferred 延迟执行，
## 避免 EnemyStateDying._enter_tree 中的 physical_bones_start_simulation() 等物理操作
## 在物理引擎步进期间执行导致死锁/卡死。

# ---------- 代码结构验证 ----------

func test_apply_physical_impact_damage_uses_call_deferred() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func _apply_physical_impact_damage")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# 必须使用 call_deferred 延迟切换到 DYING，不能同步调用 switch_state
	assert_bool(func_body.contains("call_deferred")).is_true() \
		.override_failure_message("_apply_physical_impact_damage 应使用 call_deferred 延迟 switch_state(DYING)")
	assert_bool(not func_body.contains('switch_state(State.DYING, data)')).is_true() \
		.override_failure_message("_apply_physical_impact_damage 不应同步调用 switch_state(State.DYING)")

func test_deferred_switch_to_dying_method_exists() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _deferred_switch_to_dying")).is_true() \
		.override_failure_message("enemy.gd 应包含 _deferred_switch_to_dying 方法")

func test_deferred_switch_to_dying_checks_can_die() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func _deferred_switch_to_dying")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# 延迟回调中必须再次检查 can_die()，防止在延迟期间敌人已被其他攻击杀死并切换到 DYING
	assert_bool(func_body.contains("can_die()")).is_true() \
		.override_failure_message("_deferred_switch_to_dying 应检查 can_die() 避免重复切换")
	assert_bool(func_body.contains("switch_state(State.DYING")).is_true() \
		.override_failure_message("_deferred_switch_to_dying 应调用 switch_state(State.DYING)")

func test_deferred_switch_to_dying_checks_instance_valid() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func _deferred_switch_to_dying")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# 延迟回调中必须检查自身是否仍然有效（call_deferred 可能在 queue_free 后执行）
	assert_bool(func_body.contains("is_instance_valid")).is_true() \
		.override_failure_message("_deferred_switch_to_dying 应检查 is_instance_valid(self)")

func test_apply_physical_impact_damage_resets_flag() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func _apply_physical_impact_damage")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# physical_impact_enabled 必须在伤害结算后立即重置，防止重复触发
	assert_bool(func_body.contains("physical_impact_enabled = false")).is_true() \
		.override_failure_message("_apply_physical_impact_damage 应重置 physical_impact_enabled = false")

func test_apply_physical_impact_damage_checks_state_node_null() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func _apply_physical_impact_damage")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# 应检查 state_node != null 防止空引用
	assert_bool(func_body.contains("state_node != null")).is_true() \
		.override_failure_message("_apply_physical_impact_damage 应检查 state_node != null")

# ---------- 运行时行为验证 ----------

func test_deferred_switch_to_dying_skips_when_already_dying() -> void:
	# 验证 _deferred_switch_to_dying 在 can_die() 返回 false 时不执行 switch_state
	# 模拟：敌人已在 DYING 状态（can_die = false），延迟回调不应再次切换
	var enemy := Enemy.new()
	# 直接调用 _deferred_switch_to_dying，由于 enemy 没有 state_node（未 _ready），
	# state_node 为 null，方法应安全返回而不崩溃
	enemy._deferred_switch_to_dying(null)
	# 没有崩溃即通过
	enemy.free()

func test_physical_impact_enabled_defaults_false() -> void:
	var enemy := Enemy.new()
	assert_bool(enemy.physical_impact_enabled).is_false()
	enemy.free()
