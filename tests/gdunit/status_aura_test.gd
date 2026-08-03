extends GdUnitTestSuite

## 状态效果光环测试：颜色/形态配置、setup 应用、_process 跟随与生命周期回收。
## 使用 Node3D 访问器而非 @onready，使 setup 可在 add_child 后立即生效；
## _process 测试关闭自动处理（set_process(false)）以获得确定性时序。

const StatusAuraScript := preload("res://fx/status_aura.gd")
const STATUS_AURA_SCENE := preload("res://fx/status_aura.tscn")

const EXPECTED_STATUSES := [
	"burn", "poison", "slow", "blind", "fear", "corrupt", "stun", "ensnare",
	"wet", "choke", "tremor", "terror", "armor_break", "sunder",
]

# 暴露 combat_debuffs 字典的最小敌人替身（与 Enemy.combat_debuffs 接口对齐）
class _EnemyDouble extends Node3D:
	var combat_debuffs: Dictionary = {}


func test_scene_and_script_exist() -> void:
	assert_bool(ResourceLoader.exists("res://fx/status_aura.gd")).is_true()
	assert_bool(ResourceLoader.exists("res://fx/status_aura.tscn")).is_true()
	assert_object(StatusAuraScript).is_not_null()
	var inst: Node3D = STATUS_AURA_SCENE.instantiate() as Node3D
	assert_object(inst).is_not_null()
	inst.free()  # 避免孤儿节点（root + Particles + Light）


func test_status_config_covers_all_expected_types() -> void:
	for status in EXPECTED_STATUSES:
		assert_bool(StatusAuraScript.STATUS_CONFIG.has(status)).is_true()
		var cfg: Dictionary = StatusAuraScript.STATUS_CONFIG[status]
		for key in ["color", "dir", "spread", "vel", "gravity", "radius", "turb", "light_e", "light_r"]:
			assert_bool(cfg.has(key)).is_true()


func test_status_colors_match_design_spec() -> void:
	assert_bool(Color(1.0, 0.4, 0.1).is_equal_approx(StatusAuraScript.STATUS_CONFIG["burn"]["color"])).is_true()
	assert_bool(Color(0.3, 0.8, 0.2).is_equal_approx(StatusAuraScript.STATUS_CONFIG["poison"]["color"])).is_true()
	assert_bool(Color(0.3, 0.5, 1.0).is_equal_approx(StatusAuraScript.STATUS_CONFIG["slow"]["color"])).is_true()
	assert_bool(Color(0.6, 0.3, 0.8).is_equal_approx(StatusAuraScript.STATUS_CONFIG["blind"]["color"])).is_true()
	assert_bool(Color(0.9, 0.9, 0.9).is_equal_approx(StatusAuraScript.STATUS_CONFIG["fear"]["color"])).is_true()
	assert_bool(Color(0.5, 0.1, 0.15).is_equal_approx(StatusAuraScript.STATUS_CONFIG["corrupt"]["color"])).is_true()
	assert_bool(Color(1.0, 0.9, 0.2).is_equal_approx(StatusAuraScript.STATUS_CONFIG["stun"]["color"])).is_true()
	assert_bool(Color(0.6, 0.4, 0.2).is_equal_approx(StatusAuraScript.STATUS_CONFIG["ensnare"]["color"])).is_true()
	assert_bool(Color(0.2, 0.6, 0.9).is_equal_approx(StatusAuraScript.STATUS_CONFIG["wet"]["color"])).is_true()
	assert_bool(Color(0.4, 0.4, 0.4).is_equal_approx(StatusAuraScript.STATUS_CONFIG["choke"]["color"])).is_true()
	assert_bool(Color(0.7, 0.5, 0.3).is_equal_approx(StatusAuraScript.STATUS_CONFIG["tremor"]["color"])).is_true()
	assert_bool(Color(0.4, 0.2, 0.5).is_equal_approx(StatusAuraScript.STATUS_CONFIG["terror"]["color"])).is_true()
	assert_bool(Color(0.8, 0.6, 0.3).is_equal_approx(StatusAuraScript.STATUS_CONFIG["armor_break"]["color"])).is_true()
	assert_bool(Color(0.9, 0.5, 0.2).is_equal_approx(StatusAuraScript.STATUS_CONFIG["sunder"]["color"])).is_true()


