# Lantern Tavern 架构审查与首轮整改（2026-08-03 19:10）

## 执行结论

本轮先完成增量复审，随后按优先级直接收口两个可独立验证的阻断项；没有触碰酒馆手工场景或资产生成流程。

- **已关闭 P0-2**：`EquipmentPolicy` 现在严格校验护甲固有部位，并保留显式 `armor_slots` 多部位扩展契约。
- **已关闭 P0-1 的 ray 重复伤害子项**：射线只经 `_apply_damage()` 调用一次实体端口；权威端口拒绝时整次 ray 世界执行失败，禁止提交法力/冷却。
- **P0 剩 1 个大项**：联机法术的远端玩家 heal/barrier/buff 权威状态与 projectile 命中仍未统一接入 SessionRoot；持续场/召唤 outbox 和 ray 同步 `extra_events` 已有实现。
- **P1：4 项维持**：远端可信存档来源；性能预算与 LightingController 运行时协调；多人领域仍有 `GameState.current_player` 回退；专服真实 seed 地牢 collision-only 端到端门禁。
- **P2**：tavern shader artist-facing uniform hint、源码字符串测试、`tools/load_check.gd` 误报及巨型混合工作树仍需处理。
- **验证**：法术世界执行器 8/8、装备策略 15/15、法术事务 13/13、法术网络 4/4，合计 **40/40**，全部 0 failure、0 orphan、runner exit 0。Godot editor 首次扫描完成，但退出时提示 `Scan thread aborted`，只记作“扫描完成伴随关闭诊断”，不当作干净解析门禁。

> 当前工作树包含大量已修改和未跟踪文件。本报告描述当前磁盘快照，不代表干净提交或可复现发布候选。

---

## P0 — 发布阻断

### P0-1 联机法术没有完整的权威玩家状态、投射物和实体事件复制闭环

**状态：部分收口，仍为 1 个 P0 大项。**

#### A. 自目标法术仍可能“成功但不改权威状态”

- `globals/combat/spell_authority.gd:49-66`：heal/barrier/buff 仅在 caster 存在 `health`/`buffs` 组件时才修改；组件缺失时仍保持 `execution.ok=true`。
- `globals/multiplayer/session_root.gd:762-793`：只要 authority execution 返回成功就扣 `ctx.spell_mana`、提交冷却并广播 `EVT_SPELL_RESOLVED`；没有统一的 `SpellEffectPort` 写回 `PlayerContext`。
- movement 在 `spell_authority.gd:60-62` 直接改可见 caster 位置，但没有同步更新 `SessionRoot._live_state[peer_id].position`，后续位置快照可能覆盖该位移。
- `globals/core/player_context.gd:29-37` 仍只聚合 spell 状态，未提供权威生命、护盾、增益、位置的统一效果接口。

**后果**：远端治疗、护盾、增益可能消耗法力并进入冷却但没有权威效果；位移可能出现短暂表现后回弹。

#### B. projectile 仍绕过会话实体仓，且失败可 commit

- `globals/combat/spell_authority.gd:67-74` 直接取 `/root/ProjectileService` 调 `spawn()`；服务缺失、投射物 id 未注册或生成返回 `null` 时，没有把结果转换成 `ok=false`。
- `globals/combat/projectile_service.gd:254-299` 的 spawn 是全局服务并把 projectile 添加到场景父节点，不经过 SessionRoot 的 `SpellWorldExecutor.damage_entity_port`。
- `scenes/equipment/projectile_entity.gd:264-360` 命中后走本地 `Enemy.try_receive_hit_result` / `try_receive_hit`，未按 `_entities` 权威实体 ID 写回，也没有经 NetworkManager 的服务端事件出口。
- `globals/combat/spell_recipe_data.gd:11-43` 中 33 个配方多数仍标记 `status: "not_wired"` 或 `"projectile_ready_not_wired"`，不应把配方/图标/局部执行器当作全部法术已完成。

**后果**：专服 projectile 可能只生成本地节点、无法对权威敌人结算，或生成失败仍扣法力/提交冷却。

#### C. 持续场/召唤 tick 的实体事件没有 outbox 提升

