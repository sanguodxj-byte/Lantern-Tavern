# Lantern Tavern 架构审查报告

> **执行透明度说明：** 原计划并行开展的 3 个只读子审查（Godot 配置、数据流、场景与测试）均因客户端鉴权错误 `403` 在启动时失败，没有产出任何发现。本报告不包含、也没有假装包含这些失败子审查的结论；报告中的所有判断仅来自主审查流程直接读取的文件、搜索结果和实际执行的测试。并行交叉复核因此缺失，报告置信度相应下调。

- 审查时间：2026-08-08 00:14（GMT+8）
- 审查方式：从当前工作树重新取证；按用户要求，不读取项目记忆、自动化执行记忆或旧架构报告作为判断依据。
- 范围：Godot 项目配置、Autoload/服务定位、多人权威链、撤离链、存档、技能/法术、测试/CI、文档与架构门禁。
- 工作树状态：审查前已存在大量未提交修改、删除和未跟踪文件。本报告不修改源码、不替用户清理工作树。

## 结论

**总体判定：RED（架构基础已明显改善，但当前不能把项目称为“架构门禁全绿”。）**

本轮聚焦架构/权威/撤离/技能/法术的 4 个 gdUnit4 套件共 **27/27 通过，0 failure、0 error、0 orphan**；其中依赖方向、/root 趋势、Autoload 上限、多人撤离装配、技能效果和法术端到端测试均通过（`reports/report_8222/results.xml`）。

但标准 CI 在约 2 分钟后失败，失败发生在“gdUnit4 全量套件”阶段而非编辑器扫描或导出预设阶段；日志显示套件已执行到大量场景/实体测试后仍未完成，进程超时失败。真实 ENet 集成在本次标准 CI 中未执行，因为 `run_ci.ps1` 默认只有显式传 `-RunIntegration` 才进入集成门禁（`run_ci.ps1:105-126`）；GitHub workflow 虽有独立 ENet job，但本地默认命令不能证明网络链路通过。

因此：**关键局部架构测试绿，不等于全量回归绿，也不等于真实网络链路本轮已验收。**

## P0 / 阻断项

### P0-1：全量 CI 当前不可收敛

证据：
- `run_ci.ps1:79-103` 执行整个 `tests/gdunit`，本轮执行超过 120 秒后由宿主超时终止，未得到最终 gdUnit 总结。
- 编辑器 headless scan 已通过，导出 preset 识别已通过；阻断点在全量 gdUnit 阶段。
- `reports/report_8222/results.xml` 只代表本轮 4 个聚焦套件，不代表全量套件。

影响：合并门禁无法在可接受的本地审查周期内给出全量确定性结果；若 CI runner 也出现相同耗时/崩溃，开发者会得到“门禁红但原因不稳定”的反馈。

建议：
1. 将全量测试拆为可并行、可独立失败的批次，并对每批输出明确 exit code、超时和 crash 分类。
2. 将架构/联机/存档/战斗核心设为快速阻断批次；视觉捕获和重型场景测试移入独立长批次。
3. 对单套件设置硬超时，超时必须 RED，并上传最后一个套件日志。
4. 修复/隔离重复测试发现与场景泄漏噪声后，再恢复“全量绿”声明。

### P0-2：真实 ENet 本轮没有证据

证据：
- `run_ci.ps1:105-126`：未传 `-RunIntegration` 时明确输出 `INTEGRATION GATE: NOT RUN`。
- 本轮只执行了 `run_ci.ps1` 默认路径和 4 个聚焦逻辑套件；没有拿到 Listen/Dedicated 本轮 verdict。
- `.github/workflows/ci.yml:57-105` 定义了独立 ENet job，这说明设计上有门禁，但不能替代本次执行结果。

影响：多人出征、移动、战斗、掉落、撤离、重连的真实进程装配仍可能与纯逻辑测试不一致。

建议：网络环境下必须单独运行并保存 Listen + Dedicated 两份 verdict；把“未运行”作为明确的 NOT RUN 状态，不得汇总为 GREEN。

## P1 / 高风险

### P1-1：Autoload/服务定位仍是全局耦合面

证据：
- `project.godot:17-49` 当前声明 33 个 Autoload（包括进程基础设施、领域权威、策略/数据和网络会话对象）。
- `tests/gdunit/architecture_dependency_rule_test.gd:24-32` 以 `AUTOLOAD_LIMIT := 31`、`ROOT_REF_LIMIT := 11` 作为趋势门禁，但当前 `project.godot` 的 Autoload 段实际超过 31；本轮聚焦测试却仍通过，说明该计数门禁存在“只读到首个区段/当前配置与测试基线不一致”的可疑契约，需要立即核对。
- `globals/core/service.gd:7-16` 通过 `Engine.get_main_loop().root.get_node_or_null()` 解析单例；它减少了散落字符串，但本质仍是运行时根节点服务定位器。
- 生产源码仍有 `/root` 访问，例如 `scenes/multiplayer/dungeon_session_controller.gd:181-190`、`scenes/expedition/procedural_dungeon.gd:90`、`scenes/ui/lobby_menu.gd:55`；静态趋势门禁本轮通过，但路径依赖仍存在。

