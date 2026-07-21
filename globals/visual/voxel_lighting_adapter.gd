class_name VoxelLightingAdapter
extends RefCounted
## 体素模型受光适配器。
## 将导入 GLB 的 StandardMaterial3D 调成 toon 风格；
## 角色/道具路径压低金属高光，武器路径保留金属/木柄对比。
## 将项目共用体素 ShaderMaterial 写入半兰伯特/量化光照参数。

const SHADER_PARAM_WRAP := "voxel_light_wrap"
const SHADER_PARAM_FLOOR := "voxel_light_floor"
const SHADER_PARAM_STEPS := "voxel_light_steps"
const SHADER_PARAM_QUANTIZE := "voxel_light_quantize"
const SHADER_PARAM_STRENGTH := "voxel_light_strength"

## 适配模式
const MODE_DEFAULT := "default"  ## 角色/道具：无金属、高 roughness
const MODE_WEAPON := "weapon"    ## 武器/盾：保留金属与木/皮对比

const DEFAULT_SHADER_PROFILE := {
	"voxel_light_wrap": 0.45,
	"voxel_light_floor": 0.22,
	"voxel_light_steps": 6.0,
	"voxel_light_quantize": 0.20,
	"voxel_light_strength": 1.0,
}

const PROP_SHADER_PROFILE := {
	"voxel_light_wrap": 0.58,
	"voxel_light_floor": 0.30,
	"voxel_light_steps": 4.0,
	"voxel_light_quantize": 0.85,
	"voxel_light_strength": 1.0,
}

## 武器金属材质下限/上限（toon 下仍能读出金属块面）
const WEAPON_METAL_ROUGHNESS_MIN := 0.18
const WEAPON_METAL_ROUGHNESS_MAX := 0.55
const WEAPON_METAL_THRESHOLD := 0.25
const WEAPON_EMISSIVE_ROUGHNESS_MIN := 0.18
const WEAPON_EMISSIVE_ROUGHNESS_MAX := 0.45
const MATERIAL_TIERS := ["wood", "iron", "steel", "meteoric", "mithril", "adamantite"]
const WOOD_TEXTURE_PRESERVE := 0.48
const METAL_FINISH_TEXTURE_SIZE := 32
const METAL_NORMAL_SCALE := 0.35

## 共享适配结果缓存：避免每次装备/拾取都 duplicate 同一 GLB 材质。
## key = "mode|source_id|albedo|metallic|roughness|has_tex"
static var _adapt_cache: Dictionary = {}
static var _metal_finish_texture_cache: Dictionary = {}
static var _cache_hits: int = 0
static var _cache_misses: int = 0


static func apply_to_tree(
	root: Node,
	force: bool = false,
	shader_profile: Dictionary = DEFAULT_SHADER_PROFILE,
	mode: String = MODE_DEFAULT,
	material_tier: String = "",
) -> void:
	if root == null:
		return
	# headless 模式下跳过材质适配：S3TC 纹理无法在无 GPU 环境加载，
	# duplicate() 操作可能引发段错误。
	if OS.has_feature("headless"):
		return
	var should_apply := force or _looks_like_voxel(root) or mode == MODE_WEAPON
	_apply_node(root, should_apply, shader_profile, mode, material_tier)


static func apply_weapon_tree(root: Node, material_tier: String = "") -> void:
	## 武器/盾专用入口：保留金属与握把材质对比。
	apply_to_tree(root, true, DEFAULT_SHADER_PROFILE, MODE_WEAPON, material_tier)


static func apply_shader_profile(material: ShaderMaterial, shader_profile: Dictionary = DEFAULT_SHADER_PROFILE) -> void:
	if material == null:
		return
	for key in shader_profile.keys():
		material.set_shader_parameter(String(key), shader_profile[key])


static func adapt_standard_material(
	source: StandardMaterial3D,
	mode: String = MODE_DEFAULT,
	material_tier: String = "",
) -> StandardMaterial3D:
	if source == null:
		return null
	var cache_key := _cache_key(source, mode, material_tier)
	if _adapt_cache.has(cache_key):
		_cache_hits += 1
		return _adapt_cache[cache_key] as StandardMaterial3D
	_cache_misses += 1

	var copy := source.duplicate() as StandardMaterial3D
	copy.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	# 保留 GLB 材质原始的 vertex_color_use_as_albedo 设置。
	# 强制设为 true 会把依赖 albedo_color / albedo_texture 的材质变成白色。

	if mode == MODE_WEAPON:
		_adapt_weapon_standard(copy, source, material_tier)
	else:
		_adapt_default_standard(copy)

	_adapt_cache[cache_key] = copy
	return copy


