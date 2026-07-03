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
│   │   ├── base_goblin.tscn    # 基础哥布林玩家
│   │   ├── base_goblin.gd      # 纸娃娃装配与状态逻辑
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
*   **哥布林冒险强化 (Goblin Upgrades)**：
    *   *Max Health* (最大生命值)：提升在白天搜寻阶段的容错率。
    *   *Inventory Slots* (背包格数)：提升单次出航能够带回的酿酒素材上限。
    *   *Speed* (移动速度)：提升搜刮效率。
*   **酒馆生产力升级 (Tavern Upgrades)**：
    *   *Brewing Master* (酿酒精通)：酿酒时额外获得 10% 随机风味点数奖励。
    *   *Tavern Seat Capacity* (酒馆座位容量)：增加夜晚每波来客的数量上限。
    *   *Barrel Ageing* (木桶陈酿)：使存放在酒馆的多余素材过夜后产生风味自然发酵 (+1 风味)。

---

## 三、 纸娃娃装备系统 (Paper Doll System)

为了让哥布林穿戴不同的装备并在 3D 世界中即时可见，我们将采用 **「槽位网格动态替换 (Modular Mesh Swap)」** 的架构：

### 1. 骨骼挂载与节点层级 (BoneAttachment3D)
在 `base_goblin.tscn` 场景中，我们基于骨骼节点建立如下装备槽：
```
BaseGoblin (CharacterBody3D)
└── Skeleton3D (哥布林骨骼)
    ├── RightHand_Attachment (BoneAttachment3D) -> 绑定右手指骨
    │   └── WeaponSlot (Node3D)                 -> 武器插槽 (可变模型)
    ├── LeftArm_Attachment (BoneAttachment3D)   -> 绑定左手腕骨
    │   └── ShieldSlot (Node3D)                 -> 防具插槽 (可变模型)
    └── Head_Attachment (BoneAttachment3D)      -> 绑定头部骨骼
        └── HelmetSlot (Node3D)                 -> 头盔/发型插槽 (可变模型)
```

### 2. 纸娃娃动态更新代码框架 (`base_goblin.gd`)
```gdscript
extends CharacterBody3D
class_name PlayerGoblin

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
