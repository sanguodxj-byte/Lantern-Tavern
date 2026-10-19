# Lantern Tavern 项目架构审查（从头独立审查）

- 审查时间：2026-08-06 23:48–23:58（GMT+8）
- 审查对象：当前未提交工作树
- 审查依据：当前源码、`project.godot`、`docs/术语表.md`、`docs/24-联机架构迁移.md`、本轮实际测试
- 排除项：未读取 `.workbuddy/memory`，未读取旧 `outputs/architecture_review*` 或旧 overview 作为判断依据。自动化平台强制先读其运行历史，但以下结论均重新由当前代码和本轮测试验证。

## 一、结论

当前架构正在进行有效拆分：`SessionRoot` 已缩至 786 行，职责被迁移到 `session_*_service.gd`；联机结算桥接、技能未实现语义硬拒绝、CI 集成分支可达性等都出现了实质修复。不过当前工作树**不具备可合并状态**，原因不是抽象层次不够漂亮，而是存在两个直接正确性问题和一个门禁失真问题：

1. **P0：全量 gdUnit 在测试发现阶段即失败（exit 105）**，`service_test.gd` 仍引用已从 `Service` 移除的访问器，当前 CI 无法作为主干门禁。
2. **P0：联机技能自 buff 的时间单位错误**，将“持续秒数”写进声明为“绝对过期毫秒”的 `PlayerContext.buffs`，`iframes` / `dodge_frames` 会长期不失效。
3. **P1：聚焦测试虽 58/58 断言通过，但 stderr 有真实 Godot ERROR**；当前测试汇总绿色掩盖重复信号连接和未入树节点读取全局变换。

此外，真实 ENet 仍是可选门禁，默认 CI 不执行；联机撤离虽然已有 `CMD_EXTRACT → settlement → notify_extraction_applied` 组件，但普通 `DungeonRuntime` 仍直接本地结算，必须以生产联机场景装配测试证明不会误走单机路径。

## 二、验证结果

### 1. Godot 无头编辑器扫描

命令：Godot 4.7 Mono `--headless --editor --quit`

- 退出码：0
- stdout：项目扫描、autoload、插件加载完成
- stderr：`EditorSettings not instantiated yet when getting setting export/android/shutdown_adb_on_exit`

该 stderr 已被 `run_ci.ps1` 精确白名单列为引擎噪声，可接受，但不能扩大为泛化忽略规则。

### 2. 聚焦架构/联机测试

执行 9 个套件：

- `network_manager_integration_test.gd`
- `network_protocol_test.gd`
- `spell_network_behavior_test.gd`
- `multiplayer_scene_bridge_test.gd`
- `multiplayer_scope_test.gd`
- `extraction_portal_test.gd`
- `extraction_loot_test.gd`
- `spawn_save_state_security_test.gd`
- `service_access_contract_test.gd`

结果：**58/58 用例通过，0 failures，0 gdUnit errors，0 orphans，退出码 0。**

但 stderr 出现：

- `session_event` 重复连接到同一 callable；
- `multiplayer_entity.gd:36` 对未入场景树的 `Node3D` 读取 `global_transform`，多次报错。

因此这次“绿色”不是干净通过，只能证明断言层通过。

### 3. 全量 gdUnit

执行 `res://tests/gdunit` 全目录时，测试发现阶段失败：

- `tests/gdunit/service_test.gd:58`：`Service.skill_data` 不存在；
- `tests/gdunit/service_test.gd:59`：`Service.action_skills` 不存在；
- `tests/gdunit/service_test.gd:74-75`：对应静态函数不存在。

结果：**测试发现异常退出 105，随后 Godot 进程发生 segmentation fault。**

这是当前最直接的主干阻断项。`service_access_contract_test.gd` 的新门禁通过不代表旧 `service_test.gd` 已同步迁移；两者形成了互相矛盾的契约。

## 三、架构发现

## P0-1：全量测试门禁已经断裂

**证据**

