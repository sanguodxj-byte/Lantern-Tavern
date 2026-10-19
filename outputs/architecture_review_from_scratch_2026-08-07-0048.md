# Lantern Tavern 架构审查报告（从头开始）

- 审查时间：2026-08-07 00:48（GMT+8）
- 审查原则：仅基于本轮当前工作树源码、`project.godot`、`AGENTS.md`、`docs/术语表.md`、ADR 与本轮实际命令输出；未读取项目记忆、自动化记忆以外的历史记录、旧审查报告或既有结论。
- Godot：4.7.stable.mono.official.5b4e0cb0f

## 一、结论

当前架构已具备较清晰的分层方向：多人权威状态、命令路由、服务拆分、ServerSaveRepository、会话级法术执行器、地牢生成 assembler 化均已存在；本轮聚焦测试 11 个套件 / 111 个用例全部通过，Dedicated Server 双进程垂直切片通过。

但项目当前不能判定为整体健康：标准 CI 在测试发现阶段失败并随后触发 Godot 崩溃；Listen ENet 集成测试本轮失败；主动技能数据契约与权威执行器仍不一致，存在“命令成功、冷却提交、核心效果没有发生”的事务风险。优先级应先修测试门禁和技能事务，再补 Listen 恢复链路，最后处理全局依赖与存档聚合债。

## 二、本轮验证结果

| 验证项 | 结果 | 证据 |
|---|---|---|
| Godot 无头编辑器扫描 | 退出码 0 | 仅出现 `EditorSettings not instantiated yet...` 已被 `run_ci.ps1` 精确白名单允许 |
| 聚焦架构/联机/撤离/技能/存档测试 | 111/111 通过，0 error/failure/orphan | 本轮命令输出，11/11 套件执行完成 |
| 标准 `run_ci.ps1` | 失败 | `tests/gdunit/service_test.gd` 发现阶段 4 个解析错误，退出 105；随后 Godot signal 11 崩溃，脚本最终退出 1 |
| Listen ENet 双进程 | 失败 | 地牢、移动、实体、战斗、掉落、撤离均报告成功，但 `RECOVERY: MISSING`，最终 `INTEGRATION DUNGEON TEST: FAIL`，退出 1 |
| Dedicated Server ENet 双进程 | 通过 | seed/fingerprint、实体复制、移动均通过，服务器 SCRIPT ERROR=0 |

## 三、阻断项 / P0

### P0-1：标准 CI 的全量测试发现已被当前源码打坏

证据：
- `tests/gdunit/service_test.gd:58-59,74-75` 调用 `Service.skill_data()` 与 `Service.action_skills()`。
- `globals/core/service.gd` 当前没有这两个静态方法；本轮 `run_ci.ps1` 明确报：`Cannot find member` / `Static function not found`。
- gdUnit 发现阶段退出 105，之后同一命令触发 Godot signal 11 崩溃。

影响：聚焦测试全绿不能代表标准门禁可用；测试发现失败还伴随引擎崩溃，降低 CI 反馈可信度，并可能掩盖后续套件错误。

修复建议：立即删除/迁移 `service_test.gd` 中已移出 Autoload 的旧访问器断言，或恢复兼容访问器（二选一，但必须与 `project.godot` 的真实 Autoload 清单一致）；随后单独验证全量发现不再 105/崩溃。

### P0-2：Listen 集成的晚到/恢复垂直切片本轮未完成

证据：
- `tools/run_integration_dungeon_test.ps1:57-60` 等待 `client2_recovery.txt`。
- 本轮实际输出：`RECOVERY: MISSING`，尽管其它断言均为 true，脚本正确返回 1。
- Dedicated 测试通过，说明不是所有真实 ENet 路径都失效，而是 Listen 测试的晚到/恢复链路仍未形成稳定生产闭环。

影响：多人房主模式的 late-join/recovery 不能作为已验收能力；不能用聚焦逻辑测试替代此缺口。

修复建议：先定位 `dungeon_cli2` 未生成 `client2_recovery.txt` 的具体进程日志；将“客户端连接→spawn/布局追平→实体对账→恢复 verdict 文件”做成显式状态机，失败必须输出阶段性错误而不是只留下 MISSING。

## 四、高风险 / P1

### P1-1：主动技能数据字段与权威执行语义不一致

