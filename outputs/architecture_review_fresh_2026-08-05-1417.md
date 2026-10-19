# Lantern Tavern 项目架构审查（从零审查）

审查时间：2026-08-05 14:17（GMT+8）  
审查方式：仅依据当前工作区源码、配置和本次执行结果；未读取项目记忆或既有架构审查报告。  
审查范围：`project.godot`、`globals/`、`data/`、`scenes/`、`fx/`、`tests/gdunit/`、CI/导出配置。  
工作树状态：审查开始时已有未提交修改；本次没有修改生产源码。

> **验收注记（2026-08-05 同日修复）**：P0-1 / P0-2 / P2-2 / P2-3 已修复关闭（见条目 ✅ 标注与第 8.1 节修复清单）；P1-2 已落地趋势门禁并迁移最大集中点，P2-4 已改为默认严格 + 显式豁免，P2-5 已固定 Android SDK（见 8.1 扩展）；P1-1 / P1-3 / P1-4 / P2-1 保留为结构治理开放项。修复均带针对性测试。

## 1. 结论

当前项目不是“架构失控”，但处在**模块化已起步、全局耦合尚未收口**的中间阶段。地牢生成、装备数据、存档模型、联机权威子系统已出现明确边界；同时，33 个 Autoload、119 处 root 查找、`SessionRoot` 的 1529 行编排体量，以及单机/联机并行状态模型，正在形成下一轮维护瓶颈。

**总体评级：B-（可继续开发，但应先处理 2 个高风险行为缺口和 4 个中风险架构债）。**

最需要优先处理的不是“再拆目录”，而是：

1. 让联机生产入口真正走 `SessionRoot` 的出征事务，而不是绕过它；
2. 完成联机技能的权威结算，禁止“验证已拥有后只广播触发事件”；
3. 收缩依赖获取方式和 Autoload 面积；
4. 把 `SessionRoot` 从会话总管拆成更窄的应用服务。

## 2. 本次验证摘要

### 已执行

- Godot 4.7 Mono headless 启动：**成功，退出码 0**。
- 关键架构回归：
  - `architecture_dependency_rule_test.gd`
  - `service_access_contract_test.gd`
  - `project_bootstrap_test.gd`
  - `session_root_test.gd`
  - `save_manager_test.gd`
- 结果：**5/5 套件，115/115 用例通过，0 error，0 failure，0 orphan，退出码 0**。

### 启动警告

启动虽成功，但出现 3 条资源 UID 警告：

- `scenes/characters/enemies/goblin.tscn:3` 的 GLB UID 无效，回退文本路径；
- `weapons_voxel_crossbow.glb` 内两张外部纹理 UID 无效，回退文本路径。

这不是当前启动阻断项，但属于可迁移性/资源重导入风险，见 P2-3。

### 规模信号

- 生产 GDScript：295 个文件，约 66,398 行；
- gdUnit 测试脚本：496 个；
- Autoload：33 个；
- 生产源码中的 root 查找：约 119 处；
- `Service.*` 调用：约 127 处；
- `SessionRoot`：1529 行；`NetworkManager`：753 行；`GameState`：539 行。

## 3. 架构现状

### 3.1 启动与场景编排

- 主场景是 `scenes/ui/main_menu.tscn`（`project.godot:14`）。
- 实际世界空间由 `scenes/world/world.gd` 统一在 intro / tavern / dungeon 间切换。
- `World` 持有共享 UI、环境交接、场景装载和楼层切换；职责总体清晰，但仍直接依赖全局单例与反射式能力探测。

### 3.2 数据边界

- 装备以 `data/weapons/weapons.json` 为权威输入，由 `data/weapon_registry.gd` 构建 `WeaponData`；GLB 延迟加载，避免启动期全量载入。该边界是当前项目较成熟的部分。
- 探险库存、装备装配、酒馆账本已提取为 `RefCounted` 数据模型：
  - `globals/core/state/expedition_inventory.gd`
  - `globals/core/state/equipment_loadout.gd`
  - `globals/core/state/tavern_ledger.gd`
