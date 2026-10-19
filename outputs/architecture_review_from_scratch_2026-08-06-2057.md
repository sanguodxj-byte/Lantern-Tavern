# Lantern Tavern 项目架构审查（从头开始）

- 审查时间：2026-08-06 20:57（GMT+8）
- 审查方式：仅基于本轮直接读取的当前工作树源码、`project.godot`、`docs/术语表.md`、当前 ADR、测试源文件和本轮实际命令结果。
- 明确排除：项目记忆、自动化历史、既有审查报告、既有 overview 结论。本报告不采纳并行工作器的分析：3 个工作器均在启动阶段因 WorkBuddy 客户端鉴权限制返回 403，未产生源码或测试结论。
- 范围：架构边界、Autoload/根节点耦合、多人权威链路、技能与撤离、存档、测试与 CI。
- 总结结论：**当前项目已具备可运行的多人权威垂直切片，但不具备“全量验证绿、默认 CI 覆盖真实网络、联机撤离完成后必然离场”的交付条件。最高优先级不是继续堆功能，而是修复发布门禁和联机离场闭环。**

## 1. 本轮实测基线

### 1.1 编辑器扫描

命令：

```text
Godot_v4.7-stable_mono_win64_console.exe --headless --path "D:\123\Lantern Tavern" --editor --quit
```

结果：退出码 0。插件 MCP listener 能启动并停止。stderr 只有：

```text
ERROR: EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit".
```

这是当前 CI 脚本明确白名单的引擎初始化噪声；不能把“退出码 0”解释成 stderr 完全干净。

### 1.2 架构/联机聚焦测试

本轮直接运行 12 个聚焦套件：

- `architecture_dependency_rule_test.gd`
- `session_root_test.gd`
- `network_manager_test.gd`
- `network_protocol_test.gd`
- `dedicated_server_seed_test.gd`
- `spell_network_behavior_test.gd`
- `spell_network_completion_test.gd`
- `extraction_portal_test.gd`
- `expedition_exit_test.gd`
- `save_manager_test.gd`
- `project_bootstrap_test.gd`
- `service_access_contract_test.gd`

结果：**177/177 通过，0 failure，0 orphan，退出码 0。**

但 stderr 出现一次重复信号连接错误：

```text
Signal 'session_event' is already connected to given callable ... spell_network_behavior_test.gd::_on_session_event
```

这不影响本轮断言结果，却说明测试/会话对象的连接生命周期还不够幂等；未来若把 stderr 作为严格错误门禁，当前聚焦测试会变红。

### 1.3 全量 gdUnit4

命令：

```text
Godot_v4.7-stable_mono_win64_console.exe --headless --path "D:\123\Lantern Tavern" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" -a "res://tests/gdunit" --ignoreHeadlessMode -c
```

结果：

- 498 个测试套件
- 4898 个测试用例
- 4897 执行，1 skipped
- **76 failures，7 errors，62 orphans**
- 退出码 **100**

失败/错误分布在 `dungeon_real_overview_capture_test`、`dungeon_stress_perf_probe_test`、`extraction_loot_test`、`level_up_panel*`、`projectile_service_test`、`project_bootstrap_test`、`session_event_outbox_test`、`spell_end_to_end_test`、`spell_session_atomicity_test`、`spell_world_executor_test`、`weapon_registry_test`、`voxel_shield_asset_test`、`view_model_test`、`trap_variety_test` 等多个区域。

因此，聚焦架构测试的绿色只能证明所选契约通过，不能外推为项目全绿。当前全量结果本身就是交付阻断信号。

### 1.4 真实 ENet 双进程测试

本轮实际运行两个脚本，均 PASS：

1. `tools/run_integration_dungeon_test.ps1`
   - Listen server + client + late-join client
   - `seed_match=true`、`fp_match=true`
   - 移动、实体、战斗、掉落、拾取、撤离、重连恢复均报告 OK
   - 进程最终输出 `INTEGRATION DUNGEON TEST: PASS`，脚本退出成功

2. `tools/run_dedicated_server_test.ps1`
   - Dedicated server + client
   - server/client 地牢指纹匹配
   - 实体同步与权威移动通过
   - `DEDICATED SERVER TEST: PASS`，脚本退出成功

