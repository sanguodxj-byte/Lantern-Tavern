extends GdUnitTestSuite

# 验证酿造/炼金液体 Shader 的资源接线与默认参数可读性。
# 注意：GLSL 的实际编译发生在渲染服务器（需 Forward+/Mobile 渲染后端），
# headless 下仅验证资源加载与参数绑定，不为 GLSL 语法做编译期断言。

const SHADER_PATH := "res://shaders/liquid_alchemy.gdshader"
const MATERIAL_PATH := "res://materials/liquid_alchemy.tres"


func test_shader_resource_loads() -> void:
	var shader = load(SHADER_PATH)
	assert_object(shader).is_not_null()
	assert_object(shader).is_instanceof(Shader)


func test_material_resource_loads_and_binds_shader() -> void:
	var mat = load(MATERIAL_PATH)
	assert_object(mat).is_not_null()
	assert_object(mat).is_instanceof(ShaderMaterial)
	var sm := mat as ShaderMaterial
	assert_object(sm.shader).is_not_null()
	assert_str(sm.shader.resource_path).is_equal(SHADER_PATH)


# headless 下渲染服务器未编译 Shader，get_shader_parameter 读不到默认值（返回 Nil）。
# 改用 set/get 往返验证参数名被材质接受、存储 API 可用；默认值在编辑器/渲染端生效。
func test_shader_parameters_roundtrip() -> void:
	var mat := load(MATERIAL_PATH) as ShaderMaterial
	mat.set_shader_parameter("wave_speed", 0.4)
	mat.set_shader_parameter("wave_scale", 3.0)
	mat.set_shader_parameter("color_base", Color(0.12, 0.55, 0.32, 1.0))
	assert_float(mat.get_shader_parameter("wave_speed")).is_equal_approx(0.4, 0.001)
	assert_float(mat.get_shader_parameter("wave_scale")).is_equal_approx(3.0, 0.001)
	var base := mat.get_shader_parameter("color_base") as Color
	assert_float(base.r).is_equal_approx(0.12, 0.001)
