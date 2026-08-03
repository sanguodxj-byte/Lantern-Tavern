# Lantern Tavern 项目架构梳理与审查

**审查日期**：2026-08-02  
**审查性质**：当前工作树的只读静态架构审查；未修改业务代码、场景、资产或项目配置。  
**基线风险**：工作树当前约有 **387 个已修改/删除路径 + 1539 个未跟踪路径，共 1926 个脏路径**。因此本报告描述的是当前机器状态，不是可复现的发布基线。  
**总体评级**：**D+（局部架构方向正确，但联机权威战斗/移动、法术事务、平台交付和工程门禁存在发布阻断项）**。

---

## 1. 执行摘要

项目已经不是早期原型：它拥有明确的领域目录、较丰富的 gdUnit4 契约、服务器权威联机骨架、确定性地牢生成、数据注册表、独立伤害解析器和视觉/结算分层。但它目前处于“多轮功能快速落地后，架构收口尚未完成”的阶段。

### 最重要的判断

1. **不能把当前联机称为服务器权威完成**：服务器移动只是坐标数学积分，没有使用碰撞世界；战斗仍信任客户端 `attack_type`，并用残缺的默认 `AttackInput`。
2. **法术链存在事务断裂**：可能先扣法力、提交冷却，再因为没有绑定权威 caster 而不执行世界效果。
3. **单机与联机玩法规则分叉**：攻击冷却至少三套；玩家成长/击杀经验仍围绕本地 `GameState.current_player`，服务器联机击杀链没有同等结算。
4. **大脚本已成为变更风险中心**：`DungeonSceneBuilder` 2417 行/114 函数，`TavernEquipmentPanel` 1926 行/131 函数，`Player` 1322 行/102 函数，`SessionRoot` 909 行/48 函数。
5. **平台交付没有闭环**：移动 renderer 配置仍为 Forward+，导出预设只有 Web，没有目标桌面与 Android。
6. **测试很多，但过度依赖源码字符串**：457 个测试脚本中，244 个包含源码读取/反射式断言，共约 1047 次；这类测试能守结构，却不能证明真实行为。

### 风险统计

| 级别 | 数量 | 含义 |
|---|---:|---|
| P0 | 7 | 发布/联机正确性/运行时阻断 |
| P1 | 8 | 高概率造成规则漂移、维护失控或平台性能失真 |
| P2 | 6 | 工程治理、文档、测试与可维护性债务 |

---

## 2. 当前架构全景

### 2.1 代码规模与依赖指标

使用当前源码重新生成临时代码图谱（未覆盖仓库旧图谱）：

- 首方 `.gd`：**783**
- `class_name`：**187**
- 函数：**9452**
- 信号：**84**
- RPC 函数：**10**
- 依赖边（preload/extends/autoload）：**1422**
- Autoload：**31**

高频全局依赖使用次数（静态扫描）：

| Autoload | 使用脚本数 |
|---|---:|
| `GameState` | 55 |
| `PhysicsSetup` | 40 |
| `GameEvents` | 39 |
| `TavernManager` | 24 |
| `AudioManager` | 23 |
| `WeaponRegistry` | 20 |
| `NetworkManager` | 13 |

这说明项目领域划分存在，但大量规则仍通过全局状态和服务定位器横向连接。

### 2.2 运行时模块地图

```text
MainMenu / World / Lobby
  ├─ 单机世界切换：TavernManager -> World.load_space / change_scene
  ├─ 单机玩家状态：GameState
  │    ├─ ExpeditionInventory
  │    ├─ EquipmentLoadout
  │    ├─ SpellLoadout
  │    └─ PlayerContext（过渡句柄）
  ├─ 属性/技能：AttrPanel + SkillRuntime（autoload 兼容层）
  ├─ 存档：SaveManager 汇总 TavernManager/GameState/AttrPanel/SkillRuntime/...
  └─ 联机：NetworkManager
       -> SessionRoot
          ├─ PlayerRegistry / WorldState / CommandRouter / Validator
          ├─ MovementAuthority / CombatAuthority / InteractionAuthority
          ├─ LootAuthority / DungeonAuthority / SaveAuthority
          └─ EntitySyncAuthority / SpellAuthority
       -> MultiplayerSceneBridge（显式 RPC 表现复制）
```

