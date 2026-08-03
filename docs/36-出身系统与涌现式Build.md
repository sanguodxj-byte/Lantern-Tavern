# 36 - 出身系统与涌现式 Build

> **用途**：定义替代传统职业系统的"出身（Origin）"机制，以及由酿酒需求驱动战斗 build 自然涌现的成长框架。
> **设计红线**：出身只决定起跑姿势，不规定终点。任何武器 / 流派 / 属性均可通过实际使用成长。
> **前置文档**：`01-世界观设定.md`（玩家身份）、`03-酿酒与材料系统.md`（产区与口味）、`战斗数值体系.md`（属性派生与流派）、`08-酒馆成长系统.md`（酒馆等级）。

---

## 1. 为什么不用职业系统

### 1.1 核心矛盾

| 维度 | 传统职业（Barony 式） | 本作实际需求 |
|---|---|---|
| 玩家身份 | 战士/法师/盗贼等战斗从业者 | 中立酒馆老板，非战斗职业 |
| 核心循环 | 纯 dungeon crawl → 战斗变强 → 深入更难的地牢 | 探索采料 → 酿酒 → 经营 → 扩展关系网 |
| 成长锁定 | 职业锁定属性成长权重表，限制可用武器/技能 | 探索需求多变，今天采果明天杀虫后天挖矿 |
| Build 来源 | 开局选择决定 build 方向 | 酿酒目标驱动探索方向，探索中自然适应出 build |

### 1.2 设计原则

1. **出身 ≠ 职业**：出身回答"开酒馆之前是干什么的"，解释为什么会打架、为什么认识某些种族
2. **起点微调，不锁路径**：出身只提供初始属性偏移 + 一件武器 + 关系微调，不限制任何后续成长
3. **使用驱动成长**：属性/熟练度通过实际战斗行为累积（已有双轨经验基础设施），不靠升级点分配
4. **酿酒驱动涌现**：酒谱与产区绑定，产区决定怪物生态，怪物生态决定武器适应，build 自然成型

---

## 2. 出身定义

### 2.1 总览

| 出身 | 身份背景 | 主属性 +3 | 副属性 +1 | 初始武器 | 初始关系↑ | 酿酒方向 | 目标产区 |
|---|---|---|---|---|---|---|---|
| 退役佣兵 | 厌倦杀戮的退役人类佣兵 | STR | CON | 旧铁剑 | 人类冒险者 | 浓烈麦酒 | 火山区 |
| 林间猎人 | 地下城边缘的采药猎人 | DEX | PER | 猎弓 | 哥布林 / 精灵 | 清爽果酒 | 森林区 |
| 半吊子术士 | 跟幽灵学者学过几年魔法 | MAG | PER | 旧法杖 | 幽灵 | 灵性酒 | 墓园区 |
| 矮人学徒 | 矮人铁匠铺出师的人类学徒 | CON | STR | 战锤 | 牛头人 | 烈性黑啤 | 洞窟区 |

> 属性偏移在六属性全 5 基础上叠加。偏移后退役佣兵 STR=8/CON=6，其余仍为 5。
> 初始关系↑ = 对应势力 `faction_reputation` 起始 +30（进入"中立"阶梯 101-300 的起点附近）。

### 2.2 详细规格

#### 退役佣兵 (Retired Mercenary)

```gdscript
{
    "id": "retired_mercenary",
    "name": "退役佣兵",
    "lore": "厌倦了无休止的杀戮，靠旧人脉盘下地下城边缘的破酒馆。刀口舔血的日子结束了，但手艺没丢。",
    "attr_bonus": {"str": 3, "con": 1},
    "starting_weapon": "sword",           # 旧铁剑（剑类，单手流派）
    "starting_shield": "shield_round",    # 圆盾
    "faction_bonus": {"human": 30},
    "brewing_direction": "烈性麦酒",
    "target_zone": "volcano",
    "proficiency_headstart": {"sword": 2},  # 熟练度起始 +2（接近 T1 门槛 3）
}
```