- 酿造核心数据仍硬编码于 `globals/tavern/brewing_data.gd`，而仓库保留一个已废弃但仍可见的 `data/brewing_materials.json`，容易误导维护者。
- 技能存在两套明确不同的来源：`skill_data.gd` 的主动/流派技能，以及 `data/skills.json` 的扩展被动。它们并非天然冲突，但命名为同一“技能数据”领域，且由不同加载路径消费，缺少显式目录/类型边界。

### 3.3 运行时与联机

- 单机状态主要位于 `GameState + AttrPanel + SkillRuntime + TavernManager`。
- 联机状态通过 `PlayerContext` 聚合 per-peer 属性、技能、库存、装配、法术与战斗状态。
- `NetworkManager` 负责 ENet/RPC/节流，`SessionRoot` 负责权威会话编排，多个 `*Authority` 类承担纯逻辑或规则子域。
- 方向是对的：传输层与权威逻辑已分开，命令白名单、世界修订号、重连、可信存档仓、出征结算幂等均有自动测试。
- 但 `SessionRoot` 已经重新长成会话级 God Object。

## 4. 发现与风险

## ✅ P0-1（已关闭）：联机生产出征入口绕过 `SessionRoot` 出征事务

**证据**

- 正确事务入口：`globals/multiplayer/session_root.gd:755-764` 的 `_handle_start_expedition()` 同时：
  1. 调用 `dungeon_auth.start_expedition()`；
  2. 调用 `save_auth.begin_expedition(layout_revision)` 清空本次结算账本；
  3. `_bump_world("dungeon")` 推进权威世界修订；
  4. 发布布局事件。
- 实际生产入口：`globals/multiplayer/multiplayer_session.gd:67-79` 调用 `NetworkManager.start_expedition()`。
- `globals/core/network_manager.gd:590-598` 的 `start_expedition()` 仅直接调用 `session.dungeon_auth.start_expedition()` 并广播事件，**没有调用 `save_auth.begin_expedition()`，也没有推进 `world.current_space/world_revision`**。
- 集成测试 `tests/integration/mp_dungeon_test.gd:125-135` 同样走这个绕行入口，因此测试会固化错误路径而不是揭示它。
- 只有 `session_root_test.gd:646-656` 验证了通过 `CMD_EXPEDITION` 的正确账本重置行为。

**影响**

- 新一轮联机出征可能沿用上一轮 `SaveAuthority` 的结算账本：同一 GUID 在新 run 中仍可能被判断为已结算；
- `WorldState.current_space` 与 `world_revision` 未随生产出征入口更新，客户端命令修订语义与会话真实空间可能分叉；
- 同一业务动作存在两条实现路径，单测通过不能证明生产路径正确。

**建议**

- 删除 `NetworkManager.start_expedition()` 内对 `dungeon_auth` 的直调；统一构造服务器自身的 `CMD_EXPEDITION`，或暴露 `SessionRoot.start_expedition_authoritatively()` 供本地房主和命令路由共用；
- 增加生产入口回归：调用 `MultiplayerSession.start_expedition()` 后断言：
  - `save_auth.expedition_revision == dungeon_auth.layout_revision`；
  - 旧 GUID 的 `is_settled()` 变为 false；
  - `world.current_space == "dungeon"`；
  - `world_revision` 递增；
  - 布局事件只下发一次。

## ✅ P0-2（已关闭）：联机技能只做所有权确认，没有权威效果结算

**证据**

- `globals/multiplayer/session_root.gd:1196-1221` 明确写明：实际技能效果结算留待 `SkillAuthority`；当前 `_handle_skill()` 只验证技能已绑定，然后发布 `EVT_SKILL_STATE_CHANGED`。
- 没有扣资源、冷却提交、目标/范围校验、伤害或 buff 结算。
- 当前测试 `session_root_test.gd:673-694` 只验证“未拥有拒绝 / 已拥有接受 / 序列防重放”，没有验证技能产生任何游戏效果。

