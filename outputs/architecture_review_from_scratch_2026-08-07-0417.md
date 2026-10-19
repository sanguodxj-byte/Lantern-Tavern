# Lantern Tavern 项目架构审查（从头开始）

- 审查时间：2026-08-07 04:17（GMT+8）
- 审查对象：当前未提交工作树
- 引擎基线：Godot 4.7 stable mono / GDScript
- 结论来源：当前源码、`project.godot`、`AGENTS.md`、`docs/术语表.md`、ADR、CI 脚本与本轮实测
- 隔离说明：未读取项目记忆、旧架构报告或旧 overview 作为判断依据；工作器启动均因 403 鉴权失败，本文所有结论由主审直接核验

## 一、执行摘要

当前架构处于“核心联机权威链已搭起，但工作树不能交付”的状态。

正向进展很明确：`SessionRoot` 已从单体编排器拆为五个会话服务，Dedicated Server 的 seed 解包和权威碰撞链可工作；聚焦架构/联机/存档测试 189/189 通过；Dedicated ENet 垂直切片通过。

但存在两个阻断项：

1. **标准 CI 在测试发现阶段失败**：`service_test.gd` 仍引用已经移除的 `Service.skill_data()` / `Service.action_skills()`，导致退出 105，随后 Godot signal 11；因此当前工作树无法形成可合并的全绿证据。
2. **真实 Listen 联机垂直切片失败**：地牢与晚到恢复成功，但移动判定文件缺失，战斗、掉落、撤离均失败；源码同时显示生产联机地牢没有把 `ExtractionPortal.extraction_requested` 接到 `DungeonSessionController.request_extraction()`。

综合评级：**RED / 不可合并**。先恢复 CI 契约和 Listen 撤离/战斗垂直链，再继续扩大架构改造。

## 二、范围与量化

| 指标 | 当前值 | 判断 |
| --- | ---: | --- |
| 生产 GDScript（globals/scenes/data/fx） | 303 | 中大型单体仓库 |
| gdUnit 测试脚本 | 499 | 测试面广，但质量分布不均 |
| 使用源码字符串检查的测试文件 | 256 | 过半测试仍含结构/源码断言，重构脆弱 |
| Autoload | 31 | 已到架构门禁上限 |
| `session_root.gd` | 786 行 | 已明显拆分，但仍是高耦合组合根 |
| `network_manager.gd` | 756 行 | 传输、会话、事件转发职责仍偏重 |
| `save_manager.gd` | 413 行 | 正在迁移 SaveSection，但双轨并存 |
| 未提交变更 | 54 个已跟踪文件，另有多项新增文件 | 审查对象不是干净基线，结论只能代表当前工作树 |

## 三、验证结果

### 3.1 Godot 编辑器扫描

命令：Godot 4.7 console，`--headless --editor --quit`

- 退出码：0
- 解析/脚本错误：未发现
- stderr：仅 `EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit"`，与 `run_ci.ps1` 精确白名单一致

### 3.2 聚焦架构测试

本轮执行 11 个套件：

- `architecture_dependency_rule_test.gd`
- `dedicated_server_seed_test.gd`
- `dungeon_host_assembly_contract_test.gd`
- `expedition_exit_test.gd`
- `network_manager_test.gd`
- `network_protocol_test.gd`
- `session_root_test.gd`
- `save_manager_test.gd`
- `spell_network_behavior_test.gd`
- `spell_network_completion_test.gd`
- `spell_session_atomicity_test.gd`

结果：**189/189 通过，0 failure，0 error（报告统计），0 orphan，退出码 0**。

但 stderr 实际出现：

- `Signal 'session_event' is already connected`，来源 `spell_network_behavior_test.gd:40/111`。

这说明 gdUnit 的统计结果没有把引擎级 `ERROR` 转成失败；“189 全绿”不能等价为日志干净。

### 3.3 标准 CI

执行 `run_ci.ps1`（未启用 `-RunIntegration`）：

