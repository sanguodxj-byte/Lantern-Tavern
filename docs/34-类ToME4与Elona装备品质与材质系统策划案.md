# 34 - 类 ToME4 与 Elona 装备品质、材质与词缀实装策划案

> **设计核心**：
> 融合 **Tales of Maj'Eyal (ToME4)** 与 **Elona (伊洛纳)** 的经典 Roguelike 装备构筑深度，建立 **【材质 Tier (Material)】 × 【品质稀有度 (Rarity)】 × 【32 项双轴极克制词缀 (Affixes)】** 的硬核装备生成与实装结算体系。

---

## 一、 类 ToME4 / Elona 装备品质与材质矩阵

装备的面板属性由 **【材质 Material】** 与 **【品质稀有度 Rarity】** 共同决定：

```
[材质前缀 Material] + [稀有度前缀 Quality] + [前缀 Prefix] + [基础装备 Base] + [后缀 Suffix]
例如: "粗糙的 秘银 铁质长剑 之 斩杀"
```

### 1. 材质阶梯 (Material Tiers - 对齐 ToME4 / Elona)
材质决定了装备的基础坚固度、负重倍率与固有材质特质：

| 材质名称 | 对应层级 (Zone) | 基础物理加成 | 重量系数 | 特殊固有材质属性 |
|---|---|---|---|---|
| **木/皮 (Wood/Leather)** | Zone 0 (序章) | **0%** 基础 | **0.6x** (极轻) | 钝击抗性低，易燃 |
| **铁质 (Iron)** | Zone 0 ~ 1 | **+0%** 标称 | **1.0x** (标准) | 基础沉稳 |
| **钢质 (Steel)** | Zone 1 ~ 2 | **+5%** 面板 | **1.1x** (略重) | 耐久度提升，防磨损 +10% |
| **玄铁/陨铁 (Meteoric)** | Zone 2 ~ 3 | **+10%** 面板 | **1.2x** (重) | 附带 +2% 暗/暗影伤害 |
| **秘银 (Mithril)** | Zone 3 ~ 4 | **+15%** 面板 | **0.7x** (轻盈) | 破甲 +3%，法力消耗 -2% |
| **精金/龙骨 (Adamantite/Dragonic)** | Zone 4 ~ 5 | **+20%** 面板 | **1.3x** (沉重) | 物理防御 +2，全减伤 +2% |

### 2. 品质稀有度阶层 (Quality Rarity Tiers)
品质稀有度决定了装备的 UI 显示颜色、词缀插槽数量（Affix Slots）与浮动倍率：

| 稀有度阶层 | UI 显示颜色 | 词缀插槽规则 | 面板系数浮动 |
|---|---|---|---|
| **劣质 (Inferior)** | 灰色 (`#888888`) | 强制含 **1 负向前缀** | **0.85x ~ 0.95x** |
| **普通 (Common)** | 白色 (`#FFFFFF`) | **0 词缀** | **1.00x** |
| **优秀 (Superior)** | 绿色 (`#33FF55`) | 必含 **1 正向前缀** | **1.02x ~ 1.05x** |
| **稀有 (Rare)** | 蓝色 (`#3399FF`) | 必含 **1 正向前缀 + 1 后缀** | **1.05x ~ 1.08x** |
| **史诗 (Epic)** | 紫色 (`#AA33FF`) | 包含 **2 正向前缀 + 1 后缀** | **1.08x ~ 1.12x** |
| **神器 (Artifact)** | 金黄色 (`#FFCC00`) | 专属材质 + **2 赐福前缀 + 1 顶级后缀** | **1.15x (固定顶峰)** |

---

## 二、 32 项词缀的实装结算逻辑 (Gameplay & Combat Implementation)

所有 32 项微数值词缀必须在游戏战斗与角色属性中**真实触发与结算**：

### 1. 伤害与暴击层结算 (Damage & Crit Resolution)
在 `DamageResolver.gd` 中解析 `WeaponData` 的词缀数组：
* **`sharp` (+3% 伤, +1% 暴)**、**`flamereached` (+3% 火伤)**、**`blessed` (+4% 伤, +2% 暴)**、**`rusty` (-4% 伤)**：直接计入 `damage_mult` 乘以基础面板。
* **`bloodthirsty` (+0.5% 吸血)**：当结算实际物理伤害 $D_{\text{deal}} > 0$ 时，触发回复 $\max(1, \lfloor D_{\text{deal}} \times 0.005 \rfloor)$ HP。
* **`cursed_vampiric` (+5% 伤, 自扣 1点 HP)**：玩家攻击释放瞬间强制扣除 1 点自身 HP，并在装备栏强行锁定 `is_locked = true`。
* **`of_slaying` (+5% 低血伤害)**：当目标 HP $\le 25\%$ 时，伤害乘以 $1.05$。

### 2. 格挡与物理防守层结算 (Block & Defend Resolution)
在 `CombatBridge.gd` 防守判定中：
* **`sturdy` (物防 +1)**、**`cracked` (物防 -1)**、**`of_tenacity` (残血物防 +2)**：在玩家/敌人计算防具面板时直接加减最终物理防具值。
* **`of_parrying` (格挡扣损 +4%)**：完美格挡或盾牌受击减伤时额外增加 4% 减伤率。

### 3. 地牢探险与品质磨损层结算 (Adventure & Durability)
在 `equipment_loadout.gd` 与品质退阶判定中：
* **`brittle` (磨损率 +15%)**、**`sturdy` (磨损率 -10%)**：直接修改 $P_{\text{degrade}}$ 判定基准。
* **`shining` (照亮 +1m)**：动态更新玩家的 `OmniLight3D.omni_range += 1.0`。
