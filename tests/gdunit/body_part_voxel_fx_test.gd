extends GdUnitTestSuite

## 被击部位体素纹理相关特效的单元覆盖：
##  - 体素调色板查表（生物覆盖 / 材质覆盖 / 默认回退）
##  - 最近骨骼解析（纯数组版，可单测）
##  - 由击退方向估计命中点（朝向攻击者一侧）
##  - voxel_chip 场景按部位色参数化

const VP := preload("res://globals/combat/voxel_palette.gd")
const BPR := preload("res://globals/combat/body_part_resolver.gd")
const VOXEL_CHIP_SCENE := preload("res://fx/voxel_chip.tscn")


func test_palette_creature_override() -> void:
	var c := VP.color_for_part("goblin", "Head")
	assert_bool(c.is_equal_approx(Color(0.3, 0.5, 0.2, 1.0))).is_true()


func test_palette_material_override() -> void:
	# 命中骨头 → 骨白，忽略部位
	var c := VP.color_for_part("anything", "Torso", "bone")
	assert_bool(c.is_equal_approx(Color(0.92, 0.90, 0.82, 1.0))).is_true()


func test_palette_default_fallback() -> void:
	var c := VP.color_for_part("unknown_creature", "UpperLeg")
	assert_bool(c.is_equal_approx(Color(0.40, 0.42, 0.50, 1.0))).is_true()


func test_palette_strips_lr_suffix() -> void:
	# UpperArm.R 应与 UpperArm 命中同一默认色
	var c := VP.color_for_part("unknown_creature", "UpperArm.R")
	assert_bool(c.is_equal_approx(Color(0.45, 0.50, 0.32, 1.0))).is_true()


func test_nearest_bone_from_picks_closest() -> void:
	var bones := [
		{"name": "Head", "pos": Vector3(0, 1.6, 0)},
		{"name": "Torso", "pos": Vector3(0, 1.0, 0)},
		{"name": "LowerLeg.R", "pos": Vector3(0, 0.2, 0)},
	]
	assert_str(BPR.nearest_bone_from(bones, Vector3(0.05, 1.55, 0))).is_equal("Head")
	assert_str(BPR.nearest_bone_from(bones, Vector3(0.0, 0.25, 0))).is_equal("LowerLeg.R")


func test_approx_hit_point_faces_attacker() -> void:
	# 击退方向(攻击者→敌人)指向 +Z，命中点应在敌人 -Z 侧、抬升到命中高度
	var hp := BPR.approx_hit_point(Vector3(0, 0, 0), Vector3(0, 0, 1), 0.4, 1.0)
	assert_float(hp.z).is_equal_approx(-0.4, 0.001)
	assert_float(hp.y).is_equal_approx(1.0, 0.001)


func test_voxel_chip_setup_applies_color() -> void:
	# 真实调用顺序：setup() 在 add_child 之前（fx_helper 如此），_ready 发射前已应用颜色
	var chip: Node3D = VOXEL_CHIP_SCENE.instantiate()
	var col := Color(0.3, 0.5, 0.2, 1.0)
	chip.call("setup", Vector3(1, 1, 1), col)
	var holder := Node.new()
	Engine.get_main_loop().root.add_child(holder)
	holder.add_child(chip)  # _ready 触发：应用已配置颜色后再发射
	var chips := chip.get_node_or_null("Chips") as GPUParticles3D
	assert_object(chips).is_not_null()
	assert_bool(chips.process_material.color.is_equal_approx(col)).is_true()
	holder.free()


func test_normalize_creature_id_strips_instance_suffix() -> void:
	assert_str(BPR.normalize_creature_id("Goblin")).is_equal("goblin")
	assert_str(BPR.normalize_creature_id("goblin_2")).is_equal("goblin")
	assert_str(BPR.normalize_creature_id("Goblin (2)")).is_equal("goblin")
	assert_str(BPR.normalize_creature_id("@Goblin@2")).is_equal("goblin")
	assert_str(BPR.normalize_creature_id("Kobold")).is_equal("kobold")