证据：
- `globals/multiplayer/skill_authority.gd:67-109` 的 `execute()` 仅执行：`damage_mult` 单目标伤害、movement 族位移、`buff_type/buff_value` 自 buff；成功后可返回 `ok=true`。
- `skill_authority.gd:115-130` 会硬拒绝 `grapple`、`stun_sec`、`breaks_shield`、`ignore_def`、`ignore_block`、`lifesteal`、AoE 字段，但不会拒绝单独存在的 `knockback_m`。
- `globals/combat/action_skills.gd:24-59` 中踢击/冲撞声明 `knockback_m`，冲撞还声明 `stun_sec` 与 `breaks_shield`；踢击没有 `damage_mult`，冲撞的击退不进入 damage 分支。
- `globals/multiplayer/session_combat_service.gd:318-348` 在 `execute()` 返回成功后无条件提交冷却。

判断：
- 踢击可能无伤害、无位移、无 buff，却返回成功并提交冷却。
- 冲撞会执行移动，但其声明的击退/眩晕/破盾语义没有完整兑现；因 `stun_sec`/`breaks_shield` 会被硬拒绝，调用方只得到泛化 `ERR_INVALID_TARGET`。

影响：客户端看到技能触发事件，服务器却没有完成设计语义；这是权威事务“成功状态”与游戏效果不一致的核心风险。

修复建议：建立逐技能 execution contract：每个技能声明的字段必须映射到独立执行器；未实现字段在数据层禁止登记，或由执行器按技能粒度硬拒绝并提供可诊断错误。特别是 `knockback_m` 不得只在“有 damage_mult”分支里顺带执行。

### P1-2：联机撤离存在两套生产路径，地牢运行时入口仍偏向单机结算

证据：
- `scenes/expedition/dungeon_runtime.gd:402-414,495-500` 将撤离 portal 信号直接接到 `on_extraction_requested()`，随后调用本地 `finish_expedition()`；`finish_expedition()` 在 `472-482` 读取 `GameState`/`TavernManager` 并本地写入酒馆。
- 联机专用控制器 `scenes/multiplayer/dungeon_session_controller.gd:202-207` 才会提交 `CMD_EXTRACT`；桥接层 `globals/multiplayer/multiplayer_scene_bridge.gd:350-389` 才会应用服务器结算并通知控制器。
- 本轮源码搜索未发现 `DungeonRuntime.on_extraction_requested()` 在多人模式下转调 `DungeonSessionController.request_extraction()` 的生产分支；现有联机 controller/bridge 证明了另一条路径，但没有证明 portal 信号已统一接入它。

影响：多人真实场景可能执行本地结算，或 portal 完成后不触发服务器事务；会造成重复结算、玩家不离场或单机/联机结果分叉。

修复建议：把“portal 完成”抽象为唯一 ExpeditionExitPort：多人模式只发 `CMD_EXTRACT`，单机模式只走本地结算；禁止 `DungeonRuntime` 直接同时拥有两种结算实现。增加真实场景测试断言 portal→命令→服务器结算→桥接应用→离场事件完整发生一次。

### P1-3：技能自 buff 的时间单位存在边界不一致

证据：
- `globals/core/player_context.gd:47,64-66,87-95` 将 `buffs` 存为 `Time.get_ticks_msec()` 绝对到期毫秒。
- `globals/multiplayer/skill_authority.gd:101-107` 却直接写入 `ctx.buffs[buff_type] = buff_sec`，写入的是秒数；`SessionRoot.tick_player_buffs()` 以绝对毫秒比较。

影响：技能 `iframes` / `dodge_frames` 等 buff 可能被立即视为过期，或在极端情况下出现错误的长期状态；权威状态与 HUD 快照也会不一致。

修复建议：技能统一调用 `PlayerContext` 的带时间语义 API（例如 `record_skill_buff`），禁止执行器直接写 `ctx.buffs`；用注入时钟测试“现在、未过期、恰到期、已过期”四个边界。

### P1-4：法术投射物仍有直接 `/root` 依赖，削弱会话注入边界

证据：
- `globals/combat/spell_authority.gd:120` 通过 `caster.get_node_or_null("/root/ProjectileService")` 获取投射物服务。
- 该类同时声明了会话级 world executor 与 movement/self-effect 端口，说明投射物服务仍未完全收敛到同一 composition root。

影响：headless、独立会话、重连/销毁和测试隔离时存在隐藏全局依赖；当前 `/root` 趋势测试只约束数量，不证明依赖已注入。

修复建议：在 `SpellAuthority` 注入 `projectile_port` 或由 `SessionCombatService` 直接传入会话拥有的 ProjectileService；删除该直接 root lookup，并增加“无 Autoload 但有注入端口仍可执行”的测试。

### P1-5：Autoload 与 Service Locator 仍是高耦合面