这证明当前真实网络垂直切片可运行；但它没有改变“默认 CI 不执行”的门禁结论。

## 2. 架构规模与边界

### 2.1 规模快照

直接从当前文件统计：

| 项目 | 当前值 | 证据 |
| --- | ---: | --- |
| Autoload | 33 | `project.godot` `[autoload]` |
| 生产 GDScript | 303 | `globals/`、`scenes/`、`data/`、`fx/` 递归统计 |
| 测试 GDScript | 512 | `tests/` 递归统计 |
| `SessionRoot` | 723 行 | `globals/multiplayer/session_root.gd` |
| `NetworkManager` | 756 行 | `globals/core/network_manager.gd` |
| `SaveManager` | 413 行 | `globals/core/save_manager.gd` |
| `DungeonRuntime` | 616 行 | `scenes/expedition/dungeon_runtime.gd` |
| 根节点/绝对根路径宽扫描 | 56 个生产文件、112 次命中 | 包含 `/root/`、`get_root()`、`root.get_node` 形式 |

当前 ADR-003 已把 SessionRoot 拆出多个 authority/service；这是正确方向，但 723 行的编排器仍是高耦合中心。当前 `architecture_dependency_rule_test.gd` 的趋势门禁只扫描非注释行中的 `"/root/` 字面量，和本轮宽扫描口径并不一致。因此“门禁通过”不等于“根依赖只有 11 处”：统计口径必须统一，否则趋势图会失真。

### 2.2 Autoload 与 ServiceLocator

33 个 Autoload 正好等于架构门禁上限，说明没有继续增长，但也说明全局服务面已经到达治理红线。`Service` 兼容层降低了直接根路径引用，却没有消除隐藏依赖；场景和领域对象仍可以通过全局服务读取进程状态。

ADR-005 已提出分层迁移与 SaveSection，但状态仍是 Proposed，且当前 `SaveManager` 仍在 `serialize_all()` / `deserialize_all()` / `reset_all()` 中显式拉取多个领域单例。虽然已经存在 `_sections` 注册协议并迁移 `ZoneSaveSection`，新旧两条路径仍并存。新增持久化领域仍可能继续扩大中央聚合器，形成“协议已存在、主路径未收敛”的架构债。

### 2.3 手工酒馆边界

本轮未运行任何酒馆烘焙、合并、批量重写或材质生成工作流。现有代码显示酿造面板的写入已冻结，写入入口指向 `BrewFlowSystem` / 3D 酿造间链路；这符合当前手工酒馆场景边界。该区域不应通过批量生成方式修复架构问题。

## 3. P0：交付阻断项

### P0-1：默认 CI 跳过真实 ENet，网络垂直切片可被“逻辑绿”掩盖

`run_ci.ps1:105-126` 只有传入 `-RunIntegration` 才会运行 Listen 与 Dedicated 集成脚本；默认分支只输出：

```text
INTEGRATION GATE: NOT RUN — real ENet listen/dedicated tests skipped
```

随后仍可输出 `CI passed: unit + smoke gates green.`。这使默认成功语义只代表 gdUnit + smoke，而不代表真实网络可用。两套 ENet 脚本虽然本轮实际 PASS，但未进入默认门禁，回归可在合并时漏过。

**整改要求：** 将网络门禁拆成明确的必需环境检查：发布/主分支必须执行真实 Listen + Dedicated；无网络环境只能返回明确的 `NOT_RUN` 非发布结果，不能复用 `CI passed`。至少在 CI 输出中区分 `UNIT_GREEN`、`INTEGRATION_GREEN` 与 `RELEASE_GREEN`，并让发布 job 对缺少集成结果失败。

### P0-2：全量测试退出码 100，当前工作树不是可交付绿基线

全量 498 套件出现 76 failures、7 errors、62 orphans，退出码 100。即便部分是渲染器、视觉捕获或存量契约债，当前项目没有一个可被称为“全量绿”的基线。不能用 177 个聚焦测试掩盖全量红。

