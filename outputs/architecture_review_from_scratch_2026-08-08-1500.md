# Lantern Tavern 项目架构审查（2026-08-08 15:00）

## 审查范围与限制

- 结论只依据当前工作树中的源码、`project.godot`、`AGENTS.md`、ADR、CI 配置及本轮实际测试。
- 按用户要求，未读取项目长期记忆、旧 overview 或既有审查报告来形成判断。
- 自动化调度框架要求在执行末尾读取并更新其执行摘要；该摘要未作为本报告证据来源。
- 本轮不修改游戏源码，只做只读审查与测试。

## 总结判定

**架构状态：YELLOW（可继续开发，但应收紧数据源和全局依赖边界）。**

当前联机权威垂直链、撤离链和标准 CI 相比常见原型状态已经完整得多：本轮 32 个联机/权威聚焦用例与 56 个撤离/运行时用例均全绿，联机撤离生产接线可以从源码与测试得到证据。当前最高风险不再是“链路缺失”，而是：

1. **区域散落材料存在两个定义源，且内容语义明显不一致。**
2. **31 个 Autoload + Service/root 查找形成过宽的隐式全局依赖面。**
3. **联机会话虽然拆成服务，但 SessionRoot/NetworkManager 仍是共享可变状态中心。**
4. **测试体系有大量源码字符串断言，重构时容易出现“实现正确、测试契约过时”或反向假绿。**
5. **多个生产脚本仍是 600–2400 行巨型文件，职责拆分不均衡。**

## P0 阻断项

**本轮未确认新的 P0 阻断项。**

- 撤离真实装配已存在：`scenes/multiplayer/dungeon_session_controller.gd:41-85` 将真实 portal 的 `extraction_requested` 接入 `request_extraction()`；`request_extraction()` 在 `:239-270` 通过 `ClientCommandDriver.send_extract()` 走 `CMD_EXTRACT`；`globals/multiplayer/multiplayer_scene_bridge.gd:350-389` 应用结算、按活动槽位落盘并通知 controller。
- 权威场景、技能、存档聚焦测试本轮 7 套件 32/32 通过；撤离及地牢运行时 6 套件 56/56 通过，均为 0 error / 0 failure / 0 orphan。
- CI 配置已有独立、合并必跑的 ENet job：`.github/workflows/ci.yml:57-105`，Listen 与 Dedicated 两条 runner 都传播非零退出码。

## P1 高风险

### P1-1 区域材料双源漂移

**证据**

- `globals/tavern/loot_table.gd:60-78` 明确声明 `ZONE_SCATTER_WEIGHTS` 是区域散落材料的单一数据源，并由 `ZoneManager` 委托。
- `scenes/expedition/dungeon_spawn_planner.gd:76-85, 537` 又维护 `ZONE_MATERIAL_POOLS` 并直接抽取。
- 两套内容不是同一映射：例如 zone 0 的权威散落池包含 `rat_tail/moldy_bread/rusty_nail/...`，planner 却使用 `blackberry/glowshroom/moongrass`。

**影响**

掉落平衡、材料可获得性、测试和策划文档可能随调用路径不同而分叉。注释声称“单一数据源”，实际架构却有两个来源，这是当前最明确的业务数据完整性风险。

**建议**

让 `DungeonSpawnPlanner` 只依赖注入的材料池查询端口或 `ZoneManager.get_scatter_materials()`；移除本地常量。为每个 zone 加契约测试，断言规划结果的 material id 必须来自唯一数据源。

### P1-2 Autoload 面过宽，Service 仍是隐藏 root 查找

**证据**

- `project.godot:17-49` 注册 31 个 Autoload，覆盖游戏状态、UI、战斗、酒馆、地牢、装备、网络、存档、视觉与性能。
- 生产代码仍有直接绝对 root 查找，例如 `scenes/multiplayer/dungeon_session_controller.gd:181,190`、`globals/multiplayer/multiplayer_session.gd:37,60`。
- `GameEvents` 在 `globals/core/game_events.gd:5-27` 同时承载玩家生命、UI、教程、交互、酒馆 HUD 与命中特效等不同作用域事件。

**影响**

场景无法完全独立实例化，依赖只有运行时才暴露；全局事件语义变更可能波及无关 UI/玩法；测试需要构造更多根节点或靠字符串替身。

**建议**

冻结 Autoload 数量；新领域服务必须作为场景节点或构造依赖。把 `GameEvents` 按作用域拆为场景内信号/组件信号，跨场景才保留全局事件。优先消灭生产代码的绝对 `/root` 查找，改由装配根注入。

### P1-3 联机会话拆分后仍由共享 root 状态耦合

**证据**

- `globals/core/network_manager.gd` 持有并创建 `SessionRoot`，负责连接与会话生命周期。
- `globals/multiplayer/session_root.gd` 仍是约 786 行编排器；`session_combat_service.gd` 等服务通过无静态类型的 `_r` 回指 root，共享玩家、实体、事件与其他服务状态。
- `dungeon_session_controller.gd:185-222` 仍硬编码 Rat/Skeleton 测试型实体规格，而正式敌人 roster/AI 是另一套系统。

**影响**

服务看似拆分，但修改 root 字段或初始化顺序可能跨服务破坏；联机敌人垂直切片与正式敌人系统仍可能行为分叉。