影响：场景生命周期、headless 测试、独立服务器和多会话并存时，隐式全局依赖会导致装配顺序与运行环境差异。

建议：
- 先冻结 Autoload 增长；将纯数据/纯策略继续退出 Autoload。
- Composition Root 显式注入场景级服务；Service 仅保留兼容层并新增使用计数/禁止新增调用的门禁。
- 将门禁从“字符串计数”升级为解析后的真实 section 统计，并对允许项逐项列白名单与理由。

### P1-2：SaveManager 仍是中央聚合器，迁移协议处于双轨

证据：
- `globals/core/save_manager.gd:230-287` 的 `serialize_all()` 仍显式拉取 TavernManager、GameState、AttrPanel、SkillRuntime、FermentationSystem、BrewFlowSystem、TavernSettlement、ArmorProficiency、ZoneManager。
- `globals/core/save_manager.gd:289-364` 的 `deserialize_all()`/`reset_all()` 仍维护同一长列表。
- 同文件 `:28-33`、`:43-57`、`:281-287` 已引入 `SaveSection` 注册表，但当前只注册 ZoneManager，并且以兼容追加方式与旧路径并存。
- `docs/adr/ADR-005-service-locator-and-save-manager.md:16-22` 明确 SaveManager 聚合器迁移尚未完成。

影响：新增持久化领域仍需修改中央文件；双轨格式容易产生“旧字段与 section 字段同时写入、恢复顺序覆盖”的隐性问题。

建议：为每个 section 定义 schema/version、唯一 ownership 和迁移顺序；完成一个领域迁移后删除旧路径，不要长期双写。先补 save round-trip、旧版本迁移和损坏恢复测试。

### P1-3：多人撤离链已有装配代码和局部测试，但仍存在双入口风险

证据：
- 联机装配：`scenes/multiplayer/dungeon_session_controller.gd:41-85` 扫描真实 portal 并接入 `extraction_requested → request_extraction → CMD_EXTRACT`；`scenes/multiplayer/dungeon_session_controller.gd:239-261` 接收一次性结算完成。
- 桥接应用结算并落盘：`globals/multiplayer/multiplayer_scene_bridge.gd:346-389`。
- 单机路径仍在 `scenes/expedition/dungeon_runtime.gd:481-515` 直接调用 `finish_expedition()`、`TavernManager.extract_to_tavern()`。
- `tests/gdunit/expedition_exit_test.gd` 的 5 个局部契约本轮通过。

判断：联机垂直接线已不再是“完全无代码证据”的 P0，但单机与联机仍是两套结算策略；生产路径的跨进程行为必须以真实 ENet 验收确认，尤其是结算应用、离场、重连重放和活动存档槽。

建议：抽象统一 `ExtractionSettlementPort`/结果协议，由单机和联机分别实现 adapter；portal 只发布领域事件，不直接承担结算策略。补真实场景中 portal 进入→倒计时→CMD_EXTRACT→EVT_RESULT→回城的端到端测试。

### P1-4：技能与法术权威实现已明显补齐，但仍有双数据源和执行协议脆弱性

证据：
- `globals/multiplayer/skill_authority.gd:15-35` 同时从 `action_skills.gd` 和 `skill_data.gd` 查找定义；这是主动/被动模型在运行时的双数据源入口。
- `globals/multiplayer/skill_authority.gd:69-123` 统一做技能效果执行、位移、自 buff 和冷却提交约束。
- `globals/multiplayer/session_combat_service.gd:418-538` 已实现 AoE、击退、眩晕、破盾、穿透、吸血、抓取等字段结算；本轮 `skill_effects_test` 10/10 通过。
- `globals/combat/action_skills.gd:24-87` 的字段密集字典仍缺少强类型 schema；任何新增字段都可能只被数据声明但未进入端口协议。
- `globals/multiplayer/skill_authority.gd:110-121` 已正确通过 `ctx.apply_timed_buff()` 生成绝对毫秒 expiry，局部测试覆盖了关键效果；但仍应把时间单位封装成明确类型/命名，避免秒/毫秒回归。

建议：将技能定义收敛到一个不可变 `SkillDefinition`/Resource schema，主动与被动用 kind 区分，不再靠“先查 A 再查 B”兼容。执行结果统一为结构化 effect list，由权威端口消费；新增字段必须通过 schema 校验和行为测试。

## P2 / 维护债

### P2-1：God Object 仍然存在，拆分成果尚未完全反映在代码规模上

证据（当前行数）：
- `scenes/expedition/dungeon_scene_builder.gd`：2466 行。
- `scenes/ui/tavern_equipment_panel.gd`：1936 行。
- `scenes/characters/player/player.gd`：1430 行。
- `globals/core/network_manager.gd`：756 行。
- `globals/multiplayer/session_root.gd`：786 行。
- `globals/core/save_manager.gd`：413 行。
- `docs/adr/ADR-003-god-object-splitting-strategy.md:29-38` 已决定按变更频率拆分，DungeonSceneBuilder 的 assembler 拆分仍是后续高优先级。

