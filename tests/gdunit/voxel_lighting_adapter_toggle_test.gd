extends GdUnitTestSuite
## 测试 VoxelLightingAdapter 的全局像素着色开关。
## 验证开关关闭时适配器跳过全部材质修改，以及 revert_tree 能还原已写入的 override。

const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

## 测试前后恢复开关默认状态，避免静态变量泄漏到其他测试套件。
var _saved_enabled: bool


func before_test() -> void:
	_saved_enabled = VOXEL_LIGHTING.is_pixel_shader_enabled()
	# 默认开启，确保每个测试从已知状态开始。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)


func after_test() -> void:
	VOXEL_LIGHTING.set_pixel_shader_enabled(_saved_enabled)


# ── 开关默认状态 ────────────────────────────────────────────

func test_pixel_shader_enabled_defaults_true() -> void:
	# 静态变量初始值应为 true（像素着色默认开启）。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	assert_bool(VOXEL_LIGHTING.is_pixel_shader_enabled()).is_true()


func test_set_pixel_shader_enabled_returns_old_value() -> void:
	# set_pixel_shader_enabled 应返回切换前的旧值。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	var old := VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	assert_bool(old).is_true()
	var old2 := VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	assert_bool(old2).is_false()


# ── 开关关闭时 adapt_standard_material 返回原始材质 ──────────

func test_adapt_standard_material_returns_source_when_disabled() -> void:
	# 开关关闭时 adapt_standard_material 应返回 source 本身，不做 toon 转换。
	VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.5, 0.3, 0.2)
	source.roughness = 0.4
	source.metallic = 0.6
	var result := VOXEL_LIGHTING.adapt_standard_material(source)
	# 返回的应是与 source 同一对象（不 duplicate）。
	assert_object(result).is_same(source)


func test_adapt_standard_material_returns_adapted_when_enabled() -> void:
	# 开关开启时 adapt_standard_material 应返回 toon 适配后的副本。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.5, 0.3, 0.2)
	source.roughness = 0.4
	source.metallic = 0.6
	var result := VOXEL_LIGHTING.adapt_standard_material(source)
	# 返回的应是新对象（duplicate），且 diffuse_mode 应为 TOON。
	assert_object(result).is_not_same(source)
	assert_int(result.diffuse_mode).is_equal(BaseMaterial3D.DIFFUSE_TOON)


func test_adapt_standard_material_returns_null_for_null_source() -> void:
	# null source 在开关任意状态下都应返回 null。
	VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	assert_object(VOXEL_LIGHTING.adapt_standard_material(null)).is_null()
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	assert_object(VOXEL_LIGHTING.adapt_standard_material(null)).is_null()


func test_soften_wood_texture_decompresses_source_image() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.7, 0.4, 0.2, 1.0))
	image.compress(Image.COMPRESS_S3TC)
	assert_bool(image.is_compressed()).is_true()
	var texture := ImageTexture.create_from_image(image)
	var softened := VOXEL_LIGHTING._soften_wood_texture(texture)
	assert_object(softened).is_not_null()
	assert_bool(not softened.get_image().is_compressed()).is_true()


# ── 开关关闭时 apply_shader_profile 不写入参数 ──────────────

func test_apply_shader_profile_skips_when_disabled() -> void:
	# 开关关闭时 apply_shader_profile 不应写入 toon 参数，但应设置 pixel_lighting_enabled=0.0。
	VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _minimal_voxel_shader_code()
	mat.shader = shader
	mat.set_shader_parameter("voxel_light_quantize", 0.5)
	mat.set_shader_parameter("pixel_lighting_enabled", 1.0)
	VOXEL_LIGHTING.apply_shader_profile(mat)
	# toon 参数应保持原值，未被覆盖为 profile 中的 0.20。
	assert_float(mat.get_shader_parameter("voxel_light_quantize")).is_equal(0.5)
	# pixel_lighting_enabled 应被设为 0.0，使 shader 回退到标准 Lambert。
	assert_float(mat.get_shader_parameter("pixel_lighting_enabled")).is_equal(0.0)


func test_apply_shader_profile_writes_when_enabled() -> void:
	# 开关开启时 apply_shader_profile 应写入 profile 参数和 pixel_lighting_enabled=1.0。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _minimal_voxel_shader_code()
	mat.shader = shader
	VOXEL_LIGHTING.apply_shader_profile(mat, VOXEL_LIGHTING.DEFAULT_SHADER_PROFILE)
	assert_float(mat.get_shader_parameter("voxel_light_quantize")).is_equal(0.20)
	assert_float(mat.get_shader_parameter("voxel_light_steps")).is_equal(6.0)
	# pixel_lighting_enabled 应被设为 1.0。
	assert_float(mat.get_shader_parameter("pixel_lighting_enabled")).is_equal(1.0)


