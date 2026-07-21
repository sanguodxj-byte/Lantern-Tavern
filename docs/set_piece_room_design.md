# 设计文档：作者化「特殊房间印章」(Set-Piece Room) 数据驱动系统

> 文档状态：**Draft v1（待评审）**
> 起草日期：2026-07-21
> 范围：`scenes/expedition/` 地牢生成管线 + `data/` 资源层
> 关联文档：[`docs/mapgen_vs_barony.md`](./mapgen_vs_barony.md)（LT vs Barony 生成架构对比，本设计的调研基础）
> 关键结论：在「地图生成」维度，LT 的 isaac 程序化几何生成比 Barony 的模板拼装更接近用户想要的「真 roguelike 系统涌现」范式；本设计在保留 isaac 内核的前提下，向 Barony 借其「手工房间印章」工作流。

---

## 0. TL;DR — 决策摘要

**采用方案：在 isaac 程序化管线中注入「作者化房间印章」（hybrid / 混合范式）。**

- 不替换现有 isaac 几何生成器（它是项目「真 roguelike 深度」的更好基础）。
- 把现有 `WFC_RoomGenerator.RoomTemplate`（`wfc_generator.gd:15`）的**数据模型外置**为可编辑的 `SetPieceRoom` 资源（`.tres`），由 `SetPieceRegistry`（仿 `WeaponRegistry`）加载。
- 特殊房间（固定 Boss 竞技场、仪式房、宝库、谜题房）作为 `SetPieceRoom` 资源，**策划可直接增删/编辑，无需改生成代码**。
- 集成点：set-piece 作为 **macro 图的一等节点** 注入（带 `door_anchors` 连接锚点 + 可变 footprint 多 macro 格预留），经 `DungeonConnectivityValidator`（可达比 ≥ 0.9）把关，由现有 `DungeonSceneBuilder` + `DungeonSpawnPlanner` 消费。
- 确定性：用独立域盐 `_seeded_rng(layout, 0x53455450)`，与敌人/物品序列互不串扰，联机指纹自动覆盖。

**为什么不是「纯 Barony 模板拼装」或「纯 isaac」：** 见 §3 决策对比。

---

## 1. 背景与目标

### 1.1 问题来源
用户确认需求（来自对话）：
> 「我们的程序化生成最终也是生成大小不一的房间，新特殊房间应也作为一个数据可以编辑和加入。」

即：特殊房间（Boss 房、仪式房、宝库等）当前是 isaac 算法按图距离**自动分配角色**到程序化雕刻出的房间（`_assign_room_roles()`），策划无法手工设计固定形态。要让「新特殊房间」成为**可编辑、可加入的数据**。

### 1.2 目标
1. 特殊房间形态由**数据资源**定义，策划增删/改无需触碰生成器代码。
2. 不破坏现有：分层架构、纯数据 `DungeonLayout` 契约、确定性/联机重建、连通性验证。
3. 复用而非重写：现有瓦片驱动的场景构建与生成规划直接消费 set-piece 图案。
4. 保持「真 roguelike 涌现」——程序化变化仍是主体，set-piece 是点睛的可控特殊点。

### 1.3 非目标（v1 明确不做）
- 不替换 isaac 为 Barony 式纯模板拼装。
- 不在 WFC / BSP 算法中接入 set-piece（v1 仅 isaac；WFC 已有自己的 `RoomTemplate`，见 §6 未来工作）。
- v1 不做可视化盖章编辑器插件（文本编辑 `.tres` 即可；编辑器工具留 Phase 5）。

---

## 2. 调研结论（基于真实源码，非臆测）

### 2.1 现状生成管线（`DungeonGenerator.generate`）
入口：`dungeon_generator.gd:19` `generate(config: DungeonGenerationConfig) -> DungeonLayout`
按 `config.algorithm` 分派 `isaac`(默认) / `wfc` / `bsp`，包装进统一 `DungeonLayout`，调用方不再重复推导关键点。

