extends GdUnitTestSuite

## 敌人 imposter 替身渲染 Viewport 配置回归测试。
## 根因：Godot 4.x 的 Viewport/SubViewport 已移除 Godot 3.x 的
## `render_target_clear_color` 属性。enemy.gd 在 _build_imposter_texture()
## 中对该属性赋值会导致运行时崩溃：
##   "Invalid assignment of property or key 'render_target_clear_color'
##    with value of type 'Color' on a base object of type 'SubViewport'"
## 透明背景应改用 SubViewport.transparent_bg = true（配合
## render_target_clear_mode = CLEAR_MODE_ONCE）实现。本测试确保：
##   1) 我们使用的 Godot 4 SubViewport API 合法（transparent_bg /
##      CLEAR_MODE_ONCE / UPDATE_ONCE 存在）；
##   2) 已移除的 render_target_clear_color 属性确实不存在，防止被重新引入；
##   3) enemy.gd 源码不再引用该非法属性。

const ENEMY_SCRIPT_PATH := "res://scenes/characters/enemies/enemy.gd"


func test_subviewport_api_is_valid_in_godot4() -> void:
	var vp := SubViewport.new()
	# 我们使用的关键属性/常量必须存在。
	assert_bool("transparent_bg" in vp).is_true()
	assert_bool("render_target_clear_mode" in vp).is_true()
	assert_bool("render_target_update_mode" in vp).is_true()
	assert_int(SubViewport.CLEAR_MODE_ONCE).is_not_null()
	assert_int(SubViewport.UPDATE_ONCE).is_not_null()
	vp.free()


func test_subviewport_render_target_clear_color_is_removed() -> void:
	# Godot 4 不再提供该属性；若有人误加回赋值会直接崩溃。
	var vp := SubViewport.new()
	assert_bool("render_target_clear_color" in vp).is_false()
	vp.free()


func test_enemy_script_no_longer_uses_render_target_clear_color() -> void:
	# 直接检查源码，防止非法属性被重新引入 enemy.gd。
	var f := FileAccess.open(ENEMY_SCRIPT_PATH, FileAccess.READ)
	assert_object(f).is_not_null()
	var src := f.get_as_text()
	f.close()
	assert_bool(src.contains("render_target_clear_color")).is_false()


func test_imposter_camera_orients_before_tree_attachment_without_node_tree_error() -> void:
	var f := FileAccess.open(ENEMY_SCRIPT_PATH, FileAccess.READ)
	assert_object(f).is_not_null()
	var src := f.get_as_text()
	f.close()
	assert_bool(src.contains("cam.look_at_from_position")).is_true() \
		.override_failure_message("imposter 相机在加入 SubViewport 前必须使用 look_at_from_position，避免 Node not inside tree")
	assert_bool(src.contains("cam.look_at(Vector3(0.0, 0.9, 0.0)")).is_false() \
		.override_failure_message("不得在 SubViewport 入树前调用 cam.look_at")