- **叙事钩子**：旧佣兵 comrades 会作为人类冒险者顾客出现，提供初期装备委托
- **酿酒引导**：火山区产熔岩麦芽 `[麦香:3][温暖:3]`，酿出高溢价饱腹黑啤，牛头人铁匠任务线入口
- **build 涌现示例**：STR 偏向近战，但火山区多高防石甲虫，可能被迫拾起战锤（破甲被动）

#### 林间猎人 (Forest Hunter)

```gdscript
{
    "id": "forest_hunter",
    "name": "林间猎人",
    "lore": "常年在地下城边缘的林区采药狩猎，与哥布林拾荒者和精灵隐居者打过多年交道。",
    "attr_bonus": {"dex": 3, "per": 1},
    "starting_weapon": "bow",              # 猎弓（弓类，远程流派）
    "starting_shield": "",
    "faction_bonus": {"goblin": 30, "elf": 30},
    "brewing_direction": "清爽果酒",
    "target_zone": "forest",
    "proficiency_headstart": {"bow": 2},
}
```

- **叙事钩子**：哥布林猎人格鲁姆和精灵学者艾琳娜是旧识，初期任务线加速解锁
- **酿酒引导**：森林区产黑莓 `[果香:3][甜美:2]`，酿出性价比最高的基础果酒
- **build 涌现示例**：DEX/PER 偏向远程精准，但林区多快速近战哥布林，可能需要短剑防身

#### 半吊子术士 (Half-baked Warlock)

```gdscript
{
    "id": "half_baked_warlock",
    "name": "半吊子术士",
    "lore": "跟幽灵学者学过几年魔法，天赋不足没能出师，转行开酒馆。残缺的咒书还能凑合用。",
    "attr_bonus": {"mag": 3, "per": 1},
    "starting_weapon": "staff",            # 旧法杖（法杖类，法系流派）
    "starting_shield": "",
    "faction_bonus": {"ghost": 30},
    "brewing_direction": "灵性酒",
    "target_zone": "graveyard",
    "proficiency_headstart": {"staff": 2},
}
```

- **叙事钩子**：幽灵学者是旧师父，墓园区文献室任务线直接开启
- **酿酒引导**：墓园区产灵魂薄荷 `[寒凉:3][香醇:2]`，酿出重度清冷灵性酒，幽灵任务常备
- **build 涌现示例**：MAG 偏向法术，但墓园区多亡灵系高魔抗怪物，可能需要银附魔武器或转物理

#### 矮人学徒 (Dwarven Disciple)

```gdscript
{
    "id": "dwarven_disciple",
    "name": "矮人学徒",
    "lore": "在矮人铁匠铺当学徒出师的人类，想自己做老板。打铁练就的体魄比一般人类壮实得多。",
    "attr_bonus": {"con": 3, "str": 1},
    "starting_weapon": "hammer",           # 战锤（锤类，双手流派）
    "starting_shield": "shield_wood",      # 木盾
    "faction_bonus": {"minotaur": 30},
    "brewing_direction": "烈性黑啤",
    "target_zone": "caves",
    "proficiency_headstart": {"hammer": 2},
}
```

- **叙事钩子**：牛头人铁匠是旧雇主，装备修理折扣和熔炉特权加速获取
- **酿酒引导**：洞窟区产黑麦根 `[麦香:3][浓郁:2]`，酿出最普适的粗酒和烈性黑啤
- **build 涌现示例**：CON 偏向坦克生存，但洞窟区多虫类快速怪物，锤类慢攻速可能需要补短剑

---

## 3. 熟练度连续成长改造

### 3.1 现状分析

当前 `attr_panel.gd` 的 `accumulate_proficiency()` 仅做累加，无阶梯奖励：

```gdscript
# 现状：纯累加，达门槛仅用于 check_skill_unlocks() 判定
func accumulate_proficiency(weapon_type: String, gain: int) -> void:
    var cur: int = int(weapon_proficiency.get(weapon_type, 0))
    weapon_proficiency[weapon_type] = cur + gain
    _recompute_mechanism_passives()
```