```text
地牢生成
DungeonGenerationConfig
  -> DungeonGenerator / IsaacRoomDungeonGenerator
  -> DungeonLayout（确定性布局 + 出生点）
  -> DungeonSceneBuilder
       terrain / collision / occluder / doors / hazards / chests
       room focus / cliff / ramp / navmesh / decor / torches / batching
  -> DungeonRuntime + DungeonStreamingController
```

```text
单机战斗
Player 状态机 / Enemy 状态机
  -> CombatBridge
  -> DamageResolver (+ ArmorResolver)
  -> Health / 状态 / FX / 成长

联机战斗
ClientCommandDriver
  -> NetworkManager.submit_command
  -> SessionRoot._handle_combat
  -> CombatAuthority -> DamageResolver
  -> entity snapshot/despawn + combat_resolved
  -> MultiplayerSceneBridge
```

### 2.3 当前架构中做得正确的部分

- `DamageResolver` 从 `CombatEngine` 外观层拆出，避免反向 preload 循环，纯逻辑边界方向正确（`globals/combat/damage_resolver.gd:1-15`、`combat_engine.gd:5-21`）。
- 装备静态数据以 `data/weapons/weapons.json` 为入口，`WeaponRegistry` 构造运行时 `WeaponData` 并提供旧 `.tres` 兼容（`data/weapon_registry.gd:9-21,81-189`）。
- `ExpeditionInventory`、`EquipmentLoadout`、`TavernLedger` 等已从巨型全局状态中抽出为纯数据对象。
- 联机有统一协议常量、序列防重放、world revision、GUID+token 重连、实体差集对账（`network_protocol.gd`、`command_validator.gd`、`session_root.gd:268-380,825-909`）。
- 快照已做 30Hz 合并缓冲，spawn/despawn 保持即时；实体重连快照会反查清理幽灵节点（`network_manager.gd:55-69,371-388`；`multiplayer_scene_bridge.gd:215-242`）。
- 地牢已有生成配置、布局、构建结果、运行时配置、流控配置等分层对象，并落地敌人分帧、导航错峰、AI 半径、动态物理激活等性能措施。
- 法术 FX 与伤害职责有明确意图：`PixelSpellFx` 只表现，`SpellRuntime` 产 effect plan，世界效果由 Authority/Executor 消费。

---

## 3. P0：必须先处理的阻断项

## P0-1 服务器移动没有物理碰撞，权威位置可穿墙

**证据**：

- `globals/multiplayer/movement_authority.gd:51-57`：`integrate_position()` 仅执行 `old_pos + dir * speed * dt`。
- `movement_authority.gd:61-80`：输入通过后直接产生新位置，没有 `CharacterBody3D.move_and_slide()`、`PhysicsDirectSpaceState3D` sweep、导航可行性或地牢格阻挡校验。
- `scenes/multiplayer/dungeon_session_controller.gd:38-41` 明确写出 Dedicated Server 移动为“纯数学积分，不依赖碰撞几何”。
- `docs/25-联机总体方案.md:393-401` 的规范要求服务器“根据服务器物理状态执行移动”。

**影响**：客户端不能自报坐标，但可以持续提交合法方向输入穿过墙体、门、障碍和敌人；这不是服务器权威移动，只是服务器权威积分。

**最小整改切片**：

1. 新增 `ServerCharacterMotor` 接口：输入 `live_state + move intent + collision world`，输出 `MotionResult`。
2. Listen Server 直接绑定真实 `CharacterBody3D` 并调用 `move_and_slide()`；Dedicated Server 加载简化碰撞场景，而不是 authority-only 纯布局。
3. `MovementAuthority` 只负责输入校验和速率政策，不再拥有最终坐标积分。
4. 补“墙前持续输入不得穿透、门关闭不得穿过、悬崖/高差不可瞬移”的真实场景双进程测试。

## P0-2 联机攻击信任客户端 `attack_type`，并使用残缺默认 AttackInput