- `globals/core/service.gd` 当前没有 `skill_data()` / `action_skills()`。
- `tests/gdunit/service_test.gd:58-59,74-75` 仍把二者当成 autoload 访问器。
- 全量发现阶段 exit 105，无法执行剩余数千测试。

**影响**

- 所有“聚焦测试全绿”都不能替代全量回归；
- CI 当前无法确认本次大规模工作树中的场景、存档、酿造、装备、UI 等其他区域；
- 进程随后段错误，日志可读性和稳定性进一步下降。

**建议**

先裁定真实契约：若 `SkillData` / `ActionSkills` 已改为静态数据库脚本而非 autoload，则更新 `service_test.gd`，不得重新把它们伪装成全局节点；若仍应是服务，则恢复实现并在 `project.godot` 注册。随后必须重新执行完整套件。

**验收**

- 测试发现无 parse error；
- 完整 gdUnit 退出码 0（或经过明确白名单的 101）；
- 不发生进程段错误。

## P0-2：技能自 buff 时间单位不一致，可能产生永久无敌/闪避

**证据**

- `globals/core/player_context.gd:47` 明确规定 `buffs` 值是绝对 `Time.get_ticks_msec()` 过期时刻。
- `PlayerContext.expire_buffs()` 仅当 `now_ms >= expiry` 时删除。
- `globals/multiplayer/skill_authority.gd:104-106` 将 `buff_value`（秒）直接写入 `ctx.buffs[buff_type]`。
- `action_skills.gd` 中 `iframes=0.5`、`dodge_frames=0.3`。

在正常运行时 `now_ms` 已远大于 0.5，但 `expire_buffs()` 把字典值强转为 int，0.5/0.3 变为 0；注释规定 0 表示不由此机制过期。因此这类 buff 会常驻。

**影响**

联机滑铲/战术步可能永久保留无敌帧或闪避状态；若后续战斗逻辑开始消费这些键，会直接成为严重战斗漏洞。

**建议**

统一由 `PlayerContext` 提供 `set_timed_buff(buff_id, duration_sec)`，内部生成绝对毫秒 expiry。禁止调用方直接写 `buffs`。增加真实时间推进测试：施放后存在，expiry 前存在，expiry 后删除；两个 peer 互不污染。

## P1-1：绿色聚焦测试仍输出引擎 ERROR

**证据**

- `spell_network_behavior_test.gd` 重复连接 `session_event`；
- `multiplayer_scene_bridge_test.gd` 触发 `multiplayer_entity.gd:36` 在节点未入树时读取全局变换；
- gdUnit 汇总仍报 58/58 PASS、退出 0。

**影响**

断言绿色与运行时干净被混为一谈。未来生产错误可能被同类噪声掩盖，CI 的 stderr 精确门禁也可能在聚焦直跑方式下被绕开。

**建议**

- 测试 setup 前用 `is_connected()` 防重复连接，teardown 断开；
- 测试实体先 `add_child()` 再应用依赖 global transform 的 spawn，或生产函数在 `is_inside_tree()` 前仅写局部 transform；
- 将测试命令封装进与 `run_ci.ps1` 同等严格的 stderr 检查，不允许 ERROR 在 exit 0 下通过。

## P1-2：真实 ENet 仍不是默认门禁

**证据**

- `run_ci.ps1:111-126` 只有传入 `-RunIntegration` 才执行 Listen + Dedicated ENet；默认明确打印 `NOT RUN`。
- 当前全量 gdUnit 又在发现阶段阻断，因此本轮未获得真实网络垂直切片证据。

**影响**

RPC sender、跨进程序列化、world revision、断线重连、Listen/Dedicated 场景装配等问题，逻辑测试无法覆盖。

**建议**

保持本地默认可跳过，但在至少一个隔离 CI job 中强制 `-RunIntegration`，并把该 job 设为合并必需检查。报告必须区分“逻辑测试通过”和“真实 ENet 通过”。

## P1-3：联机撤离组件已具备，但生产装配边界仍需闭环证明

**已确认的正向进展**

