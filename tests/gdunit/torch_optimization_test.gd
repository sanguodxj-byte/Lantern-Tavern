extends GdUnitTestSuite

## 火把优化（P1 视觉随光预算隐藏 + P2 火焰 overdraw + P3 距离剔除 + P4 实时阴影修复隔墙漏光）回归测试。
## 注：torch.tscn 直接 preload（不触发 game_state.gd 依赖链）；
## 对 procedural_dungeon.gd / voxel_prop.gd 的结构断言用 FileAccess 读文本，避免编译其依赖。

const TORCH_PREFAB := preload("res://scenes/props/torch/torch.tscn")
const DUNGEON_PATH := "res://scenes/expedition/procedural_dungeon.gd"
const VOXEL_PROP_PATH := "res://scenes/props/voxel_prop.gd"

func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func test_torch_flame_amount_and_range() -> void:
	# P2: 火焰粒子数 36→10；P3: 火焰距离剔除 35m（在 .tscn 直接设置）
	var torch := TORCH_PREFAB.instantiate()
	add_child(torch)
	var flame := torch.get_node("FlameParticles") as GPUParticles3D
	assert_object(flame).is_not_null()
	assert_int(flame.amount).is_equal(10)
	assert_float(flame.visibility_range_end).is_equal_approx(35.0, 0.001)
	torch.free()

func test_torch_visual_hides_with_light_budget() -> void:
	# P1: 火把光被光预算关闭(visible=false)时，火焰与网格同步隐藏；恢复时再现
	var torch := TORCH_PREFAB.instantiate()
	add_child(torch)
	var light := torch.get_node("TorchVisual/OmniLight3D") as Light3D
	assert_object(light).is_not_null()
	light.visible = false
	assert_bool(torch.get_node("FlameParticles").visible).is_false()
	for child in torch.get_node("TorchVisual").get_children():
		if child is MeshInstance3D:
			assert_bool(child.visible).is_false()
	light.visible = true
	assert_bool(torch.get_node("FlameParticles").visible).is_true()
	for child in torch.get_node("TorchVisual").get_children():
		if child is MeshInstance3D:
			assert_bool(child.visible).is_true()
	torch.free()

func test_torch_light_casts_real_time_shadow() -> void:
	# 漏光修复：火把点光源必须开启实时阴影，否则光以球状范围无视墙体几何而透墙。
	# 开销由灯光预算收敛——_update_streamed_lights 只让预算内(最近12盏)火把可见，
	# 不可见火把不渲染阴影，cubemap 阴影代价仅落在预算内火把上。
	var torch := TORCH_PREFAB.instantiate()
	add_child(torch)
	var light := torch.get_node("TorchVisual/OmniLight3D") as Light3D
	assert_object(light).is_not_null()
	assert_bool(light.shadow_enabled).is_true()
	assert_int(light.omni_shadow_mode).is_equal(1)  # 1 = cubemap 阴影(干净无接缝，双抛物面=0 有黑色三角伪影)
	torch.free()

func test_dungeon_applies_torch_distance_culling() -> void:
	# P3: 火把距离剔除已迁入 DungeonSceneBuilder
	var src := _read_source("res://scenes/expedition/dungeon_scene_builder.gd")
	assert_bool(src.contains("const TORCH_VISIBILITY_RANGE_END := 35.0")) \
		.override_failure_message("缺少 TORCH_VISIBILITY_RANGE_END 常量") \
		.is_true()
	assert_bool(src.contains("_apply_distance_culling(torch, TORCH_VISIBILITY_RANGE_END)")) \
		.override_failure_message("_spawn_torch_on_wall 必须对火把应用距离剔除") \
		.is_true()
func test_voxel_prop_hides_flame_on_light_off() -> void:
	# P1: _build_torch 必须连接 light.visibility_changed 并隐藏 FlameParticles
	var src := _read_source(VOXEL_PROP_PATH)
	assert_bool(src.contains("_on_torch_light_visibility_changed")) \
		.override_failure_message("缺少火把光可见性变化回调") \
		.is_true()
	assert_bool(src.contains("visibility_changed.connect(_on_torch_light_visibility_changed")) \
		.override_failure_message("_build_torch 必须连接 light.visibility_changed") \
		.is_true()
	assert_bool(src.contains("get_node_or_null(\"../FlameParticles\")")) \
		.override_failure_message("灯灭时必须隐藏 FlameParticles") \
		.is_true()
	assert_bool(src.contains("shadow_enabled = true")) \
		.override_failure_message("_build_torch 必须为火把开启实时阴影以修复隔墙漏光") \
		.is_true()
	assert_bool(src.contains("omni_shadow_mode = 1")) \
		.override_failure_message("_build_torch 必须为火把选用 cubemap 阴影模式(干净无接缝)") \
		.is_true()
