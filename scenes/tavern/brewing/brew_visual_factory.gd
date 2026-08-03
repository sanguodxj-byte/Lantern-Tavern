class_name BrewVisualFactory
extends RefCounted
## 3D 酿酒流程视觉工厂：为手持物品/酿酒装置构建体素与粒子视觉。
## 复用项目现有体素道具（barrel/bucket/tankard/brew_cauldron）、材料 GLB 模型与
## fire_flame_particle 粒子 Shader；不引入新插件或外部资源。

const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const FIRE_SHADER := preload("res://shaders/fire_flame_particle.gdshader")
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")

# ============================================================================
# 1. 原料视觉（材料 GLB 模型，缺失时回退为彩色体素盒）
# ============================================================================

static func make_material_visual(material_id: String) -> Node3D:
	var glb_path := MATERIAL_MODELS.get_model_path(material_id)
	if glb_path.is_empty():
		glb_path = "res://assets/models/materials/materials_%s.glb" % material_id
	var root := Node3D.new()
	root.name = "IngredientVisual_%s" % material_id
	var visual: Node3D = null
	if ResourceLoader.exists(glb_path):
		var packed := load(glb_path) as PackedScene
		if packed != null:
			visual = packed.instantiate() as Node3D
	if visual != null:
		root.add_child(visual)
	else:
		var mi := MeshInstance3D.new()
		mi.name = "FallbackBox"
		var box := BoxMesh.new()
		var entry := MATERIAL_MODELS.get_entry(material_id)
		var bbox: Array = entry.get("bbox", [0.2, 0.2, 0.2])
		if bbox.size() >= 3:
			box.size = Vector3(
				maxf(float(bbox[0]), 0.05), maxf(float(bbox[1]), 0.05), maxf(float(bbox[2]), 0.05))
		else:
			box.size = Vector3(0.2, 0.2, 0.2)
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _material_highlight_color(material_id)
		mat.vertex_color_use_as_albedo = true
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mi.material_override = mat
		root.add_child(mi)
	root.position += MATERIAL_MODELS.get_visual_offset(material_id)
	root.rotation_degrees = MATERIAL_MODELS.get_visual_rotation_degrees(material_id)
	VOXEL_LIGHTING.apply_to_tree(root, true)
	return root


static func _material_highlight_color(id: String) -> Color:
	var lower_id := id.to_lower()
	if "glowcap" in lower_id:
		return Color(0.1, 0.5, 1.0)
	if "berry" in lower_id:
		return Color(0.9, 0.1, 0.2)
	if "bloom" in lower_id:
		return Color(1.0, 0.3, 0.0)
	if "lichen" in lower_id or "moss" in lower_id:
		return Color(0.3, 0.6, 0.4)
	if "honeycomb" in lower_id or "sap" in lower_id:
		return Color(1.0, 0.7, 0.1)
	if "grass" in lower_id or "fern" in lower_id or "mint" in lower_id or "moon" in lower_id:
		return Color(0.4, 0.8, 0.2)
	if "ear" in lower_id or "root" in lower_id or "rye" in lower_id or "malt" in lower_id:
		return Color(0.5, 0.45, 0.35)
	if "sac" in lower_id or "mushroom" in lower_id or "fungus" in lower_id:
		return Color(0.6, 0.1, 0.7)
	if "jelly" in lower_id:
		return Color(0.2, 0.8, 0.5)
	if "bone" in lower_id or "shard" in lower_id or "ash" in lower_id or "dust" in lower_id or "crystal" in lower_id or "quartz" in lower_id:
		return Color(0.85, 0.85, 0.9)
	if "blood" in lower_id or "pepper" in lower_id or "sulfur" in lower_id:
		return Color(0.9, 0.25, 0.1)
	if "tear" in lower_id:
		return Color(0.5, 0.75, 1.0)
	return Color(0.8, 0.6, 0.2)

# ============================================================================
# 2. 体素道具视觉（禁物理：layer=0，不参与选择射线/实体碰撞）
# ============================================================================

static func make_voxel_prop(prop_kind: String) -> VoxelProp:
	var prop := VoxelProp.new()
	prop.name = "Visual_%s" % prop_kind
	prop.prop_kind = prop_kind
	prop.collision_layer = 0
	prop.collision_mask = 0
	return prop

# ============================================================================
# 3. 粒子与光照
# ============================================================================

## 蒸汽粒子：复用像素火焰 Shader，改为冷白灰配色，缓慢上升。
static func make_steam_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SteamParticles"
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.amount = 24
	particles.lifetime = 2.2
	particles.explosiveness = 0.35
	particles.randomness = 0.7
	particles.fixed_fps = 12
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.08
	proc.gravity = Vector3(0, -0.35, 0)
	proc.initial_velocity_min = 0.2
	proc.initial_velocity_max = 0.45
	proc.scale_min = 0.12
	proc.scale_max = 0.2
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 0.4))
	scale_curve.add_point(Vector2(0.6, 1.0))
	scale_curve.add_point(Vector2(1, 0.15))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex
	particles.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.24)
	var mat := ShaderMaterial.new()
	mat.shader = FIRE_SHADER
	mat.set_shader_parameter("color_core", Color(0.88, 0.89, 0.92))
	mat.set_shader_parameter("color_mid", Color(0.72, 0.74, 0.78))
	mat.set_shader_parameter("color_edge", Color(0.55, 0.58, 0.63))
	mat.set_shader_parameter("intensity", 0.7)
	mat.set_shader_parameter("ember_strength", 0.0)
	mat.set_shader_parameter("turbulence", 1.4)
	mat.set_shader_parameter("pixel_grid", 8.0)
	mat.set_shader_parameter("color_steps", 3.0)
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.emitting = false
	return particles


## 炉膛火焰粒子：与火把同源的像素火焰。
static func make_fire_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "FireParticles"
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.amount = 18
	particles.lifetime = 1.2
	particles.explosiveness = 0.2
	particles.randomness = 0.6
	particles.fixed_fps = 15
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.07
	proc.gravity = Vector3(0, 1, 0)
	proc.scale_min = 0.1
	proc.scale_max = 0.2
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 0.5))
	scale_curve.add_point(Vector2(0.55, 1.0))
	scale_curve.add_point(Vector2(1, 0.25))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex
	particles.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	var mat := ShaderMaterial.new()
	mat.shader = FIRE_SHADER
	mat.set_shader_parameter("intensity", 1.5)
	mat.set_shader_parameter("pixel_grid", 10.0)
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.emitting = false
	return particles


## 炉膛暖光（预算友好：单盏点光）。
static func make_fire_light() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = Color(1.0, 0.72, 0.42)
	light.light_energy = 0.9
	light.omni_range = 5.0
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	VOXEL_LIGHTING.disable_light_specular(light)
	light.visible = false
	return light


## 半透明液体盒（炼药锅麦汁/酒桶液面）。
static func make_liquid_box(width: float, height: float, depth: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 站台状态标签（炼药锅进度 / 桶位状态）。
static func make_status_label(text: String = "") -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 26
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.modulate = Color(1.0, 0.95, 0.72)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.visible = not text.is_empty()
	return label
