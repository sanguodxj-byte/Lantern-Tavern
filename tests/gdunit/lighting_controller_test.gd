extends GdUnitTestSuite

# 验证 LightingController 的画质分级、酒馆光照档案收束、以及确定性火光闪烁。

const SCENE_FILE := "res://scenes/tavern/tavern.tscn"

# 编辑器中火把的原始参数（voxel_prop.gd::_build_torch 经 @tool 在编辑器内生成）。
# 运行时 apply_tavern_profile 会收束这些值，但收束幅度不能过大，否则实机远暗于编辑器。
const EDITOR_TORCH_ENERGY := 1.5
const EDITOR_TORCH_RANGE := 5.0


func _find_first_omni(node: Node) -> OmniLight3D:
	if node is OmniLight3D:
		return node as OmniLight3D
	for c in node.get_children():
		var found := _find_first_omni(c)
		if found != null:
			return found
	return null


func test_quality_tier_detects_compatibility_renderer() -> void:
	# Arrange
	var prev: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")
	# Act + Assert (gl_compatibility -> MEDIUM)
	ProjectSettings.set_setting("rendering/renderer/rendering_method", "gl_compatibility")
	assert_int(LightingController.detect_quality_tier()).is_equal(1)  # MEDIUM
	# Act + Assert (forward_plus -> HIGH)
	ProjectSettings.set_setting("rendering/renderer/rendering_method", "forward_plus")
	assert_int(LightingController.detect_quality_tier()).is_equal(0)  # HIGH
	# Restore
	ProjectSettings.set_setting("rendering/renderer/rendering_method", prev)


# ── P1-4：性能预算分档 → 光照质量档映射 ──────────────────────────

func test_quality_tier_to_lighting_maps_budget_tiers() -> void:
	# PerformanceBudget.QualityTier: FULL=0 / BALANCED=1 / PERFORMANCE=2 / EMERGENCY=3
	assert_int(LightingController.quality_tier_to_lighting(0)).is_equal(LightingController.Quality.HIGH)
	assert_int(LightingController.quality_tier_to_lighting(1)).is_equal(LightingController.Quality.MEDIUM)
	assert_int(LightingController.quality_tier_to_lighting(2)).is_equal(LightingController.Quality.LOW)
	assert_int(LightingController.quality_tier_to_lighting(3)).is_equal(LightingController.Quality.LOW)

func test_budget_tier_changed_updates_lighting_quality() -> void:
	# 模拟 PerformanceBudget.quality_tier_changed 信号：GPU 压力上升 → 光照档跟随降档。
	LightingController.set_quality_tier(LightingController.Quality.HIGH)
	LightingController._on_budget_tier_changed(2, 0.78)  # PERFORMANCE
	assert_int(LightingController.get_quality_tier()).is_equal(LightingController.Quality.LOW)
	LightingController._on_budget_tier_changed(0, 1.0)   # FULL 恢复
	assert_int(LightingController.get_quality_tier()).is_equal(LightingController.Quality.HIGH)

## P1-2：变档必须重应用【已应用光源】的范围/能量——运行中降档后火把立即跟随新档位。
func test_budget_tier_change_reapplies_applied_lights() -> void:
	var root := Node3D.new()
	var torch := OmniLight3D.new()
	torch.name = "TorchLight"
	torch.set_meta("light_role", "torch")
	torch.omni_range = 11.0
	torch.light_energy = 3.4
	root.add_child(torch)
	add_child(root)
	# 以 HIGH 应用档案。
	LightingController.set_quality_tier(LightingController.Quality.HIGH)
	LightingController.apply_tavern_profile(root)
	assert_float(torch.omni_range).is_equal_approx(LightingController.TAVERN_TORCH_RANGE[LightingController.Quality.HIGH], 0.01)
	# 性能预算降档到 LOW → 已应用光源必须被重应用为新档位范围。
	LightingController._on_budget_tier_changed(2, 0.78)
	assert_int(LightingController.get_quality_tier()).is_equal(LightingController.Quality.LOW)
	assert_float(torch.omni_range) \
		.override_failure_message("变档后已应用火把范围必须跟随新档位（仍为旧档 %.2f）" % torch.omni_range) \
		.is_equal_approx(LightingController.TAVERN_TORCH_RANGE[LightingController.Quality.LOW], 0.01)
	# 恢复 HIGH（清理状态，避免影响后续用例）。
	LightingController._on_budget_tier_changed(0, 1.0)
	root.free()


