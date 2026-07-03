# 灯火酒馆 (Lantern Tavern) - 核心项目架构与设计规约

本文档详尽规划了『灯火酒馆』项目的高级架构，涵盖：**局外成长系统（Progression）**、**纸娃娃装备系统（Paper Doll）**、**像素风格UI与本地化规约**，供我们完全远端的分布式开发进行参考和模块对接。

---

## 一、 项目目录结构设计 (Project Directory Layout)

```
/Lantern-Tavern/
├── assets/                     # 3D 资产与 2D 美术素材
│   ├── models/                 # 程序化生成的 low-poly 3D 模型 (.obj)
│   ├── textures/               # 贴图与纹理 (.png)
│   ├── screenshots/            # 素材自验证预览截图 (.png)
│   └── fonts/                  # 像素风格字体文件 (例如: IPix.ttf / m5x7.ttf)
├── data/                       # 结构化数据
│   ├── brewing_materials.json  # 30种酿酒素材的数据库
│   └── brewing_materials.md    # 酿酒素材的可读说明
├── globals/                    # 全局单例 (Autoloads)
│   ├── audio_manager.gd        # 音效管理器
│   ├── game_events.gd          # 全局信号事件中心
│   ├── game_state.gd           # 运行时临时状态
│   └── tavern_manager.gd       # 昼夜交替、酿酒与背包状态管理器
├── scenes/                     # 游戏关卡与实体场景
│   ├── characters/             # 角色与纸娃娃
│   │   ├── player/player.tscn    # 基础人类酒馆老板
│   │   ├── player/player.gd      # 纸娃娃装配与状态逻辑
│   │   └── monster_customer.gd # 怪物顾客AI及口味偏好
│   ├── expedition/             # 搜打撤 (白天关卡)
│   │   ├── levels/             # 地形与关卡
│   │   ├── items/              # 采集物与掉落物实体
│   │   └── extraction_point.gd # 撤离口逻辑
│   ├── tavern/                 # 夜晚经营 (酒馆场景)
│   │   ├── bar_manager.gd      # 酒馆营业与酿酒台控制
│   │   ├── customer_spawner.gd # 顾客生成器
│   │   └── upgrade_desk.gd     # 局外成长升级台
│   └── ui/                     # 用户界面
│       ├── hud.tscn            # 昼夜信息与血量UI
│       ├── tavern_menu.tscn    # 酿酒与升级UI
│       └── localization/       # 本地化翻译源文件
│           └── translations.csv # 多语言翻译键值对表格
└── project.godot               # 项目配置文件
```

---

## 二、 局外成长系统 (Out-of-run Progression)

利用夜晚酒馆经营中，售卖高风味酒品给各类怪物顾客赚取的 **金币 (Gold)**，玩家可以在夜晚的「升级台 (Upgrade Desk)」进行局外永久强化：

### 1. 升级类型
*   **酒馆老板冒险强化 (Owner Upgrades)**：
    *   *Max Health* (最大生命值)：提升在白天搜寻阶段的容错率。
    *   *Inventory Slots* (背包格数)：提升单次出航能够带回的酿酒素材上限。
    *   *Speed* (移动速度)：提升搜刮效率。
*   **酒馆生产力升级 (Tavern Upgrades)**：
    *   *Brewing Master* (酿酒精通)：酿酒时额外获得 10% 随机风味点数奖励。
    *   *Tavern Seat Capacity* (酒馆座位容量)：增加夜晚每波来客的数量上限。
    *   *Barrel Ageing* (木桶陈酿)：使存放在酒馆的多余素材过夜后产生风味自然发酵 (+1 风味)。

---

## 三、 纸娃娃装备系统 (Paper Doll System)

为了让酒馆老板穿戴不同的装备并在 3D 世界中即时可见，我们将采用 **「槽位网格动态替换 (Modular Mesh Swap)」** 的架构：

### 1. 骨骼挂载与节点层级 (BoneAttachment3D)
在 `player/player.tscn` 场景中，我们基于骨骼节点建立如下装备槽：
```
BaseOwner (CharacterBody3D)
└── Skeleton3D (人类骨骼)
    ├── RightHand_Attachment (BoneAttachment3D) -> 绑定右手指骨
    │   └── WeaponSlot (Node3D)                 -> 武器插槽 (可变模型)
    ├── LeftArm_Attachment (BoneAttachment3D)   -> 绑定左手腕骨
    │   └── ShieldSlot (Node3D)                 -> 防具插槽 (可变模型)
    └── Head_Attachment (BoneAttachment3D)      -> 绑定头部骨骼
        └── HelmetSlot (Node3D)                 -> 头盔/发型插槽 (可变模型)
```

