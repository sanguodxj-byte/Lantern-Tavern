# Lantern Tavern 项目架构审查（从头审查）

- 审查时间：2026-08-07 09:52（GMT+8）
- 工作树基线：`865d2603`
- 审查对象：当前未提交工作树
- 审查方式：仅以当前源码、`project.godot`、术语表、ADR、测试脚本和本轮实测为判断依据；未使用项目记忆、旧架构报告或旧 overview 形成结论。
- 说明：当前工作树有大量既有修改与未跟踪文件；本轮只审查，不修改生产源码。
- 并行审查状态：`core-auditor`、`network-auditor`、`test-auditor` 均因 WorkBuddy 客户端鉴权 403 启动失败，未产生可采纳结论。下述结论均由主审直接读取源码与执行测试得出。

## 1. 执行结论

**当前不应合并。**

阻断原因不是编辑器无法加载，也不是聚焦架构测试失败，而是标准 CI 在测试发现阶段就被失效测试契约打断；同时真实 Listen ENet 本轮明确失败。Dedicated Server 路径本轮通过，说明联机基础设施并非整体失效，但两种服务器模式的可靠性尚未达到同一标准。

当前架构已经出现有效收敛：`SessionRoot` 已拆到 786 行并委托五个 session service；31 个 Autoload 和 `/root` 引用都有趋势门禁；技能未实现语义改为硬拒绝；撤离结果回传链路也已有桥接实现。但这些改进还没有完全闭环到默认 CI、真实 Listen 网络运行和生产撤离入口。

## 2. 本轮验证结果

### 2.1 Godot 无头编辑器扫描

命令：

```text
D:/123/Godot_v4.7-stable_mono_win64_console.exe --headless --path "D:/123/Lantern Tavern" --editor --quit
```

结果：

- 退出码：`0`
- 项目扫描、Autoload 创建、插件初始化完成
- stderr：`EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit"`
- 判断：项目可被 Godot 4.7 编辑器加载；该 stderr 当前属于环境/编辑器初始化噪声，不是本轮阻断项。

### 2.2 标准 CI

命令：

```text
D:/123/Lantern Tavern/run_ci.ps1 -GodotPath D:/123/Godot_v4.7-stable_mono_win64_console.exe
```

结果：

- 总退出码：`1`
- editor scan 门禁：通过
- Web / Windows Desktop / Android 导出预设识别：通过
- gdUnit4 全量发现：失败
- 首个确定性失败：`tests/gdunit/service_test.gd:58-59,74-75`
- 原因：测试仍引用已从 `Service` 删除的 `skill_data` / `action_skills` 成员与静态函数
- gdUnit4 首先报告异常退出 `105`，随后 Godot 发生 signal 11，PowerShell 最终接收到 `-1073741819`
- 判断：**默认质量门禁当前不可用，属于 P0。** 在测试发现完成前，不能用“其他聚焦测试全绿”代替全量回归。

### 2.3 聚焦架构、联机、法术、撤离测试

执行 11 个套件：

- `architecture_dependency_rule_test.gd`
- `network_protocol_test.gd`
- `network_manager_test.gd`
- `session_root_test.gd`
- `extraction_portal_test.gd`
- `extraction_loot_test.gd`
- `expedition_exit_test.gd`
- `spell_runtime_test.gd`
- `spell_network_behavior_test.gd`
- `spell_session_atomicity_test.gd`
- `service_transaction_test.gd`

结果：

- `185/185` 通过
- `0 errors / 0 failures / 0 skipped / 0 orphans`
- 退出码：`0`
- stderr 仍出现一次重复连接：`spell_network_behavior_test.gd:40` 重复连接 `session_event`
- 判断：核心局部契约可运行，但测试日志并不完全干净；重复信号连接应修复为 `is_connected()` 防重或在 teardown 中断开。

### 2.4 真实 ENet

Listen Server：