建议：不要机械按行数重构；下一次改动触及地牢构建时优先拆 terrain/traversal/encounter/decoration 四个 assembler，并保持每刀可回滚、每刀配套测试。

### P2-2：测试门禁本身存在“测试测试规则”而非验证运行时行为的倾向

证据：
- `tests/gdunit/architecture_dependency_rule_test.gd` 主要通过源码扫描与字符串计数约束依赖；这适合防回退，但不能证明动态装配和运行时生命周期。
- `tests/gdunit` 中大量套件包含 `source_code`/字符串扫描痕迹；`docs/adr/ADR-008-ci-gate-policy.md:19` 也承认存量源码字符串断言债。
- 本轮聚焦测试 27/27 通过，只能证明聚焦契约，不能替代全量运行时验证。

建议：保留少量静态门禁用于禁止模式；新功能强制行为测试，尤其是多进程、场景树、物理碰撞、存档恢复和事件去重。

### P2-3：当前工作树变化面过大，架构审查结果与提交边界不清

证据：本轮 `git status --short` 显示大量已修改、删除和未跟踪文件，涉及源码、资源、测试、文档、GLB、导出配置和 CI；同时存在 `data/brewing_materials.json` 删除、多个历史 outputs 删除及新测试/工具未跟踪。

影响：即使局部测试绿，也很难判断哪一变更导致全量 CI 超时或场景差异；审查报告不能替代提交前的差异分组审查。

建议：按领域拆成小提交或至少建立 change manifest；先把架构/功能/资产/报告清晰分组，再做全量回归。

### P2-4：项目声明为 GDScript，但配置启用 C#/.NET 特征

证据：`project.godot:13-15` 的 `config/features=PackedStringArray("4.7", "C#")`，根目录存在 `LanternTavern.csproj`；AGENTS.md:20 将项目定义为 GDScript。

判断：这不是立即运行阻断，但会增加导出、CI、开发环境和维护者认知负担。若 C# 仅为 Godot Mono 运行时依赖，应在 README/架构文档明确；若无 C# 生产代码，应评估切回标准发行版/去除误导性特征。

## 做得好的部分

- 数据和权威边界已经有明显收敛：多人命令进入 `SessionRoot.on_command()`，并按 authority/service 分发（`globals/multiplayer/session_root.gd:272-301,385-406`）。
- 服务化拆分已有实质成果：ADR-003 列出的出征、战斗、库存、成长、生命周期服务已在 `SessionRoot` 中构造注入（`globals/multiplayer/session_root.gd:199-208`）。
- `SpellAuthority`/`SkillAuthority` 采用端口注入，效果失败不提交冷却的事务语义清晰（`globals/multiplayer/skill_authority.gd:51-68`）。
- 依赖方向、UI 不直接改权威实体仓、状态层不依赖 Node/SceneTree 等门禁本轮 8/8 通过。
- `run_ci.ps1` 已确保 gdUnit 成功后继续进入可选集成分支（`run_ci.ps1:83-85`），没有发现旧式提前成功退出问题。
- 导出预设 Web/Windows Desktop/Android 本轮识别通过（`run_ci.ps1:54-77`）。

## 建议整改顺序

1. **先恢复可判定的 CI**：拆分/限时全量套件，锁定 discovery、crash、timeout、orphan 的 exit code；确保本轮 RED 的根因可定位。
2. **再跑真实 ENet**：Listen + Dedicated 必须形成带日志和 verdict 的独立证据。
3. **统一撤离协议**：保留 portal 事件与权威结算分层，消除单机/联机业务策略分叉。
4. **收敛技能 schema**：单一权威定义、强类型执行计划、秒/毫秒单位封装。
5. **推进 SaveSection**：每迁移一个领域删除旧聚合路径，并补版本迁移与恢复测试。
6. **最后拆 God Object**：以功能变更为触发点拆 DungeonSceneBuilder assembler，不做无收益的大规模重写。
7. **整理提交边界**：审查完成后不要直接提交当前全部工作树；先按功能/架构/资产/报告分组。

## 本轮验证记录

| 验证项 | 结果 |
|---|---|
| Godot editor headless scan | 通过（标准 CI 日志） |
| Web/Windows/Android preset recognition | 通过（标准 CI 日志） |
| 架构依赖门禁 | 8/8 通过 |
| 多人撤离局部契约 | 5/5 通过 |
| 技能权威效果 | 10/10 通过 |
| 法术端到端局部契约 | 4/4 通过 |
| 聚焦套件合计 | 27/27 通过，0 error/failure/orphan |
| 标准 CI 全量 gdUnit | 本轮未完成，宿主 120 秒超时失败 |
| 真实 ENet Listen/Dedicated | 本轮未运行（需要显式 `-RunIntegration` / 独立 workflow job） |

## 审查边界声明

本报告是当前工作树的架构审查，不是代码修复提交。没有修改源码、配置或资产；报告文件本身为新增交付物。工作树中已有的改动、删除和未跟踪文件均保留原状。
