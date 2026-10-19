# Lantern Tavern 项目架构审查（从头开始）

- 审查时间：2026-08-06 19:44（GMT+8）
- 审查方式：仅基于当前工作树源码、project.godot、AGENTS.md、docs/术语表.md、ADR 与本轮实测；未读取项目记忆、自动化记忆、旧审查报告或 overview。
- 范围：核心依赖、多人权威链路、撤离/结算、技能/法术、存档、测试与 CI 门禁。
- 结论：**当前架构不具备“全绿可交付”状态。联机核心已形成可测试的权威事务边界，但仍有两个生产链路风险和一个验证门禁风险必须优先处理。**

## 一、实测基线

1. Godot 4.7 无头编辑器扫描退出码 0；stderr 有一条已知引擎噪声：`EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit"`。
2. 聚焦架构/联机/存档测试：13 个套件、214/214 用例通过，0 failure、0 orphan、退出码 0；日志仍出现一次重复 `session_event` 信号连接 ERROR，说明测试现场隔离/连接幂等仍有噪声。
3. 全量 `tests/gdunit`：498 个套件、4898 个用例中 4897 执行；**32 failures、7 errors、1 skipped、63 orphans，退出码 100**。失败并非单一架构主题，分布在地牢捕获、提取库存、升级面板、武器/视图模型、投射物池、法术会话状态、资源注册等多个区域；因此不能把“聚焦联机全绿”外推为项目全绿。
4. 当前工作树存在大量未提交改动及新增文件，审查只把它们作为当前状态取证，不假设其已提交或已集成。

## 二、P0 / 阻断项

### P0-1：真实 ENet 集成不是默认门禁，且当前默认 CI 明确跳过

**事实证据**：
- `run_ci.ps1:105-126` 只有传入 `-RunIntegration` 才执行 `tools/run_integration_dungeon_test.ps1` 与 `tools/run_dedicated_server_test.ps1`；默认路径输出 `INTEGRATION GATE: NOT RUN` 后仍继续并最终输出 `CI passed`。
- `tools/run_integration_dungeon_test.ps1:85-110` 与 `tools/run_dedicated_server_test.ps1:64-84` 当前已将 verdict 正确映射为 PASS=0、FAIL=1，不能再指责它们固定 exit 0；但这只修复了 runner 结果传播，未改变默认跳过事实。

**影响**：真实 RPC、ENet 双进程启动、listen/dedicated 生命周期、客户端场景恢复和真正网络撤离仍可能在默认 CI 之外回归；“CI passed”只能证明编辑器扫描、导出预设识别与 gdUnit 门禁通过，不能证明网络生产链路。

**建议**：把至少一个可复现的双进程 ENet smoke 作为网络环境的强制门禁；若基础设施无法每次运行，CI 输出必须是显式 `NOT RUN` 的非成功状态而不是统一绿结论，并在发布/合并工作流中设独立 required check。保留 runner 的非零失败传播。

### P0-2：联机撤离 portal 的生产接线仍缺少从真实场景到 `request_extraction()` 的调用证据

**事实证据**：
- `scenes/expedition/extraction_portal.gd:175-245` 负责自动进入倒计时，并在完成时发出 `extraction_requested(Player)`。
- `scenes/expedition/dungeon_runtime.gd` 通过 `wire_extraction_portal_signal()` 连接该信号到 `on_extraction_requested()`，随后 `finish_expedition()` 进入单机 `GameState/TavernManager` 结算路径。
- `scenes/multiplayer/dungeon_session_controller.gd:192-218` 新增了正确的 `request_extraction()` → `ClientCommandDriver.send_extract()`，并有幂等的 `notify_extraction_applied()`。
- `globals/multiplayer/multiplayer_scene_bridge.gd:180-186,346-389` 能应用服务器 `EVT_EXTRACTION_RESULT`，保存到活动槽位并通知 controller。
- 但在当前生产源码搜索中，未发现 `ExtractionPortal.extraction_requested` 或联机地牢控制器把 portal 完成事件路由到 `DungeonSessionController.request_extraction()` 的调用；`DungeonSessionController.request_extraction()` 只有定义与测试/注释证据。`DungeonSceneBuilder` 也明确在 `...` 行注释接线属于 runtime 阶段，实际接线集中在 `DungeonRuntime`。

