extends RefCounted
## 体素骨骼动画规格 —— 单一真相源。
##
## 定义体素模型 `_rig.glb` 必须包含的骨骼名与动画名。
## 每个模型的独立 Blender 生成器按此规格制作动画；Godot 运行时与
## `voxel_rig_validator.gd` 只校验导出的 GLB，不在运行时补写动画轨道。
##
## 目标：使体素模型 `_rig.glb` 的动画名集与 `character.glb` 对齐，
## 从而可直接替换场景中的 `character` 节点，而不会触发
## `CombatSlashAnimator` 的 `"slash"` 兜底（兜底会让所有武器攻击外观相同）。
##
## @see docs/18-体素骨骼动画工作流.md
## @see globals/combat/combat_slash_animator.gd
##
## 注意：不声明 class_name，与 loot_table.gd / combat_engine.gd 一致，
## 通过 preload() 引用以兼容 gdUnit4 测试扫描器。

# ============================================================================
# 比例尺（与 docs/17-体素建模工作流.md 一致：1m = 32px）
# ============================================================================
const METERS_PER_PIXEL := 1.0 / 32.0

# ============================================================================
# 人形模型必需骨骼
# ============================================================================
# 顺序与 tools/voxel_humanoid_rig.py 的 REFERENCE_BONES 一致。
# BoneAttachment3D 武器 / 盾挂点依赖 Hand.R / Hand.L，二者不可缺失。
#
# 注意：使用普通 Array 而非 PackedStringArray —— Godot 4.7 的 GDScript 解析器
# 不认为 PackedStringArray([...]) 构造调用是常量表达式，
# 而 [...] 数组字面量是合法的常量表达式。查询方法仍返回 PackedStringArray。
const HUMANOID_REQUIRED_BONES := [
	"Root", "Pelvis", "Torso", "Neck", "Head",
	"UpperArm.R", "LowerArm.R", "Hand.R",
	"UpperArm.L", "LowerArm.L", "Hand.L",
	"UpperLeg.R", "LowerLeg.R", "Foot.R",
	"UpperLeg.L", "LowerLeg.L", "Foot.L",
]

# 武器挂载骨骼（BoneAttachment3D.bone_name 使用）
const WEAPON_HAND_BONE := "Hand.R"
const SHIELD_HAND_BONE := "Hand.L"

# ============================================================================
# 动画名集
# ============================================================================

## 基础动作动画：移动 / 受击 / 死亡 / 拾取 / 投掷 / 踢 / 格挡。
const BASE_ANIMATIONS := [
	"idle",               # 待机
	"run",                # 奔跑
	"hurt",               # 受击
	"stunned",            # 眩晕
	"death",              # 死亡倒地（无布娃娃时的兜底）
	"kick",               # 踢击
	"lift",               # 举起家具
	"pickup",             # 拾取
	"throw_weapon",       # 投掷武器
	"throw_furniture",    # 投掷家具
	"block",              # 格挡
]

## 武器攻击动画：`CombatSlashAnimator.player_animation_name()` 的映射目标。
## 缺失任一时，`CombatSlashAnimator.play()` 会回退到 `"slash"`，
## 导致对应武器类型的攻击外观与通用挥砍完全相同。
const WEAPON_ATTACK_ANIMATIONS := [
	"slash",          # 通用挥砍兜底
	"slash_one_hand", # 单手武器（剑 / 斧 / 钉锤）
	"slash_heavy",    # 双手重武器（大剑 / 战锤）
	"slash_dagger",   # 匕首快速连斩
	"thrust_spear",   # 长矛突刺
	"bash_shield",    # 盾击
	"claw_swipe",     # 徒手爪击（无武器）
]

## 姿态动画（单帧 / 极短）。
## - `default`：零姿态 / rest pose，所有骨骼归零，用于重置与校验基准。
## - `hold_weapon`：装备武器时的待机持握姿态（右臂前抬握持，左臂备盾）。
const POSE_ANIMATIONS := [
	"default",
	"hold_weapon",
]

# ============================================================================
# 查询方法
# ============================================================================

## 人形完整必需动画集（基础 + 武器攻击 + 姿态）。
## 体素人形 `_rig.glb` 必须包含其中每一项。
static func humanoid_required_animations() -> PackedStringArray:
	var all := PackedStringArray()
	for a in BASE_ANIMATIONS:
		all.append(a)
	for a in WEAPON_ATTACK_ANIMATIONS:
		all.append(a)
	for a in POSE_ANIMATIONS:
		all.append(a)
	return all

## 非人形生物最小动画集。
## 非人形生物不持武器，只需基础动作 + 通用 `slash` + `claw_swipe` 兜底 + `default`。
static func creature_required_animations() -> PackedStringArray:
	var all := PackedStringArray()
	for a in BASE_ANIMATIONS:
		all.append(a)
	all.append("slash")
	all.append("claw_swipe")
	all.append("default")
	return all

## 判断动画名是否为武器攻击动画。
static func is_weapon_attack_animation(anim_name: String) -> bool:
	return anim_name in WEAPON_ATTACK_ANIMATIONS

## 判断骨骼名是否为武器挂载骨骼。
static func is_weapon_bone(bone_name: String) -> bool:
	return bone_name == WEAPON_HAND_BONE or bone_name == SHIELD_HAND_BONE
