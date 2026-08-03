extends GdUnitTestSuite

## 敌人 billboard 替身回归测试（源码级校验）。
## 采用 FileAccess 读源码文本断言，避免加载依赖 game_state 的怪物脚本
##（gdUnit 扫描器下 game_state.gd 有已知类型推断编译错误，但游戏运行时正常）。
## 任务背景（P3，对齐 godot-voxel VoxelInstancer / Barony 远敌换贴片）：
## 移动状态的敌人隐藏蒙皮网格、显示始终朝向玩家的 Sprite3D billboard 替身；
## 攻击/受击等非 MOVING 状态临时恢复完整骨架网格以保留动作可读性。

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

## 定义了 imposter LOD 距离常量；12m 后切纸片，避免远敌保留完整蒙皮。
func test_imposter_lod_distance_constant_defined() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	assert_bool(src.contains("ENEMY_IMPOSTER_LOD_DISTANCE := 12.0")).is_true() \
		.override_failure_message("enemy.gd 缺少 imposter LOD 距离常量 ENEMY_IMPOSTER_LOD_DISTANCE := 12.0")

## _update_render_optimization 仅在远距且 MOVING 时切换 billboard。
func test_render_optimization_uses_billboard_only_for_far_moving_enemy() -> void:
	var body := _extract_func(_read_source(ENEMY_GD_PATH), "_update_render_optimization")
	assert_bool(body.contains("_imposter_texture_ready and dist > ENEMY_IMPOSTER_LOD_DISTANCE and state == State.MOVING")).is_true() \
		.override_failure_message("只有远处且 MOVING 的敌人才能使用 billboard 替身")
	assert_bool(body.contains("state == State.MOVING and _imposter_texture_ready")).is_false() \
		.override_failure_message("不能把所有移动敌人提前切成 billboard")
	assert_bool(body.contains("_set_lod_far(lod_far)")).is_true() \
		.override_failure_message("_update_render_optimization 未调用 _set_lod_far 切换 LOD")
	# DYING/DEAD 与无目标分支必须强制 _set_lod_far(false)，保证死亡/攻击状态显示完整网格。
	assert_int(body.count("_set_lod_far(false)")).is_equal(2) \
		.override_failure_message("_update_render_optimization 的死亡与无目标分支应各调用一次 _set_lod_far(false)")

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

func test_imposter_capture_camera_includes_enemy_render_layer() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	assert_bool(src.contains("cam.cull_mask = ENEMY_RENDER_LAYER")) \
		.override_failure_message("运行时怪物替身截图相机必须渲染独立怪物层")

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

func test_billboard_uses_nearest_pixel_sampling() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	assert_bool(src.contains("texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST")).is_true()
	assert_bool(src.contains("_imposter_sprite.shaded = true")).is_true() \
		.override_failure_message("billboard 必须使用受光材质，不能变成无光的平面贴图")
	assert_bool(src.contains("_imposter_sprite.pixel_size = target_height / frame_height")).is_true()
	assert_bool(src.contains("_imposter_sprite.position.y = target_height * 0.5")).is_true()
	assert_bool(src.contains("_set_lod_far(true)")).is_false() \
		.override_failure_message("加载贴图时不能无视距离强制切到 billboard")

func test_goblin_uses_authored_8px_billboard_sheet() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	var body := _extract_func(src, "_build_imposter_texture")
	assert_bool(src.contains("AUTHORED_IMPOSTER_TEXTURES")).is_true() \
		.override_failure_message("敌人必须支持按类型注册 authored billboard 纹理")
	assert_bool(src.contains("\"goblin\": \"res://assets/textures/enemies/goblin_billboard_4x4.png\"")).is_true() \
		.override_failure_message("哥布林必须使用重新生成的 8×8 像素纸片素材")
	assert_bool(body.contains("_set_imposter_texture(authored_texture, 4, 4)")).is_true() \
		.override_failure_message("哥布林 authored 纸片必须按 4×4 动画格加载")
	var texture := load("res://assets/textures/enemies/goblin_billboard_4x4.png") as Texture2D
	assert_object(texture).is_not_null()
	assert_int(texture.get_width() % 4).is_equal(0)
	assert_int(texture.get_height() % 4).is_equal(0)

func test_runtime_imposter_capture_activates_its_viewport_camera() -> void:
	var body := _extract_func(_read_source(ENEMY_GD_PATH), "_build_imposter_texture")
	assert_bool(body.contains("cam.make_current()")).is_true() \
		.override_failure_message("运行时 imposter 截图必须显式激活 SubViewport 相机")
	assert_bool(body.contains("vp.own_world_3d = true")).is_true()
	assert_bool(body.contains("background_color = Color(0.0, 0.0, 0.0, 0.0)")).is_true()
	assert_bool(body.contains("cam.position = Vector3(0.0, 1.0, -2.6)")).is_true()

func test_failed_imposter_capture_releases_in_flight_lock() -> void:
	var body := _extract_func(_read_source(ENEMY_GD_PATH), "_finish_imposter_capture")
	assert_bool(body.contains("_imposter_capture_in_flight.erase(cache_key)")).is_true() \
		.override_failure_message("截图失败时必须释放同类敌人的截图锁")

func test_imposter_cache_key_prefers_spawned_enemy_base_type() -> void:
	var body := _extract_func(_read_source(ENEMY_GD_PATH), "_imposter_cache_key")
	assert_bool(body.contains("enemy_base_type")).is_true() \
		.override_failure_message("imposter 缓存键应优先使用 DungeonSpawner 注入的 enemy_base_type")

## 敌人的 LOD 与运行时代码都不得管理自带光源。
func test_enemy_runtime_does_not_manage_presence_lights() -> void:
	var src := _read_source(ENEMY_GD_PATH)
	var ready_body := _extract_func(src, "_ready")
	assert_bool(src.contains("presence_light")).is_false() \
		.override_failure_message("enemy.gd 不应引用或控制敌人自带灯光")
	assert_bool(ready_body.contains("Light3D.new(")).is_false() \
		.override_failure_message("敌人运行时不能创建常驻灯光；独立 SubViewport 截图灯不属于敌人场景")