**影响**：联机真实撤离可能仍走单机本地结算，或 portal 完成后只进入单机路径；服务器 `CMD_EXTRACT`、ServerSaveRepository 幂等结算与生产离场通知未形成端到端调用闭环。测试通过的 `notify_extraction_applied()` 不能替代生产调用证据。

**建议**：在 MultiplayerSession/DungeonSessionController 的真实构建路径中显式连接 portal 完成信号：portal → `request_extraction()` → `CMD_EXTRACT`；让 `EVT_EXTRACTION_RESULT` 应用后通过 `extraction_completed` 统一切回酒馆/释放地牢。增加一个真实场景装配测试，断言联机控制器连接到 portal，而不是只测试 stub driver。

## 三、P1：高风险设计债

### P1-1：技能权威执行器只接受“已实现字段”，但当前技能数据仍声明大量未兑现语义

**事实证据**：
- `globals/multiplayer/skill_authority.gd:59-130` 当前采用前置硬拒绝：`grapple`、`stun_sec`、`breaks_shield`、`ignore_def`、`ignore_block`、`lifesteal`、AoE 字段均返回 `unsupported_skill_effect:*`，因此不会在失败时提交冷却。
- `globals/combat/action_skills.gd:21-92` 的冲撞声明击退/眩晕/破盾，抓取投掷声明抓取/眩晕，踢击声明击退；`globals/combat/skill_data.gd` 仍有 cone/circle/line AoE、目标 debuff 等声明。
- 当前执行器实际兑现的是单目标 damage、knockback（经 `skill_damage`）、movement 族位移和自 buff；其余字段被拒绝而不是结算。这个防“空效果成功”的选择是安全的，但技能表与联机可用能力不一致。
- `skill_authority.gd:101-107` 将 `ctx.buffs[buff_type] = ... buff_sec` 写入；而 `PlayerContext` 的 `buffs` 明确是 `buff_id -> expiry_ms`，`expire_buffs(now_ms)` 按绝对毫秒时间比较（`globals/core/player_context.gd:87-100`）。技能自 buff 当前写入秒数，后续会被当作已过期/无效的时间戳，属于状态表示不一致。

**影响**：用户在多人中释放某些已绑定技能会得到拒绝；能成功的滑铲/战术滑步类自 buff 可能无法按声明持续。数据层、单机动作分发与多人权威能力没有共享一份“可执行语义契约”。

**建议**：短期保留硬拒绝，并把可用/不可用状态显式呈现给 UI；修复 buff 的统一表示（全部使用绝对 expiry_ms，或通过 PlayerContext 专用 API 写入），补行为测试验证过期。中期为 AoE、眩晕、破盾、抓取/投掷、目标 debuff、吸血各自建立权威执行器与事件契约，不能只从拒绝名单移除字段。

### P1-2：SessionRoot/NetworkManager 仍是高耦合编排中心，ADR 拆分只完成了编排迁移的一部分

**量化事实**：当前统计为 296 个生产 GDScript（globals/scenes/data）、512 个测试 GDScript、33 个 Autoload；`SessionRoot` 723 行、`NetworkManager` 756 行、`SaveManager` 413 行；生产源码绝对 `/root` 引用 11 处。`project.godot:17-51` 注册 33 个 Autoload。

**事实证据**：
- `SessionRoot` 已把出征、战斗、库存、成长、生命周期委托到 5 个 service，但仍持有 registry/world/router/validator、9 个 authority、5 个 service、输入采样、实体同步、敌人战斗、战斗状态广播、投射物生命周期、服务器碰撞移动等大量生命周期和跨域状态。
- `SaveManager:234-365` 已增加 SaveSection 注册表，但旧的 `serialize_all/deserialize_all/reset_all` 仍集中拉取多套 Autoload；ADR-005 明确 SaveManager 聚合器尚未完成迁移，当前是新旧双路径并存。
- `architecture_dependency_rule_test.gd:24-32,73-80` 只把 Autoload 与 `/root` 约束在静态数量/趋势上限，达到上限即可通过，未验证依赖是否注入、服务是否持有错误生命周期或生产场景是否实际装配。