技能领悟门槛 (`skill_data.gd:24-28`) 以熟练度等级为门槛：
- T1: proficiency 3, attr 15
- T2: proficiency 8, attr 35
- T3: proficiency 15, attr 70

**问题**：熟练度到 15 后无继续成长的激励——玩家没有动力继续使用已精通的武器。

### 3.2 改造方案：0-100 连续成长 + 阶梯奖励

将熟练度从"纯门槛计数器"改造为"0-100 连续成长轴"，每 20 级解锁一个阶梯奖励：

| 熟练度 | 阶梯 | 奖励类型 | 效果 |
|---|---|---|---|
| 0-19 | 初学 | — | 基础使用 |
| 20 | 熟练 | 伤害加成 | 该武器伤害 +5% |
| 40 | 精通 | 攻速加成 | 该武器攻速 +5% |
| 60 | 专家 | 暴击加成 | 该武器暴击率 +3% |
| 80 | 大师 | 专精被动 | 解锁该武器类别专属被动（见下） |
| 100 | 宗师 | 终极加成 | 该武器伤害 +10%、攻速 +5%（总计） |

> 硬上限 100。超过 100 的累积不再增加。
> 阶梯奖励是**武器类别级**（sword/dagger/axe/hammer/spear/bow/crossbow/staff/grimoire/shield），不是单件武器级。

### 3.3 大师级专属被动（熟练度 80 解锁）

| 武器类别 | 大师被动 | 效果 |
|---|---|---|
| sword 剑 | 剑意 | 暴击倍率 +0.2 |
| dagger 匕首 | 致命突刺 | 背刺倍率 +0.3 |
| axe 斧 | 裂甲 | 命中时 10% 概率降低目标防御 20%（5 秒） |
| hammer 锤 | 震荡 | 命中时 15% 概率眩晕 0.5 秒 |
| spear 枪 | 穿透 | 攻击距离 +0.5m，可穿透 1 个目标 |
| bow 弓 | 精准 | 远程暴击率 +5% |
| crossbow 弩 | 连射 | 10% 概率追加一次免费射击 |
| staff 法杖 | 法力回涌 | 施法后恢复 5 点法力 |
| grimoire 魔导书 | 诅咒强化 | 施加的负面状态持续时间 +30% |
| shield 盾 | 盾反大师 | 完美格挡窗口 +0.1 秒，格挡反击伤害 +20% |

### 3.4 数据结构

在 `attr_panel.gd` 新增熟练度阶梯追踪：

```gdscript
# 已解锁的熟练度阶梯奖励 {weapon_type: [milestone_id, ...]}
var proficiency_milestones: Dictionary

# 熟练度硬上限
const PROFICIENCY_CAP: int = 100

# 熟练度阶梯阈值
const PROFICIENCY_MILESTONE_THRESHOLDS: Array = [20, 40, 60, 80, 100]
```

改造后的 `accumulate_proficiency()`:

```gdscript
func accumulate_proficiency(weapon_type: String, gain: int) -> void:
    var cur: int = int(weapon_proficiency.get(weapon_type, 0))
    var new_val: int = mini(cur + gain, PROFICIENCY_CAP)
    weapon_proficiency[weapon_type] = new_val
    _check_proficiency_milestones(weapon_type, new_val)
    _recompute_mechanism_passives()

func _check_proficiency_milestones(weapon_type: String, val: int) -> void:
    if not proficiency_milestones.has(weapon_type):
        proficiency_milestones[weapon_type] = []
    var unlocked: Array = proficiency_milestones[weapon_type]
    for threshold in PROFICIENCY_MILESTONE_THRESHOLDS:
        if val >= threshold and not unlocked.has(threshold):
            unlocked.append(threshold)
            print("[AttrPanel] 熟练度阶梯解锁: %s @%d" % [weapon_type, threshold])

func get_proficiency_bonus(weapon_type: String) -> Dictionary:
    var unlocked: Array = proficiency_milestones.get(weapon_type, [])
    return {
        "damage_mult": 1.0 + (0.05 if unlocked.has(20) else 0.0) + (0.10 if unlocked.has(100) else 0.0),
        "attack_speed_mult": 1.0 + (0.05 if unlocked.has(40) else 0.0) + (0.05 if unlocked.has(100) else 0.0),
        "crit_bonus": 3.0 if unlocked.has(60) else 0.0,
        "master_passive": unlocked.has(80),
    }
```