### 2. 纸娃娃动态更新代码框架 (`player/player.gd`)
```gdscript
extends CharacterBody3D
class_name PlayerOwner

@onready var weapon_slot = $Skeleton3D/RightHand_Attachment/WeaponSlot
@onready var shield_slot = $Skeleton3D/LeftArm_Attachment/ShieldSlot
@onready var helmet_slot = $Skeleton3D/Head_Attachment/HelmetSlot

# 装备模型路径定义
var EQUIP_MODELS: Dictionary = {
	"rusty_sword": "res://assets/models/rusty_sword.obj",
	"iron_shield": "res://assets/models/iron_shield.obj",
	"horned_helmet": "res://assets/models/horned_helmet.obj"
}

func equip_item(slot_name: String, item_id: String) -> void:
	var slot_node: Node3D = null
	match slot_name:
		"weapon": slot_node = weapon_slot
		"shield": slot_node = shield_slot
		"helmet": slot_node = helmet_slot
		
	if slot_node == null:
		return
		
	# 清除已有模型
	for child in slot_node.get_children():
		child.queue_free()
		
	# 实例化并添加新模型
	if item_id in EQUIP_MODELS:
		var mesh_instance = MeshInstance3D.new()
		var mesh_res = load(EQUIP_MODELS[item_id])
		if mesh_res:
			mesh_instance.mesh = mesh_res
			slot_node.add_child(mesh_instance)
			print("Equipped ", item_id, " in slot ", slot_name)
```

---

## 四、 UI、像素字体与中英文本地化

### 1. 像素风格字体配置
我们将在 `assets/fonts/` 目录下放置像素风格 TTF 字体，并在 Godot UI 组件中，建立通用的 **Theme (主题)** 文件来覆盖全局 Label 字体。这可以保证 UI 的像素风格与低模画面保持完美契合。

### 2. 本地化 CSV 规范
我们将采用 Godot 内置的 CSV 自动导入本地化技术。文件位于 `scenes/ui/localization/translations.csv`，表头定义如下：

```csv
keys,en,zh
TAVERN_NAME,"The Lantern Tavern","灯火酒馆"
DAY_LABEL,"Day {0} (Expedition)","第 {0} 天 (搜刮搜集)"
NIGHT_LABEL,"Night {0} (Tavern open!)","第 {0} 晚 (酒馆营业中!)"
BREW_DRINK,"Brew Drink","酿造酒品"
GOLD_AMOUNT,"Gold: {0}","金币: {0}"
INVENTORY,"Inventory","背包"
UPGRADE_HEALTH,"Upgrade Max Health (Cost: {0})","升级最大血量 (消耗: {0})"
UPGRADE_SEATS,"Upgrade Seats Capacity (Cost: {0})","升级座位容量 (消耗: {0})"
MATERIAL_GLOWCAP,"Wild Glowcap","野生荧光菇"
MATERIAL_FROSTBERRY,"Frost Berry","霜冻浆果"
CUSTOMER_WANTS,"A guest wants {0} flavors","顾客想要 {0} 风味"
```

Godot 4 会自动将此 `.csv` 识别并编译为 `.translation` 资源文件，我们在代码中只需要调用 `tr("BREW_DRINK")` 即可实现中英文在运行时无缝、即时地切换。


## 五、 地牢房间生成算法：结构化 + WFC 模板化生成 (Structured + WFC Room Generation)

为了在白天的冒险搜刮阶段（DAY_EXPEDITION）提供无穷的可玩性、策略深度与拓扑合理性，我们采用 **「宏观结构化布局 + 微观波函数坍缩（Wave Function Collapse）」** 的模板化生成算法。

### 1. 算法核心步骤

1.  **宏观结构化布线 (Macro Structured Layout)**:
    -   系统首先生出一个基于图（Graph）或树（Tree）的拓扑关系关卡骨架。
    -   定义起点（老板出航入口）、核心探索路径、旁支危险区（高等级怪物与宝箱）以及撤离点（Extraction Point）。
    -   锁、门、密室根据拓扑强关联规律分布，保证撤离通道在逻辑和流程上 100% 绝对通畅。