**整改要求：** 先按套件分类处理：生产功能失败、测试环境/渲染器失败、过期断言、orphan。每类都要有明确处置：修复、显式跳过并记录理由、或从发布门禁隔离；不能仅降低门禁或扩大白名单。

### P0-3：联机撤离完成事件没有发现生产消费者，存在“结算成功但不离场”风险

当前联机撤离链路存在：

```text
DungeonSessionController.request_extraction()
  -> ClientCommandDriver.send_extract()
  -> CMD_EXTRACT
  -> server settlement
  -> MultiplayerSceneBridge._apply_extraction_settlement()
  -> save_to_slot(active_slot)
  -> controller.notify_extraction_applied(settlement)
  -> extraction_completed.emit(settlement)
```

这些代码证据分别位于：

- `scenes/multiplayer/dungeon_session_controller.gd:202-218`
- `scenes/multiplayer/client_command_driver.gd:187-199`
- `globals/multiplayer/multiplayer_scene_bridge.gd:350-389`

但在当前生产源码中没有找到 `extraction_completed.connect(...)` 的消费者；只找到 `expedition_exit_test.gd` 对该信号的测试连接。与此同时，单机路径仍由 `scenes/expedition/dungeon_runtime.gd:402-499` 把 portal 信号直接接到本地 `finish_expedition()`。这意味着：服务端结算与本地存档写回可以成功，但联机模式下上层场景切换/回到酒馆的生产接线尚未被当前源码证明。

**整改要求：** 为联机控制器建立唯一生产离场消费者（例如由 `MultiplayerSession` 或 World transition composition root 连接 `extraction_completed`），并补一个真实场景测试：portal 自动倒计时完成 → CMD_EXTRACT → EVT_EXTRACTION_RESULT → 本地一次写回 → `World` 离开地牢。测试必须断言事件消费者确实存在，而不是只调用 `notify_extraction_applied()`。

## 4. P1：高优先级结构风险

### P1-1：技能权威执行器采用“硬拒未实现字段”，正确防止假成功，但能力面与设计语义仍不完整

`globals/multiplayer/skill_authority.gd:59-130` 当前实际兑现：

- 单目标伤害（经 `damage_port`）
- 目标击退（由 damage port 返回并广播）
- movement 族碰撞安全位移（经 `movement_port`）
- 自 buff

对 grapple、stun、breaks_shield、ignore_def、ignore_block、lifesteal、AoE 等字段，代码会返回 `unsupported_skill_effect:*` 并阻止提交冷却。这是比“返回成功但效果缺失”更安全的设计，也应保留。但它同时意味着动作技能设计表仍不能全部在线上使用。

**整改要求：** 把技能定义字段与 `SkillExecutionPlan`/执行器能力做成自动契约矩阵；每增加一项语义，必须补服务端行为测试、事件 schema、目标选择规则和重连快照规则，完成后再从硬拒列表移除。不要把硬拒列表当作完成标记。

### P1-2：技能自 buff 的时间表示需要统一协议

`SkillAuthority` 的冷却以 `expire_ticks_ms`（绝对毫秒）记录，而自 buff 在 `ctx.buffs[buff_type]` 中写入 `buff_sec`（秒数）。二者生命周期表达不同。当前聚焦测试证明技能资源与冷却隔离，但没有证明 buff 在服务器 tick、重连快照和过期清理中始终以同一时间语义消费。

**整改要求：** 统一为服务器绝对 expiry（毫秒或 tick），在 `PlayerContext`、快照、重连恢复、抵抗/免疫检查中使用同一字段；秒数只作为输入配置，不作为运行时状态。

### P1-3：SessionRoot 仍是编排高压点

虽然 ADR-003 已拆出大量 authority/service，`SessionRoot` 仍保留服务装配、命令入口、tick 调度、共享状态、快照和公共委托，723 行并 preload 大量类型。其风险不是“现在完全不可维护”，而是任何新联机功能都会触碰中央编排器，容易再次形成 god object。

**整改要求：** 后续按变更频率继续拆，不做大爆炸重构。优先把 tick 调度拆成明确的 `SessionTickCoordinator`（输入、敌人、buff、连接四类时钟），再把公共委托接口收敛成稳定的端口集合；每刀保持单文件改动和聚焦测试。

