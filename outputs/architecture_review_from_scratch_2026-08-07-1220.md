# Lantern Tavern 项目架构审查（从头开始）

- 审查时间：2026-08-07 12:20（GMT+8）
- 审查口径：只基于本次读取的当前工作树源码、`project.godot`、`docs/术语表.md`、ADR 与本次实测；不使用项目记忆、自动化记忆正文、`outputs/` 历史报告或 overview 作为结论依据。
- 工作树：审查开始时存在大量用户未提交改动；本轮未修改生产源码。

## 结论

当前架构已经形成“单机领域状态 + 多人 SessionRoot 权威编排 + 服务拆分 + 客户端表现桥接”的主干，联机安全边界和法术/技能事务原子性已有明确设计，聚焦测试覆盖较强；但项目尚未达到“标准 CI 全绿、无崩溃、跨场景生命周期稳定”的交付门槛。

**当前判定：RED（不能把本轮项目称为架构稳定）。**

## 实测结果

| 门禁 | 结果 | 证据 |
|---|---|---|
| Godot headless editor scan | 退出码 0 | 有 2 条 `EditorSettings` 初始化 ERROR，被 `run_ci.ps1` 精确白名单允许；未见其他错误 |
| 聚焦架构/联机/法术/撤离/服务测试 | **180/180 通过，0 error/failure/orphan** | 12 个套件，退出码 0 |
| gdUnit4 全量 | **失败** | 执行过程中 Godot `CrashHandlerException: signal 11`；未得到可靠全量汇总，不能判绿 |
| 真实 Listen ENet 双进程 | **PASS** | `seed_match=true`、`fp_match=true`、实体/移动/战斗/掉落/撤离/late-join recovery 均通过 |
| 真实 Dedicated ENet | **PASS** | seed/fingerprint、实体复制、移动通过；退出码 0 |

## 问题清单（按优先级）

### P0-1：全量 CI 在测试阶段发生 Godot 原生崩溃

- 证据：全量命令 `GdUnitCmdTool.gd -a res://tests/gdunit --ignoreHeadlessMode -c` 最终出现 `CrashHandlerException: Program crashed with signal 11`，未输出可靠 Overall Summary/Exit code。
- 崩溃前最后可见路径为 `tests/gdunit/terrain_texture_test.gd` 的地牢场景/纹理测试，日志出现 `DungeonSceneBuilder` 和 `ItemSpawner` 输出；但当前证据不足以把责任唯一归因到某个测试或引擎组件。
- 影响：`run_ci.ps1` 将该阶段视为非 0 失败；提交门禁无法证明全量通过，且原生崩溃会污染后续诊断。
- 建议：将全量测试按套件分批隔离运行；对最后一套件做最小复现；把崩溃信息、套件名、Godot 版本和 dump 作为 CI artifact；先修复或隔离触发 native crash 的场景/纹理测试，再恢复全量门禁。

### P0-2：默认 CI 不执行真实 ENet，交付状态与“网络验收”分离

- 证据：`run_ci.ps1:105-126` 只有显式传 `-RunIntegration` 才运行 Listen + Dedicated；默认路径只输出 `INTEGRATION GATE: NOT RUN` 并继续。
- 这不是代码错误，而是门禁策略风险：网络关键路径（移动、战斗、掉落、撤离、late join/recovery）不在默认 CI 的 RED 条件内。
- 实测补充：本轮手动传入集成入口时，Listen 与 Dedicated 均 PASS；因此当前问题是默认交付治理，而非本次双进程功能失败。
- 建议：拆成 `unit` 与 `network-integration` 两个明确 job；发布/合并主分支必须要求 network job；若开发分支允许跳过，必须把 skip 状态写入机器可读 verdict，而不是只在日志中 warning。

### P1-1：SaveManager 仍是迁移中的中央聚合器，旧路径与 SaveSection 并存且存在“双写/双读”风险

- 证据：`globals/core/save_manager.gd:235-287` 继续显式序列化 TavernManager、GameState、AttrPanel、SkillRuntime、FermentationSystem、BrewFlowSystem、TavernSettlement、ArmorProficiency、selected_zone；同时 `:281-286` 再追加 `_sections`。
- `:290-327` 先走旧字段恢复，再走 sections；`reset_all():334-364` 也维护两套清单。
- ADR-005 声明目标是让 SaveManager 只编排 section，但当前只是兼容过渡；新增领域仍需判断该进旧字段还是 section，且迁移领域必须维护旧字段兼容语义。
- 风险：字段优先级、迁移顺序和版本兼容不清晰时，旧字段可覆盖 section 或 section 再覆盖旧字段；遗漏 reset/deserialize 的可能性持续存在。
- 建议：为每个迁移领域建立唯一权威字段；旧字段只在读取旧版本时适配一次，不再作为当前版本写入；为 schema/version 写迁移测试与重复键检测。

### P1-2：SpellAuthority 的 headless fallback 仍允许直接改节点位置，安全性依赖调用方是否注入端口

- 证据：`globals/combat/spell_authority.gd:104-115`：`movement_port` 有效时走 `ServerCharacterMotor`，否则执行 `caster.global_position += ...`。
- 测试覆盖了有端口的会话权威路径，但 fallback 本身仍是穿墙/越界风险；如果生产装配漏注入或未来新增调用点直接使用 SpellAuthority，行为会静默退化为无碰撞位移。
- 建议：生产模式缺失 `movement_port` 时硬失败；只允许显式 `allow_headless_fallback` 的测试/纯逻辑路径使用直接位移，并让 fallback 不能被导出构建启用。

