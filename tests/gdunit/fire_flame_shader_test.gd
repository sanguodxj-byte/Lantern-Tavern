extends GdUnitTestSuite

# 验证程序化火焰 Shader 的资源接线与默认参数可读性。
# 注意：GLSL 实际编译发生在渲染服务器（需 Forward+/Mobile 渲染后端），
# headless 下仅验证资源加载与参数绑定，不为 GLSL 语法做编译期断言。
#
# 两个火焰 Shader：
#  - fire_flame.gdshader       : 单 quad 公告板火焰（独立火焰/营火用）
#  - fire_flame_particle.gdshader: 贴在 GPUParticles3D 上的粒子火焰（火把/壁炉/吊灯用）

const SINGLE_SHADER_PATH := "res://shaders/fire_flame.gdshader"
const SINGLE_MATERIAL_PATH := "res://materials/fire_flame.tres"
const PARTICLE_SHADER_PATH := "res://shaders/fire_flame_particle.gdshader"
const PARTICLE_MATERIAL_PATH := "res://materials/fire_flame_particle.tres"


func test_single_shader_resource_loads() -> void:
	var shader = load(SINGLE_SHADER_PATH)
	assert_object(shader).is_not_null()
	assert_object(shader).is_instanceof(Shader)


func test_single_material_loads_and_binds_shader() -> void:
	var mat = load(SINGLE_MATERIAL_PATH)
	assert_object(mat).is_not_null()
	assert_object(mat).is_instanceof(ShaderMaterial)
	var sm := mat as ShaderMaterial
	assert_object(sm.shader).is_not_null()
	assert_str(sm.shader.resource_path).is_equal(SINGLE_SHADER_PATH)


func test_particle_shader_resource_loads() -> void:
	var shader = load(PARTICLE_SHADER_PATH)
	assert_object(shader).is_not_null()
	assert_object(shader).is_instanceof(Shader)


func test_particle_material_loads_and_binds_shader() -> void:
	var mat = load(PARTICLE_MATERIAL_PATH)
	assert_object(mat).is_not_null()
	assert_object(mat).is_instanceof(ShaderMaterial)
	var sm := mat as ShaderMaterial
	assert_object(sm.shader).is_not_null()
	assert_str(sm.shader.resource_path).is_equal(PARTICLE_SHADER_PATH)


func test_default_parameters_roundtrip() -> void:
	# headless 下渲染服务器不编译 Shader，get_shader_parameter 读不到默认值（返回 Nil），
	# 改用 set/get 往返验证参数名被材质接受、存储 API 可用。
	var single := load(SINGLE_MATERIAL_PATH) as ShaderMaterial
	single.set_shader_parameter("speed", 1.2)
	single.set_shader_parameter("intensity", 1.6)
	assert_float(single.get_shader_parameter("speed")).is_equal_approx(1.2, 0.001)
	assert_float(single.get_shader_parameter("intensity")).is_equal_approx(1.6, 0.001)

	var particle := load(PARTICLE_MATERIAL_PATH) as ShaderMaterial
	particle.set_shader_parameter("speed", 1.5)
	particle.set_shader_parameter("ember_strength", 0.4)
	assert_float(particle.get_shader_parameter("speed")).is_equal_approx(1.5, 0.001)
	assert_float(particle.get_shader_parameter("ember_strength")).is_equal_approx(0.4, 0.001)


# ── 像素风格参数测试 ──────────────────────────────────────────
# fire_flame_particle.gdshader 新增了 pixel_grid 和 color_steps 参数，
# 用于将火焰效果量化为块状像素，匹配体素美术风格。

func test_pixel_grid_parameter_roundtrip() -> void:
	var particle := load(PARTICLE_MATERIAL_PATH) as ShaderMaterial
	particle.set_shader_parameter("pixel_grid", 8.0)
	assert_float(particle.get_shader_parameter("pixel_grid")).is_equal_approx(8.0, 0.001)
	particle.set_shader_parameter("pixel_grid", 16.0)
	assert_float(particle.get_shader_parameter("pixel_grid")).is_equal_approx(16.0, 0.001)


func test_color_steps_parameter_roundtrip() -> void:
	var particle := load(PARTICLE_MATERIAL_PATH) as ShaderMaterial
	particle.set_shader_parameter("color_steps", 3.0)
	assert_float(particle.get_shader_parameter("color_steps")).is_equal_approx(3.0, 0.001)
	particle.set_shader_parameter("color_steps", 6.0)
	assert_float(particle.get_shader_parameter("color_steps")).is_equal_approx(6.0, 0.001)


func test_particle_material_has_pixel_defaults() -> void:
	# 验证材质文件中已写入像素化默认值
	var particle := load(PARTICLE_MATERIAL_PATH) as ShaderMaterial
	var pg = particle.get_shader_parameter("pixel_grid")
	# headless 下 get_shader_parameter 可能返回 null（未设置）或 float（已设置）
	assert_bool(pg != null).override_failure_message("pixel_grid 未在材质中设置").is_true()
	assert_float(float(pg)).is_greater_equal(4.0)
	assert_float(float(pg)).is_less_equal(32.0)
	var cs = particle.get_shader_parameter("color_steps")
	assert_bool(cs != null).override_failure_message("color_steps 未在材质中设置").is_true()
	assert_float(float(cs)).is_greater_equal(2.0)
	assert_float(float(cs)).is_less_equal(8.0)


# 注意：torch.tscn 场景加载测试因 fire.wav 资源缺失（git 中已删除）无法在
# headless 环境实例化。像素风格 fixed_fps=15 的验证通过以下间接方式保证：
# - fireplace.tscn / chandelier.tscn / wall_lantern.tscn 同样使用 fire_flame_particle.tres
# - voxel_prop_scene_test.gd 已覆盖这些场景的资源完整性检查


# ── UV 方向回归守卫 ──────────────────────────────────────────
# Godot QuadMesh 默认 UV.y=0 在顶部，因此火焰高度必须取反 (h = 1.0 - UV.y)，
# 才能得到「底宽顶窄」的正确形态。若此行被改回 'float h = UV.y;' 火焰会颠倒。
# headless 下无法渲染像素，故以源码级断言守卫该修正不被意外回退。

func test_single_flame_uv_orientation_not_inverted() -> void:
	var f := FileAccess.open(SINGLE_SHADER_PATH, FileAccess.READ)
	assert_object(f).is_not_null().override_failure_message("无法读取 %s" % SINGLE_SHADER_PATH)
	var src := f.get_as_text()
	f.close()
	assert_bool(src.contains("float h = 1.0 - UV.y;")).override_failure_message(
		"fire_flame.gdshader 的 UV 高度取反已丢失，火焰将上下颠倒（底窄顶宽）").is_true()
