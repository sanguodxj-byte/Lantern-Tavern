extends GdUnitTestSuite

## 符文命中爆发特效测试：爆发类型配置、自然色/自定义色调、一次性发射与 finished→queue_free 接线。
## 配置由 setup() 直接应用（不依赖 _ready 时序）；emitting/finished 接线需 _ready 运行后断言。

const RuneHitBurstScript := preload("res://fx/rune_hit_burst.gd")
const RUNE_BURST_SCENE := preload("res://fx/rune_hit_burst.tscn")


func test_scene_and_script_exist() -> void:
	assert_bool(ResourceLoader.exists("res://fx/rune_hit_burst.gd")).is_true()
	assert_bool(ResourceLoader.exists("res://fx/rune_hit_burst.tscn")).is_true()
	assert_object(RuneHitBurstScript).is_not_null()
	var inst: Node3D = RUNE_BURST_SCENE.instantiate() as Node3D
	assert_object(inst).is_not_null()
	inst.free()  # 避免孤儿节点（root + Particles + Light）


func test_burst_config_covers_all_types() -> void:
	# 7 种爆发类型均有配置
	assert_int(RuneHitBurstScript.BURST_CONFIG.size()).is_equal(7)
	for bt in [
		RuneHitBurstScript.BurstType.FIRE_EXPLOSION,
		RuneHitBurstScript.BurstType.STORM,
		RuneHitBurstScript.BurstType.LIGHTNING_CHAIN,
		RuneHitBurstScript.BurstType.SMOKE_TRAP,
		RuneHitBurstScript.BurstType.TREMOR,
		RuneHitBurstScript.BurstType.DARK_DRAIN,
		RuneHitBurstScript.BurstType.HOLY_LIGHT,
	]:
		assert_bool(RuneHitBurstScript.BURST_CONFIG.has(bt)).is_true()
		var cfg: Dictionary = RuneHitBurstScript.BURST_CONFIG[bt]
		for key in ["color", "amount", "radius", "dir", "spread", "vel", "gravity", "turb", "lifetime", "scale", "light_e", "light_r"]:
			assert_bool(cfg.has(key)).is_true()
		# 粒子数保持在低量区间（性能约束 8–40）
		var amt: int = int(cfg["amount"])
		assert_int(amt).is_greater_equal(8)
		assert_int(amt).is_less_equal(40)


func test_setup_applies_natural_color_when_no_tint() -> void:
	# 未显式指定 color（默认白色哨兵）→ 使用爆发类型自身的自然色
	var burst := _instantiate(RuneHitBurstScript.BurstType.STORM, Vector3(2, 3, 4))
	var particles := burst.get_node("Particles") as GPUParticles3D
	var mat := particles.process_material as ParticleProcessMaterial
	assert_object(mat).is_not_null()
	assert_bool(mat.color.is_equal_approx(Color(0.3, 0.7, 1.0))).is_true()
	# 位置应用
	assert_vector(burst.global_position).is_equal_approx(Vector3(2, 3, 4), Vector3(0.001, 0.001, 0.001))
	# 粒子数与寿命按配置
	assert_int(particles.amount).is_equal(40)
	assert_float(particles.lifetime).is_equal_approx(1.2, 0.001)
	# 点光源颜色与能量
	var light := burst.get_node("Light") as OmniLight3D
	assert_bool(light.light_color.is_equal_approx(Color(0.3, 0.7, 1.0))).is_true()
	assert_float(light.light_energy).is_equal_approx(1.5, 0.001)
	burst.queue_free()


func test_setup_custom_tint_overrides_natural_color() -> void:
	var tint := Color(0.2, 0.8, 0.2)
	var burst := _instantiate(RuneHitBurstScript.BurstType.FIRE_EXPLOSION, Vector3.ZERO, tint)
	var mat := (burst.get_node("Particles") as GPUParticles3D).process_material as ParticleProcessMaterial
	# 显式色调覆盖自然橙色
	assert_bool(mat.color.is_equal_approx(tint)).is_true()
	var light := burst.get_node("Light") as OmniLight3D
	assert_bool(light.light_color.is_equal_approx(tint)).is_true()
	burst.queue_free()


func test_setup_smoke_trap_has_largest_scale() -> void:
	var burst := _instantiate(RuneHitBurstScript.BurstType.SMOKE_TRAP, Vector3.ZERO)
	var mat := (burst.get_node("Particles") as GPUParticles3D).process_material as ParticleProcessMaterial
	# 烟雾云缩放最大
	assert_float(mat.scale_max).is_greater_equal(mat.scale_min)
	assert_float(mat.scale_max).is_equal_approx(2.0, 0.001)
	burst.queue_free()


func test_ready_emits_one_shot_and_wires_finished() -> void:
	var burst := _instantiate(RuneHitBurstScript.BurstType.LIGHTNING_CHAIN, Vector3.ZERO)
	await await_idle_frame()  # 确保 _ready 已执行
	var particles := burst.get_node("Particles") as GPUParticles3D
	assert_bool(particles.one_shot).is_true()
	assert_bool(particles.emitting).is_true()
	# finished 信号应连接到本节点的 queue_free
	var wired := false
	for c in particles.finished.get_connections():
		var callable: Callable = c["callable"]
		if callable.get_object() == burst and String(callable.get_method()) == "queue_free":
			wired = true
	assert_bool(wired).is_true()
	burst.queue_free()


func _instantiate(burst_type: int, pos: Vector3, tint: Color = Color.WHITE) -> Node3D:
	var burst: Node3D = RUNE_BURST_SCENE.instantiate() as Node3D
	add_child(burst)
	burst.call("setup", burst_type, pos, tint)
	return burst