**证据**：

- `client_command_driver.gd:114-130`：客户端直接提交 `attack_type`。
- `session_root.gd:423-430`：服务器用客户端 `attack_type` 决定 18m 或 2.5m 射程；任意非空武器都能支撑“远程”。
- `session_root.gd:462-475`：服务器只填六维属性和客户端攻击类型，没有填武器骰、平伤、武器倍率、流派、熟练度、词缀、元素、被动、手位。
- `DamageResolver.AttackInput` 的这些字段均有默认值（`damage_resolver.gd:109-156`），因此联机实际上会退化为默认 1d6/ONE_HAND 等占位输入。
- `combat_authority.gd:75-82` 已有武器归属校验，但 `_handle_combat()` 没有使用。

**影响**：可伪报 ranged 获得错误射程；联机伤害与单机装备/流派/熟练度完全分叉。

**最小整改切片**：

1. 命令只允许 `action_id/hand/target_hint/charge_ratio`，移除 `attack_type`。
2. 服务端从 `ctx.loadout + WeaponRegistry + ctx.attributes + ctx.skills` 构造唯一 `AttackContext`。
3. 由同一 `AttackContext` 派生攻击类型、射程、冷却、`AttackInput`、表现标签。
4. 单机 `CombatBridge.build_player_attack()` 改为消费同一个纯逻辑构造器，禁止两套装配逻辑。

## P0-3 攻击冷却至少三套，已决定语义没有成为单一真相

**证据**：

- `CombatEngine.compute_attack_interval()`：`1.0 / (style_mult * dex_mult)`（`combat_engine.gd:32-57`）。
- 单机玩家硬锁使用 `PlayerCombatRuntime` 的 0.45 秒基础、双手 1.5 倍、副手 0.38 秒和被动乘区（`player_combat_runtime.gd:17-23,93-125`）。
- 服务端固定 `SERVER_ATTACK_CD = 0.4`（`session_root.gd:94-100,476-477`）。
- 客户端网络发送节流固定 0.5 秒（`client_command_driver.gd:25-27,119-121`）。

**影响**：HUD、动画、本地输入门与服务器裁决不同步；DEX、流派、双持、被动在联机中失真。玩家硬冷却已经落地，但**没有按已裁定公式落地**。

**最小整改切片**：建立纯逻辑 `AttackCadencePolicy`，只接受 `AttackContext`，返回权威冷却；PlayerCombatRuntime、SessionRoot 和 HUD 共用。客户端 0.5 秒只能作为防洪，不参与玩法。

## P0-4 法术资源 commit 与世界执行不具原子性

**证据**：

- `session_root.gd:606-611`：先检查并提交冷却，再扣法力。
- `session_root.gd:617-618`：只有 `ctx.player_node != null` 才执行 `spell_auth.execute()`。
- `session_root.gd:184-185`：spawn 时创建 `PlayerContext`，传入的 player 为 `null`。
- `dungeon_session_controller.gd:94-107`：创建本地真实 Player 后，没有将其绑定回对应服务器 `PlayerContext.player_node`。

**影响**：真实入口可能返回成功、减少法力、开始冷却、播放 FX，但没有投射物/治疗/区域/召唤的权威效果。

**最小整改切片**：

1. 新增明确的 `SessionRoot.bind_player_entity(peer_id, player_entity)`。
2. caster 未绑定时在任何资源 commit 前拒绝 `PLAYER_NOT_READY`。
3. 改为 `prepare -> validate world execution -> commit mana/cooldown -> publish event`；执行失败必须不扣资源，或提供回滚。
4. 补真实行为测试，而不是只检查源码包含 `spell_auth.execute`。

## P0-5 服务端未重新验证施法资格，且正常远端入口没有权威法术装配来源

**证据**：

