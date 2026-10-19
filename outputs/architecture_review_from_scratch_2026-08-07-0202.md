# Lantern Tavern 项目架构审查（从头审查）

- 审查时间：2026-08-07 02:02–02:13（GMT+8）
- 审查对象：当前未提交工作树
- 技术栈：Godot 4.7 / GDScript
- 方法约束：除自动化调度强制读取其执行摘要外，未读取项目记忆、旧架构审查报告或旧概览形成判断；结论来自当前源码、`project.godot`、`docs/adr/`、`docs/术语表.md` 与本轮实测。
- 本轮只读审查，未修改生产源码或测试。

## 1. 结论摘要

当前架构已建立较清晰的多人会话权威骨架：`SessionRoot` 是组合根，命令经 `CommandRouter` 进入出征、战斗、库存、成长和生命周期服务；移动、法术和技能均有服务器侧权威端口；Dedicated 出征返回值解包、真实 ENet runner 的失败退出码、CI 集成分支可达性在当前源码中均已修正。

但当前工作树**不可合入**。原因不是抽象层次不够漂亮，而是标准 CI 在测试发现阶段直接失败。另有两个生产风险：技能短时 buff 采用错误的时间表示，可能永久不失效；真实联机地牢的撤离传送门没有看到从生产 portal 信号接到 `CMD_EXTRACT` 的装配证据。

严重度汇总：

- P0（阻断）：1 项
- P1（高风险）：3 项
- P2（维护债）：4 项

## 2. 实测结果

### 2.1 编辑器扫描

命令：

```text
D:/123/Godot_v4.7-stable_mono_win64_console.exe --headless --path D:/123/Lantern Tavern --editor --quit
```

结果：退出码 0。唯一 stderr 为项目 CI 已精确白名单的 Godot 编辑器初始化噪声：

```text
EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit"
```

### 2.2 聚焦架构测试

排除当前无法解析的 `service_test.gd` 后，运行 9 个关键套件：

- `architecture_dependency_rule_test.gd`
- `session_root_test.gd`
- `service_transaction_test.gd`
- `spell_session_atomicity_test.gd`
- `spell_network_behavior_test.gd`
- `spell_network_completion_test.gd`
- `extraction_portal_test.gd`
- `network_manager_integration_test.gd`
- `dungeon_session_collision_authority_test.gd`

结果：**163/163 通过，0 error，0 failure，0 orphan，退出码 0**。

stderr 仍出现一条测试装配错误：`spell_network_behavior_test.gd` 重复连接同一个 `session_event` callable。gdUnit 未把它计作失败，但日志并非干净。

单独复核 `extraction_portal_test.gd`：11/11 通过，0 error/failure/orphan。

### 2.3 标准 CI

运行：

```text
run_ci.ps1 -AllowOrphan
```

结果：

- 编辑器扫描：通过
- Web / Windows Desktop / Android export preset 识别：通过
- gdUnit 全量发现：失败
- 根因：`tests/gdunit/service_test.gd:58-59,74-75` 仍引用已移除的 `Service.skill_data()`、`Service.action_skills()`
- gdUnit 报测试发现异常 105，随后 Godot 发生 signal 11；PowerShell 最终非零退出
- 因单元门禁失败，真实 ENet 集成分支未执行

因此，当前工作树没有“全绿”证据。

## 3. 架构规模快照

基于当前文件系统统计：

- 生产 GDScript：296 个（`globals/`、`scenes/`、`data/`）
- gdUnit 测试套件：499 个
- Autoload：31 个
- 生产源码显式 `"/root/` 引用：11 处
- 使用 `source_code` / `get_file_as_string` 的测试文件：256 个
- 关键脚本行数：
  - `globals/multiplayer/session_root.gd`：约 671 行（物理行读取显示 787 行，统计口径受空行影响）
  - `globals/core/network_manager.gd`：679 行
  - `globals/core/save_manager.gd`：375 行
  - `globals/multiplayer/session_combat_service.gd`：495 行

