# Lantern Tavern 项目架构审查（从头独立审查）

- 审查时间：2026-08-07 22:28（GMT+8）
- 审查对象：当前未提交工作树
- 引擎：Godot 4.7 / GDScript（Mono）
- 结论等级：**RED（当前不可作为稳定架构基线）**

## 1. 审查边界

本轮从当前源码、`project.godot`、术语表、ADR、联机权威文档和本轮实际测试重新形成判断。按要求未读取 `.workbuddy/memory`、旧架构报告或旧 overview；自动化调度器强制读取的自身执行摘要仅用于执行协议，不作为本报告证据。

重点覆盖：

- Composition Root / Autoload / 隐式依赖
- 多人服务器权威边界、重连、结算、撤离
- 技能/法术权威执行
- 单机与服务器存档
- CI、gdUnit4、真实 ENet 门禁
- 当前工作树可验证性

## 2. 执行摘要

当前架构已经有明确的正确方向：`SessionRoot` 已拆成 5 个会话服务，服务层通过窄端口访问共享容器；联机撤离 portal 已有生产接线测试；技能 timed buff 已改为绝对毫秒；架构依赖规则测试已建立。编辑器无头扫描退出 0，说明当前源码至少可被编辑器完整扫描。

但当前工作树不具备稳定基线资格：

1. **标准 CI 失败**：500 套、4916 用例中出现 **6 errors、109 failures、126 orphans**，退出码 100。
2. **重连后的结算幂等缓存错误**：同一 GUID 换 peer_id 重连后，重复撤离虽然被标记 `already_settled=true`，但缓存 settlement 从预期 2 变成 0。
3. **真实 ENet runner 在本机挂起**：Listen 只到 `server ready`，Dedicated 只执行进程清理，均超过 10 分钟且未产生本轮 verdict；这不是“未运行”，而是门禁基础设施自身不终止。
4. **工作树规模过大且混合多个领域**：至少 144 个文件、约 2894 行新增 / 8606 行删除，包含联机、存档、法术、酒馆、素材、体素资产、CI、文档等，无法获得可靠的失败归因。

因此本轮最重要的判断不是“继续拆大类”，而是：**先恢复可验证基线，再继续架构演进。**

## 3. 阻断项（P0）

### P0-1 标准 CI 为 RED，当前架构没有可信回归基线

**证据**

- `run_ci.ps1:79-103` 将全量 gdUnit4 作为正式门禁，非 0/101 均失败。
- 本轮 `outputs/architecture_ci_2026-08-07-2228.log:68090-68096`：
  - 500/500 suites
  - 4915/4916 executed，1 skipped
  - 6 errors
  - 109 failures
  - 126 orphans
  - exit 100
- 编辑器扫描和 Web / Windows Desktop / Android preset 识别门禁通过，但测试阶段失败，集成分支不会执行。

**架构影响**

这意味着任何“拆分完成”“边界闭环”的判断都缺少全仓证据。失败横跨地牢、撤离库存、升级 UI、第一人称动画、投射物池、重连、事件 outbox、法术会话、体素资产与注册表。部分可能是工作树中多项未完成变更互相污染，不能简单归因于单个模块。

**处理建议**

- 暂停新增架构重构。
- 按领域把当前工作树拆成可独立验证的 change set：联机/存档、酒馆、第一人称动画、体素资产、测试基础设施。
- 每个 change set 恢复相关测试后再合并；最终要求标准 CI 退出 0，或对已知 orphan 使用明确、可审计的豁免。

### P0-2 重连后的结算幂等结果损坏

**证据**

- `tests/gdunit/reconnect_recovery_test.gd:138-167` 构造同 GUID 从 peer 3 重连为 peer 9：首次拾取 `goblin_tooth ×2` 并结算，重连后再次撤离应返回首次缓存 settlement。
- 本轮聚焦测试：`outputs/architecture_focused_tests_2026-08-07-2228.log:581-587`，预期 2，实际 0。
- `SaveAuthority` 的账本本身以 GUID 为键（`globals/multiplayer/save_authority.gd:23-64`），设计正确；失败更可能位于重连迁移期间 inventory baseline / context / 结算快照装配。
- `SessionExpeditionService.settle_expedition()` 在已结算时直接返回 `save_auth.get_settlement(guid)`（`session_expedition_service.gd:83-94`），所以实际 0 表明首次记录的 settlement 已错误，或重连过程改写了账本/基线关联。

**风险**

客户端会收到“已结算”但奖励明细为 0。若表现层依赖该缓存恢复 UI/离场结果，会造成已获得战利品显示丢失或状态分歧；更糟的是开发者可能为修 UI 而绕开幂等账本，重新打开刷物品漏洞。

**建议**

- 把 `inventory_baseline` 的键从临时 `peer_id` 收敛到稳定 GUID，或在 resume 的 peer 迁移事务中显式迁移 baseline。
- 在首次结算前后断言：GUID、base、current inventory、computed settlement、save_auth cached settlement。
- 增加行为测试覆盖 `spawn → baseline → loot → extract → disconnect → resume(new peer) → extract`，禁止用源码字符串断言替代。