- 本地 `PlayerSpellCaster.cast_selected()` 检查 `is_active_spell_focus_weapon()`（`player_spell_caster.gd:15-19`）。
- `session_root.gd:595-635` 只验证槽、配方、法力、冷却；没有使用 `SpellAccessPolicy` 检查法杖/魔导书/奥法之剑。
- `multiplayer_session.gd:47-86` 房主与客户端实际均用空字典 spawn。
- `session_root.gd:194-198` 的 `_apply_save_state()` 只恢复 `materials/loadout`，不恢复 `spell_state`。
- `PlayerContext` 默认为空 `SpellLoadout`（`player_context.gd:34-37`）。

**影响**：绕过本地 UI 可直接提交施法；而正常远端玩家默认又没有服务器权威法术槽，形成“安全校验不足 + 生产入口不可用”的双重断裂。

**最小整改切片**：服务端身份仓库加载统一 `DungeonPlayerSnapshot`（attributes/skills/inventory/loadout/spell_state）；`SpellAccessPolicy` 改为纯逻辑并在服务端 commit 前调用。

## P0-6 库存 UI 仍引用已迁出的 GameState 常量

**证据**：

- `tavern_equipment_panel.gd:1511-1523` 使用 `GameState.MATERIAL_SPACE_PER_ITEM` / `RUNE_SPACE_PER_ITEM`。
- 常量实际位于 `ExpeditionInventory`（`expedition_inventory.gd:7-10`），`GameState` 没有这些成员。

**影响**：材料/符文跨库存转移路径可在运行时触发无效成员访问；容量和事务规则仍散落在 UI。

**最小整改切片**：将 `move_items_between`、容量检查和回滚移动到 `InventoryTransferService`；UI 只提交来源、目标和物品列表。

## P0-7 目标平台 renderer 与导出基线缺失

**证据**：

- `project.godot:177-180`：`renderer/rendering_method.mobile="forward_plus"`，与项目目标的现代 Android Mobile renderer 不一致。
- `export_presets.cfg:1-49`：只有 Web preset，没有桌面与 Android。

**影响**：Android 承担桌面级 renderer 成本；ABI、纹理压缩、包名、权限、资源过滤和 renderer 无法版本化复现。

**最小整改切片**：移动端改为 Mobile renderer；补 Windows 和 Android preset；CI 增加 export dry-run；Android 真机记录 GPU frame time、热稳定性、内存和动态光数量。

---

## 4. P1：高优先级架构问题

## P1-1 PlayerContext 迁移未完成，规则层仍依赖 `GameState.current_player`

`procedural_dungeon.gd:159-160,225`、`dungeon_runtime.gd:148,214,502,549`、`extraction_portal.gd:193`、`enemy.gd:306,684,745` 仍读取单一当前玩家。`GameState.player_context()` 除注释外几乎没有成为调用入口。

**建议**：明确拆为 `LocalPlayerPresentationContext`（相机/HUD/LOD）和 `PlayerEntityProvider`（规则/AI/撤离）；服务器规则禁止读取 `GameState.current_player`。

## P1-2 单机与联机世界实体是两套不同实现

真实单机敌人使用 `Enemy` 场景、状态机、导航、武器与体素表现；联机测试中的服务器实体只是 `_entities` 字典，客户端显示为 `multiplayer_entity.gd` 的 Label3D/HP 文本代理（`multiplayer_entity.gd:1-68`）。`dungeon_session_controller.gd:109-142` 还硬编码 Rat/Skeleton 测试实体。

**影响**：当前双进程“战斗通过”证明的是字典代理链，而不是正式 Enemy AI/碰撞/动画/掉落链。

**建议**：建立 `AuthoritativeEntityAdapter`，真实 Enemy 生命周期必须注册/更新 SessionRoot 实体表；客户端可用同一正式模型的非权威 proxy，而不是测试标签实体。

## P1-3 已决定的流派武器伤害倍率没有统一进入结算

`damage_resolver.gd:33-65` 的 `STYLE_META` 未包含完整已决定 `damage_mult`；双手仍是 1.0 占位。`combat_bridge.gd:302-303` 主要乘武器实例词缀 `damage_mult`，不是流派政策。

**建议**：在 `AttackContext` 构建时明确只对武器伤害应用流派倍率；法术卡伤害不乘。为七流派建立契约测试。

## P1-4 联机击杀经验/升级选择没有权威闭环

