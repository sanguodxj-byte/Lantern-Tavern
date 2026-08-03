# Lantern Tavern 架构审查（2026-08-03 18:26）

## 执行结论

本轮为增量只读架构复审，未修改业务源码、场景、资产或项目配置。结论：**2 项 P0 仍开放；4 项 P1 维持；5 项 P2/质量债确认。** 结论基于当前磁盘快照与上一轮报告；本轮未得到可信 Godot runner 统计/退出码，因此不把测试计数冒充为本轮通过。

> 工作树仍包含大量混合修改与未跟踪内容。本报告不是干净提交或可复现发布候选的证明。

---

## P0 — 发布阻断

### P0-1 联机法术仍缺完整的权威状态、投射物与实体事件复制闭环

**状态：仍开放。**

证据：

- `globals/combat/spell_authority.gd:49-66`：heal/barrier/buff 只有 caster 存在对应组件时才写入；组件缺失时仍保持 `execution.ok=true`。
- `globals/multiplayer/session_root.gd:762-793`：只要 authority execution 成功就扣法力、提交冷却并发布 `EVT_SPELL_RESOLVED`，没有统一 `SpellEffectPort` 把生命、护盾、增益、位移同时写回 per-peer `PlayerContext` 与 `_live_state`。movement 直接改 `caster.global_position`，后续快照仍可能覆盖位移。
- `globals/combat/spell_authority.gd:67-74`：projectile 直接调用 `/root/ProjectileService.spawn()`；服务缺失、ID 未注册或 `spawn()` 返回 null 时没有转成 `ok=false`，仍可能进入 commit。
- `globals/combat/projectile_service.gd:260-299` 与 `scenes/equipment/projectile_entity.gd:264-360`：投射物由全局服务挂到场景树，命中走可见 Enemy 节点的本地 `try_receive_hit*`，未纳入 SessionRoot `_entities` 权威仓与统一网络事件出口。
- `globals/combat/spell_world_executor.gd:141-147`、`:174-181`：field/summon tick 调用 `damage_entity_port` 后丢弃返回的 `events`；`session_root.gd:770-793` 也未将 `world_execution.port_result.events` 提升为 `extra_events`，远端可能收不到实体快照、死亡或掉落。
- **本轮新增确认**：`globals/combat/spell_world_executor.gd:42` 先调用 `_apply_damage()`；目标带 `entity_id` 且端口有效时，`:86-90` 已调用一次 `damage_entity_port`，随后 `:45-46` 又再次调用同一端口，ray 单次命中存在双重扣血/重复击杀风险。

影响：远端自目标法术可能出现“法力与冷却已提交但权威效果未生效”；projectile 可能只在本地生成或命中不改服务器实体；持续场/召唤的 HP、死亡、掉落事件可能不复制；ray 可能一次命中扣两次血。

最小整改边界：

1. SessionRoot 持有 `SpellEffectPort`，heal/barrier/buff/movement 统一写回 per-peer `PlayerContext`；movement 同时更新 `_live_state` 和服务器物理体。
2. projectile 纳入会话级权威实体/模拟，或让 ProjectileService 接受会话实体与事件端口；服务缺失、ID 未注册、spawn 失败必须让施法整体失败且不 commit。
3. 建立 SessionRoot 事件 outbox：ray/field/summon 的端口结果事件统一提升到 `extra_events` 后由 NetworkManager flush；ray 只调用实体端口一次。
4. 补远端自目标、projectile 命中/失败、field/summon 异步复制、ray 单次扣血的行为型端到端测试。

### P0-2 EquipmentPolicy 未校验护甲固有部位

**状态：仍开放。**

证据：

- `globals/core/equipment_policy.gd:55-64`：显式 `slot_name` 只验证属于 `EquipmentLoadout.VALID_ARMOR_SLOTS`，没有要求等于 `meta.armor_slot`。
- `tests/gdunit/equipment_policy_test.gd:49-67`：只覆盖默认槽、正确显式槽与非法槽名，没有头盔进 `body`、胸甲进 `head` 的反例。
- `globals/multiplayer/session_root.gd:953-963` 完全依赖该策略写入权威 loadout；因此 `leather_cap -> body` 仍可污染权威装备、属性、存档与外观。

最小整改边界：单部位护甲要求 `target_name == meta.armor_slot`；未来多部位装备必须显式声明允许槽数组；策略层与 SessionRoot 各补反例测试。

---

## P1 — 高优先级架构债

### P1-1 远端没有可信服务器存档来源