- `DungeonSessionController.request_extraction()` 会通过 `ClientCommandDriver.send_extract()` 提交 `CMD_EXTRACT`；
- `MultiplayerSceneBridge._apply_extraction_settlement()` 在落盘后调用 `notify_extraction_applied()`；
- `ExtractionPortal` 已实现按玩家自动倒计时和一次性 `extraction_requested`。

**仍需关注**

- `DungeonRuntime.wire_extraction_portal_signal()` 把 portal 连接到 `on_extraction_requested()`；
- `DungeonRuntime.on_extraction_requested()` 仍直接 `finish_expedition()`，进而本地 `_settle_extraction_loot()` + `TavernManager.extract_to_tavern()`。

若联机场景完全不使用 `DungeonRuntime` 的该接线，分叉可以成立；但当前需要生产装配测试证明，而不能只靠类级单测推断。

**建议验收**

新增 Listen/Dedicated 垂直测试：真实玩家进入 portal → 自动倒计时 → 客户端仅提交一次 `CMD_EXTRACT` → 服务端账本只结算一次 → 客户端活动槽位落盘 → `extraction_completed` 仅一次 → 没有调用本地 `TavernManager.extract_to_tavern()`。

## P2-1：拆分已有进展，但大文件和全局面仍然偏重

当前规模：

- `SessionRoot`：786 行（较明显拆分进步）；
- `NetworkManager`：756 行；
- `SaveManager`：413 行；
- `DungeonSceneBuilder`：2466 行；
- `project.godot`：31 个 autoload。

生产代码中仍能找到多处直接 `/root` 查找，虽然 `Service` 已提供统一入口。风险不是立即故障，而是依赖难以替换、测试需启动完整树、初始化顺序敏感。

**建议顺序**

1. 先修正确性和全量门禁，不要继续大拆；
2. 固化 `Service` 契约，禁止新增直接 `/root` 依赖；
3. 下一拆分对象优先 `DungeonSceneBuilder`（按布局构建、交互物、装饰、导航/物理注册分层），其次 `NetworkManager`（传输、握手、命令提交、集成生命周期）；
4. Autoload 只保留跨场景生命周期和基础设施，静态数据库/纯策略继续使用 preload/Resource，不要为测试方便重新全局化。

## 四、当前架构评分

| 维度 | 评分 | 判断 |
|---|---:|---|
| 模块边界 | 7/10 | SessionRoot 拆分有效，联机服务层方向正确；DungeonSceneBuilder、NetworkManager 仍偏重 |
| 权威一致性 | 6/10 | 未实现技能语义已硬拒绝，撤离桥接补齐；自 buff 时间单位是严重漏洞 |
| 测试可信度 | 3/10 | 聚焦断言绿，但 stderr 不干净；全量发现阶段直接失败 |
| 联机可验证性 | 5/10 | 逻辑覆盖不错，真实 ENet 默认可跳过，撤离装配闭环缺垂直证明 |
| 可维护性 | 6/10 | Service 与 session service 改善依赖；31 Autoload 和大构建器仍提高变更半径 |
| 当前可合并性 | 2/10 | 全量门禁 exit 105，必须先修 |

## 五、修复优先级

1. **立即修复 `service_test.gd` 与当前 Service 契约冲突，恢复全量测试可发现性。**
2. **修复 SkillAuthority 的 timed buff 写入，增加 expiry 与 per-peer 隔离测试。**
3. 清理聚焦测试 stderr ERROR，并把 ERROR 纳入测试失败标准。
4. 运行全量 gdUnit，逐项处理全部 failures/errors/orphans，直到门禁真实绿色。
5. 在隔离环境强制跑 Listen + Dedicated ENet；补 portal 到结算离场的垂直闭环测试。
6. 正确性稳定后，再继续拆 `DungeonSceneBuilder` / `NetworkManager`，避免在红色门禁上扩大重构面。

## 六、工作器状态说明

本轮尝试并行启动文档、核心运行时、联机边界和 CI 四个审查工作器；四者都在启动阶段因 WorkBuddy 客户端鉴权 403 失败，未产生任何源码分析或测试结论。本文所有结论均由主审直接读取当前代码并执行测试得到，不包含或假装包含失败工作器的产出。