- 单机敌人只奖励本机 `GameState.current_player`（`enemy.gd:607-621`）。
- `CombatProgression._get_local_player_attributes()` 同样要求本地 current_player（`combat_progression.gd:46-64`）。
- SessionRoot `_on_entity_killed()` 只生成掉落，没有给 killer 的 per-peer attributes 增加角色经验。
- `LevelUpPanel` 直接锁本地 `GameState.current_player`、修改本地 AttrPanel 和 GameState（`level_up_panel.gd:105-205`）。

**建议**：新增服务器 `ProgressionAuthority`，击杀归属、经验、待升级队列和符文候选均属于 `PlayerContext`；客户端面板只发送选择意图。

## P1-5 `DungeonSceneBuilder` 是高风险 God Object

当前 2417 行/114 函数，覆盖：地形、MultiMesh、碰撞、遮挡、门、楼梯、危险、箱子、房间焦点、悬崖、坡道、导航、装饰、火把、批处理和出生占位。

**拆分 seam**：

- `DungeonTerrainAssembler`：terrain/multimesh/collision/occluder
- `DungeonTraversalAssembler`：door/downstairs/ramp/navigation
- `DungeonEncounterAssembler`：hazard/chest/focus/composition
- `DungeonDecorationAssembler`：planned decor/torches/batching
- `DungeonBuildPipeline`：只编排阶段并汇总 `DungeonBuildResult`

必须保持现有手工酒馆场景规则不受影响；这里只拆地牢运行时构建。

## P1-6 `TavernEquipmentPanel` 同时承担 View、Presenter 和 Domain Transaction

1926 行/131 函数，包含布局、装备槽、库存筛选、仓库转移、技能绑定、符文镶嵌、符文之语说明、3D 预览、属性汇总、拖拽协议和本地化。

**建议拆分**：

- `EquipmentPanelPresenter`
- `InventoryTransferService`
- `SkillLoadoutEditor`
- `RuneSocketEditor`
- `EquipmentPreviewController`
- 当前脚本仅保留控件接线和渲染

## P1-7 `Player` 仍是输入、移动、战斗、交互、UI、光照和联机的聚合点

1322 行/102 函数，外向 preload 23 个。虽然已有 `PlayerCombatRuntime`、`CombatBuffComponent`、`PlayerSpellCaster` 等提取，但主脚本仍直接管理：输入边缘、移动、交互射线、宝箱 UI、状态机、光照、ViewModel、联机模式、被动 tick、伤害接收。

**建议拆分**：`PlayerInputRouter`、`PlayerMotor`、`PlayerInteractionController`、`PlayerCombatController`、`PlayerPresentationController`；Player 只组合组件和持有身份。

## P1-8 性能质量分档只有分辨率，下游没有消费者

- `performance_budget_controller.gd:102-113` 只修改 FSR scale 并发 `quality_tier_changed`。
- 全仓没有该信号连接方。
- `LightingController` 另有独立 HIGH/MEDIUM/LOW 质量政策（`lighting_controller.gd:19-38,51-67`）。

**建议**：建立统一 `RenderingProfile`，输出 render scale、动态光、阴影、粒子、透明、法术场、召唤和后处理预算；LightingController/FX/地牢流控消费同一 profile。

---

## 5. P2：工程治理与文档问题

## P2-1 Autoload 面过宽，Service Locator 只隐藏依赖，没有消除依赖

31 个 Autoload。`Service` 通过根节点字符串返回 `Node`（`service.gd:7-127`），类型安全有限；`spell_authority()`/`spell_runtime()` 每次调用还直接 `load().new()`（`service.gd:67-71`）。

**建议**：仅保留真正进程级基础设施；数据表/纯策略用 preload 常量；场景级服务由 Composition Root 构造并显式注入。

## P2-2 存档汇总器仍直接知道全部领域单例

`SaveManager.serialize_all()/deserialize_all()` 显式拉取 TavernManager、GameState、AttrPanel、SkillRuntime、FermentationSystem、TavernSettlement、ArmorProficiency、ZoneManager（`save_manager.gd:154-229`）。添加新领域必须修改中央文件。