static func clear_cache() -> void:
	_adapt_cache.clear()
	_metal_finish_texture_cache.clear()
	_cache_hits = 0
	_cache_misses = 0


static func get_cache_stats() -> Dictionary:
	return {
		"size": _adapt_cache.size(),
		"hits": _cache_hits,
		"misses": _cache_misses,
	}


static func _adapt_default_standard(copy: StandardMaterial3D) -> void:
	## 角色/道具：无金属高光、偏哑光体素块面。
	copy.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	copy.roughness = maxf(copy.roughness, 0.85)
	copy.metallic = 0.0


static func _adapt_weapon_standard(
	copy: StandardMaterial3D,
	source: StandardMaterial3D,
	material_tier: String = "",
) -> void:
	## 武器：金属保留 metallic + 可控 roughness；木/皮保持哑光。
	if source.emission_enabled:
		# 魔力晶体：保留 GLB 的贴图和发光，同时避免非金属分支把晶体压成哑光。
		copy.specular_mode = BaseMaterial3D.SPECULAR_TOON
		copy.metallic = 0.0
		copy.roughness = clampf(
			source.roughness,
			WEAPON_EMISSIVE_ROUGHNESS_MIN,
			WEAPON_EMISSIVE_ROUGHNESS_MAX,
		)
	else:
		var is_metal := _is_metal_material(source)
		if is_metal:
			# 金属：toon 漫反射 + soft 高光，避免变成塑料
			copy.specular_mode = BaseMaterial3D.SPECULAR_TOON
			copy.metallic = clampf(source.metallic, 0.55, 1.0)
			# 管线导出的钢约 0.25–0.4；夹到可读区间
			var r := source.roughness
			if r < WEAPON_METAL_ROUGHNESS_MIN:
				r = WEAPON_METAL_ROUGHNESS_MIN
			elif r > WEAPON_METAL_ROUGHNESS_MAX:
				r = WEAPON_METAL_ROUGHNESS_MAX
			copy.roughness = r
			# 略提亮钢面，避免地牢暗光下刀刃发黑
			copy.albedo_color = Color(
				minf(copy.albedo_color.r * 1.06, 1.0),
				minf(copy.albedo_color.g * 1.06, 1.0),
				minf(copy.albedo_color.b * 1.08, 1.0),
				copy.albedo_color.a
			)
		else:
			# 握把/木/皮：哑光体素
			copy.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			copy.metallic = 0.0
			copy.roughness = maxf(source.roughness, 0.75)
	_apply_material_tier_variant(copy, source, material_tier)