## 4. 发现与证据

### P0-1：标准 CI 在测试发现阶段失败，当前工作树不可合入

**证据**

- `globals/core/service.gd:1-149` 已无 `skill_data()` 和 `action_skills()`。
- `project.godot:17-50` 也已把 SkillData / ActionSkills 移出 Autoload。
- `tests/gdunit/service_test.gd:55-67` 仍把两个访问器列为必须存在。
- `tests/gdunit/service_test.gd:70-78` 仍要求这两个 Autoload 可解析且非空。
- 标准 CI 在发现阶段报四个 Parse Error，无法进入测试执行。

**影响**

测试与 ADR-005 的“纯数据退出 Autoload”迁移没有原子同步。任何合入都会让 CI 红灯，且测试发现错误后 Godot 还会 signal 11，污染诊断。

**建议**

不要恢复已经删除的数据 Autoload。更新 `service_test.gd`：删除这两个 Service 访问器断言，改为验证 `action_skills.gd` / `skill_data.gd` 可通过 preload/load 直接访问，并补一个架构门禁，确保纯数据表不重新进入 `[autoload]`。

---

### P1-1：技能短时 buff 把“秒数”写入“绝对毫秒过期时间”容器

**证据**

- `globals/core/player_context.gd:43-48` 明确规定 `buffs` 的值为 `expiry_ms` 绝对时间。
- `globals/core/player_context.gd:63-68` 的法术 buff 正确写入 `Time.get_ticks_msec() + duration * 1000`。
- `globals/core/player_context.gd:87-95` 仅当 `now_ms >= expiry` 才清除。
- `globals/multiplayer/skill_authority.gd:101-108` 却直接把 `buff_value` 秒数（0.5 / 0.3）写入 `ctx.buffs`。
- `globals/combat/action_skills.gd:70-72,84-86` 明确 `iframes=0.5 秒`、`dodge_frames=0.3 秒`。

**影响**

在正常会话中 `Time.get_ticks_msec()` 通常远大于 0.5，但值经 `float -> int` 变成 0；`expire_buffs()` 对 `expiry == 0` 不清除。结果是无敌帧/闪避帧可能常驻，属于联机战斗权威错误。

**建议**

把技能 buff 统一交给 `PlayerContext` 的权威 API，例如新增/复用 `apply_timed_buff(buff_id, duration_sec)`；任何代码不得直接写 `ctx.buffs`。补行为测试：在确定性 now_ms 下验证施加前、持续期内和过期后三个阶段，而不是只断言技能表里的 `buff_value`。

---

### P1-2：真实联机撤离缺少 portal → `CMD_EXTRACT` 的生产装配证据

**证据**

- `scenes/expedition/extraction_portal.gd:237-244` 完成倒计时后只发 `extraction_requested(player)`。
- `scenes/expedition/dungeon_runtime.gd:402-414` 只在单机 `DungeonRuntime` 中连接该信号。
- `scenes/expedition/dungeon_runtime.gd:475-499` 连接后的处理是本地 `finish_expedition()`、`TavernManager.extract_to_tavern()`，不是网络命令。
- `scenes/multiplayer/dungeon_session_controller.gd:196-227` 虽提供 `request_extraction()` 并能调用 `ClientCommandDriver.send_extract()`，但全项目生产源码搜索未发现 `extraction_requested.connect(controller.request_extraction)` 或等价装配。
- `scenes/multiplayer/dungeon_session_controller.gd:37-43,81-103` 构建真实联机地牢时没有接 portal 信号。
- `globals/multiplayer/session_root.gd:397`、`session_expedition_service.gd:73-109` 已有完整的 `CMD_EXTRACT` 服务端事务；问题在入口装配，不在结算服务。

**影响**

联机地牢中玩家即便走完自动撤离倒计时，也可能只触发无人监听的 portal 信号，无法提交服务器结算。现有 `extraction_portal_test.gd` 证明 portal 自身行为，但没有证明真实联机场景垂直接线。

**建议**