- 编辑器扫描：通过
- Web / Windows Desktop / Android export preset 识别：通过
- gdUnit 全量发现：失败
- 第一失败：`tests/gdunit/service_test.gd:58-59,74-75`
- 原因：`Service.skill_data`、`Service.action_skills` 已从 `globals/core/service.gd` 删除，但旧测试仍要求访问器存在
- gdUnit 首次报告退出 105；随后 Godot signal 11；外层 CI 最终退出 1
- 真实 ENet 分支未执行

### 3.4 真实 ENet

**Listen Server：FAIL，脚本退出 1**

- seed/layout 指纹：匹配
- 实体复制：通过（2 个实体）
- 晚到/恢复：通过
- movement：`MISSING`
- combat：false
- loot：false
- extract：false

**Dedicated Server：PASS，脚本退出 0**

- seed/layout 指纹：匹配
- 实体复制：通过
- movement：通过（18 snapshots）
- 服务端脚本错误：未触发失败

结论：Dedicated 的基础移动垂直切片可靠性高于 Listen；两种服务器模式尚未达到一致验收标准。

## 四、问题清单

## P0 — 阻断项

### P0-1 标准 CI 因测试契约失配不可运行

**证据**

- `globals/core/service.gd:1-149` 已无 `skill_data()` / `action_skills()`。
- `tests/gdunit/service_test.gd:58-59,74-75` 仍直接引用这两个静态成员。
- `run_ci.ps1:79-103` 正确把非 0 gdUnit 结果设为 RED；本轮实测最终退出 1。

**影响**

- 全量回归无法发现后续真实失败；任何“聚焦测试全绿”都不能替代标准 CI。
- 由于测试发现失败后又触发引擎 signal 11，失败输出被二次噪声污染，诊断成本增加。
- `-RunIntegration` 分支本轮不可达，不是脚本控制流问题，而是前置全量测试已阻断。

**处理建议**

1. 立即更新 `service_test.gd`，删除已迁出纯数据表的访问器契约，改为验证 `Service` 只暴露保留的进程级/场景级服务。
2. 增加一个契约测试：`service_test.gd` 本身必须可被 scanner 加载，防止服务定位器收敛时测试反向卡死 CI。
3. 修复后先跑标准 CI，再跑 `-RunIntegration`；不要只跑聚焦套件。

### P0-2 真实联机撤离入口没有完成生产装配，Listen 集成已实测失败

**证据**

- `ExtractionPortal` 在 `scenes/expedition/extraction_portal.gd:237-244` 只发出 `extraction_requested`。
- 单机 `DungeonRuntime` 在 `scenes/expedition/dungeon_runtime.gd:402-414,495-499` 将信号接到本地 `finish_expedition()`。
- 联机 `DungeonSessionController` 提供 `request_extraction()`（`scenes/multiplayer/dungeon_session_controller.gd:192-207`），但其 `build_and_enter()` / `_build_real_dungeon()`（同文件 `37-43,81-103`）只构建几何和玩家，没有实例化 `DungeonRuntime`，也没有扫描并连接撤离 portal。
- 全仓生产调用中未发现 `ExtractionPortal.extraction_requested -> DungeonSessionController.request_extraction()`；现有 `expedition_exit_test.gd` 是直接调用 API 的水平测试。
- 本轮 Listen ENet：`extract_ok=false`。

**影响**

- 联机玩家进入撤离区域后可能走不到 `CMD_EXTRACT`，服务器结算、幂等账本、存档写回和离场事件整体不发生。
- 单机与联机在同一世界物体上存在两套生命周期，极易继续分叉。

**处理建议**

1. 在 `DungeonSessionController` 的生产构建完成点装配 portal 信号；联机只提交 `send_extract()`，禁止调用单机 `DungeonRuntime.finish_expedition()`。
2. 增加真实场景测试：实例化联机地牢，找到实际 portal，触发完成，断言 driver 仅收到一次 `CMD_EXTRACT`。
3. Listen ENet 必须把 `extract_ok=true` 作为硬门禁，并验证结算应用后只发一次 `extraction_completed`。

## P1 — 高风险