### P1-3：ActionSkills 与 SkillData 的双数据源仍需要严格契约

- 证据：`globals/multiplayer/skill_authority.gd:30-35` 按 ID 先查 `ActionSkills`，再查 `SkillData`；`globals/combat/action_skills.gd:1-5` 明确是独立技能表。
- 这条设计当前可工作，但同一 `skill_id` 在两个表重名时，主动技能优先级会覆盖武器技能，且两类字段不是完全同构（例如媒介/技能族/效果字段）。
- 聚焦测试 `skill_effects_test.gd` 10/10 通过，证明已登记效果当前兑现；没有证明跨表 ID 全局唯一或冲突时构建失败。
- 建议：启动时校验两个数据源 ID 全局唯一；使用显式 `skill_kind`/registry，不要用“先查 A 再查 B”的隐式优先级。

### P1-4：`/root` 绝对路径与 31 个 Autoload 仍是运行时组合根的结构性债务

- 证据：`project.godot:[autoload]` 当前 31 个；`tests/gdunit/architecture_dependency_rule_test.gd:24-32` 将 31 与 11 处生产 `/root` 引用硬编码为趋势上限。
- 聚焦测试通过只能说明未越过当前基线，并不说明依赖已经收敛。`SpellAuthority` 本身已改为端口注入，但 `dungeon_session_controller.gd:157-183` 仍直接访问 `NetworkManager`/`/root/NetworkManager`。
- 建议：把阈值门禁从“不得增长”升级为“必须下降/允许白名单”；场景控制器改为显式注入 NetworkSession；逐步把进程级服务迁入 Composition Root。

### P2-1：SessionRoot 虽已拆服务，但仍持有大量状态、权威实例与编排端口

- 证据：`globals/multiplayer/session_root.gd` 当前约 786 行、字段含 registry/world/router/validator、8+ authority、5 个 session service、多个状态字典、投射物与广播端口，并在 `_init()` 完成全部装配。
- ADR-003 的拆分方向正确，聚焦 86 个 SessionRoot 测试通过；但 SessionRoot 仍是所有依赖的组合与生命周期中心，新增系统继续堆到它会重新形成 God Object。
- 建议：明确 Composition Root 与 Domain Session 的边界；将服务装配移到独立 `SessionComposition`，SessionRoot 只保留生命周期和命令路由；为每个 authority 定义输入/输出协议。

### P2-2：架构测试存在大量源码字符串断言，行为门禁的信号质量偏低

- 证据：当前 `tests/gdunit` 有 500 个测试文件，其中 256 个使用 `source_code` 或 `get_file_as_string`；ADR-008:19 也承认存量字符串断言债务。
- 这类测试能阻止简单回归，但不能证明运行时行为，重构时容易出现“源码满足、装配失败”。本轮聚焦测试全绿与全量 native crash 并存，正说明静态与运行时信号不等价。
- 建议：按功能修改逐步改为实例化/调用/端到端断言；源码扫描只保留禁止模式、目录边界和资源存在性检查。

### P2-3：资源/测试生命周期噪声仍可能放大 native crash 诊断难度

- 证据：全量日志出现 `intro_scene_screenshot_test` 中 dummy renderer `texture_2d_get` 的 null 图像 ERROR，虽测试最终 PASSED；多个地形纹理测试通过直接加载 PNG 触发“Loaded resource as image file”警告；全量最终 signal 11。
- 聚焦测试 0 orphan，但全量场景/截图/地形套件的资源生命周期更重。
- 建议：截图测试在 dummy renderer 下显式跳过图像读取分支或改用兼容渲染器；纹理测试用 Image.load_from_file 或导入资源路径；每套件独立 Godot 进程运行并报告 orphan/error/crash。

## 已确认的正向架构

- `SkillAuthority` 已实现效果失败不提交冷却的事务边界，聚焦技能效果 10/10 通过。
- `SpellAuthority` 已使用会话级世界执行器和端口注入，投射物失败/世界预算失败不会提交资源；法术原子性 29/29 通过。
- `dungeon_session_controller.gd:44-84` 真实 portal 已接到 `ClientCommandDriver.send_extract()`；撤离生产装配测试 5/5 通过。
- 本轮真实 Listen ENet：seed/fingerprint、移动、实体、战斗、掉落、撤离、恢复全部 PASS；Dedicated ENet：布局、实体、移动 PASS。
- 方向性架构规则、服务访问契约、存档回环测试均通过。

## 建议执行顺序

1. 先把全量 native crash 变成可定位的单套件失败：分批进程隔离、保留最后套件与崩溃 dump。
2. 将真实 ENet 接入合并/发布必需门禁，并输出机器可读 skip/pass/fail verdict。
3. 收紧 SpellAuthority：生产缺失碰撞位移端口必须拒绝，headless fallback 仅测试显式开启。
4. 收敛存档当前版本为 section 唯一写入路径，保留旧字段只做版本适配。
5. 消除 ActionSkills/SkillData 隐式优先级，增加全局 ID 冲突门禁。
6. 从 `/root` 和 Autoload 趋势门禁转向下降型治理，并把 SessionRoot 装配移出自身。
7. 按功能将源码字符串断言迁移为行为测试，优先覆盖网络集成和资源生命周期。

## 审查限制

- 并行审查工作器因客户端鉴权限制返回 403，未产出独立结论；本报告所有判断由主审基于当前工作树直接核验。
- 全量测试发生 Godot 原生 signal 11，故无法提供全量用例总数；不能用聚焦 180/180 替代全量门禁。