**影响**

- 联机玩家可以收到“技能触发成功”的表现事件，但服务器世界不发生对应变化；
- 客户端若本地播放或结算效果，会造成权威分叉；若不本地结算，则技能在联机中实际不可用；
- 这是行为完整性问题，不只是代码整洁问题。

**建议**

- 建立 `SkillAuthority`，复用单机已有的技能定义、冷却与效果执行器；
- 采用与法术一致的 `validate -> prepare -> execute -> verify -> commit -> publish` 事务；
- 对主动技能至少覆盖：资源不足、冷却、错误媒介、非法目标、效果执行失败不提交、成功后世界状态变化、重放拒绝。

## P1-1：`SessionRoot` 已成为 1529 行会话级 God Object

**证据**

`SessionRoot` 同时负责：注册/重连、命令路由、移动、普通攻击、法术、技能、装备、丢弃、掉落、实体仓、敌人攻击 tick、成长、出征、存档、结算、快照、事件发布与服务器世界查询。

虽然它调用多个 Authority，但仍保留大量事务编排、状态字典和场景端口，导致新的业务继续往同一文件增长。

**影响**

- 单个改动容易跨越网络、存档、战斗和实体复制；
- 回归测试主要集中于 `session_root_test.gd`，修改冲突和理解成本持续上升；
- “已有 Authority”没有真正形成可独立演进的应用服务边界。

**建议**

按命令族拆应用层处理器，而不是再拆纯工具类：

- `SessionLifecycleService`：spawn/leave/disconnect/resume；
- `ExpeditionTransactionService`：start/extract/save/baseline；
- `CombatCommandService`：attack/cast/skill + 事务提交；
- `InventoryCommandService`：pickup/equip/drop；
- `ReplicationCoordinator`：outbox/snapshot/entity baseline。

`SessionRoot` 只保留：服务装配、统一命令入口、tick 调度和共享状态容器。

## ✅ P1-2（趋势门禁已落地，存量迁移开放）：依赖获取约定没有真正统一

**证据**

- 项目有 `globals/core/service.gd`，声称替代 root 字符串查找；
- 生产源码仍约有 119 处 root 查找，典型包括：
  - `scenes/ui/chest_loot_panel.gd` 大量查找 `GameState/AudioManager`；
  - `scenes/ui/character_panel.gd` 查找 `AttrPanel/GameState`；
  - `scenes/multiplayer/client_command_driver.gd` 多次查找 `NetworkManager`；
  - `globals/tavern/fermentation_system.gd` 与 `brew_flow_system.gd` 互相通过 root 查找；
  - `globals/combat/combat_bridge.gd` 查找多个单例。
- `service_access_contract_test.gd` 只守卫 4 个迁移文件；同时维护了 10 个“免检” Autoload。它能证明抽样没有回退，不能证明全项目约定统一。
- 代码同时使用：裸 Autoload 标识符、`Service.*`、绝对 `/root`、动态 `has_method`/属性探测。

**影响**

- 依赖在静态阅读时不可见，测试必须模拟整棵 root；
- 单例重命名和 per-peer 迁移成本高；
- “Service 统一入口”目前只是第四种依赖形式，而不是收口。

**建议**

- 先明确规则，不要全仓机械替换：
  - 纯数据/纯规则：构造注入；
  - 场景 Controller：`configure()` 注入端口或引用；
  - 顶层 composition root：允许访问 Autoload；
  - UI：依赖 ViewModel/Facade，不直接摸 `GameState`。
- 把全项目 root 查找数量纳入趋势门禁；允许白名单但必须绑定原因与负责人。
- `Service` 返回 `Node` 的弱类型只能作为迁移桥，不应成为长期 DI 容器。

## P1-3：33 个 Autoload 让全局生命周期与初始化顺序成为隐性架构

**证据**