证据：
- `project.godot:17-49` 当前 31 个 Autoload，已达到 `tests/gdunit/architecture_dependency_rule_test.gd:27` 的硬上限。
- `globals/core/service.gd:7-16` 通过主循环根节点字符串查找并返回未类型化 `Node`；`ADR-005:8-16` 也明确记录了隐藏依赖和渐进迁移状态。
- `Service` 只是把根节点查找集中起来，没有消除运行时缺失、错误命名和生命周期耦合。

影响：新领域继续加 Autoload 会直接撞门禁；场景级服务的生命周期难以推断，单元测试需要大量隐式项目环境。

修复建议：保持 Autoload 冻结；新功能使用组合根注入，优先迁移 ProjectileService/DungeonSpawner/ItemSpawner 等场景级依赖；逐步将 Service 返回 `Object`/接口端口，避免继续扩大字符串访问器。

### P1-6：SaveManager 仍是跨领域聚合器，且旧路径与 sections 路径并存

证据：
- `globals/core/save_manager.gd:234-287,289-328,333-365` 仍显式拉取 TavernManager、GameState、AttrPanel、SkillRuntime、FermentationSystem、BrewFlowSystem、TavernSettlement、ArmorProficiency、ZoneManager。
- 同时又维护 `_sections` 注册表；`ADR-005:16` 明确说新聚合协议本轮未完全实施。

影响：新增持久化领域需要同时判断旧中央列表和 section 注册表，容易出现重复字段、迁移顺序不一致或 reset/deserialize 不对称。

修复建议：在存档版本迁移窗口一次性收口所有领域为 `SaveSection`，为每个 section 提供 schema/version/reset/idempotence 测试；在收口前禁止新增第二套持久化入口。

## 五、中低风险 / P2

1. **绝对 root 依赖门禁仍是趋势门禁而非架构证明**：当前生产扫描上限是 11 处；`Service._root()` 自身仍把所有依赖锚定到主循环根节点。应将新增引用门禁升级为白名单逐项审计，并要求端口注入测试。
2. **测试契约漂移**：本轮聚焦套件全绿，但标准扫描被 `service_test.gd` 的旧 API 直接打断；这说明“架构迁移完成”与“测试迁移完成”不是同一事务，应在 ADR-003/005 变更中强制同步更新测试。
3. **源码字符串断言仍有存量**：本轮扫描到大量测试使用 `source_code` / `get_file_as_string` 相关断言。ADR-008 已禁止新测试继续采用，但存量债仍会在重构时制造脆弱失败；应随触碰文件逐步替换为行为断言。
4. **编辑器扫描存在已知 stderr 噪声**：当前仅有 `EditorSettings` 初始化错误，CI 通过精确白名单放行；Godot 升级或真实错误若匹配同样片段，需要持续审计白名单。

## 六、健康项 / 已验证边界

- `SessionRoot` 已将命令族拆到 `SessionExpeditionService`、`SessionCombatService`、`SessionInventoryService`、`SessionProgressionService`、`SessionLifecycleService`，当前文件约 671 行，拆分方向有效，但仍是高耦合编排器。
- `SessionRoot` 的固定 tick 输入缓冲、服务器移动马达、实体复制、周期可靠基线、会话级法术世界执行器均有源码实现。
- `ServerSaveRepository` 与 GUID 重连身份链路已存在。
- 聚焦的地牢架构、网络管理、撤离 portal、撤离 loot、技能数据、服务访问契约、服务事务、法术 focus、多人场景和完整流程测试均通过。
- Dedicated Server 真实双进程闭环通过，且服务器日志 SCRIPT ERROR=0。
- Listen/Dedicated runner 当前均在 verdict 失败时返回非零；本轮未发现“FAIL 仍 exit 0”的假绿问题。

## 七、修复顺序

1. 修复 `service_test.gd` 过期访问器并让标准 CI 完整进入全量套件；调查 Godot 105 后 signal 11 是否可复现。
2. 修正 `SkillAuthority` 技能契约：先处理“无效果成功/冷却提交”，再实现或删除击退、眩晕、破盾、抓取、AoE 等字段。
3. 统一 `PlayerContext.buffs` 的绝对毫秒时间表示。
4. 修复 Listen `client2_recovery` 垂直切片，并把恢复结果纳入默认网络验收证据。
5. 将撤离 portal 收口为唯一单机/联机出口，增加真实生产接线测试。
6. 移除法术执行器直接 `/root/ProjectileService`，继续冻结 Autoload 并推进 SaveSection 全量收口。

## 八、审查限制

本轮并行审查工作器因客户端鉴权限制返回 403，未产生源码结论；本报告所有判断均由主审直接读取当前工作树并复核命令输出得出。视觉审查不在本轮架构范围内，未对截图作内容判断。