在联机 Composition Root 中显式连接真实 portal 的 `extraction_requested` 到 `DungeonSessionController.request_extraction()`；监听 `extraction_completed` 后再执行离场。新增生产装配测试：实例化真实联机控制器和真实 portal，完成倒计时后断言只发送一次 `CMD_EXTRACT`，并在 `EVT_EXTRACTION_RESULT` 应用后只发一次离场事件。

---

### P1-3：技能权威覆盖仍是“硬拒绝未实现语义”，不是功能闭环

**证据**

- `globals/multiplayer/skill_authority.gd:59-66` 声明未实现字段整体拒绝。
- `globals/multiplayer/skill_authority.gd:115-130` 对 grapple、stun、breaks_shield、ignore_def、ignore_block、lifesteal、AoE 全部返回 unsupported。
- `globals/combat/action_skills.gd:40-60` 的冲锋斩、抓取/投掷等当前定义真实使用这些字段。
- `globals/multiplayer/session_combat_service.gd:291-348` 会将上述拒绝统一映射为 `ERR_INVALID_TARGET`。

**影响**

当前做法比“静默成功并提交冷却”安全，但部分已登记主动技能在联机中必然不可用，而且客户端拿到的错误码不区分“目标无效”和“服务端尚不支持该技能语义”，可观测性差。

**建议**

按技能族逐个闭环，不要回退为部分成功。优先实现 stun / shield break（单目标状态端口），再实现 grapple / AoE。协议增加明确的 unsupported effect 错误码或结构化 reason，便于客户端提示与测试定位。

---

### P2-1：场景级 ProjectileService 仍被法术执行器通过 `/root` 反向定位

**证据**

- `globals/combat/spell_authority.gd:120-136` 直接 `caster.get_node_or_null("/root/ProjectileService")`。
- `project.godot:46` 将 `ProjectileService` 注册为进程级 Autoload。
- ADR-005 已把它列为应在需要独立生命周期时迁移的场景级服务。

**影响**

虽然投射物节点被 SessionRoot 跟踪释放，但“生成器服务”仍是全局定位，测试需要依赖完整树，且多会话隔离边界不彻底。

**建议**

给 `SpellAuthority` 注入 `projectile_spawn_port` 或会话级服务实例；去除 `/root/ProjectileService`。这也能把 11 处 root 引用继续压低。

---

### P2-2：SaveManager 正处于双协议迁移期，中央聚合与 sections 并存

**证据**

- `globals/core/save_manager.gd:43-57` 已引入 `SaveSection` 注册表。
- `globals/core/save_manager.gd:234-287` 仍集中拉取 TavernManager、GameState、AttrPanel、SkillRuntime、Fermentation 等领域。
- `globals/core/save_manager.gd:281-286` 又附加 `sections`；当前仅 ZoneManager 迁移。
- `globals/core/save_manager.gd:289-327` 恢复时先跑旧路径，再让 section 覆盖。

**影响**

同一领域在迁移窗口内有两条序列化/恢复路径，顺序本身成为隐藏契约；新增领域仍容易继续堆进中央文件。

**建议**

先用测试锁定“双写兼容期”的优先顺序和版本迁移，再按领域逐个迁出。迁移完成的领域必须从旧路径删除，避免永久双轨。

---

### P2-3：Autoload 面和 Service Locator 仍偏宽

**证据**

- `project.godot:17-50` 当前 31 个 Autoload。
- `globals/core/service.gd:7-148` 通过根节点字符串返回宽泛 `Node`，编译期不能证明具体契约。
- 架构测试 `AUTOLOAD_LIMIT=31`、`ROOT_REF_LIMIT=11` 只防增长，不保证下降。

**影响**

依赖获取仍有“直接全局名 / Service / `/root` / 构造注入”多套方式，装配边界和测试替身策略不统一。

**建议**

保持禁止新增 Autoload。功能触及场景级服务时顺手迁移为显式注入，并把趋势门禁从固定上限改为白名单或逐项理由清单。

