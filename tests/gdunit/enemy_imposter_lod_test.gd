extends GdUnitTestSuite

## 敌人距离 LOD + imposter 替身回归测试（源码级校验）。
## 采用 FileAccess 读源码文本断言，避免加载依赖 game_state 的怪物脚本
##（gdUnit 扫描器下 game_state.gd 有已知类型推断编译错误，但游戏运行时正常）。
## 任务背景（P3，对齐 godot-voxel VoxelInstancer / Barony 远敌换贴片）：
## 近处(<~18m)或处于攻击/受击等非 MOVING 状态的敌人用完整骨架蒙皮网格；
## 远处且 MOVING 的敌人隐藏蒙皮网格、显示 Sprite3D billboard 替身（运行时 Viewport 截图），
## 省 CPU 蒙皮 + draw call。敌人本身不得携带任何实时灯光。

const ENEMY_GD_PATH := "res://scenes/characters/enemies/enemy.gd"

func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var src := f.get_as_text()
	f.close()
	return src

## 抽取某个 func 的函数体（从 "func <name>" 到下一个顶层 "func " 之前），便于按函数断言。
func _extract_func(src: String, name: String) -> String:
	var start := src.find("func " + name + "(")
	if start < 0:
		return ""
	var end := src.find("\nfunc ", start + 1)
	if end < 0:
		end = src.length()
	return src.substr(start, end - start)

## 定义了 imposter LOD 距离常量（约 18m）。
func test_imposter_lod_distance_constant_defined() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	assert_bool(src.contains("ENEMY_IMPOSTER_LOD_DISTANCE := 18.0")).is_true() \
		.override_failure_message("enemy.gd 缺少 imposter LOD 距离常量 ENEMY_IMPOSTER_LOD_DISTANCE := 18.0")

## _update_render_optimization 依据距离+状态计算 LOD，并调用 _set_lod_far。
## 关键：LOD 仅对 MOVING 状态生效，攻击/受击等非 MOVING 状态始终保留完整骨架网格（可读招式）。
func test_render_optimization_computes_lod_for_moving_far() -> void:
	var body := _extract_func(_read_source(ENEMY_GD_PATH), "_update_render_optimization")
	assert_bool(body.contains("var lod_far := dist > ENEMY_IMPOSTER_LOD_DISTANCE and state == State.MOVING")).is_true() \
		.override_failure_message("_update_render_optimization 未以『远处且 MOVING』计算 lod_far（应保留非 MOVING 招式可读）")
	assert_bool(body.contains("_set_lod_far(lod_far)")).is_true() \
		.override_failure_message("_update_render_optimization 未调用 _set_lod_far 切换 LOD")
	# DYING/DEAD 与无目标分支必须强制 _set_lod_far(false)，保证死亡/频死显示完整网格。
	assert_int(body.count("_set_lod_far(false)")).is_equal(2) \
		.override_failure_message("_update_render_optimization 的 DYING/DEAD 与无目标分支应各调用一次 _set_lod_far(false)")

## _set_lod_far 正确切换：隐藏/恢复蒙皮网格 + 显示/隐藏 imposter 替身。
func test_set_lod_far_toggles_meshes_and_imposter() -> void:
	var body := _extract_func(_read_source(ENEMY_GD_PATH), "_set_lod_far")
	assert_bool(body.contains("m.visible = not far")).is_true() \
		.override_failure_message("_set_lod_far 未根据 LOD 切换蒙皮网格 visible")
	assert_bool(body.contains("_imposter_sprite.visible = far")).is_true() \
		.override_failure_message("_set_lod_far 未根据 LOD 切换 imposter 替身 visible")

## imposter 替身 Sprite3D 在 _ready 创建（billboard），贴图由 _build_imposter_texture 生成。
func test_imposter_sprite_created_in_ready() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	var ready_body := _extract_func(src, "_ready")
	assert_bool(ready_body.contains("_build_imposter_sprite()")).is_true() \
		.override_failure_message("_ready 未调用 _build_imposter_sprite 创建 imposter 替身")
	var build_body := _extract_func(src, "_build_imposter_sprite")
	assert_bool(build_body.contains("Sprite3D.new()")).is_true() \
		.override_failure_message("_build_imposter_sprite 未创建 Sprite3D")
	assert_bool(build_body.contains("\"ImposterSprite\"")).is_true() \
		.override_failure_message("_build_imposter_sprite 未将替身命名为 ImposterSprite")
	assert_bool(build_body.contains("_build_imposter_texture()")).is_true() \
		.override_failure_message("_build_imposter_sprite 未触发运行时截图生成贴图")

## 截图生成在 headless 下跳过（无 GPU），保证测试/无头环境不崩；imposter 仍按 LOD 切换（仅无贴图）。
func test_imposter_capture_skipped_in_headless() -> void:
	var body := _extract_func(_read_source(ENEMY_GD_PATH), "_build_imposter_texture")
	assert_bool(body.contains("OS.has_feature(\"headless\")")).is_true() \
		.override_failure_message("_build_imposter_texture 未在 headless 下跳过截图（无头环境会崩）")

func test_imposter_capture_is_shared_per_enemy_type() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	var body := _extract_func(src, "_build_imposter_texture")
	assert_bool(src.contains("static var _imposter_texture_cache")).is_true() \
		.override_failure_message("同类敌人必须共享 imposter 贴图缓存")
	assert_bool(src.contains("static var _imposter_capture_in_flight")).is_true() \
		.override_failure_message("并发生成同类敌人时必须合并重复截图任务")
	assert_bool(body.contains("_imposter_texture_cache.get")).is_true()
	assert_bool(body.contains("_imposter_capture_in_flight.has")).is_true()

func test_imposter_cache_key_prefers_spawned_enemy_base_type() -> void:
	var body := _extract_func(_read_source(ENEMY_GD_PATH), "_imposter_cache_key")
	assert_bool(body.contains("enemy_base_type")).is_true() \
		.override_failure_message("imposter 缓存键应优先使用 DungeonSpawner 注入的 enemy_base_type")

## 敌人的 LOD 与运行时代码都不得管理自带光源。
func test_enemy_runtime_does_not_manage_presence_lights() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	assert_bool(src.contains("presence_light")).is_false() \
		.override_failure_message("enemy.gd 不应引用或控制敌人自带灯光")
	assert_bool(src.contains("Light3D.new(")).is_false() \
		.override_failure_message("enemy.gd 不应在运行时创建灯光")