static func _apply_material_tier_variant(
	copy: StandardMaterial3D,
	source: StandardMaterial3D,
	material_tier: String,
) -> void:
	var tier := material_tier.to_lower()
	if not MATERIAL_TIERS.has(tier):
		return
	# 盾牌 GLB 的 shield_material_* 名称同时包含木板、皮握把和原生金属硬件；
	# 只有 wood_* 是木面，铁/钢/陨铁/秘银/精金件必须保留为硬件，
	# 否则木盾会被整张刷成同一块木色，正背面也失去结构层次。
	# 魔力晶体和符文颜色是武器身份的一部分，不被材质阶梯抹平。
	var material_name := _material_name(source)
	if source.emission_enabled or material_name.contains("magic") or material_name.contains("rune"):
		return
	var is_shield_embedded := material_name.contains("shield_material_")
	var is_shield_wood_source := material_name.contains("shield_material_wood_")
	var is_shield_hardware := is_shield_embedded and not is_shield_wood_source
	var is_named_wood_source := (
		material_name.contains("wood")
		or material_name.contains("oak")
		or material_name.contains("walnut")
		or material_name.contains("endgrain")
		or material_name.contains("ash")
		or material_name.contains("parchment")
		or material_name.contains("grimoire_leather")
	)
	var is_staff_textured_body := material_name.contains("staff_oak_") or material_name.contains("staff_wine_leather")
	var is_wood_surface := is_shield_wood_source or is_named_wood_source or is_staff_textured_body
	var is_wood_tier_surface := tier == "wood" and is_wood_surface
	if is_shield_hardware and tier == "wood":
		# 木盾仍然要有铁钉、边框和背带等原生硬件；只让木面受 WeaponData 的木档控制。
		return
	var palette := _material_palette(tier)
	var source_luma := clampf(
		source.albedo_color.r * 0.30 + source.albedo_color.g * 0.59 + source.albedo_color.b * 0.11,
		0.78,
		1.25,
	)
	source_luma = clampf(source_luma * _surface_tone_factor(material_name), 0.38, 1.25)
	# 木质主体（包括弩的 walnut/endgrain、斧/矛的 ash、盾牌木面和法杖主体）
	# 在木档保留压低对比度的木纹；升级后切换到带细微锻造纹理的金属表面，
	# 避免精金/秘银只是“换色木头”或纯色块。
	var is_metal_upgrade := is_wood_surface and tier != "wood"
	var is_metal := (not is_wood_surface and _is_metal_material(source)) or is_metal_upgrade
	if is_wood_tier_surface:
		copy.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		copy.metallic = 0.0
		copy.roughness = maxf(copy.roughness, 0.82)
		copy.albedo_texture = _soften_wood_texture(source.albedo_texture)
		copy.vertex_color_use_as_albedo = false
	if is_metal and tier != "wood":
		# 金属升级使用按真实表面逻辑绘制的 albedo / roughness / normal 三张图，
		# 避免把单一灰度条纹误当作所有金属的材质。
		var finish_maps := _metal_finish_maps(tier, material_name)
		copy.albedo_texture = finish_maps["albedo"] as Texture2D
		copy.roughness_texture = finish_maps["roughness"] as Texture2D
		copy.normal_texture = finish_maps["normal"] as Texture2D
		copy.normal_scale = METAL_NORMAL_SCALE
		copy.vertex_color_use_as_albedo = false
	var tint: Color = palette["metal_color"] if is_metal else palette["organic_tint"]
	# 现有武器 GLB 经常带有深色贴图/顶点色；弱混合会让钢、秘银在地牢灯光下
	# 几乎不可分辨。提高有机材质的混合强度，同时保留 source_luma，避免抹平
	# 木纹、皮革和不同刀刃的明暗层次。
	var strength := 1.0 if is_metal else 0.72
	if tier == "meteoric" and is_metal:
		# 陨铁保持深色镍铁，不在黑色材质预览背景中沉到不可见。
		source_luma = maxf(source_luma, 0.90)
	if tier == "adamantite" and is_metal:
		source_luma = maxf(source_luma, 0.64)
	var blended := Color(
		lerpf(1.0, tint.r, strength) * source_luma,
		lerpf(1.0, tint.g, strength) * source_luma,
		lerpf(1.0, tint.b, strength) * source_luma,
		copy.albedo_color.a,
	)
	copy.albedo_color = Color(
		minf(blended.r, 1.0),
		minf(blended.g, 1.0),
		minf(blended.b, 1.0),
		blended.a,
	)
	if is_metal:
		copy.metallic = palette["metallic"]
		copy.roughness = clampf(
			palette["roughness"] + (1.0 - _surface_tone_factor(material_name)) * 0.10,
			WEAPON_METAL_ROUGHNESS_MIN,
			WEAPON_METAL_ROUGHNESS_MAX,
		)


static func _soften_wood_texture(source_texture: Texture2D) -> Texture2D:
	## 保留木纹方向与细节，只把过强的明暗/饱和度压回体素材质可读范围。
	if source_texture == null:
		return null
	var source_image := source_texture.get_image()
	if source_image == null or source_image.is_empty():
		return source_texture
	var softened := source_image.duplicate() as Image
	softened.convert(Image.FORMAT_RGBA8)
	var anchor := Color(0.48, 0.29, 0.14, 1.0)
	for y in range(softened.get_height()):
		for x in range(softened.get_width()):
			var pixel := softened.get_pixel(x, y)
			softened.set_pixel(x, y, Color(
				lerpf(anchor.r, pixel.r, WOOD_TEXTURE_PRESERVE),
				lerpf(anchor.g, pixel.g, WOOD_TEXTURE_PRESERVE),
				lerpf(anchor.b, pixel.b, WOOD_TEXTURE_PRESERVE),
				pixel.a,
			))
	return ImageTexture.create_from_image(softened)


