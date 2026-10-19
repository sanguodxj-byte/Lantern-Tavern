# Lantern Tavern 项目架构审查（从头审查）

- 审查时间：2026-08-07 06:43（GMT+8）
- 审查对象：当前未提交工作树
- 方法：仅依据当前源码、`project.godot`、当前 ADR/术语表及本轮实际命令结果形成判断；未读取项目记忆、旧审查报告或历史 overview 作为证据来源。
- 限制：自动化调度器强制读取了其执行摘要；该摘要未用于本报告的问题判定。四个并行工作器均在启动阶段返回 403，未产生任何源码分析或验证结论，本报告由主审直接完成。

## 一、结论

当前架构处于“拆分方向正确，但主分支门禁不可用、两个联机闭环仍不完整”的状态。

**发布/合并判断：不建议合并。**

阻断原因不是聚焦架构测试——它们本轮是全绿的；阻断原因是标准 CI 在测试发现阶段即失败，无法证明全量回归。同时，联机撤离的生产入口仍未装配到权威命令链，主动技能短时无敌/闪避 buff 的时间表示与统一过期容器冲突。

## 二、验证结果

### 2.1 标准 CI：失败

执行：

```powershell
D:\123\Lantern Tavern\run_ci.ps1 -GodotPath D:\123\Godot_v4.7-stable_mono_win64_console.exe
```

结果：

- editor headless scan：通过；stderr 仅命中当前白名单。
- export preset 解析：通过；Web / Windows Desktop / Android 均被识别。
- gdUnit4 全量发现：失败。
- 根因：`tests/gdunit/service_test.gd:58-59,74-75` 仍调用已经从 `Service` 移除的 `skill_data()` 与 `action_skills()`；当前 `globals/core/service.gd` 不再定义这两个访问器。
- gdUnit4 首先报告发现阶段异常退出 105，随后 Godot 出现 signal 11；CI 最终失败。
- 因单元测试门禁先失败，真实 ENet 集成分支没有执行。

这是 **P0 合并阻断项**：标准入口无法给出全量回归结论。

### 2.2 聚焦架构测试：通过但有 stderr ERROR

执行 14 套与架构、联机、法术、撤离和事务相关的测试：

- 14/14 suites
- 191/191 test cases
- 0 errors / 0 failures / 0 skipped / 0 orphans
- 退出码 0

但 stderr 出现：

- `tests/gdunit/spell_network_behavior_test.gd:40` 重复连接 `session_event` 信号，Godot 报 ERROR。
- `spell_session_atomicity_test` 的未注册投射物 warning 属错误路径用例的预期噪声。

因此“断言全绿”不等于“执行干净”；重复信号 ERROR 应作为 P2 测试卫生问题处理。

## 三、关键问题

## P0-1：标准 CI 与当前 Service 契约失配

**证据**

- `tests/gdunit/service_test.gd:55-67` 将 `Service.skill_data`、`Service.action_skills` 放入访问器清单。
- `tests/gdunit/service_test.gd:70-79` 又断言两者应解析为 Autoload。
- `project.godot:17-49` 当前共有 31 个 Autoload，其中没有 `SkillData`、`ActionSkills`。
- `globals/core/service.gd:13-148` 当前也没有这两个访问器。
- 同一工作树中的 `tests/gdunit/service_access_contract_test.gd` 已按当前 31 Autoload 契约通过，说明失败来自旧测试契约残留，不是当前 Service 实现缺项。

**影响**

- 全量测试无法发现，标准 CI 恒红。
- 后续真实 ENet 门禁被前置失败截断。
- signal 11 会掩盖首个可操作错误，增加排查成本。

**建议**

删除或迁移 `service_test.gd` 中关于已移出 Autoload 的四处旧断言；让 `service_access_contract_test.gd` 成为单一 Service/Autoload 契约来源。修复后必须重新运行标准 CI，而不是只跑聚焦套件。

## P0-2：联机撤离权威能力已存在，但生产 portal 没有接入

**已经闭环的部分**

- `globals/multiplayer/session_root.gd:397` 注册 `CMD_EXTRACT`。
- `scenes/multiplayer/client_command_driver.gd:187-195` 能发送 `CMD_EXTRACT`。
- `scenes/multiplayer/dungeon_session_controller.gd:196-218` 提供 `request_extraction()`，并能在结算应用后发出 `extraction_completed`。
- `globals/multiplayer/multiplayer_scene_bridge.gd:383-389` 能在结算写回后通知 controller。
- 聚焦 `expedition_exit_test.gd` 4/4 通过，证明这些孤立部件可工作。

**未闭环的生产链**

- `scenes/expedition/dungeon_runtime.gd:402-413` 将生产撤离 portal 的 `extraction_requested` 固定连接到本地 `on_extraction_requested`。
- `scenes/expedition/dungeon_runtime.gd:472-499` 收到事件后直接执行本地战利品记录与 `TavernManager.extract_to_tavern()`。
- 当前生产源码搜索中，`DungeonSessionController.request_extraction()` 没有调用方；`extraction_completed` 也没有生产连接方。
- `globals/multiplayer/multiplayer_session.gd:118-126` 创建 controller 后只调用 `build_and_enter()`，没有注入/切换撤离处理策略。

**影响**

真实联机地牢若复用该 runtime，会绕过服务器权威 `CMD_EXTRACT`，形成“部件测试通过、生产垂直接线缺失”的假闭环。结算幂等、服务器存档写回和联机离场无法由当前生产装配证明。

**建议**

让 `DungeonRuntime` 的撤离完成回调依赖显式 `ExtractionPort`：单机实现执行本地结算；联机实现只调用 controller 的 `request_extraction()`，待 `extraction_completed` 后再离场。新增生产装配测试，必须从真实 portal 信号一路断言到 `CMD_EXTRACT`，禁止只测 controller stub。

