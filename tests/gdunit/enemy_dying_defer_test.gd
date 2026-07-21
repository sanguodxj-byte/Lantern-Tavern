extends GdUnitTestSuite

## 回归测试：进入 DYING 状态时，其物理相关死亡副作用（布娃娃模拟启动 / 冲量 / 关闭碰撞 / 掉落物）
## 必须延迟到物理步骤之外执行，否则在 _physics_process 内同步进入 DYING（普攻击杀 / 击飞落地 /
## 穿刺 / 陷阱致死）会在物理引擎步进期间执行物理操作，导致引擎死锁（游戏卡死）。
##
## 本测试验证“进入 DYING 的同一调用栈内不立即执行物理副作用”（即已延迟调度）。
## 死亡物理副作用在 headless 下由守卫跳过布娃娃模拟，避免物理引擎崩溃（与既有死亡测试同策略）。

const ACCEPTED_ENEMY := preload("res://scenes/characters/enemies/goblin.tscn")
const EnemyStateDying := preload("res://scenes/characters/enemies/state/enemy_state_dying.gd")


## 安全清理：释放敌人及其所在关卡，并将 current_level 复位，避免污染其它测试。
func _cleanup(enemy: Enemy) -> void:
	var level := enemy.get_parent() if is_instance_valid(enemy) else null
	if is_instance_valid(enemy):
		enemy.free()
	if level != null and is_instance_valid(level):
		if level.get_parent() != null:
			level.get_parent().remove_child(level)
		level.free()
	if is_instance_valid(GameState.current_level):
		GameState.current_level = null
	
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.physics_frame
		await tree.physics_frame


## 单个测试内完成“延迟 → 执行”两阶段验证：只实例化一只已验收 goblin。
## 说明：headless 下重复实例化 skeleton-rig 敌人（含蒙皮 rig + 子 Viewport）
## 会触发引擎 signal 11 崩溃（非逻辑错误，真机正常）。因此把断言合并到单次实例化，
## 既覆盖“进入 DYING 不立即执行物理副作用”，又覆盖“延迟后在物理步骤之外执行”。
func test_dying_defers_then_runs_physics_effects() -> void:
	var level := Node3D.new()
	add_child(level)
	GameState.current_level = level
	var enemy := ACCEPTED_ENEMY.instantiate() as Enemy
	level.add_child(enemy)
	await get_tree().physics_frame

	# 模拟在 _physics_process 内被触发的同步进入 DYING（如普攻击杀 / 击飞落地 / 穿刺）。
	enemy.switch_state(Enemy.State.DYING, EnemyStateData.new().set_impulse(Vector3(0, 80, 0)))

	# 阶段一：进入 DYING 的同一调用栈内，死亡物理副作用尚未执行（已延迟调度）。
	var dying := enemy.state_node as EnemyStateDying
	assert_object(dying).is_not_null()
	assert_bool(dying._death_effects_deferred).is_true()
	assert_bool(dying._death_effects_started).is_false()
	# 碰撞体仍在启用：证明 collision_shape.disabled 被延迟到物理步骤之外。
	if enemy.collision_shape != null:
		assert_bool(enemy.collision_shape.disabled).is_false()

	# 让延迟的死亡副作用在物理步骤之外执行（headless 下仅布娃娃模拟被守卫跳过）。
	await get_tree().physics_frame

	# 阶段二：延迟的副作用现已执行。
	assert_bool(dying._death_effects_started).is_true()
	if enemy.collision_shape != null:
		assert_bool(enemy.collision_shape.disabled).is_true()

	await _cleanup(enemy)
