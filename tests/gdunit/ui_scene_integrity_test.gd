extends GdUnitTestSuite

# 回归测试：验证所有 UI 类脚本必须通过场景实例化，而非 .new()
# 防止 "Invalid access to property 'visible' on null instance" 类错误

# 需要场景实例化的 UI 脚本列表（脚本中有 $ 路径或 %unique_name 引用）
# 格式: { "script_path": "对应的场景路径" }
var _ui_scripts_requiring_scene := {
	"res://scenes/ui/expedition_hud.gd": "res://scenes/ui/expedition_hud.tscn",
	"res://scenes/ui/tavern_hud.gd": "res://scenes/ui/tavern_ui.tscn",
	"res://scenes/ui/main_menu.gd": "res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/pause_menu.gd": "res://scenes/ui/pause_menu.tscn",
	"res://scenes/ui/character_panel.gd": "res://scenes/ui/character_panel.tscn",
	"res://scenes/ui/model_viewer.gd": "res://scenes/ui/model_viewer.tscn",
	"res://scenes/ui/stat_indicator.gd": "res://scenes/ui/stat_indicator.tscn",
}

func test_all_ui_scripts_have_corresponding_scenes() -> void:
	for script_path in _ui_scripts_requiring_scene:
		var scene_path = _ui_scripts_requiring_scene[script_path]
		assert_bool(ResourceLoader.exists(script_path)) \
			.override_failure_message("Missing script: " + script_path) \
			.is_true()
		assert_bool(ResourceLoader.exists(scene_path)) \
			.override_failure_message("Missing scene for " + script_path + " -> " + scene_path) \
			.is_true()


func test_script_new_returns_bare_node_without_children() -> void:
	# 验证：用 .new() 创建 UI 脚本时，$ 路径返回 null
	var script = load("res://scenes/ui/expedition_hud.gd")
	var hud = script.new()
	# .new() 创建的节点没有子节点，$MobileHUD 应为 null
	assert_object(hud.get_node_or_null("MobileHUD")).is_null()
	assert_object(hud.get_node_or_null("TopHUD")).is_null()
	hud.free()


func test_scene_instantiate_provides_child_nodes() -> void:
	# 验证：用 scene.instantiate() 创建时，$ 路径正常 resolve
	var scene = load("res://scenes/ui/expedition_hud.tscn")
	assert_object(scene).is_not_null()
	var hud = scene.instantiate()
	# 场景实例化后子节点应存在
	assert_object(hud.get_node("MobileHUD")).is_not_null()
	assert_object(hud.get_node("TopHUD")).is_not_null()
	assert_object(hud.get_node("TopHUD/HPBar")).is_not_null()
	assert_object(hud.get_node("TopHUD/GoldLabel")).is_not_null()
	assert_object(hud.get_node("BottomHUD/AlertLabel")).is_not_null()
	hud.queue_free()


func test_all_ui_scenes_instantiate_without_error() -> void:
	# 遍历所有 UI 场景，确保 instantiate() 不报错
	for script_path in _ui_scripts_requiring_scene:
		var scene_path = _ui_scripts_requiring_scene[script_path]
		var scene = load(scene_path) as PackedScene
		assert_object(scene).override_failure_message("Cannot load: " + scene_path).is_not_null()
		var instance = scene.instantiate()
		assert_object(instance).override_failure_message("Cannot instantiate: " + scene_path).is_not_null()
		instance.queue_free()


func test_procedural_dungeon_mounts_hud_via_scene() -> void:
	# 回归验证：procedural_dungeon.gd 必须使用 scene.instantiate()
	# 而非 script.new() 来挂载 HUD
	var script_path = "res://scenes/expedition/procedural_dungeon.gd"
	assert_bool(ResourceLoader.exists(script_path)).is_true()
	var script = load(script_path) as GDScript
	assert_object(script).is_not_null()
	var source = script.source_code
	
	# 必须使用 tscn 加载方式，不能直接用 .gd new()
	assert_bool(source.contains("expedition_hud.tscn")) \
		.override_failure_message("procedural_dungeon.gd 必须用 expedition_hud.tscn 实例化 HUD") \
		.is_true()
	
	# 确保没有残留的 .new() 方式
	var has_new_based_hud = "hud_script.new()" in source or "ExpeditionHUD.new()" in source
	assert_bool(not has_new_based_hud) \
		.override_failure_message("procedural_dungeon.gd 不能使用 .new() 创建 HUD，必须用 scene.instantiate()") \
		.is_true()