**建议**：引入受限 `SaveSection` 注册协议或显式 `SaveGameSnapshot` 聚合器；迁移函数按版本独立，不让 SaveManager 了解领域内部字段。

## P2-3 文档状态严重漂移

- `docs/16-技术架构与代码设计.md` 仍包含 3D 俯视角、C# 接口、Mono Singleton、`gl_compatibility` 等旧口径（行 3、16、30-32、117、162、500），与当前第一人称/体素/GDScript/Forward+ 项目不符。
- `docs/24-联机架构迁移.md:3-6` 仍把联机描述为 Phase 0/0.5，且称 `globals/multiplayer` 为仅注释骨架。
- `docs/25` 落地追踪部分写“服务器权威战斗已落地”，但未揭示默认 AttackInput、无碰撞移动和测试实体代理的限制。
- `docs/法术实现审计与交付概览.md:38-46,85-90` 仍写只有 5 条配方、施法输入未接线；当前源码已有 33 条配方与施法入口。
- 根 `README_ARCHITECTURE.md` 也仍描述旧目录、OBJ、俯视/纸娃娃原型。

**建议**：确定一个唯一“实现架构现状”文档；旧设计文档标明历史/提案/权威范围。状态标签必须区分“逻辑骨架”“测试代理闭环”“真实游戏实体闭环”“平台验收”。

## P2-4 测试大量验证源码形状而非行为

静态统计：457 个测试脚本中，244 个读取 `source_code`/文件字符串，共约 1047 次。典型例子：

- `spell_network_completion_test.gd:8-29` 只检查源码包含特定字符串。
- `spawn_save_state_security_test.gd:3-18` 只检查 RPC 函数文本。

这类测试对重构极脆弱，同时会错过“存在调用文本但运行时条件永远不成立”的缺陷（法术 `ctx.player_node == null` 正是实例）。

**建议**：源码契约只保留少量禁止模式扫描；核心协议改成实例级行为测试和双进程场景测试。

## P2-5 CI 明确把 orphan 退出码 101 转为绿色

`run_ci.ps1:9-15,40-42` 将 orphan 泄漏视为 GREEN。生命周期泄漏会长期累积，尤其 SessionRoot/Node service/Viewport/材质测试。

**建议**：新测试立即要求 0 orphan；旧债可设临时 allowlist 和倒计时，但不能把所有 101 无条件转 0。

## P2-6 工作树不可审计，报告目录又被整体忽略

当前约 1926 个脏路径，跨代码、模型、纹理、文档、测试和生成物。`.gitignore:43,52-53` 又忽略代码图谱和整个 reports 目录，重要审查证据不进入版本历史。

**建议**：按主题拆分提交；禁止 `git add -A`；架构 ADR/审查结论应进入受跟踪的 `docs/architecture/`，临时截图和测试日志继续留在 ignored reports。

---

## 6. 建议目标架构

```text
Application Composition Root
  ├─ LocalGameSession
  │    ├─ LocalPlayerContext
  │    ├─ WorldRuntime
  │    └─ Domain Services
  └─ NetworkGameSession
       ├─ Transport (NetworkManager)
       ├─ SessionCoordinator
       ├─ PlayerRegistry
       ├─ WorldEntityRegistry
       ├─ Command Handlers
       │    ├─ MovementCommandHandler -> ServerCharacterMotor
       │    ├─ AttackCommandHandler -> AttackContextFactory -> DamageResolver
       │    ├─ SpellCommandHandler -> SpellTransaction
       │    ├─ InteractionCommandHandler
       │    └─ ProgressionCommandHandler
       └─ Replication / Presentation Bridge
```

### 核心规则

1. **Context 是玩家状态唯一入口**：规则层不读 `GameState.current_player`。
2. **命令只携带意图**：攻击类型、伤害、位置、法术 ID、装备属性均由服务端状态推导。
3. **一个规则，一个策略对象**：AttackCadence、SpellAccess、InventoryTransfer、RenderingProfile 只有一个纯逻辑实现。
4. **真实实体是权威真相源**：字典注册表是实体快照，不是替代正式 Enemy/Player 物理和 AI 的第二套游戏。
5. **事务原子化**：法力/冷却/库存/结算必须 prepare-commit 或可回滚。
6. **文档区分完成层级**：数据/纯逻辑/传输/测试代理/真实场景/平台验收不可都写“已完成”。