- 退出码：`1`
- 地牢 seed/fingerprint：匹配
- 实体复制：通过
- 战斗：通过
- 拾取：通过
- 撤离：通过
- late join / recovery：通过
- 移动：失败，`client_move_ok.txt` 缺失；最终客户端 verdict 为 `FAIL`
- 判断：**Listen 真实网络垂直切片本轮失败，属于 P1 发布风险。** 失败不是脚本假绿：runner 已正确以 1 退出。

Dedicated Server：

- 退出码：`0`
- seed/fingerprint：匹配
- 实体复制：通过
- 移动：通过（`dist=49.276`, `snapshots=12`）
- 服务器脚本错误：未触发失败条件
- 判断：Dedicated 路径本轮通过。

## 3. 主要发现

### P0 — 标准 CI 被失效测试契约阻断

证据：

- `tests/gdunit/service_test.gd:58-59` 把 `Service.skill_data`、`Service.action_skills` 当作可调用访问器。
- `tests/gdunit/service_test.gd:74-75` 再次调用这两个已删除 API。
- `globals/core/service.gd:46-75` 当前 combat 访问器中没有上述两个方法；技能定义现由调用方直接 preload 数据脚本，例如 `globals/multiplayer/skill_authority.gd:15-16`。
- `tests/gdunit/architecture_dependency_rule_test.gd:24-27` 也明确记录 SkillData/ActionSkills 已移出 Autoload。

影响：

- 全量测试无法完成发现，标准 CI 永远红。
- 后续所有测试结果都缺失默认入口的完整覆盖证明。
- 发现失败后的 signal 11 会掩盖根因并增加 CI 噪声。

建议：

1. 先更新 `service_test.gd`：删除旧访问器断言，改为断言 `Service` 不再承担纯数据表服务定位，或直接验证调用方使用 preload/class API。
2. 保留 Autoload 上限测试，防止为“修测试”把两个纯数据对象重新加回全局。
3. 修复后先只跑 `service_test.gd`，再跑完整 `run_ci.ps1`；不得只跑聚焦套件宣布完成。

### P1 — Listen ENet 移动垂直切片不稳定/失败

证据：

- 本轮 `tools/run_integration_dungeon_test.ps1` 真实双客户端流程退出 `1`。
- server、seed/fingerprint、entities、combat、loot、extract、recovery 都成功。
- `MOVEMENT: MISSING`，client 总 verdict 为 `FAIL local_x=-46.783 remote_x=-46.894 ...`。
- `tools/run_integration_dungeon_test.ps1:85-110` 已正确把移动结果纳入总判定，并在失败时退出 1。
- 同轮 `tools/run_dedicated_server_test.ps1` 退出 0，说明故障更可能位于 Listen 本地玩家/远端快照观察或测试时序，而不是通用协议完全失效。

影响：

- 房主模式是最常见联机入口；当前不能证明本地权威移动与远端观察稳定闭环。
- 该失败可能是竞态，也可能是本地 player/bridge/driver 双写或门槛设置问题；未定位前都不能归类为“偶发噪声”。

建议：

1. 在 `tests/integration/mp_dungeon_test.gd` 的移动判定处记录：命令 sequence、服务器 live_state、snapshot revision、本地 avatar 与远端 avatar 每阶段位置。
2. 区分“没有生成 verdict 文件”和“位置差未过阈值”，避免当前 `MISSING` 丢失具体失败阶段。
3. 连续运行 Listen 测试至少 10 次并统计失败阶段；Dedicated 同批运行作对照。
4. 修复后将 Listen 与 Dedicated 都接入默认 CI 的可控集成阶段，而不是依赖人工单跑。

### P1 — 生产撤离入口仍存在单机/联机双轨

已闭环部分：