static func _surface_tone_factor(material_name: String) -> float:
	## 高阶材质切换金属 finish 后，仍保留原模型的表面角色差异。
	## 这是通用材质命名约定，不绑定单个武器或模型注册表。
	if material_name.contains("grip") or material_name.contains("leather"):
		return 0.66
	if material_name.contains("shadow") or material_name.contains("dark"):
		return 0.72
	if material_name.contains("endgrain"):
		return 0.86
	if material_name.contains("edge") or material_name.contains("rim"):
		return 1.10
	if material_name.contains("mid"):
		return 0.95
	if material_name.contains("mithril"):
		return 1.12
	if material_name.contains("adamantite"):
		return 1.05
	if material_name.contains("meteoric"):
		return 0.92
	return 1.0


static func _metal_finish_maps(material_tier: String, material_name: String) -> Dictionary:
	## 以 PBR 逻辑生成可重复的像素材质：基色微差、粗糙度变化和微法线各司其职。
	var tier := material_tier.to_lower()
	var cache_key := tier + "|" + material_name
	if _metal_finish_texture_cache.has(cache_key):
		return _metal_finish_texture_cache[cache_key] as Dictionary
	var albedo_image := Image.create(
		METAL_FINISH_TEXTURE_SIZE,
		METAL_FINISH_TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8,
	)
	var roughness_image := Image.create(
		METAL_FINISH_TEXTURE_SIZE,
		METAL_FINISH_TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8,
	)
	var normal_image := Image.create(
		METAL_FINISH_TEXTURE_SIZE,
		METAL_FINISH_TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8,
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = tier.hash() ^ material_name.hash()
	var heights: Array[PackedFloat32Array] = []
	for y in range(METAL_FINISH_TEXTURE_SIZE):
		var row := PackedFloat32Array()
		row.resize(METAL_FINISH_TEXTURE_SIZE)
		heights.append(row)
	for y in range(METAL_FINISH_TEXTURE_SIZE):
		for x in range(METAL_FINISH_TEXTURE_SIZE):
			var xf := float(x)
			var yf := float(y)
			var pattern := 0.0
			var height := 0.0
			var roughness_delta := 0.0
			match tier:
				"iron":
					# 粗铁：锻打斑驳、凹坑和氧化暗斑，不形成均匀木纹。
					var mottling := sin(xf * 0.42 + sin(yf * 0.23)) * 0.52 + sin(yf * 0.67 + xf * 0.11) * 0.28
					var pit := rng.randf_range(-0.20, 0.20) if rng.randf() > 0.90 else 0.0
					pattern = mottling * 0.075 + pit
					height = mottling * 0.18 + pit * 0.40
					roughness_delta = absf(mottling) * 0.05 + absf(pit) * 0.12
				"steel":
					# 钢：沿加工方向的细拉丝，粗糙度随划痕轻微变化。
					var brush := sin(xf * 2.25 + sin(yf * 0.31) * 0.75) * 0.72 + sin(xf * 5.10 + yf * 0.12) * 0.18
					pattern = brush * 0.045
					height = brush * 0.10
					roughness_delta = absf(brush) * 0.06
				"meteoric":
					# 陨铁：参考 Widmanstätten 纹理，用两组交叉晶带取代紫色噪点。
					var crystal_a := absf(sin((xf * 0.84 + yf * 0.46) * 0.84 + 0.7))
					var crystal_b := absf(sin((xf * 0.72 - yf * 0.58) * 0.76 - 0.4))
					var crystal_band := 1.0 - clampf(minf(crystal_a, crystal_b) * 7.0, 0.0, 1.0)
					var inclusion := rng.randf_range(-0.13, 0.13) if rng.randf() > 0.93 else 0.0
					pattern = (crystal_band - 0.30) * 0.13 + inclusion
					height = crystal_band * 0.30 + inclusion * 0.35
					roughness_delta = crystal_band * -0.10 + absf(inclusion) * 0.12
				"mithril":
					# 秘银：高抛光银白底，只有细密冷色拉痕和少量高光。
					var polish := sin(xf * 3.60 + yf * 0.08) * 0.65 + sin(xf * 8.20 + yf * 0.15) * 0.16
					pattern = polish * 0.028
					height = polish * 0.06
					roughness_delta = polish * -0.025
				"adamantite":
					# 精金：宽阔的交错锻造面与锐利折线，不使用平行木纹。
					var facet_a := absf(sin((xf + yf) * 0.42 + 0.35))
					var facet_b := absf(sin((xf - yf) * 0.31 - 0.25))
					var facet := (facet_a * 0.60 + facet_b * 0.40)
					var facet_edge := 1.0 - clampf(absf(facet - 0.50) * 5.0, 0.0, 1.0)
					pattern = (facet - 0.50) * 0.11 + facet_edge * 0.035
					height = (facet - 0.50) * 0.22 + facet_edge * 0.12
					roughness_delta = absf(facet - 0.50) * 0.07 - facet_edge * 0.07
				_:
					pattern = sin(xf * 0.90 + yf * 0.40) * 0.04
					height = pattern
			var luma := clampf(0.94 + pattern + rng.randf_range(-0.012, 0.012), 0.72, 1.04)
			var color_shift := Color(1.0, 1.0, 1.0, 1.0)
			if tier == "meteoric":
				color_shift = Color(0.98 + pattern * 0.25, 1.0 + pattern * 0.18, 1.02 + pattern * 0.12, 1.0)
			elif tier == "mithril":
				color_shift = Color(0.96 + pattern * 0.20, 1.0 + pattern * 0.12, 1.0 + pattern * 0.24, 1.0)
			elif tier == "adamantite":
				color_shift = Color(1.02 + pattern * 0.14, 0.98 + pattern * 0.10, 0.88 + pattern * 0.05, 1.0)
			albedo_image.set_pixel(x, y, Color(
				clampf(luma * color_shift.r, 0.0, 1.0),
				clampf(luma * color_shift.g, 0.0, 1.0),
				clampf(luma * color_shift.b, 0.0, 1.0),
				1.0,
			))
			var base_roughness := 0.45
			match tier:
				"iron": base_roughness = 0.52
				"steel": base_roughness = 0.30
				"meteoric": base_roughness = 0.40
				"mithril": base_roughness = 0.16
				"adamantite": base_roughness = 0.25
			var roughness := clampf(base_roughness + roughness_delta, 0.08, 0.72)
			roughness_image.set_pixel(x, y, Color(roughness, roughness, roughness, 1.0))
			heights[y][x] = height
	for y in range(METAL_FINISH_TEXTURE_SIZE):
		for x in range(METAL_FINISH_TEXTURE_SIZE):
			var left := heights[y][maxi(x - 1, 0)]
			var right := heights[y][mini(x + 1, METAL_FINISH_TEXTURE_SIZE - 1)]
			var up := heights[maxi(y - 1, 0)][x]
			var down := heights[mini(y + 1, METAL_FINISH_TEXTURE_SIZE - 1)][x]
			var normal := Vector3((left - right) * 0.8, (up - down) * 0.8, 1.0).normalized()
			normal_image.set_pixel(x, y, Color(
				normal.x * 0.5 + 0.5,
				normal.y * 0.5 + 0.5,
				normal.z * 0.5 + 0.5,
				1.0,
			))
	var maps := {
		"albedo": ImageTexture.create_from_image(albedo_image),
		"roughness": ImageTexture.create_from_image(roughness_image),
		"normal": ImageTexture.create_from_image(normal_image),
	}
	_metal_finish_texture_cache[cache_key] = maps
	return maps


static func _material_palette(material_tier: String) -> Dictionary:
	match material_tier:
		"wood":
			return {"metal_color": Color(0.20, 0.13, 0.08), "organic_tint": Color(0.56, 0.36, 0.18), "metallic": 0.58, "roughness": 0.50}
		"iron":
			return {"metal_color": Color(0.48, 0.50, 0.52), "organic_tint": Color(0.72, 0.68, 0.58), "metallic": 0.82, "roughness": 0.52}
		"steel":
			return {"metal_color": Color(0.65, 0.70, 0.74), "organic_tint": Color(0.46, 0.72, 0.96), "metallic": 0.92, "roughness": 0.30}
		"meteoric":
			return {"metal_color": Color(0.60, 0.68, 0.76), "organic_tint": Color(0.42, 0.30, 0.62), "metallic": 0.95, "roughness": 0.40}
		"mithril":
			return {"metal_color": Color(0.88, 0.92, 0.95), "organic_tint": Color(0.82, 1.0, 1.0), "metallic": 0.96, "roughness": 0.16}
		"adamantite":
			return {"metal_color": Color(0.92, 0.70, 0.30), "organic_tint": Color(0.84, 0.58, 0.20), "metallic": 0.94, "roughness": 0.25}
		_:
			return {"metal_color": Color(0.27, 0.30, 0.32), "organic_tint": Color.WHITE, "metallic": 0.74, "roughness": 0.48}


static func _material_name(source: StandardMaterial3D) -> String:
	var name := String(source.resource_name).to_lower()
	if name.is_empty() and source.resource_path != "":
		name = source.resource_path.get_file().to_lower()
	return name


static func _is_metal_material(source: StandardMaterial3D) -> bool:
	if source == null:
		return false
	if source.metallic >= WEAPON_METAL_THRESHOLD:
		return true
	var n := String(source.resource_name).to_lower()
	if n.is_empty() and source.resource_path != "":
		n = source.resource_path.get_file().to_lower()
	# Blender 导出后材质名可能是 steel / metal_bright / fittings / blade / head 等
	for token in ["metal", "steel", "iron", "bronze", "brass", "alloy", "silver", "mithril", "adamantite", "meteoric", "blade", "fittings", "head", "rim", "boss", "limb"]:
		if n.contains(token):
			return true
	return false


static func _cache_key(
	source: StandardMaterial3D,
	mode: String,
	material_tier: String = "",
) -> String:
	var tex_flag := 1 if source.albedo_texture != null else 0
	var path_or_name := source.resource_path if source.resource_path != "" else source.resource_name
	return "%s|%s|%s|%.3f|%.3f|%.3f|%.3f|%d" % [
		mode + "|" + material_tier.to_lower(),
		path_or_name,
		source.albedo_color.to_html(true),
		source.metallic,
		source.roughness,
		source.albedo_color.a,
		source.emission_energy_multiplier if source.emission_enabled else 0.0,
		tex_flag,
	]


static func _apply_node(
	node: Node,
	inherited_voxel: bool,
	shader_profile: Dictionary,
	mode: String,
	material_tier: String,
) -> void:
	var is_voxel := inherited_voxel or _looks_like_voxel(node) or mode == MODE_WEAPON
	if node is MeshInstance3D and is_voxel:
		_apply_mesh(node as MeshInstance3D, shader_profile, mode, material_tier)
	for child in node.get_children():
		_apply_node(child, is_voxel, shader_profile, mode, material_tier)


static func _apply_mesh(
	mesh_instance: MeshInstance3D,
	shader_profile: Dictionary,
	mode: String,
	material_tier: String,
) -> void:
	var override := _adapt_material(mesh_instance.material_override, shader_profile, mode, material_tier)
	if override != null:
		mesh_instance.material_override = override
	if mesh_instance.mesh == null:
		return
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var source := mesh_instance.get_surface_override_material(surface_index)
		if source == null:
			source = mesh_instance.mesh.surface_get_material(surface_index)
		var adapted := _adapt_material(source, shader_profile, mode, material_tier)
		if adapted != null:
			mesh_instance.set_surface_override_material(surface_index, adapted)


static func _adapt_material(
	source: Material,
	shader_profile: Dictionary,
	mode: String = MODE_DEFAULT,
	material_tier: String = "",
) -> Material:
	if source is ShaderMaterial:
		var shader_copy := source.duplicate() as ShaderMaterial
		apply_shader_profile(shader_copy, shader_profile)
		return shader_copy
	if source is StandardMaterial3D:
		return adapt_standard_material(source as StandardMaterial3D, mode, material_tier)
	# source 为 null 时不创建默认白色材质：保留网格无材质状态，
	# 避免给无材质的网格套上白色 StandardMaterial3D。
	return null


static func _looks_like_voxel(node: Node) -> bool:
	if node.has_meta("voxel_style") or node.has_meta("voxel_px_per_meter"):
		return true
	var name := String(node.name).to_lower()
	if name.contains("voxel"):
		return true
	if node.scene_file_path.to_lower().contains("voxel"):
		return true
	if node.get_script() != null and String(node.get_script().resource_path).to_lower().contains("voxel"):
		return true
	return false