### P1-1 技能 buff 的时间表示错误：秒数写入“绝对毫秒 expiry”容器

**证据**

- `PlayerContext.buffs` 明确定义为 `buff_id -> Time.get_ticks_msec()` 绝对过期毫秒：`globals/core/player_context.gd:43-48`。
- `expire_buffs(now_ms)` 按绝对毫秒比较：同文件 `87-95`。
- 法术 buff 正确写入 `now + duration * 1000`：同文件 `52-68`。
- 技能 `SkillAuthority.execute()` 却把 `buff_value` 秒数直接写入 `ctx.buffs[buff_type]`：`globals/multiplayer/skill_authority.gd:101-108`。

**影响**

- `iframes` / `dodge_frames` 等短时技能 buff 会在下一次会话 tick 被立刻判过期，而不是持续声明的秒数。
- 测试只断言“字典中写入 buff”，没有验证按真实服务器时钟持续与过期。

**处理建议**

统一通过 `PlayerContext` 的 buff API 写入绝对 expiry；补充“施放后尚未到期仍存在、到期后只清一次”的行为测试。

### P1-2 Listen 联机战斗/掉落/移动垂直切片失败

**证据**

本轮 Listen 实测：

- `movement=MISSING`
- `combat_ok=false`
- `loot_ok=false`
- `extract_ok=false`
- 但 seed、layout、实体复制、晚到恢复均为 true

**影响**

架构当前更像“复制/恢复切片已通，玩法事务切片未通”。如果默认 CI 不带 `-RunIntegration`，这类问题不会阻断普通提交。

**处理建议**

按 movement → combat → loot → extract 的事务依赖顺序修复；每修一段保留失败 marker 和退出码传播，最终让 Listen 与 Dedicated 使用同一份最低验收矩阵。

### P1-3 主动技能定义与联机权威执行仍未闭环

**证据**

`globals/multiplayer/skill_authority.gd:59-130` 仅完整支持单目标伤害、击退、movement 位移和自 buff；grapple、stun、breaks_shield、ignore_def、ignore_block、lifesteal、AoE 被统一硬拒绝。

**判断**

硬拒绝比“部分成功并提交冷却”安全，当前不是数据破坏 bug；但它意味着技能表中已声明的主动能力在联机模式不可用，属于明确的功能/架构欠账。

**处理建议**

为效果语义建立独立执行器或策略表，每实现一种字段就加“定义 → 权威状态变化 → outbox → 客户端表现”的端到端测试；在此之前继续保持硬拒绝，不允许降级为静默忽略。

### P1-4 测试统计全绿但 stderr 含引擎 ERROR

**证据**

`spell_network_behavior_test.gd` 的双 peer 用例重复连接 `session_event`，Godot 输出 `Signal ... is already connected`，但 gdUnit 仍汇总 189/189、exit 0。

**影响**

CI 只看退出码时会产生“日志红、状态绿”。真实错误可能被当成测试噪声掩盖。

**处理建议**

修复测试连接生命周期；将聚焦/全量测试 stderr 的 `ERROR|SCRIPT ERROR|Parse Error` 纳入与编辑器扫描同等的精确白名单门禁。

## P2 — 结构债与治理问题

### P2-1 31 个 Autoload 已到上限，Service 仍隐藏依赖

`project.godot:17-49` 注册 31 个 Autoload；`architecture_dependency_rule_test.gd:24-32` 也把 31 和 11 个 `/root` 引用作为上限。趋势门禁能防增长，但不能证明依赖方向健康。

建议继续执行 ADR-005：纯数据/策略退出 Autoload，场景级服务由组合根注入。不要为了给新全局服务腾位置而机械上调上限。

### P2-2 SaveManager 正处于双轨迁移，ZoneManager 被重复序列化

`globals/core/save_manager.gd:235-287` 仍在中央路径写 `selected_zone`，同时 `_ready()` 注册 `ZoneSaveSection`，并在 `sections` 再写一次；恢复时旧路径先执行，新 section 后覆盖（`289-327`）。