func test_setup_applies_color_light_and_emits() -> void:
	var enemy := _EnemyDouble.new()
	add_child(enemy)
	var aura: Node3D = STATUS_AURA_SCENE.instantiate() as Node3D
	add_child(aura)
	aura.set_process(false)  # 关闭自动处理，由测试手动驱动 _process

	aura.call("setup", enemy, "burn")

	var particles := aura.get_node("Particles") as GPUParticles3D
	assert_object(particles).is_not_null()
	assert_bool(particles.emitting).is_true()  # _ready 已开启发射
	assert_bool(particles.one_shot).is_false()  # 持续型：非 one_shot
	assert_int(particles.amount).is_equal(8)

	var mat := particles.process_material as ParticleProcessMaterial
	assert_object(mat).is_not_null()
	assert_bool(mat.color.is_equal_approx(Color(1.0, 0.4, 0.1))).is_true()

	var light := aura.get_node("Light") as OmniLight3D
	assert_object(light).is_not_null()
	assert_bool(light.light_color.is_equal_approx(Color(1.0, 0.4, 0.1))).is_true()
	assert_float(light.light_energy).is_equal_approx(0.7, 0.001)
	assert_float(light.omni_range).is_equal_approx(2.0, 0.001)

	aura.queue_free()
	enemy.queue_free()


func test_setup_corrupt_uses_downward_drip_motion() -> void:
	var enemy := _EnemyDouble.new()
	add_child(enemy)
	var aura: Node3D = STATUS_AURA_SCENE.instantiate() as Node3D
	add_child(aura)
	aura.set_process(false)
	aura.call("setup", enemy, "corrupt")
	var mat := (aura.get_node("Particles") as GPUParticles3D).process_material as ParticleProcessMaterial
	# 下滴：方向向下 + 正向重力（加速下落）+ 无湍流
	assert_vector(mat.direction).is_equal_approx(Vector3(0, -1, 0), Vector3(0.001, 0.001, 0.001))
	assert_float(mat.gravity.y).is_greater(0.0)
	assert_bool(mat.turbulence_enabled).is_false()
	aura.queue_free()
	enemy.queue_free()


func test_setup_stun_enables_turbulence() -> void:
	var enemy := _EnemyDouble.new()
	add_child(enemy)
	var aura: Node3D = STATUS_AURA_SCENE.instantiate() as Node3D
	add_child(aura)
	aura.set_process(false)
	aura.call("setup", enemy, "stun")
	var mat := (aura.get_node("Particles") as GPUParticles3D).process_material as ParticleProcessMaterial
	assert_bool(mat.turbulence_enabled).is_true()
	assert_float(mat.turbulence_influence_max).is_greater(0.0)
	aura.queue_free()
	enemy.queue_free()


func test_process_follows_enemy_position_with_offset() -> void:
	var enemy := _EnemyDouble.new()
	add_child(enemy)
	enemy.global_position = Vector3(5, 0, 3)
	enemy.combat_debuffs["burn"] = {"remaining": 5.0, "value": 0}
	var aura: Node3D = STATUS_AURA_SCENE.instantiate() as Node3D
	add_child(aura)
	aura.set_process(false)
	aura.call("setup", enemy, "burn")

	aura.call("_process", 0.016)
	assert_vector(aura.global_position).is_equal_approx(
		Vector3(5, 1.0, 3), Vector3(0.001, 0.001, 0.001)
	)
	aura.queue_free()
	enemy.queue_free()


func test_process_frees_when_status_removed() -> void:
	var enemy := _EnemyDouble.new()
	add_child(enemy)
	enemy.combat_debuffs["poison"] = {"remaining": 5.0, "value": 0}
	var aura: Node3D = STATUS_AURA_SCENE.instantiate() as Node3D
	add_child(aura)
	aura.set_process(false)
	aura.call("setup", enemy, "poison")

	# 状态仍活跃：不释放
	aura.call("_process", 0.016)
	assert_bool(is_instance_valid(aura)).is_true()

	# 状态移除：_process 触发 queue_free
	enemy.combat_debuffs.erase("poison")
	aura.call("_process", 0.016)
	await await_idle_frame()
	assert_bool(is_instance_valid(aura)).is_false()
	if is_instance_valid(enemy):
		enemy.queue_free()


func test_process_frees_when_enemy_invalid() -> void:
	var enemy := _EnemyDouble.new()
	add_child(enemy)
	enemy.combat_debuffs["slow"] = {"remaining": 5.0, "value": 0}
	var aura: Node3D = STATUS_AURA_SCENE.instantiate() as Node3D
	add_child(aura)
	aura.set_process(false)
	aura.call("setup", enemy, "slow")

	# 销毁敌人（自动处理已关，光环不会自行提前回收）
	enemy.queue_free()
	await await_idle_frame()
	aura.call("_process", 0.016)
	await await_idle_frame()
	assert_bool(is_instance_valid(aura)).is_false()


func test_unknown_status_falls_back_to_white() -> void:
	var enemy := _EnemyDouble.new()
	add_child(enemy)
	var aura: Node3D = STATUS_AURA_SCENE.instantiate() as Node3D
	add_child(aura)
	aura.set_process(false)
	aura.call("setup", enemy, "nonexistent_status")
	var mat := (aura.get_node("Particles") as GPUParticles3D).process_material as ParticleProcessMaterial
	assert_bool(mat.color.is_equal_approx(Color.WHITE)).is_true()
	aura.queue_free()
	enemy.queue_free()