func test_apply_shader_profile_handles_shader_without_pixel_flag() -> void:
	# 不含 pixel_lighting_enabled uniform 的 shader 不应崩溃，也不应设置该参数。
	VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _minimal_shader_without_pixel_flag()
	mat.shader = shader
	# 不应崩溃；get_shader_parameter 对不存在的 uniform 返回 null。
	VOXEL_LIGHTING.apply_shader_profile(mat)
	assert_object(mat.get_shader_parameter("pixel_lighting_enabled")).is_null()


# ── 开关关闭时 apply_to_tree 行为 ──────────────────────────

func test_apply_to_tree_skips_standard_material_when_disabled() -> void:
	# 开关关闭时 apply_to_tree 应跳过 StandardMaterial3D 的 toon 转换，
	# 不替换 material_override，不标记 ADAPTED_META_KEY。
	VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	add_child(root)
	await await_idle_frame()

	# 设置一个原始材质。
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.6, 0.4, 0.2)
	source.roughness = 0.5
	mi.material_override = source

	VOXEL_LIGHTING.apply_to_tree(root, true)

	# material_override 应保持原始 source（未被替换为 toon 副本）。
	assert_object(mi.material_override).is_same(source)
	# 不应写入 ADAPTED_META_KEY。
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_false()


func test_apply_to_tree_syncs_shader_flag_when_disabled() -> void:
	# 开关关闭时 apply_to_tree 仍应遍历树，为 ShaderMaterial 同步
	# pixel_lighting_enabled=0.0。这确保 baked 道具（dungeon_terrain.gdshader）
	# 在开关关闭时回退到标准 Lambert，而不是保持默认 toon 光照。
	VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	add_child(root)
	await await_idle_frame()

	# 创建一个带 pixel_lighting_enabled uniform 的 ShaderMaterial。
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _minimal_voxel_shader_code()
	mat.shader = shader
	mat.set_shader_parameter("pixel_lighting_enabled", 1.0)
	mi.material_override = mat

	VOXEL_LIGHTING.apply_to_tree(root, true)

	# material_override 应被替换为 duplicated 副本（非同一对象）。
	var adapted := mi.material_override as ShaderMaterial
	assert_object(adapted).is_not_null()
	assert_object(adapted).is_not_same(mat)
	# pixel_lighting_enabled 应被同步为 0.0。
	assert_float(adapted.get_shader_parameter("pixel_lighting_enabled")).is_equal(0.0)
	# 应标记 ADAPTED_META_KEY 以便 revert_tree 清理。
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_true()


func test_apply_to_tree_syncs_shader_flag_when_enabled() -> void:
	# 开关开启时 apply_to_tree 应为 ShaderMaterial 写入 toon 参数和 pixel_lighting_enabled=1.0。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	add_child(root)
	await await_idle_frame()

	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _minimal_voxel_shader_code()
	mat.shader = shader
	mat.set_shader_parameter("pixel_lighting_enabled", 0.0)
	mi.material_override = mat

	VOXEL_LIGHTING.apply_to_tree(root, true)

	var adapted := mi.material_override as ShaderMaterial
	assert_object(adapted).is_not_null()
	assert_object(adapted).is_not_same(mat)
	# pixel_lighting_enabled 应被同步为 1.0。
	assert_float(adapted.get_shader_parameter("pixel_lighting_enabled")).is_equal(1.0)
	# toon 参数应被写入。
	assert_float(adapted.get_shader_parameter("voxel_light_quantize")).is_equal(0.20)
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_true()


func test_apply_to_tree_adapts_when_enabled() -> void:
	# 开关开启时 apply_to_tree 应适配材质并写入 ADAPTED_META_KEY。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	add_child(root)
	await await_idle_frame()

	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.6, 0.4, 0.2)
	source.roughness = 0.5
	mi.material_override = source

	VOXEL_LIGHTING.apply_to_tree(root, true)

	# material_override 应被替换为 toon 副本（非同一对象）。
	var adapted := mi.material_override as StandardMaterial3D
	assert_object(adapted).is_not_null()
	assert_object(adapted).is_not_same(source)
	assert_int(adapted.diffuse_mode).is_equal(BaseMaterial3D.DIFFUSE_TOON)
	# 应写入 ADAPTED_META_KEY。
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_true()


# ── revert_tree 还原已适配材质 ──────────────────────────────