## P1-1：主动技能短时 buff 使用秒数写入绝对毫秒过期容器

**证据**

- `globals/multiplayer/skill_authority.gd:101-108` 将 `buff_value`（0.5、0.3 秒）原样写入 `ctx.buffs[buff_type]`。
- `globals/core/player_context.gd:88-95` 将 `buffs` 的所有值解释为绝对 `ticks_msec` 过期时间。
- `globals/core/player_context.gd:63-67` 的法术 buff 正确写入 `Time.get_ticks_msec() + duration * 1000`，证明该容器的既定单位确为绝对毫秒。
- `tests/gdunit/session_root_test.gd:785-786` 反而把 `iframes == 0.5` 当作正确结果，固化了错误表示。

**影响**

在正常运行时 `now_ms` 远大于 0.5，buff 会在下一个过期 tick 立刻被删除；滑铲无敌帧和战术步闪避帧基本不生效。更严重的是，同一容器混入两种时间单位，任何消费方都无法安全解释。

**建议**

统一 `PlayerContext.buffs` 为绝对 `expire_ticks_ms`；SkillAuthority 写入 `now + round(buff_sec * 1000)`。测试应验证“施放后仍有效、到期前不删、到期后删除”，不要断言内部值等于秒数。

## P1-2：技能权威层采取硬拒绝，安全但功能语义仍未完成

`globals/multiplayer/skill_authority.gd:59-72,111-130` 对 grapple、stun、breaks_shield、ignore_def、ignore_block、lifesteal、AoE 做前置硬拒绝。这已经避免“核心效果没发生却提交冷却”的数据错误，是正确的安全降级。

但结果是：这些已登记主动技能在联机中不可用，而不是已支持。应把这视为功能缺口，而不是架构闭环。完成标准应是每种声明字段都有权威执行器、原子提交、事件广播与真实双进程验证。

## P1-3：真实 ENet 仍是可选门禁

- `run_ci.ps1:29` 通过 `-RunIntegration` 开关控制集成测试。
- `run_ci.ps1:108-125` 只有显式传参才执行 Listen 与 Dedicated；默认仅警告跳过。
- `tools/run_integration_dungeon_test.ps1:85-110` 已正确将 verdict 映射为 PASS→0 / FAIL→1，runner 假绿问题已修复。
- 标准 CI 本轮因全量测试失败，未能进入集成阶段。

建议将网络启用的合并流水线固定传 `-RunIntegration`，本地快速门禁可继续默认跳过，但二者必须是不同、明确命名的 job。

## 四、结构健康度

### 正向进展

1. `SessionRoot` 已从历史上的超大单体拆到 786 行，并引入 `session_expedition_service.gd`、`session_inventory_service.gd`、`session_progression_service.gd`、`session_lifecycle_service.gd`、`session_combat_service.gd`。
2. `tests/gdunit/architecture_dependency_rule_test.gd:166-214` 已建立 session 服务依赖方向、UI 不得写权威实体仓、state 层不得依赖 Node、服务不得摸 root 私有字段等门禁；本轮全部通过。
3. Autoload 已受上限 31 管控，`SkillData/ActionSkills` 已退出 Autoload 面。
4. 技能位移走注入的碰撞安全 movement port，未再直接写坐标。
5. Listen runner 的失败退出码传播已经修复。

### 持续债务

- 关键文件仍大：`dungeon_scene_builder.gd` 2466 行、`session_root.gd` 786 行、`network_manager.gd` 756 行、`save_manager.gd` 413 行。
- `Service` 本质仍是 root service locator，不是依赖注入；它降低字符串散落，但不会自动降低全局耦合。
- 当前 root 趋势门禁只统计字面量 `"/root/`（`architecture_dependency_rule_test.gd:82-109`），不能发现 `Engine.get_main_loop().root`、`.root.get_node*` 等等价形式；本轮搜索在 globals 中仍覆盖约 20 个文件。
- 工作树变更量很大且混有资产、架构、联机、UI、测试及大量删除/新增文件；审查结论只适用于当前瞬时工作树，后续继续修改必须重跑。

## 五、建议修复顺序

1. **恢复标准 CI**：清理 `service_test.gd` 旧契约；跑全量直到发现、断言、orphan 均干净。
2. **补生产撤离垂直链**：portal → 联机 controller → `CMD_EXTRACT` → 服务器结算/落盘 → `extraction_completed` → 离场；加真实生产装配测试。
3. **统一 buff 时间表示**：全部使用绝对毫秒；补边界测试。
4. **把真实 ENet 设为合并必跑 job**：Listen + Dedicated 都必须执行且传播失败退出码。
5. **逐项实现联机主动技能语义**：保持当前硬拒绝，完成一个字段再移出拒绝表。
6. **收紧架构扫描器**：覆盖全部 root 获取形式，并继续拆分 `DungeonSceneBuilder` / `NetworkManager` 的职责。

## 六、验收清单

- [ ] 标准 `run_ci.ps1` 退出 0，且不含发现阶段脚本错误、signal 11、orphan。
- [ ] 聚焦架构套件继续 0 failure，并清除重复 `session_event` ERROR。
- [ ] 生产撤离装配测试从真实 portal 信号覆盖到 `CMD_EXTRACT` 与最终离场。
- [ ] `iframes` / `dodge_frames` 以绝对毫秒存储，并通过到期前后测试。
- [ ] 合并流水线显式执行 `-RunIntegration`，Listen 与 Dedicated 都通过。
- [ ] 未实现技能效果继续硬拒绝；已实现效果具备权威结算与原子性测试。

---

**最终评级：C（结构治理在进步，但当前工作树不可合并）。**