---

## 7. 分阶段整改路线

### 阶段 A：止血（发布阻断）

1. 修复库存转移旧常量，落地 `InventoryTransferService`。
2. 建立 `AttackContextFactory + AttackCadencePolicy`；服务器不再接受 `attack_type`。
3. 服务端绑定 peer -> PlayerEntity；法术执行改为原子事务并补资格校验。
4. 移动权威接入真实碰撞 motor。
5. Mobile renderer + Windows/Android export presets。

### 阶段 B：统一单机/联机领域规则

1. CombatBridge 与 SessionRoot 共用 AttackContext。
2. 新增 ProgressionAuthority，击杀经验/升级/符文机会迁入 per-peer Context。
3. SpellWorldExecutor 的场/召唤纳入 WorldEntityRegistry 和复制快照。
4. 正式 Enemy/掉落接入实体注册与表现代理，移除硬编码 Rat/Skeleton 测试生产路径。

### 阶段 C：拆 God Objects

1. 拆 `DungeonSceneBuilder` 四个 assembler + pipeline。
2. 拆 `TavernEquipmentPanel` presenter/services/controllers。
3. 拆 `Player` 输入、motor、交互、战斗、表现。
4. 拆 `SessionRoot` 为命令 handler 集合；SessionRoot 只编排生命周期与事件发布。

### 阶段 D：工程门禁

1. 从干净主题分支复跑全量 gdUnit4。
2. orphan 101 改红或严格 allowlist。
3. 核心源码字符串测试替换为行为测试。
4. 双进程测试加入墙体碰撞、正式 Enemy、攻击装备差异、法术失败回滚、双 peer 成长隔离。
5. Windows/Android export dry-run；Android 真机性能与热稳定性验收。

---

## 8. 验收清单

### 联机

- [ ] 客户端持续向墙方向输入 10 秒，服务端位置不穿墙。
- [ ] 客户端伪报 ranged/spell 不影响服务器推导的攻击类型和射程。
- [ ] 不同武器、流派、DEX 在单机和联机得到相同冷却与伤害输入。
- [ ] 法术 caster 缺失/资格不符/世界执行失败时，法力和冷却均不变化。
- [ ] 场效果与召唤可被晚加入/重连客户端恢复。
- [ ] 正式 Enemy AI/碰撞/死亡/掉落通过真实双进程测试，而非 Label 代理。
- [ ] 联机击杀经验只授予正确 player_guid 的 context，升级选择不可由客户端直接修改。

### 平台与性能

- [ ] Android 使用 Mobile renderer。
- [ ] Windows/Android presets 可在干净环境导出。
- [ ] RenderingProfile 能实际改变光、阴影、粒子、透明和法术预算。
- [ ] 窗口化地牢生成/导航/战斗压力测试记录 CPU/GPU frame time。

### 工程

- [ ] 全量测试 0 assertion failure、0 script error、0 orphan（或严格、临时、可追踪 allowlist）。
- [ ] 核心测试不依赖函数源码子串来证明行为。
- [ ] 工作树按主题拆分，报告结论进入可版本化文档。
- [ ] `docs/16`、`docs/24`、`docs/25`、法术审计和根架构 README 的状态一致。

---

## 9. 范围与验证声明

本轮完成了源码、项目配置、导出配置、测试结构、当前架构文档和最新静态代码图谱的审查；没有运行全量 Godot 测试、真实窗口 3D、Android 真机或本轮双进程 ENet。仓库已有历史报告声称部分专项/双进程测试通过，但当前工作树持续变化且规模巨大，不能将历史通过视为当前可复现证据。

并行专项审查代理尝试因当前环境返回 403 而未执行，以上结论由主审查流程直接交叉读取源码得出。所有 P0 都有当前工作树的直接代码证据，应按发布阻断处理。