isaac 默认分支（`dungeon_generator.gd:36` `_generate_with_isaac`）：
```gdscript
var gen: Node = load(ISAAC_PATH).new()
var rng := RandomNumberGenerator.new()
if config.seed != 0: rng.seed = config.seed
gen.set_rng(rng)                                  # 可控随机源 → 可复现
var grid: Array = gen.generate_dungeon(config.width, config.height, config.target_room_count)
# ... 拷贝 grid/rooms/room_roles/heights 进 DungeonLayout，推导 5 个关键点
```

### 2.2 isaac 关键常量与结构（`isaac_room_dungeon_generator.gd`）
```gdscript
const ROOM_SIZE := 5
const ROOM_SPACING := 8        # 每个 macro 格占 8x8 瓦片（含房间+缓冲墙/走廊）
const TARGET_ROOM_COUNT := 14
const MACRO_RADIUS := 2
const ROOM_SHAPES := [ ... 21 种房型 ... ]   # 含 pocket_cave/circle/great_hall/ring 等
const GUARANTEED_ROOM_SHAPES := [ ... ]      # 保证出现的房型
const START_ROOM_SHAPES := ["wide","tall","alcove","offset_chamber"]
const ROOM_CONTENT_THEMES := ["empty","loot","resource","pillars","mixed","stash","ritual"]
```
**关键约束**：每个 macro 格当前只放**一个**房间（`_generate_room_graph` 逐 macro 格生长）。可变尺寸 set-piece 需要**多 macro 格预留**（见 §4.3）。

`generate_dungeon` 阶段顺序（`isaac_room_dungeon_generator.gd:76`）：
`_generate_room_graph → _pick_start_macro → _build_room_defs → _assign_room_roles → _ensure_merged_room_connection_count → _carve_rooms_and_corridors → _mark_special_room_cells → _ensure_walkable_connectivity → _lock_outer_walls`

连通性靠 `_ensure_walkable_connectivity`（BFS 自修复至单连通分量）。

### 2.3 现有可外置的数据模型：`WFC_RoomGenerator.RoomTemplate`
`wfc_generator.gd:15` 已经存在一个与需求几乎一致的数据模型——这就是「set-piece」的代码内原型：
```gdscript
enum TileType { EMPTY, FLOOR, WALL, LOOT, RESOURCE, PILLAR }  # EMPTY=0,FLOOR=1,WALL=2,LOOT=3,RESOURCE=4,PILLAR=5
const ANY := -1

class RoomTemplate:
    var name: String
    var width: int
    var height: int
    var layout: Array          # layout[y][x]: int（TileType 或 ANY）
    var spawn_weight: int = 1
```
**设计洞察**：用户想要的「可编辑特殊房间」= 把这个**写死在代码里的 `RoomTemplate` 外置成 `.tres` 资源**。无需重新发明数据模型。

### 2.4 统一结果契约 `DungeonLayout`（`dungeon_layout.gd`）
纯 `RefCounted`，**禁止任何 Node / PackedScene 引用**（否则 `validate()` 报错，`dungeon_layout.gd:298` `_spec_contains_node_ref`）。
关键字段（节选）：
- `grid: Array` —— `Array<Array<int>>`，值为 `BSP_DungeonGenerator.TileType` 枚举整数。
- `rooms: Array[Rect2i]`、`room_roles: Dictionary`（key ∈ `start/boss/extraction/stairs/reward`）。
- 关键点 `player_spawn_cell / boss_cell / extraction_cell / stairs_cell / reward_cell: Vector2i`。
- `door_specs: Array[Dictionary]`（每项 `{inside, outside, dir, boss}`）、`hazard_anchors`、`kick_lanes`、`terrain_features`。
- `enemy_spawn_specs / item_spawn_specs / chest_spawn_specs`（每项用**字符串 ID**，由 roster/registry 解析，不含 Node）。
- `is_floor_at(x,y)`：FLOOR/LOOT/RESOURCE/PILLAR 均可走（≠0 EMPTY、≠2 WALL）。
- `compute_floor_distance_field()`：BFS 距离场，驱动「房间深度」。
- `calc_player_spawn_pos()`：**唯一**出生点来源（联机两端共用，防漂移）。

