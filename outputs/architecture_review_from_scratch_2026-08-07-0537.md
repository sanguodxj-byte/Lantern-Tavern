# Lantern Tavern 架构审查（从当前工作树重新开始）

- 审查时间：2026-08-07 05:37（GMT+8）
- 范围：当前工作树源码、`project.godot`、`run_ci.ps1`、真实 ENet runner、`docs/术语表.md`；未读取项目记忆、旧审查报告或 overview。
- 工作树存在大量未提交修改与删除；本审查不假设其稳定，也未修改生产代码。

## 结论

**当前架构门禁为 RED，不可把工作树判定为可合并。** 聚焦架构/联机测试通过，但标准 CI 在测试发现阶段失败并随后触发 Godot signal 11；因此“聚焦绿”不能抵消全量门禁失败。真实 Listen 与 Dedicated ENet 本轮均 PASS，但 `run_ci.ps1` 默认不执行真实集成，只打印 NOT RUN。

## P0 / 阻断项

### P0-1：标准 CI 测试契约失配，发现阶段直接失败并触发崩溃
证据：
- `tests/gdunit/service_test.gd:58-59,74-75` 仍访问 `Service.skill_data` / `Service.action_skills` 及对应静态函数。
- 当前 `globals/core/service.gd` 已无这些成员，导致标准 `run_ci.ps1:79-80` 的目录扫描出现 4 个 Parse Error，gdUnit 返回 105；随后 Godot 发生 signal 11。
- 实测：编辑器扫描与三个导出 preset 门禁通过；全量 suite 未进入执行阶段，CI 退出码为 `-1073741819`。
影响：CI 无法可靠发现/执行测试；可能掩盖真实失败，且 runner 崩溃使退出码传播不稳定。
修复方向：同步迁移/删除失效服务契约断言；让 discovery 失败保持确定性非零退出，避免二次 crash。

### P0-2：联机撤离的真实生产装配仍未形成端到端闭环证据
证据：
- `scenes/expedition/dungeon_runtime.gd:402-414` 将 portal 信号接到 `on_extraction_requested`；`472-499` 的 `finish_expedition` 直接 `_settle_extraction_loot` 并调用 `TavernManager.extract_to_tavern`。
- 联机控制器 `scenes/multiplayer/dungeon_session_controller.gd:196-207` 有 `request_extraction()`，通过 `ClientCommandDriver.send_extract()` 提交 `CMD_EXTRACT`；`214-218` 仅由桥接层通知应用完成。
- 当前工作树中除测试外未找到 `DungeonRuntime` 调用 `DungeonSessionController.request_extraction()` 的生产调用；`request_extraction(` 只有控制器自身和 `tests/gdunit/expedition_exit_test.gd`。
- `globals/multiplayer/multiplayer_scene_bridge.gd:388-389` 存在 `notify_extraction_applied` 调用，但缺少 portal→controller 的运行时装配证据。
影响：多人真实场景可能仍走单机本地结算，或自动撤离后没有 CMD_EXTRACT；存在结算分叉/丢结算/重复结算风险。
修复方向：在多人 dungeon host assembly 中显式把 portal 完成事件接到 `request_extraction()`，并由专门生产集成测试断言 portal→CMD_EXTRACT→EVT_EXTRACTION_RESULT→离场只发生一次；单机继续保留 `finish_expedition`，但模式分支必须可证。

## P1 / 高风险

### P1-1：技能 buff 时间单位不一致，权威状态可能常驻或立即过期
- `globals/core/player_context.gd:43-48` 定义 `buffs` 为绝对毫秒 expiry；`64-66` 也写入 `Time.get_ticks_msec()+duration*1000`。
- `globals/multiplayer/skill_authority.gd:101-107` 却把 `buff_value` 秒数直接写入 `ctx.buffs[buff_type]`，没有转换成绝对毫秒。
- `player_context.gd:88-95` 按 `now_ms >= expiry` 清理，因此技能 buff 的秒数会被当作毫秒绝对时间处理。
影响：iframes/dodge_frames 等技能 buff 语义错误，联机状态与单机不一致。
修复方向：由 `PlayerContext` 提供唯一 `apply_timed_buff(buff_id, duration_sec, now_ms)`，禁止 `SkillAuthority` 直接写 `ctx.buffs`；增加未来时间、续期、过期和重连序列化测试。

### P1-2：技能主动/被动绑定仍共享一个所有权列表，边界依赖后置拒绝
- `globals/multiplayer/session_combat_service.gd:298-312` 将 `get_bound_active_skills()+get_bound_passive_skills()` 合并后检查 ownership，再用 `type == passive` 拒绝主动触发。
影响：协议层先接受错误类别再拒绝，技能类别约束分散；未来新增技能 type 若缺少明确策略可能被误放行。
修复方向：SkillRuntime/SkillAuthority 提供 `is_active_skill_owned`，命令入口只查询主动集合；被动效果走被动管线。