- `scenes/multiplayer/client_command_driver.gd:187-197` 能发送 `CMD_EXTRACT`。
- `globals/multiplayer/session_root.gd:397` 注册了 `CMD_EXTRACT` 权威处理器。
- `globals/multiplayer/session_expedition_service.gd:73-104` 负责幂等结算与 `EVT_EXTRACTION_RESULT`。
- `globals/multiplayer/multiplayer_scene_bridge.gd:388-389` 已调用 `DungeonSessionController.notify_extraction_applied()`。

未闭环部分：

- `scenes/expedition/dungeon_runtime.gd:402-414` 将 portal 的 `extraction_requested` 直接连接到 `DungeonRuntime.on_extraction_requested`。
- `scenes/expedition/dungeon_runtime.gd:472-499` 随后直接做本地掉落结算并调用 `TavernManager.extract_to_tavern()`，这是单机路径。
- `scenes/multiplayer/dungeon_session_controller.gd:196-218` 虽提供 `request_extraction()` 和 `notify_extraction_applied()`，但项目生产源码中未发现 portal 的 `extraction_requested` 连接到 `controller.request_extraction()`；现有直接调用证据主要来自 `tests/gdunit/expedition_exit_test.gd`。
- `scenes/multiplayer/dungeon_session_controller.gd:7-10` 自身注释仍称真实 Lobby 完整接入“再挂”，当前控制器聚焦垂直切片。

影响：

- 单机地牢与多人地牢的撤离事务入口并未由一个明确 composition root 选择。
- 若多人真实场景复用了 `DungeonRuntime`，可能绕过服务器 `CMD_EXTRACT`；若不复用，则 portal/HUD/压力系统可能缺装配。

建议：

1. 定义唯一的 `ExtractionGateway`/端口：单机实现调用本地结算，多人实现只提交 `CMD_EXTRACT`。
2. `DungeonRuntime` 不直接知道 `TavernManager` 或网络协议，只调用注入端口。
3. 增加生产装配测试：实例化 MultiplayerSession → DungeonSessionController → 真实 portal，完成倒计时后断言只发送一次 `CMD_EXTRACT`，且收到 `EVT_EXTRACTION_RESULT` 后才发 `extraction_completed`。

### P1 — 技能 buff 时间单位与容器契约冲突

证据：

- `globals/multiplayer/skill_authority.gd:18-19,38-57` 的冷却明确使用绝对 `expire_ticks_ms`。
- `globals/multiplayer/skill_authority.gd:101-108` 对 buff 却把 `buff_value` 秒数原样写入 `ctx.buffs[buff_type]`。
- 现有测试使用 `ctx.buffs["spell_power"] = Time.get_ticks_msec() + 60000`，说明 `PlayerContext.buffs` 的消费者把值解释为绝对毫秒到期时刻。

影响：

- `iframes`、`dodge_frames` 等短时 buff 会被写成 0.x/若干秒的小数，而非当前 tick + duration。
- 在以 `now_ms >= expiry` 判断时，它们可能立即过期；若不同消费者把它当持续时间，则同一容器语义进一步分裂。

建议：

1. 统一 `PlayerContext.buffs` 为 `buff_id -> expires_at_ms`。
2. 写入使用 `Time.get_ticks_msec() + int(buff_sec * 1000.0)`；同类 buff 取较晚到期时刻。
3. 增加技能路径测试：施加、有效窗口、到期、序列化/重连恢复四个阶段。

### P2 — 全局服务面仍宽，但已有正确的渐进收敛方向

证据：

- `project.godot` 当前 31 个 Autoload；`architecture_dependency_rule_test.gd:24-32` 固定上限 31，并将生产 `/root` 引用上限设为 11。
- `globals/core/service.gd` 仍以 SceneTree root 名称定位大量 Node，类型返回大多为 `Node`，编译期约束有限。
- `globals/core/save_manager.gd:235-287,290-327` 仍中央拉取多个领域，同时已引入 `_sections` 注册机制；当前只有 ZoneManager 首批迁移。
- `docs/adr/ADR-005-service-locator-and-save-manager.md` 的决策方向与现状一致：渐进迁移纯策略与场景服务，SaveSection 分阶段接入。

