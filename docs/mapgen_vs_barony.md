# 地图生成架构对比:Lantern Tavern vs Barony

> 审查日期:2026-07-21
> 对象:Lantern Tavern(`scenes/expedition/`) vs Barony 开源源码(`src/maps.cpp`)
> 结论:两者生成范式根本不同 —— LT 是**从零程序化生成几何**,Barony 是**拼装手工模板房间**。

---

## 1. Lantern Tavern 生成架构(现状)

管线(`ProceduralDungeon._ready()` 驱动):

```
Config(seed, zone, algorithm)
  → DungeonGenerator.generate()            // 按 config.algorithm 分派
      isaac(默认) | wfc | bsp
  → DungeonLayout (纯数据 RefCounted,无 Node 引用)
  → DungeonLayout.validate() + DungeonConnectivityValidator (BFS, 可达比≥0.9, 自修复)
  → DungeonHazardPlanner / DungeonSpawnPlanner (纯数据 spec)
  → DungeonSceneBuilder.build() → DungeonBuildResult (MultiMesh 地形/碰撞/门/陷阱/宝箱/撤离门/下楼 portal/火把/NavMesh)
  → DungeonStreamingController (chunk=8 格增量激活)
  → DungeonRuntime (spawn 玩家/敌人/物品/HUD/探索压力/撤离)
```

关键特征:
- **默认算法 isaac**:自底向上生长「宏观房间图」(macro-grid, 间距 8) → 每个 macro 雕刻 21 种房型(含噪声洞窟) → 走廊 + shortcut + merged 桥接 → **BFS 连通自修复**至单连通分量。
- **角色分配是算法的**:terminal 房间按到 start 的图距离排序,分配 start/boss/extraction(0.2 概率)/stairs/reward;关键点直接写入 `DungeonLayout`,调用方不重复推导。
- **垂直度**:每格天花板高度场(3.0–4.6m),营造洞窟体积感。
- **确定性**:seed 注入 `RandomNumberGenerator`;敌人/物品/陷阱用域盐子 RNG(`0x454E45`/`0x4D4154`/黄金比素数)互不串扰。联机时服务器选 seed,客户端凭 seed 本地重建同一地牢,`layout_fingerprint = width|height|grid.hash|player_spawn_cell` 跨进程校验;`calc_player_spawn_pos()` 为唯一出生点来源。
- **深度模型**:下楼 = 每次重新生成全新随机地牢(seed=0 → 新种子);地牢内「深度」由 `compute_floor_distance_field()`(BFS 距离场)驱动敌人密度梯度/喘息房/掉落。Zone(0..5)由酒馆选择决定生态与外观,≠ 层深。
- **架构质量**:分层、GDScript strict 静态类型、数据契约优先、零节点生成期、完整 gdUnit 单测覆盖。

---

## 2. Barony 生成架构(源码 `src/maps.cpp`)

入口:`generateDungeon(char* levelset, Uint32 seed, mapParameters)`

```
generateDungeon(levelset, seed)
  → 加载基础 .lmp 地图 + 子房间池(loadSubRoomData)
  → 按 possiblelocations 扫描候选偏移,随机挑位置放置房间(拷贝 MAPLAYERS 瓦片层 + 实体)
  → 后处理:遍历 doorList,在预定义门口之间拆掉障碍瓦片打通(无路由算法)
  → submap:模板中 tile==201 的锚点替换为随机子子图(mines00a..z.lmp)
  → 特殊房间按固定循环序号 c 或楼层表插入(c==0 起始房, c==2 商店, 宝藏每5层, orb 在 8/13/18)
  → 输出:map.tiles[] 多维瓦片数组 + map.entities 实体链表(像素坐标)
```

