extends RefCounted
## 体素 `_rig.glb` 校验器。
##
## 在运行时 / 测试中实例化 GLB，读取 `Skeleton3D` 骨骼名与 `AnimationPlayer`
## 动画名，对照 `VoxelAnimationSpec` 校验是否齐全。
##
## 用法（测试）：
##   var report := VoxelRigValidator.validate_glb("res://assets/meshes/characters/voxel_goblin_32px_rig.glb", true)
##   assert_bool(report.ok).is_true()
##   assert_str(report.missing_animations[0]).is_equal("slash_one_hand")
##
## @see docs/18-体素骨骼动画工作流.md
## @see globals/visual/voxel_animation_spec.gd
##
## 注意：不声明 class_name，与 loot_table.gd / combat_engine.gd 一致，
## 通过 preload() 引用以兼容 gdUnit4 测试扫描器。

const SPEC := preload("res://globals/visual/voxel_animation_spec.gd")

# ============================================================================
# 校验结果
# ============================================================================
## 校验报告。ok=true 表示通过；否则 errors / missing_bones / missing_animations
## 列出具体缺失项，供断言定位。
class Report:
	var ok: bool = true
	var errors: Array[String] = []
	var missing_bones: Array[String] = []
	var missing_animations: Array[String] = []
	var bone_names: Array[String] = []
	var animation_names: Array[String] = []

	func _to_string() -> String:
		if ok:
			return "VoxelRigReport[OK] bones=%d anims=%d" % [bone_names.size(), animation_names.size()]
		var parts := ["VoxelRigReport[FAIL]"]
		if not errors.is_empty():
			parts.append("errors=%s" % str(errors))
		if not missing_bones.is_empty():
			parts.append("missing_bones=%s" % str(missing_bones))
		if not missing_animations.is_empty():
			parts.append("missing_anims=%s" % str(missing_animations))
		return ", ".join(parts)

# ============================================================================
# 校验入口
# ============================================================================

## 校验指定 GLB 路径。
## `is_humanoid`：true 校验人形骨骼+动画集；false 校验非人形动画集。
static func validate_glb(glb_path: String, is_humanoid: bool) -> Report:
	var report := Report.new()
	var packed := load(glb_path) as PackedScene
	if packed == null:
		report.ok = false
		report.errors.append("无法加载 GLB 场景: %s" % glb_path)
		return report
	var inst := packed.instantiate()
	if inst == null:
		report.ok = false
		report.errors.append("无法实例化 GLB: %s" % glb_path)
		return report
	# 纯 GLB 的 Skeleton3D 骨骼名与 AnimationPlayer 动画库在实例化时即已就绪，
	# 无需挂入场景树（避免 _ready() 副作用与树内时序问题）。
	var result := _validate_instance(inst, is_humanoid)
	# 合并实例级错误到顶层 report
	if result == null:
		report.ok = false
		report.errors.append("校验器内部错误：_validate_instance 返回 null")
		inst.free()
		return report
	if not result.errors.is_empty():
		report.errors.append_array(result.errors)
	# 无论成功失败都先收集数据再清理
	report.bone_names = result.bone_names
	report.animation_names = result.animation_names
	report.missing_bones = result.missing_bones
	report.missing_animations = result.missing_animations
	report.ok = result.ok
	inst.free()
	return report

## 校验已实例化的节点（调用方负责生命周期）。
static func _validate_instance(root: Node, is_humanoid: bool) -> Report:
	var report := Report.new()
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		report.ok = false
		report.errors.append("未找到 Skeleton3D 节点（非骨骼模型？）")
		return report
	# 收集骨骼名
	for i in skeleton.get_bone_count():
		report.bone_names.append(skeleton.get_bone_name(i))
	# 校验骨骼（仅人形）
	if is_humanoid:
		for bone in SPEC.HUMANOID_REQUIRED_BONES:
			if not report.bone_names.has(bone):
				report.missing_bones.append(bone)
		if not report.missing_bones.is_empty():
			report.ok = false
	# 收集动画名
	var ap := _find_animation_player(root)
	if ap == null:
		report.ok = false
		report.errors.append("未找到 AnimationPlayer 节点（无动画？）")
		return report
	for lib_name in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			# GLB 默认库动画名为裸名；非默认库为 "lib/anim"，取裸名
			var bare := anim_name.split("/")[-1]
			if not report.animation_names.has(bare):
				report.animation_names.append(bare)
	# 校验动画集
	var required := SPEC.humanoid_required_animations() if is_humanoid else SPEC.creature_required_animations()
	for anim in required:
		if not report.animation_names.has(anim):
			report.missing_animations.append(anim)
	if not report.missing_animations.is_empty():
		report.ok = false
	return report

# ============================================================================
# 节点查找工具
# ============================================================================

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

# ============================================================================
# 快捷校验（返回缺失项列表，便于断言）
# ============================================================================

## 仅返回缺失动画名列表（空 = 通过）。
static func missing_animations(glb_path: String, is_humanoid: bool) -> Array[String]:
	var report := validate_glb(glb_path, is_humanoid)
	return report.missing_animations

## 仅返回缺失骨骼名列表（空 = 通过）。
static func missing_bones(glb_path: String) -> Array[String]:
	var report := validate_glb(glb_path, true)
	return report.missing_bones