- `globals/multiplayer/session_root.gd:811-831` 的 `_spell_damage_entity()` 返回 `events`，包含存活快照、死亡 despawn、掉落 spawn。
- `globals/combat/spell_world_executor.gd:42-48` 的 ray 把端口返回值嵌进 `world_execution.port_result`；但 `spell_world_executor.gd:141-147`、`:174-181` 的 field/summon tick 调用端口后丢弃返回值。
- `session_root.gd:770-793` 未把 `port_result.events` 提升为 `extra_events`；`globals/core/network_manager.gd:264-277` 只广播顶层 `event` 和 `extra_events`。
- `globals/multiplayer/multiplayer_scene_bridge.gd:159-172` 虽然消费 `EVT_SPELL_RESOLVED` 和实体事件，但它只能消费已从服务器出口发出的事件，不能弥补 outbox 缺失。

**后果**：服务器 HP/死亡/掉落可能已经变化，远端客户端收不到对应 `entity_snapshot`、`entity_despawned` 或 `entity_spawned`；持续场和召唤的异步伤害没有稳定复制闭环。

#### D. ray 重复伤害风险已关闭（本轮整改）

- `spell_world_executor.gd:46-59` 现在只调用 `_apply_damage()`；实体目标由 `_apply_damage()` 单次调用 `damage_entity_port` 并返回 `port_result`，不再有第二次显式端口调用。
- 若权威端口返回 `ok=false`，ray 返回 `entity_damage_rejected` 且 `ok=false`，上层事务在 commit 前拒绝。
- `tests/gdunit/spell_world_executor_test.gd:51-76` 保留单次调用门禁，并覆盖端口拒绝结果。

验证：spell_world_executor_test **8/8 通过，0 orphan，exit 0**。

**最小整改边界**：

1. SessionRoot 持有 `SpellEffectPort`，heal/barrier/buff/movement 统一写回 per-peer `PlayerContext`；位移同时更新 `_live_state` 和服务器物理体。
2. projectile 纳入会话级权威模拟，或让 ProjectileService 接受会话实体/事件端口；服务缺失、id 未注册、spawn 失败必须令施法整体失败且不 commit。
3. 为 field/summon 建立 SessionRoot 事件 outbox，tick 产生的实体事件由 NetworkManager flush；ray 只调用实体端口一次。
4. 补远端自目标、projectile 命中/失败、field/summon 异步事件复制和 ray 单次扣血端到端测试。

### P0-2 EquipmentPolicy 未校验护甲固有部位

**状态：已关闭（本轮整改）。**

- `globals/core/equipment_policy.gd:61-69`：单部位护甲要求 `target_name == meta.armor_slot`；未来多部位装备必须显式声明非空 `armor_slots` 数组，且目标槽位仍必须属于合法护甲槽。
- `tests/gdunit/equipment_policy_test.gd:64-91`：新增头盔进 body、胸甲进 head 的反例，以及多部位显式数组允许/数组外拒绝。
- `globals/multiplayer/session_root.gd` 继续只接受该策略解析结果后写入 loadout，命令入口没有旁路。

验证：equipment_policy_test **15/15 通过，0 orphan，exit 0**。

---

## P1 — 高优先级架构债

### P1-1 远端没有可信服务器存档来源

`globals/core/network_manager.gd` 的 spawn 流程已不信任客户端自报 `save_state`，安全边界正确；但远端仍以空状态创建默认 inventory/loadout/spell_state。应接服务器账户/存档仓，不要重新信任客户端字典。

### P1-2 性能预算与灯光分档仍非真正协调器

- `globals/perf/performance_budget_controller.gd:102-113` 主要改变 Viewport FSR 3D scale 并发出信号。
- `globals/lighting/lighting_controller.gd:47-67` 只更新 `_quality_tier`；已有火把范围/能量实际在 `apply_tavern_profile():91-119` 一次性应用。
- 因此运行中降档不会重应用已有 OmniLight3D 的范围/能量；阴影、粒子、雾、法术 FX、LOD 也未统一接入。

建议建立 `VisualQualityCoordinator`，变档时统一重应用当前场景资源，并为移动端做真实设备/热稳定性验证。

### P1-3 多人领域仍有单玩家全局回退

