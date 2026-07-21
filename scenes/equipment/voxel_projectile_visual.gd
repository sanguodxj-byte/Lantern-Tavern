class_name VoxelProjectileVisual
extends Node3D
## 体素投射物视觉模型。
## 根据投射物类型（arrow / bolt）程序化生成体素盒网格。
##
## 比例尺：1m = 32px，1px = 1/32m = 0.03125m（遵循 docs/17-体素建模工作流.md）。
## 箭头朝向 -Z（飞行方向），箭羽/箭尾在 +Z 端。
## 所有体素盒通过面接触组成单一附着组件，无正体积重叠。

const PX := 1.0 / 32.0  # 1px = 1/32m

## 投射物类型：arrow（长弓箭矢）/ bolt（弩箭）
@export var projectile_kind: String = "arrow"

## 共享材质缓存——按 color+metallic+roughness 复用，避免每次生成创建新材质
static var _mat_cache: Dictionary = {}


func _ready() -> void:
	_build()


## 程序化构建体素盒网格
func _build() -> void:
	for child in get_children():
		child.free()

	var boxes: Array[Dictionary] = []
	match projectile_kind:
		"bolt":
			boxes = _bolt_boxes()
		_:
			boxes = _arrow_boxes()

	for box in boxes:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = box.size
		mi.mesh = mesh
		mi.position = box.pos
		mi.name = box.name
		mi.material_override = _get_material(box.color, box.metallic, box.roughness)
		add_child(mi)


# ============================================================================
# 体素盒定义
# ============================================================================

## 体素箭矢盒定义（24px = 0.75m，箭头朝 -Z）
##
## 像素尺寸表：
##   ArrowheadTip   1×1×2  Z=-11  钢高光
##   ArrowheadMid   3×3×2  Z=-9   钢中色
##   ArrowheadBase  3×3×2  Z=-7   钢阴影
##   Shaft          1×1×12 Z=0    木质
##   FletchingInner 1×1×2  Z=+7   羽毛亮
##   FletchingOuter 3×3×2  Z=+9   羽毛暗
##   Nock           1×1×2  Z=+11  深木
##
## 附着链：Tip→Mid→Base→Shaft→FletchingInner→FletchingOuter→Nock
## 每段之间为面接触（Z 轴相邻面贴合），无正体积重叠。
static func _arrow_boxes() -> Array[Dictionary]:
	return [
		# 箭头尖端 (1×1×2, Z=-11px)
		{
			"name": "ArrowheadTip",
			"size": Vector3(PX, PX, 2 * PX),
			"pos": Vector3(0, 0, -11 * PX),
			"color": Color(0.86, 0.95, 0.98),
			"metallic": 0.8,
			"roughness": 0.25,
		},
		# 箭头中段 (3×3×2, Z=-9px)
		{
			"name": "ArrowheadMid",
			"size": Vector3(3 * PX, 3 * PX, 2 * PX),
			"pos": Vector3(0, 0, -9 * PX),
			"color": Color(0.62, 0.69, 0.73),
			"metallic": 0.8,
			"roughness": 0.30,
		},
		# 箭头根部 (3×3×2, Z=-7px)
		{
			"name": "ArrowheadBase",
			"size": Vector3(3 * PX, 3 * PX, 2 * PX),
			"pos": Vector3(0, 0, -7 * PX),
			"color": Color(0.42, 0.48, 0.53),
			"metallic": 0.8,
			"roughness": 0.35,
		},
		# 箭杆 (1×1×12, Z=0px)
		{
			"name": "Shaft",
			"size": Vector3(PX, PX, 12 * PX),
			"pos": Vector3(0, 0, 0),
			"color": Color(0.55, 0.35, 0.18),
			"metallic": 0.0,
			"roughness": 0.85,
		},
		# 箭羽内段 (1×1×2, Z=+7px) — 连接箭杆与外段羽翼
		{
			"name": "FletchingInner",
			"size": Vector3(PX, PX, 2 * PX),
			"pos": Vector3(0, 0, 7 * PX),
			"color": Color(0.92, 0.90, 0.85),
			"metallic": 0.0,
			"roughness": 0.90,
		},
		# 箭羽外段 (3×3×2, Z=+9px) — 展开的羽翼
		{
			"name": "FletchingOuter",
			"size": Vector3(3 * PX, 3 * PX, 2 * PX),
			"pos": Vector3(0, 0, 9 * PX),
			"color": Color(0.75, 0.72, 0.68),
			"metallic": 0.0,
			"roughness": 0.90,
		},
		# 箭尾扣 (1×1×2, Z=+11px)
		{
			"name": "Nock",
			"size": Vector3(PX, PX, 2 * PX),
			"pos": Vector3(0, 0, 11 * PX),
			"color": Color(0.35, 0.22, 0.10),
			"metallic": 0.0,
			"roughness": 0.85,
		},
	]