关键特征:
- **范式 = 模板拼装**:几何全部来自外部 `.lmp` 手工模板;生成 = 放置 + 门口拆墙 + submap 替换。**几乎没有算法化的房间形状生成**。
- **连通性 = 涌现的**:无走廊路由。房间边缘预标 `door_t`,后处理在相邻门口间敲掉障碍瓦片;起始房若没出口则 `checkBorderAccessibility()` 强行挖洞。
- **特殊房间 = 固定槽位/楼层表**:由 `currentlevel` 序号或 `TreasureRoomGenerator` 楼层表(宝藏每5层、神器球 8/13/18)决定,确定性按层号而非拓扑。
- **输出**:多层 2D 瓦片数组(`map.tiles[z + y*MAPLAYERS + x*MAPLAYERS*height]`;z=0 地面/实体,OBSTACLELAYER 墙,顶层天花板)+ 像素坐标实体链表。生成与内容交错写入共享可变数组,无干净的数据/渲染边界。
- **垂直度:无**。扁平单层瓦片网格(类 Dungeon Master / Legend of Grimrock 的网格地牢),第一人称 3D 渲染但生成是 2D 平面。
- **确定性**:`map_rng`/`map_server_rng` 由 seed 字节播种;宝藏用独立 `treasure_rng`(来自 uniqueGameKey±64)。同种子同图。
- **深度模型**:层级顺序(currentlevel 1..N),每层的秘密/牛头人/黑暗/商店参数由层号决定;怪物曲线 `monsterCurve()` 按地图名(The Mines/Hell/Swamp)+ 层号切换。
- **架构质量**:单体内核 C++(作者自承「C 仓促转 C++、全局变量满天飞」);但**内容极度可 mod**——丢一个新 `.lmp` + 字母后缀即可加房间变体。

---

## 3. 核心差异对照

| 维度 | Lantern Tavern | Barony |
|---|---|---|
| 生成范式 | 算法程序化生成几何(房间图生长 + 形状雕刻) | 模板房间拼装(放置 + 门口拆墙) |
| 连通性 | 算法走廊 + BFS 自修复,构造并验证 | 预定义门口拆墙,连通性涌现 |
| 特殊房间 | 按图距离算法分配角色 | 固定槽位/楼层表,按层号确定 |
| 输出表示 | 纯数据契约 → 独立实例化阶段变节点 | 直接写共享瓦片数组 + 实体链表 |
| 垂直度 | 每格天花板高度场(3D 体积) | 扁平单层网格(2D 平面) |
| 确定性 | seed 注入 + 域盐子 RNG + 指纹校验 | seed 播种 + 独立 treasure_rng |
| 深度模型 | 每次下楼 = 全新随机图;距离场驱梯度 | 顺序层号驱参数/怪物曲线 |
| 架构质量 | 分层、强类型、单测覆盖 | 单体、全局变量、但内容可 mod |
| 可扩展性 | 算法可插拔(isaac/wfc/bsp);加房型要写代码 | 加房间=丢 .lmp;内容 mod 极友好 |
| 联机确定性 | 服务器选 seed,客户端重建 + 指纹校验(防作弊) | map_server_rng 确定性(合作向) |

---

## 4. 一个反直觉的结论

尽管 Barony 在**设计精神**上是「真 roguelike」(永久死亡、网格、模拟深度),但其**生成技术**是「模板房间拼装」——这一族其实更接近 Hades/Isaac 这类 roguelite 的房间缝合。

反观 LT 的 isaac 生成器是**程序化几何生成**(房间图 + 形状雕刻 + 自修复),这一族更接近 **Brogue / NetHack / ToME4** 的「传统 roguelike 生成」。

也就是说:**在「地图生成」这一具体维度上,LT 反而比 Barony 更接近用户想要的「真 roguelike 系统涌现」范式**;Barony 更适合作为美术/手感/物理/环境的参照(与项目既有定位一致),而不适合作为生成架构的参照。

---

## 5. 对 Lantern Tavern 的启示

- **可向 Barony 借的**:「手工房间印章」(handcrafted room stamp / submap)工作流。LT 的 WFC 模板只覆盖房间内部;可加一套「作者化 set-piece 房间」(固定 Boss 竞技场、脚本谜题房)通过配置注入,无需改生成代码——兼得程序化变化与手工把控。
- **Barony 向 LT 借的(概念上)**:数据/渲染分离 + 连通性验证。Barony 的模板拼装保证「房间本身可通行」(人设计的),但 LT 的算法自修复保证「整图单连通」更稳。
- **风险提示**:LT 纯程序化房间偶尔产出怪形状需自修复;若引入 authored set-piece,需让 isaac 把「手工房间」当作 macro 节点纳入图连接,而非绕过连通性验证。