项目源码仍有 `GameState.current_player` 引用，包含 `tools/dungeon_stress_perf_probe.gd:81`、`tools/dungeon_real_overview_capture.gd:122/154`、以及敌人/地牢和测试回退路径。虽然 `NetworkManager._ensure_session():94-104` 已注入 `GameState.player_resolver`，但这不等于所有领域调用点完成 peer/context 注入。

### P1-4 专服 collision-only 缺真实地牢端到端门禁

`scenes/multiplayer/dungeon_session_controller.gd` 已有 authority collision-only 入口，但现有门禁仍主要是人工墙体/纯逻辑验证；未见真实 seed 地牢 + authority collision + 30/60/120Hz 输入一致性的完整测试。

---

## P2 — 中优先级质量债

1. **Shader Inspector hint 不完整**：`scenes/tavern/materials/tavern_atlas_world_32px.gdshader:8-24` 的 tile size、meters、roughness、metallic、noise/decal 参数没有 `hint_range`。本轮未发现新增 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 移动端阻断，但 `liquid_alchemy.gdshader` 与火焰 shader 有固定 3/4 次循环，应保持常量上限和采样预算。
2. **ray 双重端口调用**：见 P0-1-D，优先级高于普通 P2，修复后应提升为专项回归门禁。
3. **源码字符串测试脆弱**：`tests/gdunit/spell_world_executor_test.gd:37-43` 通过源码包含字符串验证执行器接线，无法证明真实调用/结果；应注入 fake executor 做行为测试。
4. **`tools/load_check.gd` 误报成功**：只检查 `load(path) != null`，依赖脚本有 Compile Error 时仍可能输出成功文案；不能把该脚本结果当解析门禁。
5. **工作树混合变更过大**：GLB、纹理、shader、网络、战斗、法术、UI、文档和测试混在同一快照，增加误提交与回归定位成本；禁止盲目 `git add -A`。

---

## 已确认保持关闭/改善

1. 身份唯一性、固定 tick 输入、专服 collision-only 生产入口、攻击上下文/硬冷却/流派伤害倍率、库存默认容量单一常量保持已改善。
2. 材料/符文/未知类别拒绝、武器/护甲类别、双手/盾互斥及护甲固有部位已由 EquipmentPolicy 统一；本轮补齐错误部位反例。
3. SpellAuthority 世界执行器已改为会话实例；字段预算失败可在 commit 前阻止资源扣减。
4. field/summon 异步 outbox、ray 同步 `port_result.events -> extra_events` 已有实现；本轮关闭 ray 重复端口调用并加入拒绝事务语义。
5. 客户端桥接层已消费 `EVT_SPELL_RESOLVED` 和实体事件，但自目标 PlayerContext 与 projectile 命中仍未闭环。

## 本轮验证边界

- 已直接读取术语表、上一轮报告、SessionRoot、SpellAuthority、SpellWorldExecutor、ProjectileService/ProjectileEntity、EquipmentPolicy、NetworkManager、MultiplayerSceneBridge、PlayerContext、LightingController、PerformanceBudget、关键测试和配置。
- Godot 4.7 runner 已尝试逐项启动 6 个专项（spell atomicity/world/network、equipment policy、lighting、performance），但未得到可信统计或退出码；不计通过。
- 未运行真实 ENet 双客户端/重连、专服真实地牢碰撞、远端自目标法术、projectile 命中、field/summon 异步复制、Windows/Android 实际导出、Android 真机 GPU/热稳定性、窗口视觉验收或全量测试。

## 建议整改顺序

1. 将 projectile 接入会话权威实体/复制链，服务缺失或命中失败不得 commit。
2. 建立 SpellEffectPort，把 heal/barrier/buff/movement 写回 per-peer PlayerContext 与 `_live_state`，补远端自目标端到端测试。
3. 把源码字符串门禁替换为行为测试，修正 load_check 失败传播。
4. 增加专服真实 seed collision-only 端到端测试。
5. 建立统一视觉质量协调器并重应用现存资源。
6. 接服务器可信远端存档仓，清理多人领域的 `GameState.current_player` 回退。
7. 按领域拆分当前混合工作树，再做发布候选验证。