### 2.5 连通性把关：`DungeonConnectivityValidator`
`dungeon_connectivity_validator.gd:11` `reachable_ratio_threshold = 0.9`
`validate(layout) -> Dictionary`：返回 `{valid, reachable_ratio, missing_required_points, unreachable_rooms, ratio_below_threshold}`。**报告-only，不自动修复**。生成器须自行处理失败（重试/回退）。

### 2.6 生成规划与确定性盐
`dungeon_spawn_planner.gd`：
```gdscript
var rng := _seeded_rng(layout, 0x454E45)  # 敌人 "ENE"
var rng := _seeded_rng(layout, 0x4D4154)  # 物品 "MAT" 域盐，错开序列
```
`_seeded_rng(layout, salt)` 实现：`layout.seed ^ (salt * 2654435761)`（黄金比素数散列）。
**确定性规则**：服务器选 `seed` → 客户端凭 `seed` 本地重建同一地牢；`layout_fingerprint = width|height|grid.hash|player_spawn_cell` 跨进程校验。

### 2.7 注册表范式参考：`WeaponRegistry`（`data/weapon_registry.gd`）
autoload（**无 class_name**，符合项目铁律），加载 `weapons.json` → `Dictionary[String, WeaponData]`，信号 `registry_ready` / `weapon_added`。这是 `SetPieceRegistry` 的直接范本：数据定位器（service/data locator），不含游戏逻辑。

### 2.8 场景构建消费瓦片（`dungeon_scene_builder.gd`）
构建器按 `TileType` 整数实例化节点：
- `5`(PILLAR) → 石柱装饰；`3`(LOOT)/`4`(RESOURCE) → 随机装饰；`≠2 且 ≠0` → 地板/火把。
**结论**：set-piece 图案复用**完全相同的瓦片整数**，无需改构建器瓦片分派逻辑即可渲染。

---

## 3. 生成方式决策对比

### 3.0 核心决策理由（为什么是 Hybrid，而非纯 Barony / 纯 isaac）

选定 **C（Hybrid：isaac 内核 + set-piece 注入）** 不是折中，而是因为它同时满足项目的「设计北极星」与用户的明确需求，且改动面最小、风险最低。逐条论证如下：

**理由 1 — 对齐项目北极星：要「真 roguelike 涌现」，不要「lite 房间拼装」。** 用户已明确：本作对标 NetHack / ToME4 的**系统涌现深度**，而非 Isaac / Hades 式的「手工房间 + 数值堆叠」lite。调研结论（`docs/mapgen_vs_barony.md`）显示：LT 的 isaac **程序化几何生成**更接近 Brogue/NetHack/ToME4 的涌现范式；Barony 的**模板拼装**更接近 lite 的房间装配。若整体换成纯 Barony，等于主动放弃项目核心差异点。Hybrid 保留 isaac 涌现内核，只把「手工可控」限缩到真正需要固定形态的少数特殊房间（Boss 竞技场、仪式房）——这恰是 NetHack/ToME4 的做法：主体程序化，少数特殊层手工固定。

**理由 2 — 复用而非重写：目标数据模型已经存在。** `WFC_RoomGenerator.RoomTemplate`（`wfc_generator.gd:15`）已是「瓦片图案 + 权重 + 尺寸」的数据原型。本设计只是把它**外置成 `.tres` 资源**，几乎零新模型发明。同时整条链路——`DungeonSceneBuilder`（按 `TileType` 整数实例化）、`DungeonSpawnPlanner`、`DungeonConnectivityValidator`——都已消费瓦片网格，set-piece 图案**零改动**即可流过。换成纯 Barony 等于抛弃这一切重造。

**理由 3 — 精确满足用户需求：「特殊房间 = 可编辑、可加入的数据」。** 用户原话：「新特殊房间应也作为一个数据可以编辑和加入。」`SetPieceRoom`（`.tres`）+ `SetPieceRegistry`（丢文件即注册，仿 `WeaponRegistry`）**逐字满足**：策划增删/改房间无需碰生成代码。纯 isaac 做不到（房间由算法分配角色、形态随机）。

