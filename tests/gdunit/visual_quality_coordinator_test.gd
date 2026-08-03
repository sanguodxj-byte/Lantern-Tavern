extends GdUnitTestSuite

## VisualQualityCoordinator（P1-2）—— 性能档位 → 环境雾/环境光/主光阴影的统一映射。
## 预算语义（2026-08-03 架构检查修正）：只降不升 + 原始值还原——
## 低档 min(原始, 预算)；高档还原原始（不覆盖地牢 zone 雾/酒馆配置、不强制开阴影）。

const VQC := preload("res://globals/perf/visual_quality_coordinator.gd")

func _make_env(fog: float = 0.006, ambient: float = 0.6) -> Environment:
	var env := Environment.new()
	env.fog_enabled = true
	env.fog_density = fog
	env.ambient_light_energy = ambient
	return env

func test_profile_for_unknown_tier_falls_back_to_full() -> void:
	var p: Dictionary = VQC.profile_for(99)
	assert_float(float(p["fog_density"])).is_equal_approx(0.006, 1e-4)
	assert_bool(bool(p["fog_enabled"])).is_true()
	# 四档全部可解析。
	for tier in [0, 1, 2, 3]:
		assert_bool(not VQC.profile_for(tier).is_empty()).is_true()

func test_budget_tier_classification() -> void:
	assert_bool(VQC.is_budget_tier(2)).is_true()
	assert_bool(VQC.is_budget_tier(3)).is_true()
	assert_bool(VQC.is_budget_tier(0)).is_false()
	assert_bool(VQC.is_budget_tier(1)).is_false()

func test_low_tier_never_raises_scene_values() -> void:
	# 场景雾比预算更浓（地牢 zone 1-5 雾 0.010）→ 降档后取 min(原始, 预算) 收紧但不改方向。
	var coordinator: VQC = auto_free(VQC.new())
	var env := _make_env(0.010, 0.5)
	assert_bool(coordinator.apply_environment(env, 2)).is_true()
	assert_float(env.fog_density).is_equal_approx(0.0, 1e-4)  # 预算 0.0 → 关
	assert_bool(env.fog_enabled).is_false()
	assert_float(env.ambient_light_energy).is_equal_approx(0.4, 1e-4)  # min(0.5, 0.4)
	# 场景雾比预算稀（tavern 0.002）→ 降档仍取 min → 0.0（不升不改变方向）。
	var env2 := _make_env(0.002, 0.3)
	coordinator.apply_environment(env2, 2)
	assert_float(env2.fog_density).is_equal_approx(0.0, 1e-4)
	assert_float(env2.ambient_light_energy).is_equal_approx(0.3, 1e-4)  # min(0.3, 0.4)=0.3 不升

func test_high_tier_restores_original_scene_values() -> void:
	# 核心回归：变档恢复 FULL 时还原场景原始值——绝不覆盖地牢/酒馆精心配置的雾。
	var coordinator: VQC = auto_free(VQC.new())
	var env := _make_env(0.010, 0.5)  # 地牢 zone-4 级别配置
	coordinator.apply_environment(env, 2)  # 降档
	assert_float(env.fog_density).is_equal_approx(0.0, 1e-4)
	coordinator.apply_environment(env, 0)  # 恢复 FULL
	assert_float(env.fog_density) \
		.override_failure_message("恢复档位必须还原原始雾密度（%.3f），不得覆盖场景配置" % env.fog_density) \
		.is_equal_approx(0.010, 1e-4)
	assert_bool(env.fog_enabled).is_true()
	assert_float(env.ambient_light_energy).is_equal_approx(0.5, 1e-4)

func test_apply_environment_null_safe() -> void:
	var coordinator: VQC = auto_free(VQC.new())
	assert_bool(coordinator.apply_environment(null, 1)).is_false()

func test_apply_to_scene_shadow_only_degrades_never_enables() -> void:
	var coordinator: VQC = auto_free(VQC.new())
	var root := Node3D.new()
	add_child(root)
	var env_node := WorldEnvironment.new()
	env_node.environment = _make_env(0.008, 0.45)  # 地牢 zone-2 级别
	root.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	root.add_child(sun)
	var unlit := DirectionalLight3D.new()
	unlit.shadow_enabled = false  # 原本就关阴影
	root.add_child(unlit)
	# 高档：还原原始（雾 0.008、开阴影、关阴影的保持关）。
	var applied: int = coordinator.apply_to_scene(root, 0)
	assert_int(applied).is_equal(1)
	assert_float(env_node.environment.fog_density).is_equal_approx(0.008, 1e-4)
	assert_bool(sun.shadow_enabled).is_true()
	assert_bool(unlit.shadow_enabled).is_false()
	# 降档：雾关、开阴影的关、原本关的仍关。
	coordinator.apply_to_scene(root, 3)
	assert_bool(env_node.environment.fog_enabled).is_false()
	assert_bool(sun.shadow_enabled).is_false()
	assert_bool(unlit.shadow_enabled).is_false()
	# 恢复：还原原始（原本关的不得被强制开启）。
	coordinator.apply_to_scene(root, 0)
	assert_float(env_node.environment.fog_density).is_equal_approx(0.008, 1e-4)
	assert_bool(sun.shadow_enabled).is_true()
	assert_bool(unlit.shadow_enabled) \
		.override_failure_message("恢复档位不得强制开启原本关闭的阴影").is_false()
	root.queue_free()

func test_apply_to_scene_null_safe() -> void:
	var coordinator: VQC = auto_free(VQC.new())
	assert_int(coordinator.apply_to_scene(null, 1)).is_equal(0)

