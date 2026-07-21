extends GdUnitTestSuite

## 测试“致命击退延迟死亡”：怪物受到致命击退时，不直接进入 DYING，而是进入飞行态 LAUNCHED，
## 撞墙/落地后才结算 DYING（Barony 风格：被打飞到墙上再四散）。无击退的致命伤仍应立即死亡。
##
## 说明：headless 下重复实例化 skeleton-rig 敌人（含蒙皮 rig + 子 Viewport）会触发
## 引擎 signal 11 崩溃（非逻辑错误，真机正常）。因此本套用例合并为“单只已验收 goblin 完整流程”，
## 一次实例化内依次覆盖：进入 LAUNCHED、飞行延迟死亡、撞墙碎裂方向、wants_launch 决策。

const ACCEPTED_ENEMY := preload("res://scenes/characters/enemies/goblin.tscn")
const EnemyStateHurt := preload("res://scenes/characters/enemies/state/enemy_state_hurt.gd")
const EnemyStateLaunched := preload("res://scenes/characters/enemies/state/enemy_state_launched.gd")

# Enemy.State.LAUNCHED 的整数值（枚举第 9 个成员，索引 8）。
# 直接引用 Enemy.State.LAUNCHED 会触发 Enemy ↔ EnemyState 循环依赖解析失败，
# 因此用整数常量替代。
const STATE_LAUNCHED := 8


## 安全清理：先冻结/清理伪布娃娃碎片，再释放敌人，避免在物理活跃的 LAUNCHED 态直接释放导致崩溃。
func _cleanup(enemy: Enemy) -> void:
	if is_instance_valid(enemy) and enemy.voxel_ragdoll != null:
		enemy.voxel_ragdoll.freeze()
		await get_tree().physics_frame
		enemy.voxel_ragdoll.clear_fragments()
		await get_tree().physics_frame
	var parent := enemy.get_parent() if is_instance_valid(enemy) else null
	if is_instance_valid(enemy):
		enemy.queue_free()
	if parent != null and is_instance_valid(parent):
		parent.queue_free()
	await get_tree().physics_frame


func test_knockback_deferred_death_full_flow() -> void:
	var level := Node3D.new()
	add_child(level)
	var enemy := ACCEPTED_ENEMY.instantiate() as Enemy
	level.add_child(enemy)
	await get_tree().physics_frame

	# ── 1) 致命击退：进入飞行态 LAUNCHED（而非立即 DYING）──────────────────
	var data := EnemyStateData.new()
	data.set_damage(9999)
	data.set_impact_direction(Vector3(0, 0, -1))
	data.set_knockback_force(8.0)
	enemy.switch_state(Enemy.State.HURT, data)
	await get_tree().physics_frame
	assert_int(enemy.state).is_equal(STATE_LAUNCHED)

	# ── 2) 无墙环境飞行数帧，仍应处于 LAUNCHED（延迟死亡尚未结算）──────────
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(enemy.state).is_equal(STATE_LAUNCHED)

	# ── 3) 撞墙结算方向：墙法线 +Z（朝角色），碎裂应朝 -Z 四散（纯数学）─────
	var launched := EnemyStateLaunched.new(enemy, EnemyStateData.new())
	var dd := launched.compute_death_data(Vector3(0, 0, 1))
	assert_float(dd.impact_direction.x).is_equal_approx(0.0, 0.001)
	assert_float(dd.impact_direction.z).is_equal_approx(-1.0, 0.001)
	assert_float(dd.impulse.x).is_equal_approx(0.0, 0.001)
	assert_float(dd.impulse.y).is_equal_approx(80.0, 0.001)
	assert_float(dd.impulse.z).is_equal_approx(-120.0, 0.001)
	# 无墙（落地停稳 / 飞行超时）：原地轻抛，无方向性碎裂
	var settled := launched.compute_death_data(Vector3.UP)
	assert_float(settled.impact_direction.length()).is_equal_approx(0.0, 0.001)
	assert_float(settled.impulse.y).is_equal_approx(80.0, 0.001)
	launched.free()

	# ── 4) wants_launch 决策：有击退+已死亡→延迟（LAUNCHED）；无击退→立即死亡 ─
	assert_bool(enemy.health.is_dead()).is_true()
	var hurt := EnemyStateHurt.new(enemy, EnemyStateData.new())
	var with_kb := EnemyStateData.new()
	with_kb.set_knockback_force(8.0)
	var no_kb := EnemyStateData.new()
	no_kb.set_knockback_force(0.0)
	assert_bool(hurt.wants_launch(with_kb)).is_true()
	assert_bool(hurt.wants_launch(no_kb)).is_false()
	hurt.free()

	await _cleanup(enemy)