- `project.godot:17-51` 注册 33 个 Autoload，覆盖核心、酒馆、地牢、战斗、装备、联机、UI、光照和性能。
- `architecture_dependency_rule_test.gd` 只限制数量不超过 33；该门禁防增长，但并不验证每个单例是否有全局生命周期的必要性。
- `AttrPanel`、`SkillRuntime`、`ActionSkills`、`SkillIcons`、`BrewFlowSystem` 等既包含状态又作为全局服务；联机又在 per-peer 上实例化一部分同类对象。

**影响**

- 新游戏重置、场景切换、重新开房、测试隔离都需要显式清理大量全局状态；
- 单机状态和 per-peer 状态容易出现双写/分叉；
- 初始化顺序和 root 可达性变成非声明式依赖。

**建议**

- 将 Autoload 分类为：真正进程级服务、会话级服务、玩家级状态、纯静态目录；
- 目标不是一次性砍数量，而是把会话级/玩家级对象移入 `GameSessionRoot` 或 `PlayerContext` 生命周期；
- 优先迁移 `AttrPanel/SkillRuntime` 的单机入口，使单机也通过唯一 `PlayerContext` 访问，避免两套状态模型长期并存。

## P1-4：单机/联机存在双状态模型与行为复制

**证据**

- `GameState` 保存单机 `expedition_inventory/equipment_loadout/spell_loadout/expedition_session`，并绑定全局 `AttrPanel/SkillRuntime`；
- `PlayerContext` 又保存 per-peer 的相同类别状态，以及独立生命/护盾/buff/法力；
- 普通攻击、法术、成长、装备分别存在单机执行链和联机权威执行链。
- `PlayerContext.bind_to_globals()` 仍直接绑定 Autoload；注释把完整迁移定位为“未来”。

**影响**

- 每个新功能需要判断改单机链、联机链还是两者；
- 同公式容易漂移；
- `has_method` 与桥接代码增多，行为差异难以被测试矩阵完整覆盖。

**建议**

- 让单机成为“本地权威会话”，复用相同领域服务和玩家上下文；
- 保留传输差异，但不要保留两套结算逻辑；
- 先统一技能与装备事务，再统一生命/法力状态所有权。

## P2-1：装备数据边界总体正确，但注册表职责过宽且遗留 `.tres` 仍渗透 API

**证据**

- `weapon_registry.gd` 同时承担 JSON 解析、兼容迁移、Resource 构建、类别索引、本地化名称、图标加载、模型查看器 DTO 和背包列表 DTO。
- `get_gear_list_entries()` 仍生成 `tres_path`，即使权威来源是 JSON。
- 注册表返回共享 `WeaponData` 模板；部分调用方必须记得 `duplicate()`，否则可能污染模板。

**建议**

- 拆成 `EquipmentCatalog`（不可变定义/索引）、`EquipmentInstanceFactory`（阶位/词缀/持久化实例）、UI Presenter/Query；
- 逐步删除生产 API 对 `.tres` 的暗示；
- 明确 `get_weapon_data()` 返回只读模板，并给写入路径只暴露实例工厂。

## ✅ P2-2（已关闭）：数据源命名与归档边界不够清晰

**证据**

- `data/brewing_materials.json` 内容使用另一套英文风味和材料集合；生产已不再消费，但文件仍在活动 `data/`，`README_ARCHITECTURE.md` 仍把它描述为数据库。
- 技能同时由 `globals/combat/skill_data.gd` 与 `data/skills.json` 提供，分别代表主动/流派技能和扩展被动，但名称没有表达差异。

**建议**

- 将废弃酿造 JSON 移入明确归档区，或删除；同步修正文档；
- 将技能源改名为 `combat_skills_catalog` / `passive_skills_catalog`，并在测试中验证 ID 跨源唯一性和消费者边界。

## ✅ P2-3（已关闭）：资源 UID 警告尚未清零

**证据**

本次 headless 启动明确产生 goblin rig 与 crossbow 两张纹理的 invalid UID 回退警告。

**影响**

文本路径回退暂时可用，但重命名、迁移、导出或缓存重建时更脆弱。

**建议**

