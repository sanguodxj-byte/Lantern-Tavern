class_name VoxelPalette
extends RefCounted

## 被击部位 → 体素颜色 查表。
## 用途："被击部位体素纹理相关"特效（voxel_chip 碎屑 / 火花）的颜色 = 该部位体素本色。
##
## 数据驱动：默认按部位大类给基色；材质大类（骨/甲/布/石/血）可覆盖；
## 每生物可用 CREATURE_OVERRIDES 微调（取自其 voxel GLB 的调色板基色）。

# 部位大类默认色（voxel 调色板基色，去 .L/.R 后缀匹配）
const DEFAULT_PART_COLORS := {
	"Head": Color(0.82, 0.66, 0.50),
	"Torso": Color(0.45, 0.50, 0.32),
	"UpperArm": Color(0.45, 0.50, 0.32),
	"LowerArm": Color(0.45, 0.50, 0.32),
	"Hand": Color(0.82, 0.66, 0.50),
	"UpperLeg": Color(0.40, 0.42, 0.50),
	"LowerLeg": Color(0.40, 0.42, 0.50),
	"Foot": Color(0.30, 0.25, 0.20),
}

# 材质大类（覆盖部位）：用于按命中材质取色
const MATERIAL_COLORS := {
	"bone": Color(0.92, 0.90, 0.82),
	"armor": Color(0.60, 0.62, 0.68),
	"cloth": Color(0.50, 0.35, 0.25),
	"skin": Color(0.82, 0.66, 0.50),
	"metal": Color(0.70, 0.72, 0.78),
	"stone": Color(0.55, 0.55, 0.58),
	"blood": Color(0.70, 0.05, 0.05),
}

# 每生物覆盖（键=creature id，取自敌人节点名小写，如 "goblin"）
const CREATURE_OVERRIDES := {
	"goblin": {"skin": Color(0.30, 0.50, 0.20), "Head": Color(0.30, 0.50, 0.20), "Torso": Color(0.35, 0.45, 0.22)},
	"kobold": {"skin": Color(0.55, 0.45, 0.25), "Head": Color(0.55, 0.45, 0.25), "Torso": Color(0.45, 0.38, 0.22)},
	"skeleton": {"bone": Color(0.92, 0.90, 0.82), "Head": Color(0.92, 0.90, 0.82), "Torso": Color(0.88, 0.86, 0.78)},
	"zombie": {"skin": Color(0.45, 0.55, 0.35), "Head": Color(0.45, 0.55, 0.35), "Torso": Color(0.40, 0.48, 0.30)},
	"slime": {"skin": Color(0.30, 0.80, 0.55), "Head": Color(0.30, 0.80, 0.55), "Torso": Color(0.25, 0.70, 0.50)},
}

## 查询某生物某部位的体素颜色。
## material 非空时优先用材质大类色（如命中骨头→骨白，命中护甲→金属灰）。
static func color_for_part(creature_id: String, part_name: String, material: String = "") -> Color:
	if material != "" and MATERIAL_COLORS.has(material):
		return MATERIAL_COLORS[material]
	var ov: Dictionary = CREATURE_OVERRIDES.get(creature_id, {})
	if ov.has(part_name):
		return ov[part_name]
	var base := part_name.replace(".L", "").replace(".R", "")
	if ov.has(base):
		return ov[base]
	if DEFAULT_PART_COLORS.has(base):
		return DEFAULT_PART_COLORS[base]
	if DEFAULT_PART_COLORS.has(part_name):
		return DEFAULT_PART_COLORS[part_name]
	return Color(0.60, 0.60, 0.60)