### P0-3 真实 ENet 门禁会挂起，无法给出网络可玩性结论

**证据**

- `run_ci.ps1:105-126` 只有显式 `-RunIntegration` 才执行真实 Listen + Dedicated。
- 本轮直接运行两个 runner：
  - Listen 超过 22 分钟，仅写出 `server launched` / `server ready: ready`；
  - Dedicated 超过 12 分钟，仅写出一次进程终止记录；
  - 均被人工终止，未产生本轮 verdict。
- `tools/run_integration_dungeon_test.ps1:38-76` 理论最大等待约 423 秒（3 + 60 + 120 + 240），实际超过 20 分钟仍不退出，说明启动器/子进程/管道或清理阶段存在阻塞。
- runner 通过 `.cmd` + `start` 管理进程，并全局 `taskkill` 同名 Godot 进程，进程所有权不精确。

**风险**

网络门禁既默认不跑，显式运行又可能永久占用 CI worker。当前不能声称 Listen / Dedicated 垂直链本轮通过。

**建议**

- runner 持有明确 PID，不再按进程名全局杀 Godot。
- 每一阶段设置硬超时并在 `finally` 清理，任何缺失 verdict 都必须 exit 1。
- CI 中将 Listen / Dedicated 分成独立 job，上传 server/client 日志与 verdict；总 job timeout 必须小于平台上限。
- 将网络集成纳入至少每日或主分支门禁，而非长期依赖手工 `-RunIntegration`。

## 4. 高优先级问题（P1）

### P1-1 工作树跨领域混杂，验证和回滚边界失效

`git status` / `git diff --stat` 显示当前工作树同时修改 144 个文件，涉及：

- `SessionRoot` 大规模拆分及 5 个新会话服务；
- NetworkManager、协议、服务器仓、SaveManager / SaveSection；
- 法术/技能、撤离、专服、集成脚本；
- 酒馆顾客/酿造；
- 多个武器 GLB 与生成器；
- 大量测试、文档与旧报告删除。

这已经超出“一个可审查 change set”的规模。即使单个模块设计正确，全量失败也难以定位是代码、资产、导入缓存、测试过时还是初始化污染。

**建议**：先保存当前状态，再按领域拆分提交/分支；不要在这个混合工作树上继续做横切重构。

### P1-2 Autoload 仍然过宽，ADR-005 实施状态与现状不一致

**证据**

- `project.godot:17-49` 当前有 31 个 Autoload。
- ADR-005 明确“新增代码禁止新增 Autoload”，并计划将场景级服务迁移到 Composition Root。
- 架构依赖门禁当前只做趋势上限，不能证明每个 Autoload 都是进程级基础设施。
- 当前仍包含 `DungeonSpawner`、`ItemSpawner`、`ProjectileService` 等场景级候选。

**判断**

不建议一次性清空 Autoload；ADR 的渐进策略合理。但新增功能应优先显式注入，尤其是场景级生命周期对象。当前更重要的是补一份“批准的 Autoload 白名单 + owner + 生命周期”而不是只有数量阈值。

### P1-3 SaveManager 处于双路径迁移期，中央聚合器仍是耦合中心

**证据**

- `globals/core/save_manager.gd:30-57` 已引入 `SaveSection`，但目前仅注册 ZoneManager。
- `save_manager.gd:234+` 仍集中拉取 TavernManager / GameState / AttrPanel / SkillRuntime / FermentationSystem 等领域。
- ADR-005 原文称 SaveSection “本轮不实施”，而当前工作树已开始实施；ADR 状态与实现阶段需要同步。

**风险**

双路径意味着同一领域可能被旧聚合器和新 section 重复序列化/反序列化；迁移顺序不明确时会出现覆盖。建议为每个 section 定义唯一 key、版本和 ownership，并增加“同 key 不允许旧路径同时写”的门禁。

### P1-4 测试结果被大量运行时 ERROR 噪声污染

全量日志中存在多类 `ERROR:`，包括预期拒绝路径、空材质、physics callback 删除节点、未入树节点读取 transform，以及 MockSpellPlayer 缺失 `buffs` 的 SCRIPT ERROR。部分套件仍显示自己的统计通过，但全局结果最终包含 errors/failures。

**建议**

- 预期业务拒绝不要使用 `push_error`；用结构化结果或可注入 logger。
- 测试预期的引擎错误必须显式捕获/断言，不能留在全局 stderr。
- 新增“套件声称通过但产生 SCRIPT ERROR 则失败”的门禁，避免假绿。

## 5. 中优先级问题（P2）

### P2-1 隐式 `/root` 依赖已下降，但仍存在于生产边界

本轮在生产目录发现约 9 处显式 `/root` 查找，主要集中于：

- `globals/multiplayer/multiplayer_session.gd`
- `scenes/multiplayer/dungeon_session_controller.gd`
- `scenes/multiplayer/dedicated_server.gd`
- `scenes/ui/lobby_menu.gd`
- `scenes/expedition/procedural_dungeon.gd`

这些多处于 Composition Root / 场景装配边界，风险低于领域层直接查根节点，但应保持“只允许在装配层”的规则。当前架构规则测试方向正确，建议从计数阈值升级为路径白名单。