**理由 4 — 爆炸半径最小、风险最低。** 注入点是 `generate_dungeon` 中**单一局部阶段**（`_generate_room_graph` 之后、`_pick_start_macro` 之前），不触碰雕刻/连通性核心；set-piece 作为 **macro 图一等节点**参与既有 `DungeonConnectivityValidator`（可达比 ≥ 0.9）门禁与 BFS 自修复。纯 Barony = 替换整个生成器 = 巨大回归面 + 需重推导关键点/角色/流式/联机全部逻辑。

**理由 5 — 确定性与联机「免费」保留。** set-piece 选择用既有 `_seeded_rng(layout, 0x53455450)` 域盐（与敌人/物品序列互不串扰），盖章内容是固定数据 → 完全可复现。`layout_fingerprint` 的 `grid.hash` **自动涵盖** set-piece 内容，联机两端凭同一 `seed` 重建即一致，无需新增同步通道。纯 Barony 需重新设计 seed→重建契约。

**理由 6 — 涌现与手工可控并不互斥，Hybrid 两者兼得。** 程序化生成仍产出绝大多数变化（大小不一的房间、危险地形、掉落分布）；set-piece 只是**稀疏、刻意**的注入，用于那些「形态本身影响玩法可读性」的房间（如固定的 Boss 十字竞技场、带仪式石柱的房间）。这正是传统 roguelike 特殊层的设计哲学。

**理由 7 — 内容管线 ergonomics 等同 Barony，却不失骨干。** 设计师加房间 = 丢一个 `.tres` 进 `data/set_pieces/`，与 Barony 丢 `.lmp` 一样顺手；但背后仍是 isaac 程序化骨干在提供变化与连通性兜底。

**被否定方案的补充反驳：**
- *「为何不纯 isaac + 加更多 `ROOM_SHAPES`？」* —— `ROOM_SHAPES` 是几何模板，仍由算法随机分配、角色模糊，无法**保证**某个 Boss 槽位落到「带脚本石柱的十字竞技场」且带专属 `spawn_overrides`；set-piece 提供确定性落位 + 内部手工结构 + 生成覆盖，这是 `ROOM_SHAPES` 给不了的。
- *「为何不直接扩展 WFC `RoomTemplate`？」* —— WFC 是另一条算法分支，不产出 `room_roles`/关键点，与默认 isaac 管线不融合，重复角色分配工作；故留作未来统一模型（§6），不在 v1 承载。
- *「为何不纯 Barony 模板拼装？」* —— 见理由 1（放弃涌现=放弃核心差异点）+ 理由 4（重写风险）。

### 3.1 候选方案对比

| 候选方案 | 描述 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| A. 纯 Barony 模板拼装 | 全图由手工 `.lmp`/`.tres` 房间拼装 + 门口拆墙 | 内容极度可 mod；形态完全可控 | 放弃 isaac 程序化涌现（用户要的「真 roguelike 深度」受损）；连通性靠涌现不稳；重写量大 | ❌ 违背项目核心目标 |
| B. 纯 isaac（现状） | 特殊房仍算法分配角色 + 程序化雕刻 | 系统涌现强；零改动 | 策划无法手工设计固定形态；无法满足「特殊房间可编辑」需求 | ❌ 不满足需求 |
| C. **Hybrid：isaac 内核 + set-piece 注入（选定）** | isaac 照常生成；set-piece 作为 macro 一等节点注入，带 `door_anchors` 接入连通性 | 兼得程序化变化 + 手工可控；外置 `RoomTemplate` 模型；复用现有构建/规划/验证链 | 需改 isaac 注入点 + 多 macro 预留；连通性需 set-piece 参与 | ✅ **采用** |
| D. 扩展 WFC `RoomTemplate` | 把 set-piece 当 WFC pin | 模型已存在 | WFC 是另一算法分支；不与 isaac 默认管线融合；room_roles 不产出 | ⚠️ 留作未来统一模型（§6） |

**决策：C（Hybrid）。** 它在本项目「真 roguelike 涌现」目标与「特殊房间可编辑」需求之间取得最佳平衡，且改动面最小（注入点局部、复用全链路）。

---

## 4. 设计详述

### 4.1 数据模型：`SetPieceRoom`（资源）

`class_name SetPieceRoom extends Resource` —— 放在 `data/set_piece_room.gd`，由编辑器「New Resource」创建 `.tres`。

