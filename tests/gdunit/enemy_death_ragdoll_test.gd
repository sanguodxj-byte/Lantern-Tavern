extends GdUnitTestSuite

## 怪物死亡体素碎裂效果修复测试。
##
## 验证修复：
## 1. 所有敌人均创建 voxel_ragdoll（无论 skeleton_simulator 是否为 null）
## 2. 死亡状态（DYING）只走 voxel_ragdoll 碎裂路径，不保留 skeleton_simulator 回退
## 3. 死亡完成状态（DEAD）优先走 voxel_ragdoll.freeze()
## 4. _death_ragdoll_active 标志阻止 LOD 系统在碎裂后重新显示原始网格
##
## 说明：headless 下实例化含蒙皮 rig 的敌人可能触发引擎崩溃（非逻辑错误），
## 因此源码断言用 string 检查替代完整实例化。

const EnemyStateDying := preload("res://scenes/characters/enemies/state/enemy_state_dying.gd")
const EnemyStateDead := preload("res://scenes/characters/enemies/state/enemy_state_dead.gd")


# ── 源码断言：死亡状态优先使用 voxel_ragdoll ─────────────────────────

func test_dying_state_uses_only_voxel_ragdoll() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_dying.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("enemy.voxel_ragdoll != null")).is_true()
	assert_bool(source.contains("physical_bones_start_simulation")) \
		.override_failure_message("敌人死亡不得重新创建或启动已废弃的骨骼刚体").is_false()


func test_dying_state_sets_death_ragdoll_active() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_dying.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_death_ragdoll_active = true")) \
		.override_failure_message("死亡碎裂激活时应设置 _death_ragdoll_active 标志").is_true()


func test_dying_state_calls_voxel_ragdoll_activate() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_dying.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("voxel_ragdoll.activate(")) \
		.override_failure_message("死亡状态应调用 voxel_ragdoll.activate()").is_true()


func test_enemy_removes_unused_physical_bones_after_ready() -> void:
	var source := (load("res://scenes/characters/enemies/enemy.gd") as GDScript).source_code
	assert_bool(source.contains("_remove_unused_physical_bones()" )).is_true()
	assert_bool(source.contains("obsolete_simulator.free()")) \
		.override_failure_message("禁用不足以释放 Body/Joint RID，必须直接释放遗留模拟器树").is_true()
	assert_bool(source.contains("skeleton_simulator = null")).is_true()


# ── 源码断言：DEAD 状态优先使用 voxel_ragdoll.freeze() ────────────────

func test_dead_state_freezes_only_voxel_ragdoll() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_dead.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("enemy.voxel_ragdoll.freeze()" )).is_true()
	assert_bool(source.contains("PhysicsServer3D.body_set_state")) \
		.override_failure_message("DEAD 状态不应再访问已释放的 PhysicalBone RID").is_false()


# ── 源码断言：enemy.gd 始终创建 voxel_ragdoll ─────────────────────────

func test_enemy_always_creates_voxel_ragdoll() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	# 不应有 "if skeleton_simulator == null" 条件守卫
	assert_bool(source.contains("if skeleton_simulator == null:\n\t\tvoxel_ragdoll")) \
		.override_failure_message("voxel_ragdoll 不应只在 skeleton_simulator == null 时创建").is_false()
	# 应直接创建 voxel_ragdoll
	assert_bool(source.contains("voxel_ragdoll = VOXEL_RAGDOLL.new()")) \
		.override_failure_message("enemy.gd 应始终创建 voxel_ragdoll").is_true()


# ── 源码断言：_death_ragdoll_active 阻止 LOD 重新显示网格 ─────────────

func test_enemy_has_death_ragdoll_active_flag() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_death_ragdoll_active")) \
		.override_failure_message("enemy.gd 应有 _death_ragdoll_active 标志").is_true()
	# _set_lod_far 应检查 _death_ragdoll_active
	assert_bool(source.contains("not _death_ragdoll_active")) \
		.override_failure_message("_set_lod_far 应在 _death_ragdoll_active 时跳过网格可见性修改").is_true()


# ── 源码断言：voxel_ragdoll 支持网格分块碎裂 ──────────────────────────

func test_voxel_ragdoll_has_grid_fragmentation() -> void:
	var script := load("res://scenes/characters/component/voxel_ragdoll.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_fragment_from_grid")) \
		.override_failure_message("VoxelRagdoll 应有网格分块碎裂方法").is_true()
	assert_bool(source.contains("_fragment_per_mesh")) \
		.override_failure_message("VoxelRagdoll 应有逐网格碎裂方法").is_true()
	assert_bool(source.contains("MIN_MESHES_FOR_PER_PART_FRAGMENT")) \
		.override_failure_message("VoxelRagdoll 应有碎裂模式阈值常量").is_true()


func test_voxel_ragdoll_freeze_sets_body_freeze() -> void:
	var script := load("res://scenes/characters/component/voxel_ragdoll.gd") as GDScript
	var source := script.source_code
	# freeze 应设置 b.freeze = true（静态化碎片，防止被碰撞唤醒）
	assert_bool(source.contains("b.freeze = true")) \
		.override_failure_message("freeze() 应设置碎片 freeze=true 防止被碰撞唤醒").is_true()