`handle_spawn_request()` 已拒绝直接信任客户端命令中的权威字段，但当前仍以调用方传入的 `save_state` 应用到远端上下文。若网络入口未先从服务器存档仓加载，该参数仍可能成为伪造材料、装备、法术状态与属性的注入面。应将 spawn 只绑定 `player_guid/reconnect_token`，由服务端 SaveRepository 按身份加载；客户端仅提供非权威连接意图。

### P1-2 性能预算与灯光控制仍不是统一视觉质量协调器

- `globals/perf/performance_budget_controller.gd:102-113` 变更 Viewport FSR 3D scale 并发出 `quality_tier_changed`。
- `globals/lighting/lighting_controller.gd:49-68` 已订阅该信号并映射档位，但 `_on_budget_tier_changed()` 只更新 `_quality_tier`，没有遍历当前场景重新应用火把范围/能量；已应用光源的 `omni_range` 仍保持旧档位。
- 阴影、粒子、雾、法术 FX、LOD 未统一接入。

建议建立 `VisualQualityCoordinator`，把分辨率、光照、阴影、粒子、雾、FX 上限和 LOD 作为一次变档事务重应用。

### P1-3 多人领域仍存在 `GameState.current_player` 回退

源码命中包括 `tools/dungeon_stress_perf_probe.gd:81`、`tools/dungeon_real_overview_capture.gd:122/154`，以及敌人/地牢回退路径与测试。`NetworkManager._ensure_session()` 的 resolver 注入不等于所有领域调用点完成 peer/context 注入；真实多人领域仍有单玩家全局耦合风险。

### P1-4 专服 collision-only 缺真实地牢端到端门禁

`scenes/multiplayer/dungeon_session_controller.gd` 已有 authority collision-only 入口，但现有验证主要是人工墙体/纯逻辑测试。仍缺真实 seed 地牢、authority 碰撞、30/60/120Hz 输入一致性和穿墙回归的端到端门禁。

---

## P2 — 中优先级质量债

1. `scenes/tavern/materials/tavern_atlas_world_32px.gdshader:5-24` 多个 artist-facing float/vec uniform 没有 `hint_range`，违反 Inspector 参数约束规范；本轮未发现新增 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或移动端 `discard` 阻断。
2. `tests/gdunit/spell_world_executor_test.gd:37-43` 通过源码字符串检查执行器接线，不能证明真实调用、返回值或事件传播；应替换为 fake port/行为测试。
3. `tools/load_check.gd:18-30` 只按 `load(path) != null` 判断，依赖脚本编译失败时可能仍输出成功文案；解析门禁必须检查引擎错误输出或使用可信 runner 退出码。
4. Godot 项目仍声明 `config/features=PackedStringArray("4.7", "C#")`，但主代码路线是 GDScript；`docs/16-技术架构与代码设计.md:14-16,498-501` 仍保留 C#/Mono 与 gl_compatibility 的旧表述，需明确“文档历史参考”与当前 Forward+/Mobile 决策边界，避免新代码按旧 renderer 目标实现。
5. 工作树混合大量 GLB、纹理、shader、网络、战斗、法术、UI、文档与测试变更，发布前必须按领域拆分并禁止盲目 `git add -A`。

---

## 本轮验证边界

- 已读取：`docs/术语表.md`、上一轮报告、`docs/16-技术架构与代码设计.md`、`docs/24-联机架构迁移.md`、SessionRoot、SpellAuthority、SpellWorldExecutor、ProjectileService、ProjectileEntity、EquipmentPolicy、EquipmentPolicy 测试、PerformanceBudget、LightingController、目标 shader、tools/load_check.gd、project.godot。
- 已直接复核 P0/P1/P2 证据链；并行复核代理因客户端鉴权 403 未执行，不采用其结果。
- 本轮未运行真实 ENet 双客户端/重连、专服真实地牢碰撞、远端自目标法术、projectile 命中、field/summon 异步复制、Windows/Android 导出、Android 真机 GPU/热稳定性、窗口视觉验收或全量测试。

## 建议整改顺序

1. 先修 ray 双重伤害，建立法术效果端口与事件 outbox。
2. 把 projectile 接入会话权威实体/复制链；生成失败不得 commit。
3. 严格校验护甲固有部位并补反例。
4. 将源码字符串门禁替换为行为测试，修正 load_check 失败传播。
5. 增加专服真实 seed collision-only 端到端测试。
6. 建立统一视觉质量协调器并重应用当前光源资源。
7. 将远端 spawn 的存档加载收口到服务器 SaveRepository，并清理多人领域 `GameState.current_player` 回退。
8. 按领域拆分工作树后，再做发布候选验证。