---

## 4. 酿酒驱动涌现式 Build 循环

### 4.1 核心链路

```
酿酒目标（NPC订单/酒谱需求）
    │
    ▼
材料产区（4大区域：森林/火山/墓园/洞窟）
    │
    ▼
怪物生态（区域决定遭遇的怪物类型）
    │
    ▼
武器适应（怪物特性迫使选择有效武器）
    │
    ▼
熟练度成长（频繁使用 → 熟练度上升 → 阶梯奖励）
    │
    ▼
属性成长（战斗行为驱动属性经验累积）
    │
    ▼
Build 自然成型（非开局选择，而是涌现）
```

### 4.2 产区-怪物-武器适应表

| 产区 | 代表怪物 | 怪物特性 | 克制武器 | 自然驱动的属性 |
|---|---|---|---|---|
| 森林 | 哥布林拾荒者、巨型蜘蛛 | 快速、低防、群聚 | 短剑（快速）、弓（风筝） | DEX、AGI |
| 火山 | 石甲虫、火蜥蜴 | 高防、火系、慢速 | 战锤（破甲）、斧（木目标加成） | STR、CON |
| 墓园 | 亡灵骷髅、幽灵 | 高魔抗、亡灵系 | 锤（对骷髅无视防御+1.4倍）、银附魔武器 | STR、MAG |
| 洞窟 | 虫类、史莱姆 | 快速、酸性、低防 | 短剑（快速）、徒手（攻速） | DEX、AGI |

> 锤对骷髅的加成已存在于 `damage_resolver.gd:220-228`（×1.4 且无视防御）。
> 斧对木目标的加成已存在于 `damage_resolver.gd:217-218`（×1.5）。

### 4.3 涌现示例

**场景**：玩家选了"半吊子术士"（MAG/PER 倾向），但接到牛头人铁匠的烈性黑啤订单，需要去洞窟区采黑麦根。

1. 洞窟区多虫类快速怪物，法杖平砍 0.50 倍率几乎不破防
2. 玩家捡起之前捡到的战锤，发现锤的慢攻速对虫类也不理想
3. 玩家改用短剑，快速攻击应对虫类的移动速度
4. 频繁使用短剑 → 短剑熟练度上升 → 20 级解锁 +5% 伤害 → 40 级解锁 +5% 攻速
5. 同时 DEX 属性因远程/快速攻击行为累积上升
6. 最终形成"法术+短剑"的双修 build——这不是开局选的，是酿酒需求逼出来的

---

## 5. 与现有系统的集成方案

### 5.1 集成总览

| 现有系统 | 文件 | 改造方式 | 侵入度 |
|---|---|---|---|
| 属性初始化 | `attr_panel.gd:37,269` | `_init()`/`reset()` 后调用 `apply_origin()` | 低 |
| 属性查询 | `attr_panel.gd:48-53` | 无改动（出身偏移直接写入 attrs） | 无 |
| 里程碑 | `attr_panel.gd:115-125` | 无改动（出身初始值自然提早触发 T1） | 无 |
| 武器熟练度 | `attr_panel.gd:91-95` | 改造为连续成长+阶梯奖励 | 中 |
| 技能领悟 | `attr_panel.gd:152-182` | 无改动（门槛不变） | 无 |
| 存档/读档 | `attr_panel.gd:237-265` | 序列化新增 `origin_id` + `proficiency_milestones` | 低 |
| 势力声望 | `tavern_settlement.gd:56-58` | 新游戏时按出身 `faction_bonus` 初始化 | 低 |
| 新游戏重置 | `save_manager.gd:236-257` | `reset_all()` 后调用出身应用 | 低 |
| 玩家上下文 | `player_context.gd` | 无改动（AttrPanel 已聚合） | 无 |
| 酿酒系统 | `03-酿酒与材料系统.md` | 无改动（产区已定义） | 无 |
| 战斗系统 | `damage_resolver.gd` | 新增熟练度加成接入点 | 低 |