### P2-2 ADR-003 的 SessionRoot 拆分方向正确，但不要继续机械拆分

当前 `SessionRoot` 约 787 行，已经从 God Object 转为：

- 装配 / 命令路由
- tick 调度
- 共享权威状态容器
- 对外兼容委托

`SessionExpeditionService`、`SessionCombatService`、`SessionInventoryService`、`SessionProgressionService`、`SessionLifecycleService` 已各自承担命令族。服务通过 `live_state()` / `entities()` / `inventory_baseline()` 等窄端口访问状态，架构测试也覆盖了服务不触碰私有字段。

这是合理的拆分终点。接下来优先修复事务一致性与测试，而不是为了行数继续拆。

### P2-3 架构文档存在历史陈述与当前实现并存

`docs/24-联机架构迁移.md` 前部明确标注运行时已落地，但中后部仍保留“游戏代码联机为零”“Phase 3 后续”等历史段落。虽然文档已说明以 `docs/25` 为准，阅读成本仍高，容易让新维护者误判现状。

建议把历史实证移动到“迁移前基线”附录，正文只保留当前状态与未完成验收。

## 6. 已确认的正向架构

1. **服务器权威命令入口**：`SessionRoot.on_command()` 验证协议、revision、禁用可信字段、在线/存活/上下文，再路由命令。
2. **会话服务窄端口**：Session 服务不再直接访问 root 私有字段，已有架构规则测试。
3. **撤离生产链有行为证据**：`expedition_exit_test.gd` 的 `portal signal → request_extraction → driver.send_extract` 本轮通过，5/5。
4. **技能 buff 时间契约已修正**：`SkillAuthority.execute()` 使用 `PlayerContext.apply_timed_buff()` 返回绝对毫秒 expiry。
5. **技能权威语义覆盖扩大**：伤害端口已处理 knockback / stun / break shield / ignore def/block / lifesteal / AoE / grapple；相关 `session_root_test` 本轮通过。
6. **编辑器扫描可通过**：无头 editor scan 退出 0；只有已知 `EditorSettings` 关闭时噪声。
7. **CI 不再假绿**：`run_ci.ps1` 对 gdUnit exit 100 正确返回失败；`-RunIntegration` 分支不再因单测成功提前退出。

## 7. 本轮验证结果

| 验证 | 结果 | 结论 |
|---|---:|---|
| Godot headless editor scan | exit 0 | 通过；有已知 EditorSettings 噪声 |
| Export preset 识别 | Web / Windows / Android 通过 | 仅证明 preset 可识别，不证明实际导出成功 |
| 聚焦架构/联机/法术/撤离/存档测试 | 142 用例，1 failure，0 orphan，exit 100 | RED；重连结算幂等失败 |
| 标准 CI 全量 gdUnit | 500 suites，4916 cases，6 errors / 109 failures / 126 orphans，exit 100 | RED |
| Listen ENet | 挂起，人工终止 | 无本轮通过证据 |
| Dedicated ENet | 挂起，人工终止 | 无本轮通过证据 |

备注：聚焦命令中指定了不存在的 `skill_authority_test.gd`，gdUnit 提示路径不存在后继续运行其余 7 套；技能权威行为实际上由 `session_root_test.gd` 与现有 `skill_effects_test.gd` 覆盖。后续应维护可执行的测试清单，避免“看似选了套件、实际未运行”。

## 8. 推荐整改顺序

### 阶段 A：恢复基线（立即）

1. 冻结新增横切重构。
2. 修复 `reconnect_recovery_test.gd` 暴露的稳定 GUID / baseline / cached settlement 问题。
3. 按领域拆分当前工作树，确保每个 change set 有独立回归范围。
4. 将全量 CI 恢复至 exit 0；对 orphan 只允许明确清单豁免。

### 阶段 B：修复网络门禁

1. runner 改为 PID 所有权 + `try/finally` 清理。
2. 为 server-ready、client-ready、verdict、cleanup 各设硬超时。
3. Listen / Dedicated 分离执行、分别上传日志。
4. 把真实 ENet 放入主分支或每日强制门禁。

### 阶段 C：完成渐进式架构收敛

1. SaveSection 明确每个领域的唯一 ownership，逐个迁移并删除对应旧聚合路径。
2. Autoload 使用批准白名单，而不是只有数量阈值。
3. `/root` 查找限定在 Composition Root 路径白名单。
4. 清理会产生未捕获 SCRIPT ERROR / 引擎 ERROR 的测试与实现。

## 9. 最终判断

架构方向比典型 Godot 单例泥团健康：服务器权威、会话服务、窄端口、稳定身份、幂等账本和行为门禁都已经有清晰骨架。问题不在“没有架构”，而在**当前工作树同时推进太多架构与内容改动，验证体系已经被压穿**。

当前应判定：

- 设计方向：**可继续**
- 当前工作树：**不可合并 / 不可作为基线**
- 首要修复：**重连结算幂等 + 全量 CI + ENet runner 终止性**
- 不建议：在上述三项恢复前继续拆 SessionRoot 或新增 Autoload/横切系统