## 体素弩箭盒定义（18px = 0.5625m，箭头朝 -Z）
##
## 像素尺寸表：
##   BoltTip   1×1×2  Z=-8   钢高光
##   BoltMid   3×3×2  Z=-6   钢中色
##   BoltBase  5×3×2  Z=-4   钢阴影（更宽的弩箭头）
##   Shaft     1×1×8  Z=+1   木质
##   Fletching 3×3×2  Z=+6   羽毛暗
##   Nock      1×1×2  Z=+8   深木
##
## 附着链：Tip→Mid→Base→Shaft→Fletching→Nock
## 每段之间为面接触（Z 轴相邻面贴合），无正体积重叠。
static func _bolt_boxes() -> Array[Dictionary]:
	return [
		# 弩箭尖端 (1×1×2, Z=-8px)
		{
			"name": "BoltTip",
			"size": Vector3(PX, PX, 2 * PX),
			"pos": Vector3(0, 0, -8 * PX),
			"color": Color(0.86, 0.95, 0.98),
			"metallic": 0.8,
			"roughness": 0.25,
		},
		# 弩箭中段 (3×3×2, Z=-6px)
		{
			"name": "BoltMid",
			"size": Vector3(3 * PX, 3 * PX, 2 * PX),
			"pos": Vector3(0, 0, -6 * PX),
			"color": Color(0.62, 0.69, 0.73),
			"metallic": 0.8,
			"roughness": 0.30,
		},
		# 弩箭根部 (5×3×2, Z=-4px) — 更宽的箭头，区别于普通箭矢
		{
			"name": "BoltBase",
			"size": Vector3(5 * PX, 3 * PX, 2 * PX),
			"pos": Vector3(0, 0, -4 * PX),
			"color": Color(0.42, 0.48, 0.53),
			"metallic": 0.8,
			"roughness": 0.35,
		},
		# 箭杆 (1×1×8, Z=+1px)
		{
			"name": "Shaft",
			"size": Vector3(PX, PX, 8 * PX),
			"pos": Vector3(0, 0, 1 * PX),
			"color": Color(0.55, 0.35, 0.18),
			"metallic": 0.0,
			"roughness": 0.85,
		},
		# 箭羽 (3×3×2, Z=+6px)
		{
			"name": "Fletching",
			"size": Vector3(3 * PX, 3 * PX, 2 * PX),
			"pos": Vector3(0, 0, 6 * PX),
			"color": Color(0.75, 0.72, 0.68),
			"metallic": 0.0,
			"roughness": 0.90,
		},
		# 箭尾扣 (1×1×2, Z=+8px)
		{
			"name": "Nock",
			"size": Vector3(PX, PX, 2 * PX),
			"pos": Vector3(0, 0, 8 * PX),
			"color": Color(0.35, 0.22, 0.10),
			"metallic": 0.0,
			"roughness": 0.85,
		},
	]


# ============================================================================
# 材质缓存
# ============================================================================

## 获取共享的 StandardMaterial3D（toon 着色），按 color+metallic+roughness 复用
static func _get_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [color.to_html(), metallic, roughness]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mat_cache[key] = mat
	return mat