```gdscript
class_name SetPieceRoom
extends Resource

## 作者化「房间印章」：手工设计的特殊房间，作为数据资源可被编辑/增删，无需改生成代码。
## tile_pattern 在 isaac 生成时被「盖章」进地牢网格，经 DungeonSceneBuilder 现有瓦片→节点管道实例化。
## 本资源是纯数据，不持有任何 Node/PackedScene（遵守 DungeonLayout 契约的 no-Node 原则）。

@export var id: String = ""                       # 唯一 ID，如 "boss_arena_cruciform"
@export var display_name: String = ""

# tile_pattern: Array[Array[int]]，与 BSP/WFC 同 TileType 枚举（0 EMPTY/1 FLOOR/2 WALL/3 LOOT/4 RESOURCE/5 PILLAR）。
# 边界（首末行/列）必须为 WALL；ANY(-1) 表示该格由 isaac 决定（默认雕为 FLOOR）。
@export var tile_pattern: Array = []

# door_anchors: 连接锚点（局部瓦片坐标，相对于 tile_pattern 左上角）。
# 每项 {edge:String("N"|"S"|"E"|"W"), cell:Vector2i(local), dir:Vector2i(朝外单位向量)}
# 注入时映射为全局格，isaac 在锚点处与相邻 macro 房间连走廊。
@export var door_anchors: Array[Dictionary] = []

@export var weight: float = 1.0                   # 被选权重（越大越常出现）
@export var allowed_zones: Array[int] = []        # 空=所有 zone
@export var min_depth: int = 0                    # 距出生点最小 BFS 深度（格）
@export var max_depth: int = 999999              # 距出生点最大 BFS 深度
@export var required_role: String = ""           # ""/"boss"/"extraction"/"reward"/"stairs" —— 强占该 role 的 macro 槽
@export var blocked_roles: Array[String] = []    # 不可出现在这些 role 房间（如 "start" 不放陷阱房）
@export var spawn_overrides: Dictionary = {}     # {enemy:Array, item:Array, chest:Array} 覆盖默认 spawn 规划
@export var ceiling_height: float = 3.4          # 该房间天花板高度（覆盖 zone 默认）

## 由 tile_pattern 尺寸推导占用的 macro 格数（每 macro = ROOM_SPACING 瓦片，含缓冲）。
## 不存储 footprint，避免与 ROOM_SPACING 常量重复耦合（注入时读 IsaacRoomDungeonGenerator.ROOM_SPACING）。
func macro_footprint(spacing: int) -> Vector2i:
    var w: int = tile_pattern[0].size() if tile_pattern.size() > 0 else 0
    var h: int = tile_pattern.size()
    return Vector2i(cei(w / spacing), ceili(h / spacing))

## 编辑器/测试期校验：图案是否矩形、边界是否 WALL、door_anchor 是否在界内。
func is_valid() -> bool:
    if tile_pattern.is_empty():
        return false
    var h: int = tile_pattern.size()
    var w: int = (tile_pattern[0] as Array).size()
    for row in tile_pattern:
        if (row as Array).size() != w:
            return false
    # 边界必须是 WALL
    for x in range(w):
        if int(tile_pattern[0][x]) != 2 or int(tile_pattern[h - 1][x]) != 2:
            return false
    for y in range(h):
        if int(tile_pattern[y][0]) != 2 or int(tile_pattern[y][w - 1]) != 2:
            return false
    for a in door_anchors:
        var c: Vector2i = a["cell"]
        if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
            return false
    return true
```

> 注：`ceili` 为示意；实装用 `ceil()`。TileType 常量值直接写整数以与 `DungeonLayout.grid` 的整数存储一致（isaac 内部也用整数）。

### 4.2 注册表：`SetPieceRegistry`（autoload，仿 WeaponRegistry）

`data/set_piece_registry.gd`——**autoload、无 class_name**（项目铁律）。在 `_ready()` 扫描 `res://data/set_pieces/` 下全部 `.tres` 的 `SetPieceRoom`，注册进 `Dictionary[String, SetPieceRoom]`。

