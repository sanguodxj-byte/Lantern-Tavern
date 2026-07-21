extends GdUnitTestSuite

## 敌人 3D 血条移除 + 离屏剔除优化回归测试（源码级校验）。
## 采用 FileAccess 读源码/场景文本断言，避免加载依赖 game_state 的怪物脚本
##（gdUnit 扫描器下 game_state.gd 有已知类型推断编译错误，但游戏运行时正常）。
## 任务背景：用户报告「朝向怪物群掉帧」。移除怪物 3D 血条 Sprite3D
##（改用语顶 EnemyHealthBar HUD 显示血量），并为 Enemy 增加离屏/远距剔除
##（visibility_range_end 远裁剪 + 离屏冻结动画省 CPU 蒙皮）。

const RETAINED_ENEMY_SCENES := [
	"res://scenes/characters/enemies/goblin.tscn",
	"res://scenes/characters/enemies/skeleton.tscn",
	"res://scenes/characters/enemies/dragon.tscn",
	"res://scenes/characters/enemies/rock_golem.tscn",
	"res://scenes/characters/enemies/orc_raider.tscn",
]
const ENEMY_GD_PATH := "res://scenes/characters/enemies/enemy.gd"

func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var src := f.get_as_text()
	f.close()
	return src

## 所有保留敌人场景的 .tscn 文本中不再含 3D 血条相关节点。
func test_retained_enemy_scenes_have_no_3d_healthbar() -> void:
	for p in RETAINED_ENEMY_SCENES:
		var src := _read_source(p)
		assert_bool(src.contains("Healthbar")).is_false() \
			.override_failure_message("敌人场景 %s 仍含 3D 血条节点 Healthbar" % p)
		assert_bool(src.contains("ViewportTexture")).is_false() \
			.override_failure_message("敌人场景 %s 仍含 ViewportTexture（血条贴图）" % p)
		assert_bool(src.contains("SubViewport")).is_false() \
			.override_failure_message("敌人场景 %s 仍含 SubViewport（血条视口）" % p)

## enemy.gd 已彻底移除 healthbar / health_indicator 引用（避免编译错误与 3D 血条驱动）。
func test_enemy_gd_no_healthbar_references() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	assert_bool(src.contains("health_indicator")).is_false() \
		.override_failure_message("enemy.gd 仍引用已移除的 health_indicator")
	assert_bool(src.contains("@onready var healthbar")).is_false() \
		.override_failure_message("enemy.gd 仍保留 healthbar @onready 引用")
	assert_bool(src.contains("var healthbar")).is_false() \
		.override_failure_message("enemy.gd 仍保留 healthbar 变量")

## enemy.gd 已实现离屏/远距剔除（远裁剪 + 离屏冻结动画）。
func test_enemy_gd_has_offscreen_culling() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	assert_bool(src.contains("ENEMY_VISIBILITY_RANGE_END")).is_true() \
		.override_failure_message("enemy.gd 缺少离屏远距剔除常量 ENEMY_VISIBILITY_RANGE_END")
	assert_bool(src.contains("func _update_render_optimization")).is_true() \
		.override_failure_message("enemy.gd 缺少 _update_render_optimization 离屏剔除逻辑")
	assert_bool(src.contains("func _collect_visual_meshes")).is_true() \
		.override_failure_message("enemy.gd 缺少 _collect_visual_meshes")
	assert_bool(src.contains("visibility_range_end = ENEMY_VISIBILITY_RANGE_END")).is_true() \
		.override_failure_message("enemy.gd 未对可视网格设置 visibility_range_end 远裁剪")
	assert_bool(src.contains("animation_player.speed_scale = 0.0")).is_true() \
		.override_failure_message("enemy.gd 未实现离屏冻结动画(speed_scale=0)")