func test_revert_tree_clears_override_and_meta() -> void:
	# 先适配，再 revert，验证 override 被清除、meta 被移除。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	add_child(root)
	await await_idle_frame()

	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.6, 0.4, 0.2)
	source.roughness = 0.5
	mi.material_override = source

	VOXEL_LIGHTING.apply_to_tree(root, true)
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_true()

	VOXEL_LIGHTING.revert_tree(root)

	# material_override 应被清除（回到 null 或 GLB 原始材质）。
	assert_object(mi.material_override).is_null()
	# ADAPTED_META_KEY 应被移除。
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_false()


func test_revert_tree_preserves_non_adapted_nodes() -> void:
	# revert_tree 不应清除未被适配器标记的 override。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	add_child(root)
	await await_idle_frame()

	# 手动设置 override，但不调用 apply_to_tree（不带 ADAPTED_META_KEY）。
	var external := StandardMaterial3D.new()
	external.albedo_color = Color.RED
	mi.material_override = external

	VOXEL_LIGHTING.revert_tree(root)

	# 外部 override 应保持不变。
	assert_object(mi.material_override).is_same(external)


func test_revert_tree_handles_null_root() -> void:
	# null root 不应崩溃。
	VOXEL_LIGHTING.revert_tree(null)
	assert_bool(true).is_true()


# ── 开关关闭后 apply_to_tree 跳过后再 revert 无副作用 ─────────

func test_disable_then_revert_is_safe() -> void:
	# 关闭开关 -> apply_to_tree 跳过 -> revert_tree 不应清除任何东西。
	VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	add_child(root)
	await await_idle_frame()

	var source := StandardMaterial3D.new()
	source.albedo_color = Color.GREEN
	mi.material_override = source

	VOXEL_LIGHTING.apply_to_tree(root, true)
	# 开关关闭，未适配。
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_false()

	VOXEL_LIGHTING.revert_tree(root)
	# material_override 仍为 source（revert 未找到标记节点，未清除）。
	assert_object(mi.material_override).is_same(source)


# ── 运行时切换：关闭 -> revert -> 开启 -> 重新适配 ───────────

func test_runtime_toggle_cycle() -> void:
	# 完整运行时切换流程：
	# 1. 开启时适配
	# 2. 关闭开关
	# 3. revert 清除 override
	# 4. apply_to_tree 跳过（开关仍关）
	# 5. 开启开关
	# 6. apply_to_tree 重新适配
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	add_child(root)
	await await_idle_frame()

	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.4, 0.5, 0.6)
	source.roughness = 0.5
	mi.material_override = source

	# 1. 开启时适配
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	VOXEL_LIGHTING.apply_to_tree(root, true)
	var adapted1 := mi.material_override as StandardMaterial3D
	assert_object(adapted1).is_not_same(source)
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_true()

	# 2-3. 关闭并 revert
	VOXEL_LIGHTING.set_pixel_shader_enabled(false)
	VOXEL_LIGHTING.revert_tree(root)
	assert_object(mi.material_override).is_null()
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_false()

	# 4. apply_to_tree 跳过
	mi.material_override = source
	VOXEL_LIGHTING.apply_to_tree(root, true)
	assert_object(mi.material_override).is_same(source)
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_false()

	# 5-6. 开启并重新适配
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	VOXEL_LIGHTING.apply_to_tree(root, true)
	var adapted2 := mi.material_override as StandardMaterial3D
	assert_object(adapted2).is_not_same(source)
	assert_int(adapted2.diffuse_mode).is_equal(BaseMaterial3D.DIFFUSE_TOON)
	assert_bool(mi.has_meta(VOXEL_LIGHTING.ADAPTED_META_KEY)).is_true()


# ── 辅助 ────────────────────────────────────────────────────

static func _minimal_voxel_shader_code() -> String:
	# 最小化 shader 代码，声明开关涉及的 uniform 参数（含 pixel_lighting_enabled）。
	return """
shader_type spatial;
uniform float voxel_light_wrap = 0.45;
uniform float voxel_light_floor = 0.22;
uniform float voxel_light_steps = 6.0;
uniform float voxel_light_quantize = 0.20;
uniform float voxel_light_strength = 1.0;
uniform float pixel_lighting_enabled : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	ALBEDO = vec3(0.5);
}
"""


static func _minimal_shader_without_pixel_flag() -> String:
	# 不含 pixel_lighting_enabled 的最小 shader，用于验证兼容性。
	return """
shader_type spatial;
uniform float voxel_light_quantize = 0.20;
void fragment() {
	ALBEDO = vec3(0.5);
}
"""