判断：

- 这是可管理的架构债，不是本轮阻断项。
- 不建议“一次性清空 Autoload”；应继续用趋势门禁和触碰即迁移策略。

建议：

1. 每次修改领域时迁移一个 Service locator 调用为 preload 或构造注入。
2. SaveManager 每迁移一个领域，就删除对应旧中央分支，避免新旧路径长期双写。
3. 将 `Service` 的 Node 返回逐步缩成明确接口/具体类型，先从联机 composition root 与场景级服务开始。

### P2 — SessionRoot 拆分有效，但仍是高耦合 composition root

证据：

- `globals/multiplayer/session_root.gd` 当前 786 行。
- `session_root.gd:12-48` preload 约 37 个生产类/模块。
- `session_root.gd:104-121` 持有大量 authority 与 service。
- `session_root.gd:199-208` 已把出征、战斗、库存、成长、生命周期委托给五个 session service。
- 架构测试 R1-R4 已约束 session service 不依赖 UI/单机全局、UI 不写权威实体、state 层无 Node 依赖、session service 不读 root 私有字段。

判断：

- 相比单体 God Object 已明显改善；当前更像“仍偏大的 composition root”，不是应该继续机械切文件的业务类。
- 后续重点应是缩窄端口与减少 preload/直接知识，而不是按行数拆分。

建议：

1. 为 authority 组合定义小型端口对象，避免 SessionRoot 同时知道每个实现细节。
2. 将事件 outbox、peer state 生命周期和命令注册分别封装成可测试组件。
3. 保持 R1-R4，并新增“SessionRoot 不直接处理新业务命令”的静态门禁。

## 4. 积极信号

- 编辑器可正常扫描当前项目。
- 聚焦 185 个架构/联机/法术/撤离测试全部通过且无 orphan。
- Dedicated Server 真实 ENet 本轮通过。
- 两个 ENet runner 已正确把 FAIL 映射为非零退出码，不再假绿。
- 技能执行器对 stun、grapple、AOE、lifesteal、破盾等未实现语义采用前置硬拒绝，避免“空效果成功并提交冷却”。
- 技能移动经注入的服务器运动端口，不再直接写 `global_position`。
- 撤离结果 bridge → controller 的回传侧已存在，并有重复应用保护。
- SaveSection 与 session service 拆分已经落地首批实现，说明架构治理不是只停留在 ADR。

## 5. 修复顺序

1. **修复 `service_test.gd` 与当前 Service/Autoload 契约失配，恢复标准 CI。**
2. **定位 Listen ENet 移动 verdict 缺失，连续运行验证稳定性。**
3. **统一 portal 撤离入口：单机/多人通过注入端口选择，不允许 DungeonRuntime 直接决定多人本地结算。**
4. **修正 SkillAuthority buff 为绝对毫秒到期时间并补生命周期测试。**
5. 清理聚焦测试中的重复 `session_event` 连接 ERROR，使成功日志真正干净。
6. 继续渐进迁移 SaveManager 与 Service locator；不做大爆炸式全局重构。

## 6. 合并判定

- Godot editor scan：通过（有允许核实的初始化噪声）
- 导出预设识别：通过
- 聚焦测试：通过，185/185
- 标准 CI：**失败**
- Listen ENet：**失败**
- Dedicated ENet：通过
- 最终判定：**NO-GO**

恢复 GO 的最低条件：

1. `run_ci.ps1` 完整退出 0，测试发现不再出现旧 Service API；
2. Listen ENet 移动、战斗、掉落、撤离、恢复全部生成 verdict 且连续运行稳定；
3. 技能 buff 时间单位修复并有回归；
4. 多人 portal 到 `CMD_EXTRACT` 的生产装配有可执行端到端测试证明。