### 5.2 新增文件

#### `globals/combat/origin_data.gd`

```gdscript
class_name OriginData
extends RefCounted

## 出身系统数据层（非 autoload，纯数据查询）。
## 在新游戏开始时由 SaveManager / GameState 调用 apply_origin() 应用到 AttrPanel。

const ORIGINS: Array = [
    {
        "id": "retired_mercenary",
        "name": "退役佣兵",
        "lore": "厌倦了无休止的杀戮，靠旧人脉盘下地下城边缘的破酒馆。",
        "attr_bonus": {"str": 3, "con": 1},
        "starting_weapon": "sword",
        "starting_shield": "shield_round",
        "faction_bonus": {"human": 30},
        "brewing_direction": "烈性麦酒",
        "target_zone": "volcano",
        "proficiency_headstart": {"sword": 2},
    },
    {
        "id": "forest_hunter",
        "name": "林间猎人",
        "lore": "常年在地下城边缘的林区采药狩猎。",
        "attr_bonus": {"dex": 3, "per": 1},
        "starting_weapon": "bow",
        "starting_shield": "",
        "faction_bonus": {"goblin": 30, "elf": 30},
        "brewing_direction": "清爽果酒",
        "target_zone": "forest",
        "proficiency_headstart": {"bow": 2},
    },
    {
        "id": "half_baked_warlock",
        "name": "半吊子术士",
        "lore": "跟幽灵学者学过几年魔法，天赋不足转行开店。",
        "attr_bonus": {"mag": 3, "per": 1},
        "starting_weapon": "staff",
        "starting_shield": "",
        "faction_bonus": {"ghost": 30},
        "brewing_direction": "灵性酒",
        "target_zone": "graveyard",
        "proficiency_headstart": {"staff": 2},
    },
    {
        "id": "dwarven_disciple",
        "name": "矮人学徒",
        "lore": "在矮人铁匠铺当学徒出师的人类，想自己做老板。",
        "attr_bonus": {"con": 3, "str": 1},
        "starting_weapon": "hammer",
        "starting_shield": "shield_wood",
        "faction_bonus": {"minotaur": 30},
        "brewing_direction": "烈性黑啤",
        "target_zone": "caves",
        "proficiency_headstart": {"hammer": 2},
    },
]

static func get_origin(origin_id: String) -> Dictionary:
    for o in ORIGINS:
        if o["id"] == origin_id:
            return o
    return {}

static func get_all_ids() -> Array:
    var ids: Array = []
    for o in ORIGINS:
        ids.append(o["id"])
    return ids

## 将出身效果应用到 AttrPanel（属性偏移 + 熟练度起跑）。
## 在新游戏初始化或 reset() 之后调用一次。
static func apply_origin(attr_panel, origin_id: String) -> bool:
    var origin: Dictionary = get_origin(origin_id)
    if origin.is_empty():
        return false
    # 属性偏移
    for attr_key in origin.get("attr_bonus", {}):
        if attr_panel.attrs.has(attr_key):
            attr_panel.attrs[attr_key] = int(attr_panel.attrs[attr_key]) + int(origin["attr_bonus"][attr_key])
    # 熟练度起跑
    for prof_key in origin.get("proficiency_headstart", {}):
        attr_panel.weapon_proficiency[prof_key] = int(origin["proficiency_headstart"][prof_key])
    # 记录出身 id
    attr_panel.origin_id = origin_id
    # 重算里程碑（初始值可能已触发 T1）
    for attr_key in origin.get("attr_bonus", {}):
        attr_panel._check_milestone_unlock(attr_key)
    return true

## 将出身势力加成应用到 TavernSettlement。
static func apply_faction_bonus(tavern_settlement, origin_id: String) -> void:
    var origin: Dictionary = get_origin(origin_id)
    for faction in origin.get("faction_bonus", {}):
        if tavern_settlement.faction_reputation.has(faction):
            tavern_settlement.faction_reputation[faction] += int(origin["faction_bonus"][faction])
        elif faction == "human":
            # 人类不在 faction_reputation 中（人类冒险者是顾客来源而非势力）
            # 但保留加成用于未来人类好感加成 hook
            pass
```