2.  **微观 WFC 拼图坍缩 (Micro WFC Tile Collapse)**:
    -   每个结构化节点被关联到一个固定尺寸（如 10x10）的房间模板边界中。
    -   利用 WFC 算法对单元格进行局部的具体填充，包含：空地 (FLOOR)、墙壁 (WALL)、宝藏 (LOOT)、酿酒素材 (RESOURCE)、立柱 (PILLAR) 等。
    -   **邻接规则约束 (Constraint Map)**:
        -   `LOOT` (宝藏) 和 `RESOURCE` (素材点) 周围必须至少有 2 个 `FLOOR` (空地) 相邻，确保酒馆老板可以顺利走过去进行采集。
        -   `WALL` (墙壁) 必须在指定的四个方向对齐外界的出入口通道，维持物理连通。

### 2. 代码实现参考

我们已将功能完备、逻辑严密的波函数坍缩房间模板填充器实现并注册在项目 `scenes/expedition/wfc_generator.gd` 中。该脚本包含了完整的叠加态（Superposition）初始化、最小信息熵（Lowest Entropy First）搜索、局部确定性选择（State Collapse）以及限制向外扩散（Propagation）核心循环，可完美自适应模板生成多变的室内微观摆设与材质排布。


## 六、 场景物体空间分布与排布算法 (Spatial Distribution Algorithms)

为了在『灯火酒馆』的白天搜猎与夜晚经营两个不同阶段中，实现物体排列的高真实感、高对称性以及完全保障 A* (NavigationAgent3D) 自动巡路逻辑通畅，我们设计并落地了严密的场景物体分布排布算法。

### 1. 白天搜掠地牢中的物体分布

-   **大理石柱 (Pillar) & 石墙 (Wall)**: 由上一章的微观 WFC 坍缩模板拼合逻辑生成，作为硬性的阻挡物静态渲染，并在生成后烘焙地牢 3D 导航网格。
-   **采集素材 (Resource Spots - wild_glowcap, sweet_grass 等)**: 
    -   采用 **泊松圆盘采样算法 (Poisson Disc Sampling)**：在每个房间的 2D 平面边界内，生成距离不小于 $R_{\min} = 1.2m$ 的密集散点。
    -   该算法能有效避免素材扎堆重叠，营造出极其自然、有机分布的植被生长感，并与墙体边缘保持防卡间距。
-   **藏宝箱 (Chest) 分布**:
    -   系统使用拓扑图的广度优先搜索 (BFS) 遍历所有生成的房间连通树。
    -   检测树中度为 1 的「叶子节点」房间（即死胡同 Dead End），将宝箱专门放置于此，赋予玩家折返搜刮的探险刺激感与奖励正反馈。
-   **传送撤离点 (Portal/Extraction Point) 摆放**:
    -   计算拓扑树中距离玩家起点（Start Room）的**最远曼哈顿/拓扑路径距离**的房间。
    -   撤离点始终在那个最深、最危险的终点房间中心生成，迫使老板经历完整的生死洗礼和战斗方可带着素材撤离。

### 2. 夜晚经营酒馆中的家具排布

为了给怪物顾客和酒馆老板预留充裕的移动空间：
-   **餐桌-木凳模组槽位分配**:
    -   采用 **二维栅格边界槽位锁死 (Grid-slot Allocation)**：餐桌按固定间隔（如 $3.0m$）纵横对齐排列。
    -   每张餐桌在其局部十字对齐坐标轴上，以偏移量 $0.6m$ 自动外挂实例化 4 张圆木凳（Stool）。
    -   相邻餐桌模组之间留有至少 $1.8m \sim 2.4m$ 的绝对空隙，完美预留为 NavigationAgent3D 巡路网格走廊，确保怪物服务生和老板送酒时 100% 绝不卡位。

### 3. 代码实现规范

该全套数学与拓扑分布排布逻辑已完整实装于项目 `scenes/expedition/prop_distributor.gd` 逻辑脚本中。包含高效的 Poisson Annulus 采样器、Topological BFS 求解器以及酒馆家具栅格生成器，供关卡场景（Level Spawner）在运行时直接调用装配。
