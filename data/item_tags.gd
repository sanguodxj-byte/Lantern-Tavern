## 物品标签枚举 — 统一定义所有物品的分类标签。
##
## 每个标签关联：
##   - 生成概率（基础值 + 按区域修正）
##   - 生成位置偏好（地面中心/靠墙/角落/散布/桌面上/随机）
##   - 物理模式（静态/刚体/触发器）
##
## 使用方式：
##   ItemTags.WEAPON      → "weapon"
##   ItemTags.all_tags()  → Array[String] 所有标签
##   ItemTags.display_name("weapon") → "武器"

class_name ItemTags

# ── 标签常量 ────────────────────────────────────────────────
const WEAPON    := "weapon"
const SHIELD    := "shield"
const MATERIAL  := "material"
const FURNITURE := "furniture"
const CONSUMABLE := "consumable"
const KEY       := "key"
const TREASURE  := "treasure"
const DECOR     := "decor"
const TRAP      := "trap"
const CONTAINER := "container"

# 所有有效标签列表
const ALL: Array[String] = [
	WEAPON,
	SHIELD,
	MATERIAL,
	FURNITURE,
	CONSUMABLE,
	KEY,
	TREASURE,
	DECOR,
	TRAP,
	CONTAINER,
]

# 标签 → 显示名（本地化用）
const DISPLAY_NAMES: Dictionary = {
	WEAPON: "武器",
	SHIELD: "盾牌",
	MATERIAL: "酿造材料",
	FURNITURE: "家具",
	CONSUMABLE: "消耗品",
	KEY: "钥匙",
	TREASURE: "宝藏",
	DECOR: "装饰",
	TRAP: "陷阱",
	CONTAINER: "容器",
}

# ── 位置偏好 ────────────────────────────────────────────────
enum LocationPreference {
	FLOOR_CENTER,     # 房间正中央
	NEAR_WALL,        # 靠近墙壁
	CORNER,           # 角落
	SCATTER,          # 随机散布（Poisson）
	ON_TABLE,         # 桌面上
	RANDOM,           # 完全随机
}

# 位置偏好显示名
const LOCATION_NAMES: Dictionary = {
	LocationPreference.FLOOR_CENTER: "地面中心",
	LocationPreference.NEAR_WALL: "靠墙",
	LocationPreference.CORNER: "角落",
	LocationPreference.SCATTER: "散布",
	LocationPreference.ON_TABLE: "桌面",
	LocationPreference.RANDOM: "随机",
}

# ── 物理模式 ────────────────────────────────────────────────
enum PhysicsMode {
	STATIC,    # StaticBody3D — 环境/家具
	RIGID,     # RigidBody3D — 可拾取/可投掷物
	TRIGGER,   # Area3D     — 交互触发器
}

const PHYSICS_MODE_NAMES: Dictionary = {
	PhysicsMode.STATIC: "静态",
	PhysicsMode.RIGID: "刚体",
	PhysicsMode.TRIGGER: "触发器",
}

# ── 工具函数 ────────────────────────────────────────────────

## 检查 tag 是否为有效标签
static func is_valid(tag: String) -> bool:
	return ALL.has(tag)

## 获取标签显示名
static func display_name(tag: String) -> String:
	return DISPLAY_NAMES.get(tag, tag)

## 获取所有标签
static func all_tags() -> Array[String]:
	return ALL.duplicate()