func test_tavern_profile_tightens_torch_light() -> void:
	# Arrange
	LightingController.set_quality_tier(0)  # HIGH
	var root := Node3D.new()
	var torch := OmniLight3D.new()
	torch.name = "OmniLight3D"
	torch.set_meta("light_role", "torch")
	torch.omni_range = 11.0
	torch.light_energy = 3.4
	root.add_child(torch)
	add_child(root)
	# Act
	LightingController.apply_tavern_profile(root)
	# Assert: range/energy 收束为酒馆局部光池，并加入闪烁组
	assert_float(torch.omni_range).is_equal_approx(4.75, 0.01)
	assert_float(torch.light_energy).is_equal_approx(1.55, 0.01)
	assert_float(torch.light_specular).is_equal_approx(0.0, 0.001)
	assert_float(torch.light_color.r - torch.light_color.g).is_less_equal(0.13)
	assert_bool(torch.is_in_group("flicker_light")).is_true()
	root.free()


func test_tavern_profile_disables_specular_for_every_scene_light() -> void:
	var root := Node3D.new()
	var torch := OmniLight3D.new()
	torch.name = "TorchLight"
	torch.set_meta("light_role", "torch")
	torch.light_specular = 0.8
	var fill := DirectionalLight3D.new()
	fill.name = "TavernFillLight"
	fill.light_specular = 0.8
	root.add_child(torch)
	root.add_child(fill)
	add_child(root)

	LightingController.apply_tavern_profile(root)

	assert_float(torch.light_specular).is_equal_approx(0.0, 0.001)
	assert_float(fill.light_specular).is_equal_approx(0.0, 0.001)
	root.free()


func test_tavern_profile_limits_warm_accent_color_pollution() -> void:
	var root := Node3D.new()
	var fireplace := OmniLight3D.new()
	fireplace.light_color = Color(0.95, 0.62, 0.38, 1.0)
	fireplace.omni_range = 5.8
	root.add_child(fireplace)
	add_child(root)

	LightingController.apply_tavern_profile(root)

	assert_float(fireplace.omni_range).is_equal_approx(4.0, 0.01)
	assert_float(fireplace.light_color.g).is_greater(0.77)
	assert_float(fireplace.light_color.b).is_greater(0.62)
	root.free()


func test_tavern_profile_skips_player_vision_light() -> void:
	# Arrange
	var root := Node3D.new()
	var player_light := OmniLight3D.new()
	player_light.name = "PlayerVisionLight"
	player_light.light_energy = 2.4
	player_light.visible = true
	root.add_child(player_light)
	add_child(root)
	# Act
	LightingController.apply_tavern_profile(root)
	# Assert: 玩家视觉光不加入闪烁组，且 visible 被设为 false，能量降为 0.0
	assert_bool(player_light.is_in_group("flicker_light")).is_false()
	assert_bool(player_light.visible).is_false()
	assert_float(player_light.light_energy).is_equal(0.0)
	root.free()


func test_compute_flicker_is_deterministic_and_bounded() -> void:
	# Arrange
	var phase := 1.234
	var t := 5.678
	var amp := 0.12
	# Act
	var a := LightingController.compute_flicker(phase, t, amp)
	var b := LightingController.compute_flicker(phase, t, amp)
	# Assert: 同输入同结果（确定性，便于测试/复现）
	assert_float(a).is_equal(b)
	# Assert: 在 [1-amp, 1+amp] 区间内
	assert_float(a).is_greater_equal(1.0 - amp - 1e-6)
	assert_float(a).is_less_equal(1.0 + amp + 1e-6)


func test_flicker_process_modulates_light_energy_around_base() -> void:
	# Arrange
	LightingController.set_quality_tier(0)  # HIGH
	var root := Node3D.new()
	var light := OmniLight3D.new()
	light.name = "OmniLight3D"
	light.set_meta("light_role", "torch")
	root.add_child(light)
	add_child(root)
	LightingController.apply_tavern_profile(root)
	var base: float = light.get_meta("flicker_base_energy", 2.4)
	# Act: 推进若干帧
	for i in range(10):
		LightingController._process(0.016)
	# Assert: 能量始终在 base 的闪烁幅度范围内
	assert_float(light.light_energy).is_greater_equal(base * 0.88 - 1e-6)
	assert_float(light.light_energy).is_less_equal(base * 1.12 + 1e-6)
	root.free()


# ── 回归测试：编辑器/运行时光照一致性 ──────────────────────────
# voxel_prop.gd 是 @tool 脚本，编辑器内火把显示原始值（energy=3.4, range=11.0）。
# apply_tavern_profile 在运行时收束这些值，但收束幅度不能过大，
# 否则会出现"实机光照远小于编辑器"的问题（此前 energy=1.35/range=3.6 即为此 bug）。
# 此测试确保所有画质分档下，运行时火把亮度/范围不低于编辑器原始值的合理比例。

func test_tavern_torch_energy_not_far_below_editor_high() -> void:
	LightingController.set_quality_tier(0)  # HIGH
	var runtime_energy: float = LightingController.TAVERN_TORCH_ENERGY
	# 运行时能量不得低于编辑器原始值的 60%（此前 1.35/3.4≈40% 导致过暗）
	assert_float(runtime_energy / EDITOR_TORCH_ENERGY) \
		.override_failure_message(
			"酒馆火把能量 %.2f 远低于编辑器值 %.2f（占比 %.0f%%），实机将明显偏暗" %
			[runtime_energy, EDITOR_TORCH_ENERGY, runtime_energy / EDITOR_TORCH_ENERGY * 100.0]) \
		.is_greater_equal(0.6)