### P1-3：SkillAuthority 的未实现效果用硬拒绝保护，但功能完整性仍缺口
- `globals/multiplayer/skill_authority.gd:59-72,111-130` 对 grapple、stun、shield break、ignore defense/block、lifesteal、AOE 全部硬拒绝；已实现的仅单目标伤害、击退端口、movement、self buff。
- 这是安全上正确的 fail-closed，但与技能定义能力面不完整；若 UI/数据把这些技能呈现为可用，将产生可用性断裂。
修复方向：要么明确把未实现技能从可获取/可展示数据中隔离，要么逐项实现并加入权威效果断言。

### P1-4：SpellAuthority 仍有绝对 `/root` 依赖
- `globals/combat/spell_authority.gd:120` 直接 `caster.get_node_or_null("/root/ProjectileService")`。
- 当前 11 套聚焦套件通过了 `architecture_dependency_rule_test`，说明现有门禁只约束部分 session service，并未覆盖 combat authority 的 root 依赖。
影响：多会话、测试隔离、嵌入式 host 与非标准树装配脆弱。
修复方向：Projectile spawn port 由 SessionRoot/SessionCombatService 注入；架构规则覆盖所有生产层。

### P1-5：`SessionRoot` 仍为编排热点
- 当前文件 `globals/multiplayer/session_root.gd` 约 786 行；新增 service 拆分改善了职责，但服务通过 `_r` 访问大量 root 保留字段/API（见 `session_combat_service.gd:9-13` 注释及全文件调用）。
- `project.godot` 当前 31 个 Autoload 条目（`[autoload]` 约 17-49 行）。
影响：变更传播面大，生命周期与依赖方向难以静态验证。
修复方向：按命令族定义窄接口/端口对象，减少服务对 SessionRoot 私有状态的透传；逐步把会话状态收进显式 SessionState。

## P2 / 观察项

1. 生产运行时 GDScript 303 个（globals/scenes/data/fx，排除 tests/addons），测试 GDScript 513 个；全项目生产脚本总行数约 78,854。
2. 生产中 >=500 行脚本至少 20 个；最大为 `scenes/expedition/dungeon_scene_builder.gd` 2466 行、`scenes/ui/tavern_equipment_panel.gd` 1936 行、`scenes/characters/player/player.gd` 1430 行、`globals/multiplayer/session_root.gd` 786 行。
3. 约 280 个测试脚本包含源码字符串/文本读取式断言模式；对重构敏感，应优先补行为测试，保留少量架构契约测试。
4. 生产字符串形式 `/root` 查找至少 11 处；除 `SpellAuthority` 外还包括 `MultiplayerSession`、`DedicatedServer`、`DungeonSessionController`、`ProceduralDungeon` 等。现有趋势测试通过，但属于趋势门禁，不是零依赖门禁。
5. 聚焦测试 stderr 有重复信号连接：`tests/gdunit/spell_network_behavior_test.gd:40` 触发 `session_event` already connected；另有预期的 ProjectileService 未注册 warning。聚焦结果仍为 11 suites / 168 cases / 0 failures / 0 errors / 0 orphans，但 stderr 不应被静默。
6. editor headless scan 退出 0；唯一 stderr 为 Godot `EditorSettings not instantiated yet...`，已由 `run_ci.ps1:43-52` 精确白名单。

## 实测验证

- 聚焦架构/联机测试：11 suites，168/168 cases，0 errors/failures/orphans，exit 0；stderr 含重复 `session_event` 连接 ERROR。
- Listen ENet：`tools/run_integration_dungeon_test.ps1` exit 0；seed/fingerprint/entities/movement/combat/loot/extract/recovery 全部报告 PASS。
- Dedicated ENet：`tools/run_dedicated_server_test.ps1` exit 0；seed/fingerprint/entities/movement/snapshots PASS。
- 标准 CI：editor scan、Web/Windows Desktop/Android preset recognition 通过；gdUnit full discovery 失败于 `service_test.gd`，exit 105 后 Godot signal 11，最终 PowerShell 显示 `-1073741819`；未执行真实 ENet（默认未传 `-RunIntegration`）。

## 优先级行动清单

1. 修复 `tests/gdunit/service_test.gd` 与 `globals/core/service.gd` 的契约失配，并让标准 CI 在 discovery error 时稳定失败而不 crash。
2. 建立生产级多人撤离接线：portal signal → controller request_extraction → server CMD_EXTRACT → settlement event → notify/applied → one-shot exit。
3. 统一 timed buff 的 expiry 表示，禁止业务服务直接写 `PlayerContext.buffs`。
4. 注入 ProjectileService / spawn port，消除 `SpellAuthority` `/root` 依赖并扩大架构规则覆盖。
5. 清理重复信号连接，之后用 `-RunIntegration` 纳入网络启用 CI；默认 CI 至少明确将未执行 ENet 记为非阻断的环境门禁，而不是整体“passed”。