**影响**：功能改动容易横跨会话、全局状态与场景表现；新增领域仍需触碰中央存档；`/root` 趋势门禁可能“守住债务”但不真正改善依赖方向。

**建议**：按变更频率继续切片，不做无收益机械重构；下一刀优先把真实生产联机控制器装配和 SessionRoot 服务端口的生命周期收口。SaveSection 迁移要有删除旧字段路径的终点、schema migration 和重复写入测试；依赖门禁增加实际装配测试与禁止跨层 API 调用规则。

### P1-3：聚焦测试与完整测试的语义不一致

**事实证据**：聚焦 13 套件 214/214 全绿，但全量 498 套件仅 4897/4898 执行，32 failure、7 error、63 orphan、退出 100；错误日志包括 `MockSpellPlayer` 缺少 `buffs`、物理回调中移除 CollisionObject、空 material 等。

**影响**：架构相关绿灯容易被误读为项目整体健康；全量失败跨多个子系统，说明当前工作树尚未达到合并基线。ADR-008 规定审查相关套件 0 failure/orphan，但没有把全量失败的归因/隔离流程作为门禁输出的一部分。

**建议**：报告必须同时展示聚焦与全量结果；将 32 failures/7 errors/63 orphans 分为真实回归、环境/渲染限制、过时断言三类并逐项清零或显式豁免；尤其修复 `MockSpellPlayer` 等测试替身，避免测试因替身接口不完整而掩盖权威状态问题。

## 四、P2：维护性与验证质量

1. **源码字符串断言规模过大**：当前 256 个测试文件使用 `source_code`/`get_file_as_string` 类静态断言；ADR-008 已禁止新测试继续增加，但存量仍会在拆分/重命名后失效。优先把联机事务、撤离装配、技能效果从字符串断言改为行为测试。
2. **重复信号连接错误**：聚焦测试日志出现 `session_event` already connected。当前测试虽 0 failure，但该 ERROR 会使未来 CI stderr 精确门禁误判，且暗示会话/测试生命周期连接未完全幂等。
3. **服务器移动存在可审计回退**：`SessionCombatService.apply_authoritative_movement:378-398` 在无物理 body 或无碰撞世界时回退纯数学积分。生产 dedicated 通过 `build_authority_collision_only()` 生成碰撞，但任何漏装配/场景不存在都会降级为无碰撞位移；应对生产模式缺少碰撞世界直接拒绝，而不是继续成功。
4. **Autoload 规模已触顶**：当前 `AUTOLOAD_LIMIT=33` 与实测 33 相等。新增全局单例会立即突破门禁；这不是坏事，但说明架构治理已依赖“不要再加”，而不是已经完成服务定位器收敛。

## 五、当前应优先执行的修复顺序

1. **先闭联机撤离生产装配**：portal 完成事件接入 `DungeonSessionController.request_extraction()`，补真实场景装配测试，再执行双进程 ENet。
2. **修复技能 buff 时间单位**：统一 expiry 表示；确认所有成功技能都有可观察状态变化，未实现技能继续硬拒绝并在 UI 显示不可用。
3. **把 ENet 集成纳入 required CI**：默认 CI 不得用统一“passed”掩盖 NOT RUN；runner 维持 PASS/FAIL 非零传播。
4. **清理全量测试门禁**：先按上面的 32/7/63 清单分类，修复真实错误与 orphans，再评估静态字符串债。
5. **最后推进 SaveSection/SessionRoot 余债**：以真实生产装配和行为契约为驱动，避免为了行数重构。

## 最终判定

- **架构方向：部分合格**——会话权威、服务拆分、服务器存档仓、撤离幂等协议的方向成立，聚焦测试证明这些局部契约当前可运行。
- **交付状态：不合格**——全量 gdUnit 退出 100；真实 ENet 默认不跑；联机 portal → CMD_EXTRACT 生产接线缺少调用证据；技能状态时间表示存在直接语义错误。
- **最高优先级不是继续扩展功能，而是先补齐联机生产装配与全量验证可信度。**