### 5.3 `attr_panel.gd` 改动

```gdscript
# === 新增字段 ===
var origin_id: String = ""                                    # 已选出身 id
var proficiency_milestones: Dictionary = {}                   # {weapon_type: [threshold, ...]}
const PROFICIENCY_CAP: int = 100
const PROFICIENCY_MILESTONE_THRESHOLDS: Array = [20, 40, 60, 80, 100]

# === 改造 accumulate_proficiency ===
func accumulate_proficiency(weapon_type: String, gain: int) -> void:
    var cur: int = int(weapon_proficiency.get(weapon_type, 0))
    var new_val: int = mini(cur + gain, PROFICIENCY_CAP)
    weapon_proficiency[weapon_type] = new_val
    _check_proficiency_milestones(weapon_type, new_val)
    _recompute_mechanism_passives()

# === 新增 _check_proficiency_milestones ===
func _check_proficiency_milestones(weapon_type: String, val: int) -> void:
    if not proficiency_milestones.has(weapon_type):
        proficiency_milestones[weapon_type] = []
    var unlocked: Array = proficiency_milestones[weapon_type]
    for threshold in PROFICIENCY_MILESTONE_THRESHOLDS:
        if val >= threshold and not unlocked.has(threshold):
            unlocked.append(threshold)

# === 新增 get_proficiency_bonus ===
func get_proficiency_bonus(weapon_type: String) -> Dictionary:
    var unlocked: Array = proficiency_milestones.get(weapon_type, [])
    return {
        "damage_mult": 1.0 + (0.05 if unlocked.has(20) else 0.0) + (0.10 if unlocked.has(100) else 0.0),
        "attack_speed_mult": 1.0 + (0.05 if unlocked.has(40) else 0.0) + (0.05 if unlocked.has(100) else 0.0),
        "crit_bonus": 3.0 if unlocked.has(60) else 0.0,
        "master_passive": unlocked.has(80),
    }

# === 改造 serialize/deserialize ===
func serialize() -> Dictionary:
    return {
        # ... 现有字段 ...
        "origin_id": origin_id,
        "proficiency_milestones": proficiency_milestones.duplicate(true),
    }

func deserialize(data: Dictionary) -> void:
    # ... 现有字段 ...
    origin_id = String(data.get("origin_id", ""))
    if data.has("proficiency_milestones"):
        proficiency_milestones = data["proficiency_milestones"].duplicate(true)

# === 改造 reset ===
func reset() -> void:
    # ... 现有重置 ...
    origin_id = ""
    proficiency_milestones = {}
```

### 5.4 `save_manager.gd` 改动

```gdscript
# reset_all() 末尾新增出身选择 hook
func reset_all() -> void:
    # ... 现有重置逻辑 ...
    # 出身默认为空；新游戏流程中由 UI 选择后调用 apply_origin
    # 旧存档兼容：origin_id 为空时不应用任何偏移，保持全 5 初始值
```

> **旧存档兼容**：`deserialize()` 中 `origin_id` 默认为空字符串。空出身 = 无偏移 = 原始全 5 初始值，完全兼容现有存档。

### 5.5 `tavern_settlement.gd` 改动

```gdscript
# 新增 apply_origin_faction 方法
func apply_origin_faction(origin_id: String) -> void:
    const OD := preload("res://globals/combat/origin_data.gd")
    OD.apply_faction_bonus(self, origin_id)
```