- 在 Godot 4.7 编辑器中重新导入并保存对应场景/GLB 依赖；
- 添加启动日志门禁：已知警告白名单可短期存在，但新增 invalid UID 直接失败。

## ✅ P2-4（已关闭）：CI 默认把 orphan 视为绿色

**证据**

`run_ci.ps1:70-76` 在退出码 101 时，默认仅告警并返回 0；只有显式 `-FailOnOrphan` 才失败。

**影响**

默认 CI 仍可能放行节点泄漏；“严格门禁”依赖调用者记得加参数。

**状态（2026-08-05）**：✅ 已关闭。`run_ci.ps1` orphan 默认 RED（严格门禁）；已知引擎级泄漏（terrain_texture_test 的 headless dummy-renderer RID 泄漏）经 `-AllowOrphan` 显式豁免；逐套件审计走 `tools/run_all_gdunit_batched.ps1`（PASS_ORPHAN 归类）。`-FailOnOrphan` 保留为兼容等价开关。

**建议**

- 将严格模式作为主分支/发布流水线默认值；✅ 已默认
- 若存量测试尚未清零，使用明确的允许列表，而不是全局把 101 转绿；✅ 已用 -AllowOrphan 显式豁免清单

## ✅ P2-5（已部分关闭）：导出配置与实际平台边界不完全一致

**证据**

- 项目目标以桌面与现代 Android 为主，但 CI 和 `export_presets.cfg` 仍维护 Web；
- Android `min_sdk/target_sdk` 留空，依赖环境默认值；
- `project.godot` 开启 C# 特性主要源自编辑器插件，运行时主体仍是 GDScript。

**建议**

- 若 Web 不是交付目标，移除或降级为非门禁实验 preset；
- 固定 Android min/target SDK 与构建工具版本；
- 评估编辑器插件是否必须让整个项目保持 Mono/C# 特性，避免无谓增加构建链复杂度。

## 5. 做得好的部分

1. **装备数据加载**：JSON 权威、Resource 兼容、GLB 延迟加载，启动期资源控制清楚。
2. **纯数据模型提取**：探险库存、装配、酒馆账本等已脱离场景树，便于测试。
3. **地牢流水线分层**：layout / builder / runtime / streaming / spawn planner 职责已有明确说明和显式注入。
4. **联机安全意识强**：命令可信字段守卫、稳定 GUID、重连 token、world revision、服务器存档仓、结算幂等均已实现并测试。
5. **测试资产丰富**：496 个 gdUnit 脚本，关键架构子集本次 115 用例全绿。
6. **存档原子性**：单机与服务器存档均采用 final/.tmp/.bak 恢复协议，并有中断窗口测试。

## 6. 建议实施顺序

### 第一批：阻断行为分叉 ✅（2026-08-05 已全部完成）

1. ~~统一联机出征入口，删除 `NetworkManager.start_expedition()` 的直通实现~~ → `start_expedition_authoritatively()` 统一事务 + 生产/命令/集成测试三路接入
2. ~~补生产入口事务回归~~ → `test_authoritative_expedition_resets_ledger_and_bumps_world`
3. ~~实现 `SkillAuthority`，让联机技能真正权威结算~~ → 权威冷却/定义/事务闭环（效果执行器为扩展点）

### 第二批：收缩会话总管（仍开放）

4. 从 `SessionRoot` 抽出出征事务、战斗命令、库存命令和复制协调服务；
5. 保持共享状态容器不变，先移动方法与测试，避免“大爆炸重写”。

### 第三批：统一状态与依赖

6. 单机改为通过唯一 `PlayerContext` 访问玩家状态；
7. 制定依赖注入规则并分批减少 root 查找；
8. 审批并下调 Autoload 上限，而不是只维持 33。

### 第四批：工程卫生

9. 清理废弃数据文件/误导文档；
10. 修复 invalid UID；
11. 主分支 CI 默认启用 orphan 严格模式；
12. 固定 Android SDK 边界，重新确认 Web/Mono 是否必要。

