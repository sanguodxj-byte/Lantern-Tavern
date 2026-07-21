extends GdUnitTestSuite

## 集成测试：怪物进入死亡掉落流程时，掉落的 PickableItem 应带物理爆出速度
## （而非静止放置）。验证「类似男爵的爆出掉落效果」已接入死亡逻辑。

const ACCEPTED_ENEMY := preload("res://scenes/characters/enemies/goblin.tscn")
const DYING := preload("res://scenes/characters/enemies/state/enemy_state_dying.gd")


func test_dying_state_bursts_dropped_item_physically() -> void:
	var level := Node3D.new()
	add_child(level)
	var enemy := ACCEPTED_ENEMY.instantiate() as Enemy
	level.add_child(enemy)
	await get_tree().physics_frame
	# 直接驱动掉落生成（绕过 _enter_tree 中装备/音频副作用，聚焦爆出效果）
	var state := DYING.new(enemy, EnemyStateData.new()) as EnemyStateDying
	state._spawn_monster_drop()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var items := level.find_children("*", "PickableItem", true, false)
	assert_int(items.size()).is_greater(0)
	var bursted := false
	for it in items:
		if (it as RigidBody3D).linear_velocity.length() > 1.0:
			bursted = true
			break
	assert_bool(bursted).is_true()
	state.free()
	enemy.queue_free()
	level.queue_free()
