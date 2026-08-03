extends GdUnitTestSuite
## 验证全局像素着色开关在所有场景加载入口都被同步。
## 每个加载 3D 场景的入口都必须调用 VOXEL_LIGHTING.apply_to_tree，
## 否则内嵌 ShaderMaterial 的 pixel_lighting_enabled 保持默认 1.0（toon 光照），
## 导致用户关闭像素着色后场景仍显示 toon 效果。

func test_world_load_space_calls_apply_to_tree() -> void:
	# World.load_space 加载酒馆/地牢场景后必须调用 apply_to_tree。
	var source := (load("res://scenes/world/world.gd") as GDScript).source_code
	assert_bool(source.contains("VOXEL_LIGHTING.apply_to_tree")) \
		.override_failure_message("World.load_space 必须调用 apply_to_tree 同步像素着色开关").is_true()

func test_main_menu_setup_3d_background_calls_apply_to_tree() -> void:
	# 主菜单 3D 背景（酒馆场景）加载后必须调用 apply_to_tree。
	var source := (load("res://scenes/ui/main_menu.gd") as GDScript).source_code
	assert_bool(source.contains("VOXEL_LIGHTING.apply_to_tree")) \
		.override_failure_message("主菜单 3D 背景必须调用 apply_to_tree 同步像素着色开关").is_true()

func test_player_ready_calls_apply_to_tree() -> void:
	# Player._ready 必须对 character 节点调用 apply_to_tree，
	# 与 enemy.gd 保持一致，使角色身体材质受全局开关控制。
	var source := (load("res://scenes/characters/player/player.gd") as GDScript).source_code
	assert_bool(source.contains("VOXEL_LIGHTING.apply_to_tree")) \
		.override_failure_message("Player._ready 必须调用 apply_to_tree 适配角色身体材质").is_true()

func test_settings_clears_cache_on_toggle() -> void:
	# Settings.set_pixel_shader_enabled 必须调用 clear_cache，
	# 避免切换开关后缓存的 toon 材质被新场景复用。
	var source := (load("res://globals/settings.gd") as GDScript).source_code
	assert_bool(source.contains("clear_cache")) \
		.override_failure_message("Settings.set_pixel_shader_enabled 必须调用 clear_cache").is_true()

func test_voxel_prop_baked_assets_call_apply_to_tree() -> void:
	# VoxelProp.rebuild 加载烘焙资产后必须调用 apply_to_tree，
	# 否则 baked_*.tscn 内嵌的 ShaderMaterial 保持 pixel_lighting_enabled=1.0。
	var source := (load("res://scenes/props/voxel_prop.gd") as GDScript).source_code
	assert_bool(source.contains("VOXEL_LIGHTING.apply_to_tree")) \
		.override_failure_message("VoxelProp 加载烘焙资产后必须调用 apply_to_tree").is_true()