### 5.6 `damage_resolver.gd` 接入点

在伤害结算的武器伤害倍率计算处，叠加熟练度加成：

```gdscript
# 在计算 weapon_damage_mult 时，叠加熟练度伤害加成
# 现有：weapon_damage_mult = STYLE_META[style].damage_mult
# 改为：weapon_damage_mult = STYLE_META[style].damage_mult * proficiency_bonus.damage_mult
# 攻速同理：叠加 proficiency_bonus.attack_speed_mult
# 暴击同理：叠加 proficiency_bonus.crit_bonus
```

> 具体接入位置需读取 `damage_resolver.gd` 的 STYLE_META 使用处，在下一阶段实现时精确定位。

---

## 6. 术语表更新

在 `docs/术语表.md` 新增以下条目：

| 术语 | 定义 | 备注 |
|---|---|---|
| 出身 | 新游戏开始时选择的玩家背景身份，替代传统职业系统。仅提供初始属性偏移、初始武器和关系微调，不锁定任何成长路径。 | 共 4 个：退役佣兵 / 林间猎人 / 半吊子术士 / 矮人学徒 |
| 熟练度阶梯 | 武器熟练度达到 20/40/60/80/100 时解锁的渐进奖励。 | 与技能领悟门槛（T1/T2/T3）独立共存 |

---

## 7. 测试计划

### 7.1 新增测试文件

#### `tests/gdunit/origin_data_test.gd`

```gdscript
extends GdUnitTestSuite

const OD := preload("res://globals/combat/origin_data.gd")

func test_get_origin_valid_id() -> void:
    var o = OD.get_origin("retired_mercenary")
    assert_str(o["id"]).is_equal("retired_mercenary")
    assert_int(o["attr_bonus"]["str"]).is_equal(3)

func test_get_origin_invalid_id_returns_empty() -> void:
    assert_dict(OD.get_origin("nonexistent")).is_empty()

func test_get_all_ids_returns_four() -> void:
    assert_array(OD.get_all_ids()).has_size(4)

func test_apply_origin_adds_attr_bonus() -> void:
    var ap = AttrPanel.new()
    OD.apply_origin(ap, "retired_mercenary")
    assert_int(ap.get_attr("str")).is_equal(8)  # 5 + 3
    assert_int(ap.get_attr("con")).is_equal(6)  # 5 + 1
    assert_int(ap.get_attr("dex")).is_equal(5)  # unchanged

func test_apply_origin_adds_proficiency_headstart() -> void:
    var ap = AttrPanel.new()
    OD.apply_origin(ap, "retired_mercenary")
    assert_int(ap.get_proficiency("sword")).is_equal(2)

func test_apply_origin_sets_origin_id() -> void:
    var ap = AttrPanel.new()
    OD.apply_origin(ap, "forest_hunter")
    assert_str(ap.origin_id).is_equal("forest_hunter")

func test_apply_origin_triggers_t1_milestone() -> void:
    # CON=8 超过 T1 阈值 5，应触发强健体魄
    var ap = AttrPanel.new()
    OD.apply_origin(ap, "dwarven_disciple")  # con+3 → 8
    assert_bool(ap.has_milestone("强健体魄")).is_true()

func test_apply_origin_invalid_returns_false() -> void:
    var ap = AttrPanel.new()
    assert_bool(OD.apply_origin(ap, "nonexistent")).is_false()

func test_each_origin_has_required_fields() -> void:
    for oid in OD.get_all_ids():
        var o = OD.get_origin(oid)
        assert_dict(o).contains_keys(["id", "name", "lore", "attr_bonus", "starting_weapon", "faction_bonus", "brewing_direction", "target_zone", "proficiency_headstart"])
```

#### `tests/gdunit/proficiency_milestone_test.gd`