## 7. 验收标准

架构整改完成后，至少满足：

- 房主生产入口与 `CMD_EXPEDITION` 共用同一事务函数；
- 新出征必重置结算账本并推进 `world_revision`；
- 联机主动技能成功时服务器状态发生可断言变化，失败时不提交资源/冷却；
- `SessionRoot` 不再直接实现装备、出征、战斗、复制四类完整事务；
- 全项目 root 查找数量持续下降并受门禁；
- 单机和联机共享同一领域结算服务；
- headless 启动无 invalid UID；
- 主分支关键回归和严格 orphan 门禁均为绿。

## 8.1 修复清单（2026-08-05 同日）

| 原条目 | 修复证据 | 新增测试 |
| --- | --- | --- |
| P0-1 生产出征入口绕行 | `SessionRoot.start_expedition_authoritatively()` 成为唯一权威事务（dungeon 布局 + `save_auth.begin_expedition()` 账本重置 + `_bump_world("dungeon")`）；`_handle_start_expedition` 改调它；`NetworkManager.start_expedition` 删除对 `dungeon_auth` 的直调与手动 dispatch（事件经 session_event 自动路由）；`MultiplayerSession` 与 `mp_dungeon_test` 消费新返回结构 | `session_root_test.gd::test_authoritative_expedition_resets_ledger_and_bumps_world`（账本重置/空间推进/修订递增/绑定 layout_revision） |
| P0-2 联机技能假成功 | 新建 `SkillAuthority`（per-peer 权威冷却 + 定义解析 + 效果钩子）；`_handle_skill` 升级为 owned→定义→冷却→execute→commit→广播事务，失败零提交；事件携带 `cooldown_ms` | `session_root_test.gd`：`test_handle_skill_commits_authoritative_cooldown` / `test_handle_skill_cooldown_blocks_repeat` / `test_handle_skill_rejects_unknown_definition`；既有测试改用真实技能 id |
| P2-2 废弃数据文件 | `data/brewing_materials.json` 移入 `data/_archive/`（零生产引用确认）；`README_ARCHITECTURE.md` 数据目录描述修正为 `weapons/weapons.json` 权威源 + `_archive` 说明 | —（文件迁移） |
| P2-3 资源 UID 警告 | 4 个缺失 `.uid` 文件补齐（rig/crossbow glb/两张纹理），引用方与资源 uid 统一（goblin.tscn 改引 `.import` 注册 uid；纹理 `.import` uid 改为 glb 内嵌引用值），编辑器重扫后加载警告消失 | —（加载路径验证：`character_voxel_overlap_test` 加载 goblin 无 UID 警告） |
| P1-2 root 查找趋势门禁 | `architecture_dependency_rule_test.gd` 新增全项目 `/root` 引用趋势门禁（上限 11，防增长）；`client_command_driver.gd` 17 处 `/root/NetworkManager` 全部迁移至 `Service.network_manager()`（28 → 11 处） | `test_root_path_references_within_trend_limit` |
| P2-4 orphan 门禁 | `run_ci.ps1` 101 默认 RED；`-AllowOrphan` 显式豁免已知引擎级泄漏（terrain_texture_test headless dummy-renderer RID 泄漏）；批处理扫描器 `PASS_ORPHAN` 逐套件审计；`terrain_texture_test` 释放改为 queue_free + 多帧（320 → ~128 orphan，残余为引擎级） | PowerShell 语法解析通过 |
| P2-5 Android SDK | `export_presets.cfg` 固定 `min_sdk=24` / `target_sdk=34`（不再依赖环境默认）；Web preset 保留为实验 preset 待平台决策 | —（配置固定） |

## 9. 限制

- 本次未运行 496 个 gdUnit 脚本的全量套件，也未执行双进程联机、Windows/Android 实际导出或真机性能测试；
- 本次未做视觉审查；
- 工作区有既有未提交修改，因此结论对应当前工作树，而不一定对应最近提交；
- 审查仅输出报告，没有修改生产源码。