这保证兼容，但形成两个真相来源。建议明确迁移窗口和删除条件：版本适配器能读取旧键后，生产写入只保留 section；否则后续字段漂移会让两个表示不同步。

### P2-3 大型组合根仍需控制变更面

- `SessionRoot` 786 行：已拆分到五个 session service，方向正确；仍持有大量权威系统、共享容器端口和路由装配。
- `NetworkManager` 756 行：传输、peer 生命周期、命令提交、事件派发、集成辅助方法共存。

建议不做纯行数拆分；下一刀应以“传输适配器”和“会话事件下发/节流”变更冲突为触发条件，并保持外部 API 不变。

### P2-4 测试中源码字符串检查占比过高

499 个 gdUnit 文件中，256 个包含 `source_code` 或 `get_file_as_string`。ADR-008 已禁止新测试用源码字符串证明行为，但存量仍超过一半。

风险是重命名、拆文件、组合根迁移会制造大量假失败或假绿。应只在触及对应模块时渐进替换为实例化行为测试；禁止单独发起大规模机械清理。

### P2-5 ADR 与现行门禁存在文档漂移

`docs/adr/ADR-008-ci-gate-policy.md:12-15` 仍写“默认 101=YELLOW，`-FailOnOrphan` 才 RED”，而 `run_ci.ps1:87-98` 实际是默认 RED，只有显式 `-AllowOrphan` 才放行。

建议以当前脚本的严格策略为准，更新 ADR，避免维护者按旧决策误判 CI 语义。

## 五、架构优点

1. **联机权威入口具备明确意图协议**：客户端技能/法术/撤离只提交意图，服务端解析定义和权威状态。
2. **SessionRoot 拆分方向正确**：出征、战斗、库存、成长、生命周期服务边界已存在，且依赖规则测试禁止回碰 UI/单机全局/私有字段。
3. **Dedicated Server seed/布局闭环已修正**：`dedicated_server.gd:89-112` 正确解包 `start_expedition()` 结果，本轮 Dedicated ENet 指纹匹配并通过移动验证。
4. **集成 runner 退出码传播正确**：两个脚本末尾均按 verdict 返回 0/1，本轮 Listen 失败实际退出 1，Dedicated 成功退出 0，没有假绿。
5. **存档 IO 有三段恢复协议**：tmp/bak/final 的恢复链和 JSON 校验比直接覆盖稳健。

## 六、建议执行顺序

### 第一批：恢复可交付基线

1. 修复 `service_test.gd` 的过期契约。
2. 跑标准 CI，要求全量发现/执行完成。
3. 修复聚焦测试重复信号连接 ERROR。

### 第二批：打通真实 Listen 垂直链

1. 接通 portal → `request_extraction()` → `CMD_EXTRACT`。
2. 修复 movement marker 缺失。
3. 修复 combat，然后 loot，最后 extract。
4. 运行 `run_ci.ps1 -RunIntegration`，要求 Listen + Dedicated 同时通过。

### 第三批：修正权威状态语义

1. 修复技能 buff expiry 单位/时间基准。
2. 为未实现技能字段逐类落地权威执行器；未实现前保持硬拒绝。
3. 将关键源码字符串测试迁为行为测试。

### 第四批：继续渐进收敛

1. 完成 ZoneSaveSection 单写入迁移。
2. 更新 ADR-008 与实际 orphan 策略一致。
3. 保持 Autoload 不增长；新增能力优先显式注入。

## 七、最终结论

当前工作树的架构方向总体正确，尤其是 SessionRoot 服务化、Dedicated 权威碰撞和集成脚本退出码；但“方向正确”不等于“可交付”。

**当前必须判 RED：标准 CI 无法完成，Listen 真实玩法事务失败，联机撤离生产装配缺失，技能 buff 时间语义错误。**

最优策略不是继续扩大重构，而是先把测试契约、Listen 垂直链和 buff 时间模型修到全绿，再继续架构收敛。否则会在一个不可验证的工作树上叠加更多变更，风险像在湿水泥上盖二楼。