---

### P2-4：测试治理存在两类脆弱性

**证据**

1. 本轮聚焦测试 163/163 通过，但 stderr 有重复信号连接 ERROR：`spell_network_behavior_test.gd:40` 在同一对象重复连接 `_on_session_event`。
2. 499 个测试文件中，256 个包含 `source_code` 或 `get_file_as_string`。ADR-008 已规定新测试禁止用源码字符串断言证明行为。

**影响**

“断言全绿”不等于运行日志干净；源码字符串测试会在 ADR-003 拆分、重命名或依赖迁移时产生大量假失败，掩盖真实行为回归。

**建议**

CI 增加测试 stderr 白名单外 ERROR 门禁。修复重复 connect；新增规则只扫描新/改测试，禁止继续增加行为型源码字符串断言，存量随触及迁移。

## 5. 已确认做对的部分

以下结论来自当前代码，不依赖旧报告：

1. Dedicated 出征解包正确：`dedicated_server.gd:89-100` 先检查 `success`，再读取 `event.seed`；`network_manager.gd:598-602` 返回结构一致。
2. ENet runner 失败退出码正确：`run_integration_dungeon_test.ps1:85-110`、`run_dedicated_server_test.ps1:64-84` 均 PASS→0 / FAIL→1。
3. CI 的 `-RunIntegration` 分支在单元测试成功后可达：`run_ci.ps1:83-128` 已无成功后提前退出。
4. SessionRoot 已按 ADR-003 拆出五个编排服务，并由窄端口访问共享容器；对应架构规则 8/8 通过。
5. 法术世界执行采用 execute→验证→commit，聚焦事务测试通过，投射物失败、预算满等不会先扣资源。
6. Dedicated 碰撞权威测试 4/4 通过；权威移动不是纯信任客户端坐标。

## 6. 修复优先顺序

### 第一批：恢复可合入性

1. 修复 `service_test.gd` 与纯数据移出 Autoload 后的契约不一致。
2. 重新跑完整 `run_ci.ps1 -AllowOrphan`，要求正常完成且非零 stderr ERROR 清单可解释。

### 第二批：修正生产权威错误

3. 统一技能 buff 的绝对毫秒过期表示，补过期行为测试。
4. 接通真实联机 portal → `CMD_EXTRACT` → `EVT_EXTRACTION_RESULT` → 离场垂直链，并用生产装配测试证明。

### 第三批：补齐联机技能语义

5. 逐项实现或明确下线当前联机不支持的技能；不要让技能表宣称支持而服务器永久拒绝。
6. 增加可区分的协议错误码与客户端提示。

### 第四批：持续收敛维护债

7. 注入 ProjectileService；减少 `/root` 与场景级 Autoload。
8. 完成 SaveSection 渐进迁移，避免长期双轨。
9. 清理重复信号连接 ERROR，并控制源码字符串测试继续增长。

## 7. 验收门槛

修复后至少满足：

- 编辑器无头扫描退出 0，白名单外无 ERROR / SCRIPT ERROR / Parse Error。
- `run_ci.ps1 -AllowOrphan` 正常完成；不允许测试发现 105、signal 11 或 PowerShell 非零退出。
- 架构聚焦测试继续 0 failure / 0 orphan。
- 技能 buff 测试覆盖实际过期，而非仅数据字段。
- 联机撤离生产装配测试覆盖真实 portal 和真实命令驱动。
- 网络可用隔离环境再运行 `run_ci.ps1 -RunIntegration`，Listen + Dedicated 都必须真实通过；本轮因单元门禁失败未执行，不得用静态脚本检查冒充网络验收。

## 8. 审查边界

- 当前工作树已有大量未提交修改和未跟踪文件；本报告评价的是这个即时状态，不等同于某个已提交基线。
- 未执行视觉验收，也未改动手工酒馆场景。
- 并行审查工作器均在启动阶段因客户端鉴权 403 失败，未产生源码分析；本报告由主审直接读源码、运行测试并交叉核验。