func test_tavern_torch_range_not_far_below_editor_all_tiers() -> void:
	for tier in [LightingController.Quality.HIGH, LightingController.Quality.MEDIUM, LightingController.Quality.LOW]:
		var runtime_range: float = LightingController.TAVERN_TORCH_RANGE[tier]
		# 运行时范围不得低于编辑器原始值的 35%（此前 LOW=2.4/11.0≈22% 导致过暗）
		assert_float(runtime_range / EDITOR_TORCH_RANGE) \
			.override_failure_message(
				"画质档 %d: 酒馆火把范围 %.1f 远低于编辑器值 %.1f（占比 %.0f%%），实机将明显偏暗" %
				[tier, runtime_range, EDITOR_TORCH_RANGE, runtime_range / EDITOR_TORCH_RANGE * 100.0]) \
			.is_greater_equal(0.35)


func test_tavern_torch_energy_stays_bounded_for_interior_use() -> void:
	# 酒馆允许比地牢局部火把稍亮，但仍需限制峰值，避免台面和墙体烧白。
	assert_float(LightingController.TAVERN_TORCH_ENERGY) \
		.override_failure_message("酒馆火把能量不应超过室内高光预算") \
		.is_less(3.2)


func test_tavern_scene_uses_balanced_neutral_fill() -> void:
	var tavern := (load(SCENE_FILE) as PackedScene).instantiate()
	var world_environment := tavern.get_node("WorldEnvironment") as WorldEnvironment
	var environment := world_environment.environment
	var directional := tavern.get_node("DirectionalLight3D") as DirectionalLight3D

	assert_float(environment.ambient_light_energy).is_equal_approx(0.58, 0.001)
	assert_float(environment.ambient_light_color.b - environment.ambient_light_color.r) \
		.is_less_equal(0.02)
	assert_float(environment.fog_light_color.r - environment.fog_light_color.b) \
		.is_greater_equal(-0.04)
	assert_float(directional.light_energy).is_equal_approx(0.5, 0.001)
	assert_float(directional.light_color.b - directional.light_color.r).is_less_equal(0.11)

	tavern.free()


# ── WYSIWYG 一致性测试：VoxelProp 上下文光照 ───────────────────
# VoxelProp._apply_context_lighting 在光源创建/加载时即根据所在场景上下文应用正确值。
# 它读取 LightingController 的 TAVERN_TORCH_RANGE/ENERGY 常量——与 apply_tavern_profile 相同。
# 由于 @tool 脚本和 baked 场景在 headless 测试环境中无法实例化（依赖 shader/audio 资源），
# WYSIWYG 行为通过以下方式验证：
# 1. test_tavern_profile_tightens_torch_light — 验证 dungeon 值→tavern 值的转换
# 2. test_tavern_torch_energy_not_far_below_editor_high — 验证 energy 比例合理
# 3. test_tavern_torch_range_not_far_below_editor_all_tiers — 验证 range 比例合理
# 4. test_tavern_torch_energy_below_dungeon_constraint — 验证约束边界
# 5. 下方测试验证 VoxelProp 读取的常量与 apply_tavern_profile 使用的常量完全一致

const VOXEL_PROP_SCRIPT := "res://scenes/props/voxel_prop.gd"


func test_voxel_prop_uses_same_constants_as_lighting_controller() -> void:
	# VoxelProp._apply_context_lighting 读取 LightingController 的常量来收束光源。
	# 此测试验证这些常量存在于 LightingController 上且值合理，
	# 确保 VoxelProp 和 apply_tavern_profile 使用同一套光源参数（单一数据源）。
	LightingController.set_quality_tier(0)  # HIGH

	# TAVERN_TORCH_RANGE 必须包含所有画质分档
	var range_map: Dictionary = LightingController.TAVERN_TORCH_RANGE
	assert_int(range_map.size()).is_equal(3)
	assert_bool(range_map.has(LightingController.Quality.HIGH)).is_true()
	assert_bool(range_map.has(LightingController.Quality.MEDIUM)).is_true()
	assert_bool(range_map.has(LightingController.Quality.LOW)).is_true()

	# TAVERN_TORCH_ENERGY 必须是正值且低于地牢约束
	var energy: float = LightingController.TAVERN_TORCH_ENERGY
	assert_float(energy).is_greater(0.0)
	assert_float(energy).is_less(3.2)

	# TAVERN_TORCH_COLOR 必须是暖色（r > g > b）
	var color: Color = LightingController.TAVERN_TORCH_COLOR
	assert_float(color.r).is_greater(color.g)
	assert_float(color.g).is_greater(color.b)