```gdscript
extends GdUnitTestSuite

func test_proficiency_caps_at_100() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 150)
    assert_int(ap.get_proficiency("sword")).is_equal(100)

func test_milestone_unlocks_at_20() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 20)
    var bonus = ap.get_proficiency_bonus("sword")
    assert_float(bonus["damage_mult"]).is_equal_approx(1.05, 0.001)

func test_milestone_unlocks_at_40() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 40)
    var bonus = ap.get_proficiency_bonus("sword")
    assert_float(bonus["attack_speed_mult"]).is_equal_approx(1.05, 0.001)

func test_milestone_unlocks_at_60() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 60)
    var bonus = ap.get_proficiency_bonus("sword")
    assert_float(bonus["crit_bonus"]).is_equal(3.0)

func test_milestone_unlocks_at_80_master() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 80)
    var bonus = ap.get_proficiency_bonus("sword")
    assert_bool(bonus["master_passive"]).is_true()

func test_milestone_unlocks_at_100_double_damage() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 100)
    var bonus = ap.get_proficiency_bonus("sword")
    # 20级 +5%, 100级 +10% → 总 +15%
    assert_float(bonus["damage_mult"]).is_equal_approx(1.15, 0.001)

func test_no_bonus_below_20() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 19)
    var bonus = ap.get_proficiency_bonus("sword")
    assert_float(bonus["damage_mult"]).is_equal(1.0)

func test_incremental_accumulation() -> void:
    var ap = AttrPanel.new()
    for i in range(20):
        ap.accumulate_proficiency("sword", 1)
    var bonus = ap.get_proficiency_bonus("sword")
    assert_float(bonus["damage_mult"]).is_equal_approx(1.05, 0.001)

func test_serialize_deserialize_preserves_milestones() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 60)
    var data = ap.serialize()
    var ap2 = AttrPanel.new()
    ap2.deserialize(data)
    var bonus = ap2.get_proficiency_bonus("sword")
    assert_float(bonus["crit_bonus"]).is_equal(3.0)

func test_reset_clears_milestones() -> void:
    var ap = AttrPanel.new()
    ap.accumulate_proficiency("sword", 60)
    ap.reset()
    var bonus = ap.get_proficiency_bonus("sword")
    assert_float(bonus["damage_mult"]).is_equal(1.0)
```

### 7.2 现有测试更新

- `attr_panel_test.gd`：更新 `test_accumulate_proficiency_adds_exp` 验证 100 封顶
- `attr_panel_test.gd`：新增出身偏移后初始属性验证

---

## 8. MVP 实施路径

### 阶段一：出身数据层（最小可测）

1. 创建 `globals/combat/origin_data.gd`（纯数据，无 UI）
2. 在 `attr_panel.gd` 新增 `origin_id` 字段 + `apply_origin` 调用
3. 在 `attr_panel.gd` 新增熟练度阶梯系统
4. 编写 `origin_data_test.gd` + `proficiency_milestone_test.gd`
5. 运行全量测试确认无回归

### 阶段二：势力声望接入

1. 在 `tavern_settlement.gd` 新增 `apply_origin_faction()`
2. 在 `save_manager.gd` 的 `reset_all()` 流程中预留出身选择 hook
3. 测试势力声望初始值

### 阶段三：战斗系统接入

1. 在 `damage_resolver.gd` 叠加熟练度伤害/攻速/暴击加成
2. 编写伤害结算集成测试
3. 大师级被动效果实装（逐个武器类别）

### 阶段四：出身选择 UI

1. 新游戏流程中加入出身选择界面
2. 4 个出身卡片展示（属性偏移、初始武器、关系、酿酒方向）
3. 选择后调用 `apply_origin()` + `apply_origin_faction()`

### 阶段五：酿酒引导验证

1. 确认每个出身的 `target_zone` 在地牢生成中可达
2. 确认对应产区的材料可采集
3. 端到端验证：选出身 → 探索目标产区 → 采集材料 → 酿酒 → 交付

> **MVP 范围**：阶段一 + 阶段二即可验证核心设计（出身偏移 + 熟练度成长 + 声望初始值）。阶段三~五为后续迭代。