```gdscript
## 特殊房间印章注册表：加载 data/set_pieces/*.tres，供 isaac 注入期按 id 查询。
## 纯数据定位器，不含游戏逻辑。新增房间 = 丢一个 .tres 进目录，无需改代码。
extends Node

var _pieces: Dictionary = {}          # String(id) -> SetPieceRoom
signal registry_ready
signal set_piece_registered(id: String)

func _ready() -> void:
    _load_all()
    registry_ready.emit()

func _load_all() -> void:
    var dir := DirAccess.open("res://data/set_pieces/")
    if dir == null:
        push_warning("[SetPieceRegistry] data/set_pieces/ 不存在")
        return
    dir.list_dir_begin()
    var fname := dir.get_next()
    while fname != "":
        if fname.ends_with(".tres"):
            var res := load("res://data/set_pieces/" + fname) as SetPieceRoom
            if res != null and res.is_valid():
                if _pieces.has(res.id):
                    push_error("[SetPieceRegistry] 重复 id: %s (%s)" % [res.id, fname])
                else:
                    _pieces[res.id] = res
                    set_piece_registered.emit(res.id)
        fname = dir.get_next()
    dir.list_dir_end()

func get_set_piece(id: String) -> SetPieceRoom:
    return _pieces.get(id, null)

func get_all() -> Array[SetPieceRoom]:
    var out: Array[SetPieceRoom] = []
    for p in _pieces.values():
        out.append(p)
    return out

## 按约束过滤（zone/depth/role），供 isaac 注入期加权随机选择。
func filter_candidates(zone: int, depth: int, reserved_role: String) -> Array[SetPieceRoom]:
    var out: Array[SetPieceRoom] = []
    for p in _pieces.values():
        if not p.allowed_zones.is_empty() and not zone in p.allowed_zones:
            continue
        if depth < p.min_depth or depth > p.max_depth:
            continue
        if reserved_role != "" and p.required_role != "" and p.required_role != reserved_role:
            continue
        if reserved_role != "" and reserved_role in p.blocked_roles:
            continue
        out.append(p)
    return out
```

### 4.3 isaac 集成：注入点（macro 一等节点 + 多 macro 预留）

**插入位置**：在 `generate_dungeon` 的 `_generate_room_graph` 之后、`_pick_start_macro` 之前，新增 `_inject_set_pieces()`。

**步骤：**
1. **选择**：用 `_seeded_rng(layout, 0x53455450)`（"SETP" 盐）加权抽取 set-piece 候选。`required_role` 非空的 set-piece 优先绑定到对应 role 的 macro 槽（在 `_assign_room_roles` 之前锁定，使其跳过自动分配）。
2. **多 macro 预留**：`footprint = piece.macro_footprint(ROOM_SPACING)`。若 `footprint > (1,1)`，在 macro 图上**预留连续 macro 块**作为单个「超级节点」，阻止程序化房间占用这些 macro 格（标记为 `reserved`，不进入 `_room_defs` 的普通雕刻）。
3. **盖章**：把 `tile_pattern` 写入 `grid`（全局偏移 = macro 原点 × `ROOM_SPACING`）。ANY(-1) 格由 isaac 后续按普通房间逻辑补雕为 FLOOR。
4. **door_anchor 接线**：将 `door_anchors` 映射为全局格，写入 `door_specs`（复用 `{inside, outside, dir, boss}` 结构，boss 标记来自 `required_role=="boss"`）；在 `_carve_rooms_and_corridors` 阶段把这些锚点视为「房间门」，与相邻 macro 房间连走廊。
5. **天花板**：set-piece 占用的 `heights` 格覆写为 `ceiling_height`。

**连通性保证（关键）**：set-piece 的 `door_anchors` 必须是图案边界上的 FLOOR 开口，且 `_ensure_walkable_connectivity`（BFS 自修复）将其当作普通门口——**set-piece 是 macro 图一等节点，绝不绕过连通性验证**（对应 `mapgen_vs_barony.md` §5 风险提示）。

**失败回退**：若 `DungeonConnectivityValidator.validate(layout).valid == false`（如某 set-piece 把房间封死），注入器**移除该 set-piece 的盖章 + 释放预留 macro**，让该 macro 回退为程序化房间，重跑连通性。最多回退 `N` 次仍失败则放弃该 set-piece（不阻塞整图生成）。