### P1-4：根节点依赖趋势门禁口径过窄

当前静态门禁只检查 `"/root/` 字符串；本轮宽扫描还发现 `get_root()`、`root.get_node` 等不同形式，合计 56 个文件/112 次命中。门禁与测量口径不一致，容易出现门禁绿而实际耦合仍上升。

**整改要求：** 建立一个共享扫描器，统一忽略注释/测试/工具的规则，并同时识别：绝对 `/root/...`、`get_tree().root`、`get_root()`、以 root 为对象的路径拼接。结果按文件和命中类型输出；白名单必须逐项写原因。

### P1-5：重复信号连接错误虽不使断言失败，但会污染生命周期可信度

聚焦测试中 `spell_network_behavior_test.gd:40` 重复连接 `session_event`。这通常意味着测试 setup、会话复用或 teardown 没有严格做到“连接前判定/结束后断开”。网络事件是一次性语义，重复监听可能导致生产事件双处理。

**整改要求：** 所有会话/桥接连接统一使用 `is_connected()` 防重复，测试 fixture 在 teardown 释放并断开；新增一条断言：同一对象重复 setup 不增加监听次数。

## 5. P2：治理与质量债

1. `SaveManager` 的 SaveSection 迁移尚未覆盖全部领域，旧中央序列化列表仍是新增耦合点。
2. 498 套件全量失败分布广，包含资源加载、渲染捕获、升级面板、投射物池、法术状态、武器注册、实体/场景和 orphan；需要专项分桶，而不是简单扩大白名单。
3. 测试中存在“源码字符串断言”和生产行为测试混杂的迹象。它能快速捕捉迁移，但容易在 ADR 拆分后失效，应逐步换成可运行行为/公共 API 契约。
4. 编辑器扫描有已知 Engine stderr 白名单；白名单应保持精确，不能退化成忽略所有 stderr。
5. 本项目有明确的手工酒馆场景和单模型建模约束；后续架构整改不得通过酒馆批量烘焙、场景整文件替换或批量模型生成绕过边界。

## 6. 建议执行顺序

### 第一阶段：把“绿”定义做实

- 发布/主分支强制拿到 Listen + Dedicated ENet 结果。
- 为 CI 返回值区分单元绿、集成绿、发布绿；默认跳过集成不能输出发布绿。
- 建立全量失败分桶，先修 7 errors 和功能性 failures，再处理视觉/渲染环境类失败和 orphan。

### 第二阶段：闭合联机撤离

- 在生产 composition root 连接 `extraction_completed`。
- 增加真实 portal-to-world-transition 测试，覆盖成功、重复 EVT、落盘失败和离场。
- 保持单机 `DungeonRuntime.finish_expedition()` 与联机服务器结算分叉，但将模式选择显式化，禁止同一玩家在联机模式误走本地结算。

### 第三阶段：收敛权威协议

- 统一 buff expiry 时间语义。
- 建立技能语义矩阵，逐项实现 AoE/眩晕/抓取/破盾/吸血等剩余能力，或继续保持硬拒并在 UI/网络协议中显式显示不可用。
- 统一 session event 的连接/断开生命周期。

### 第四阶段：降低结构债

- 统一 root 依赖扫描口径。
- 按变更频率拆 SessionRoot tick coordinator。
- 继续推进 SaveSection，减少 SaveManager 对具体 Autoload 的显式依赖。

## 7. 最终判定

- **编辑器可启动：是。**
- **聚焦架构/联机/存档测试：是，177/177。**
- **真实 Listen ENet：是，本轮 PASS。**
- **真实 Dedicated ENet：是，本轮 PASS。**
- **全量测试：否，76 failures / 7 errors / 62 orphans，exit 100。**
- **默认 CI 是否覆盖真实 ENet：否，必须传 `-RunIntegration`。**
- **联机撤离“结算完成后生产离场”是否被当前源码完整证明：否，未找到 `extraction_completed` 的生产消费者。**

**交付结论：架构方向基本正确，权威边界已有实质落地；但当前只能称为“多人垂直切片可运行、项目整体不可交付”。在 P0-1、P0-2、P0-3 关闭前，不建议宣称发布就绪。**