**建议**

下一阶段不要继续机械拆文件，而是先定义 typed port：`EntityRepository`、`CombatEventSink`、`PlayerSessionStore`、`ExpeditionSettlementPort`。服务只持有所需接口，不持有整个 root。随后把硬编码敌人规格换成服务器权威 roster adapter。

## P2 中风险 / 技术债

### P2-1 大量源码字符串测试，重构韧性差

- 本轮扫描到 **256 个** `tests/gdunit/*.gd` 文件使用 `source_code` 或 `get_file_as_string` 类源码文本检查。
- 这类测试适合少量架构禁令，但不适合作为主要行为验证；函数迁移、拆分或重命名会造成契约过时，反之也可能只满足字符串而未满足运行行为。

**建议**：保留少量禁止模式测试；其余迁为实例化、信号、状态转换和端口交互测试。为源码契约测试建立清单并要求每条说明为何无法用行为测试覆盖。

### P2-2 巨型脚本仍多

生产脚本中显著大文件包括：

- `scenes/expedition/dungeon_scene_builder.gd`：2466 行
- `scenes/ui/tavern_equipment_panel.gd`：1936 行
- `scenes/characters/player/player.gd`：1430 行
- `scenes/expedition/isaac_room_dungeon_generator.gd`：1285 行
- `scenes/characters/player/view_model.gd`：1220 行
- `scenes/characters/enemies/enemy.gd`：1189 行
- `globals/multiplayer/session_root.gd`：786 行
- `globals/core/network_manager.gd`：756 行

**建议**：按“状态拥有权”拆分，而非按函数数量拆分。优先选择变化频率高且边界清晰的设备：UI drag/drop、地牢材质构建、敌人视觉表现、玩家装备输入。每次只拆一个组件并保留行为回归测试。

### P2-3 strict typing 门禁未见项目级配置

- `project.godot` 未发现 `gdscript/warnings` 配置。
- 当前代码仍有不少 `Array`、`Dictionary`、`Variant` 和无类型局部推断，尤其联机命令/事件字典。

**建议**：先在新代码和变更文件中执行严格类型规则，不要一次性全仓强开导致噪声淹没。为网络协议引入 typed Resource/RefCounted DTO 或集中 schema 校验，逐步替代散布字典。

## 已确认的正向架构

1. **装备主数据边界清晰**：`WeaponRegistry` 从 `data/weapons/weapons.json` 读取，符合单一来源原则。
2. **撤离事务闭环存在**：portal → controller → `CMD_EXTRACT` → 服务器结算 → bridge 应用 → 活动槽位落盘 → `extraction_completed`。
3. **Dedicated 碰撞权威已不是纯位置积分**：`dungeon_session_controller.gd:104-122` 可构建 collision-only 权威地牢；相关 4 个碰撞测试通过。
4. **CI 能区分单测与真实网络验收**：workflow 有独立 `unit-and-smoke` 与 `enet-integration` job，真实 ENet 不再由逻辑测试冒充。
5. **测试 runner 会预校验路径**：`tests/gdunit4_runner.gd:56-136` 对不存在/非测试路径返回非零；本轮刻意传入 4 个不存在的旧测试路径，runner 正确退出 1，证明不会静默假绿。

## 本轮验证记录

### 1. 权威场景 / 技能 / 存档聚焦

- 7 套件，32/32 用例通过。
- 0 errors / 0 failures / 0 skipped / 0 orphans。
- 覆盖：host/authority layout、权威碰撞、dedicated seed、法术协议与双 peer 隔离、server save repository、progression settlement。

### 2. 撤离与地牢运行时

- 6 套件，56/56 用例通过。
- 0 errors / 0 failures / 0 skipped / 0 orphans。
- `expedition_exit_test.gd` 明确通过 `test_portal_signal_reaches_cmd_extract_via_real_assembly`。
- `reconnect_recovery_test.gd` 的跨 peer 重连结算幂等测试通过。

### 3. CI

- 标准 `run_ci.ps1` 已启动；编辑器扫描通过并进入导出 preset 门禁。
- 完整执行由后台任务承载，本报告生成时尚未返回最终全量套件统计，因此**不把标准 CI 宣称为全绿**。
- workflow 源码检查确认 ENet 合并门禁独立存在。

## 工作器状态说明

- `structure-reviewer` 成功完成本地只读架构盘点，其证据经主审复核后纳入。
- `network-reviewer` 与 `ci-reviewer` 首次运行均因上游 502 Bad Gateway 网络错误失败，首次运行没有产出可用分析；已要求改为本地离线重试。本报告中的联机与 CI 判断由主审直接读取源码并运行本地测试得到，不冒充失败工作器产出。

## 建议实施顺序

1. **先消除区域材料双源**，建立 zone 材料契约测试。
2. **为 Session 服务定义 typed ports**，先替换 `_r` 全 root 回指，不急于继续拆文件。
3. **冻结并削减 Autoload / `/root` 依赖**，优先 MultiplayerSession、DungeonSessionController 和 GameEvents。
4. **把源码字符串测试逐步迁为行为测试**，先覆盖高频重构区域。
5. **按状态拥有权拆 1000+ 行脚本**，一次一组件、一次一测试闭环。