**确定性**：选择序 + 盖章位置 + 图案均为 seed 确定；`layout_fingerprint` 的 `grid.hash` 自动覆盖 set-piece 内容，联机两端一致。

### 4.4 场景构建消费（`DungeonSceneBuilder`）

- **瓦片**：set-piece `tile_pattern` 用的是与现有完全相同的 `TileType` 整数（FLOOR/LOOT/RESOURCE/PILLAR/WALL），构建器瓦片分派逻辑**零改动**即可渲染。
- **富装饰（可选）**：若 set-piece 需要超出 6 种瓦片的表现（脚本谜题、专属道具摆位），在 `DungeonLayout` 新增 `set_piece_specs: Array[Dictionary]`（每项 `{set_piece_id:String, origin_cell:Vector2i, role:String}`——**只存 id 字符串，不存 Node**，满足 `validate()` 的 no-Node 检查）。构建器经 `SetPieceRegistry.get_set_piece(id)` 解析到可选的 `PackedScene` 子场景（registry 是运行时注册表，可持 `PackedScene`，与 enemy/item roster 同机制）。

### 4.5 生成规划消费（`DungeonSpawnPlanner`）

- 读取 `set_piece_specs` 中 `spawn_overrides`，对占用房间**覆盖/抑制**默认 enemy/item/chest 规划：
  - `TreasureVault` → 强制 `chest_spawn_specs`、抑制敌人。
  - `AmbushHall` → 强制精英敌人。
  - `RitualRoom` → 抑制掉落、可能放互动锚点。
- 仍走现有 `_seeded_rng(layout, salt)` 序列，与 set-piece 选择盐（0x53455450）相互独立，互不串扰。

### 4.6 配置开关
在 `DungeonGenerationConfig` 增加（保持顶层字段稳定）：
```gdscript
var enable_set_pieces: bool = true          # 是否注入 set-piece（Phase 2+ 默认开）
var max_set_pieces: int = 3                 # 单次生成最多注入数量
var set_piece_seed_salt: int = 0x53455450   # "SETP" 域盐
```
`DungeonGenerator._generate_with_isaac` 把这两个值传给 isaac 注入器。

---

## 5. 分阶段实现计划

| 阶段 | 范围 | 交付 | 验证 |
|---|---|---|---|
| **P1** | `SetPieceRoom` 资源 + `SetPieceRegistry` + 1 个示例 `.tres` | 资源可建、注册表可加载 | `set_piece_registry_test.gd`：加载示例、拒绝非法图案（非矩形/边界非 WALL/anchor 越界） |
| **P2** | isaac 注入器（单 macro footprint 1×1）+ 连通性把关 | 1–2 个简单 set-piece（如 `boss_arena_simple`）注入成功 | `set_piece_injection_test.gd`：固定 seed 下 `layout.validate().valid`、validator `reachable_ratio ≥ 0.9`、`required_role=="boss"` 命中 |
| **P3** | 多 macro footprint（2×1 / 2×2）+ 失败回退 | 大房 set-piece 可用 | `set_piece_connectivity_fallback_test.gd`：模拟封死 → 断言已回退 |
| **P4** | `spawn_overrides` + 构建器富装饰（id→PackedScene）+ 真实 3–5 个 set-piece（Boss 竞技场/仪式房/宝库/谜题房/伏击厅） | 端到端内容 | 手动 F6 单场景验证 + 回归 |
| **P5** | 编辑器辅助（@tool 预览盖章网格）、文档、平衡 | 策划可用 | 文档 + 平衡 pass |

**每阶段结束前**：相关场景可独立运行（F6）不崩；全量 gdUnit 回归通过。

---

## 6. 测试策略（gdUnit4）

- `tests/gdunit/set_piece_registry_test.gd`
  - 加载 `data/set_pieces/` 全部 `.tres`：断言 id 唯一、`is_valid()` 全过。
  - 喂入非法图案（非矩形 / 边界非 WALL / anchor 越界）：断言 `is_valid()==false`。
- `tests/gdunit/set_piece_injection_test.gd`
  - 固定 seed × 启用 set-piece → 断言 `DungeonLayout.validate().valid`；`DungeonConnectivityValidator` 的 `reachable_ratio ≥ 0.9`。
  - `required_role=="boss"` 的 set-piece 在生成后确有 boss 房间且图案匹配。
  - **确定性**：同 seed 两次生成 → `layout_fingerprint` 相等。
- `tests/gdunit/set_piece_connectivity_fallback_test.gd`
  - 注入一个会把房间封死的 set-piece → 断言注入器回退（validator 最终通过）。
- `tests/gdunit/set_piece_determinism_mp_test.gd`
  - 模拟「服务器选 seed / 客户端重建」：两端 `layout_fingerprint` 一致（含 set-piece 内容）。

---

## 7. 开放问题 / 待定

1. **跨 streaming chunk**：`DungeonStreamingController` 的 chunk=8 格。2×2 macro set-piece = 16×16 瓦片跨 2 个 chunk。需确认空间流式激活对跨 chunk 房间无碍（预期无碍，streaming 按空间非按房间）。**待 Phase 3 实测**。
2. **与 WFC/BSP 的统一**：WFC 已有 `RoomTemplate`，未来可让 WFC 直接消费 `SetPieceRoom`（统一数据模型）；BSP 无 room 概念，暂不入。本设计 v1 仅 isaac。
3. **作者化 UX**：v1 文本编辑 `.tres`；理想是 `@tool` 可视盖章器（点格设 TileType、导出 `.tres`）。留 Phase 5，不阻塞。
4. **set-piece 内「动态脚本」**：谜题房的交互逻辑（拉杠杆开门等）属于 runtime 行为，由 `set_piece_specs` 的 id→PackedScene 子场景承载，不进生成期。具体交互脚本设计另立文档。

---

## 8. 附录：真实 API 引用清单（供实现期对照）

| 符号 | 文件 | 行/说明 |
|---|---|---|
| `DungeonGenerator.generate(config)` | `scenes/expedition/dungeon_generator.gd:19` | 统一出口，按 algorithm 分派 |
| `DungeonGenerationConfig` | `scenes/expedition/dungeon_generation_config.gd` | seed/zone/width/height/tile_size/algorithm/target_room_count + isaac_params |
| `IsaacRoomDungeonGenerator` | `scenes/expedition/isaac_room_dungeon_generator.gd` | ROOM_SPACING=8、ROOM_SHAPES(21)、`generate_dungeon()`、`set_rng()` |
| `WFC_RoomGenerator.RoomTemplate` | `scenes/expedition/wfc_generator.gd:15` | 现有可外置数据模型原型 |
| `BSP_DungeonGenerator.TileType` | `scenes/expedition/bsp_generator.gd` | 枚举 {EMPTY=0,FLOOR=1,WALL=2,LOOT=3,RESOURCE=4,PILLAR=5} |
| `DungeonLayout` | `scenes/expedition/dungeon_layout.gd` | 纯数据契约；grid/rooms/room_roles/关键点/door_specs/spawn_specs；validate() 禁 Node 引用 |
| `DungeonConnectivityValidator` | `scenes/expedition/dungeon_connectivity_validator.gd:11` | reachable_ratio_threshold=0.9，报告-only |
| `DungeonSpawnPlanner._seeded_rng` | `scenes/expedition/dungeon_spawn_planner.gd:328` | 域盐 `0x454E45`(敌)/`0x4D4154`(物) |
| `WeaponRegistry` | `data/weapon_registry.gd` | autoload 注册表范本（无 class_name） |
| `DungeonSceneBuilder` | `scenes/expedition/dungeon_scene_builder.gd` | 按 TileType 整数实例化（5=PILLAR/3=LOOT/4=RESOURCE/≠2≠0=地板火把） |

---

*本设计基于 2026-07-21 对 `scenes/expedition/` 与 `data/` 真实源码的审阅，以及与 `docs/mapgen_vs_barony.md` 的关联结论。任何实现改动须保持现有分层、纯数据契约、确定性/联机重建与连通性验证不变。*
