# Lantern Tavern 架构审查（2026-08-03 13:36）

## 执行结论

本轮为相对 `outputs/architecture_review_2026-08-03-1215.md` 的增量只读复审。未修改业务源码、场景、资产或配置。

- **P0：2 项**：联机法术远端状态 / projectile / 实体事件复制闭环仍不可信；EquipmentPolicy 未校验护甲固有部位。
- **P1：4 项**：远端可信存档缺失；性能分档与 LightingController 仍是两套未协调质量系统；多人地牢仍混用 `GameState.current_player`；专服 collision-only 缺真实地牢端到端门禁。
- **P2：4 项**：shader uniform hint 债；过时法术源码字符串测试；`tools/load_check.gd` 依赖编译错误误报成功；工作树混合大量源码/资产/测试变更。
- 代理审查：spell-reviewer、equipment-reviewer、test-reviewer 均因 WorkBuddy 客户端鉴权 **403** 失败，未产生可用分析；本报告结论全部来自主流程直接读取源码与上一轮验证记录，不冒充代理结果。
- Godot 可执行文件不在当前 PATH，本轮未重复运行 Godot 测试；因此不虚构新的测试统计。上轮记录的专项基线为 145/146、0 orphan，唯一失败为过时字符串断言；SessionRoot 69/69、0 orphan、exit 0。

> 当前工作树包含大量未整理修改和未跟踪文件。本报告描述当前磁盘快照，不代表干净提交或可复现发布候选。

---

## P0 — 发布阻断

### P0-1 联机法术没有完整的权威玩家状态、投射物和实体事件复制闭环

**状态：仍开放。**

#### A. 远端自目标效果仍依赖可见 avatar，而不是 PlayerContext 权威状态

- `globals/combat/spell_authority.gd:49-66`：heal/barrier/buff 只在 caster 存在对应 `health`/`buffs` 组件时修改，否则仍保持 `execution.ok=true`；movement 直接改 `caster.global_position`。
- `globals/multiplayer/session_root.gd:762-793`：只要 authority execution 返回 ok 就扣法力、提交冷却并广播成功；没有统一的 `SpellEffectPort` 写回 `PlayerContext`，movement 也没有同步更新 `_live_state[peer_id].position`。
- `globals/multiplayer/multiplayer_scene_bridge.gd:111-121`：绑定到 context 的远端 avatar 是位置代理，不是完整玩家权威组件。

**后果**：远端治疗/护盾/增益可能消耗法力并进入冷却但不改变权威状态；位移可能短暂移动 avatar，后续被服务器位置快照拉回。

#### B. projectile 仍绕过 SessionRoot 实体仓，生成失败可成功 commit

- `globals/combat/spell_authority.gd:67-74`：直接取 `/root/ProjectileService` 并调用 `spawn()`；未将 `spawn()` 返回 null/服务缺失转换为 `ok=false`。
- projectile 没有走会话级 `SpellWorldExecutor.damage_entity_port`，也没有基于 `SessionRoot._entities` 的目标查询与伤害写回。

**后果**：专服 projectile 可能只生成节点或什么也不生成，仍扣法力/提交冷却；对会话权威敌人没有可信结算闭环。

#### C. ray/field/summon 的实体事件没有稳定提升到 NetworkManager 出口

- `globals/multiplayer/session_root.gd:811-831` 的 `_spell_damage_entity()` 返回 `events`，包含存活实体快照、死亡 despawn、掉落 spawn 等。
- `globals/combat/spell_world_executor.gd:42-48` 的 ray 将端口结果嵌入 `world_execution.port_result`；但 field/summon 在 `145`、`179` 行调用端口后丢弃返回值。
- `globals/multiplayer/session_root.gd:770-793` 没有把端口产生的事件提升为 `extra_events`。
- `globals/core/network_manager.gd:255-266` 只广播顶层 `event` 与 `extra_events`。

**后果**：服务器实体 HP/死亡/掉落可能已经改变，客户端收不到对应快照或 despawn/spawn；持续场和召唤 tick 没有异步 outbox。

**最小整改边界**：
1. SessionRoot 持有 `SpellEffectPort`，自目标效果只写 PlayerContext；位移同时更新 `_live_state` 并驱动服务器物理体。
2. projectile 纳入会话级权威模拟；服务缺失或生成失败必须令整次施法失败且不 commit。
3. 为 field/summon 建立会话事件 outbox，tick 产生的实体事件由 NetworkManager flush。
4. 补远端自目标、projectile 命中、field/summon 异步事件复制的端到端测试。

### P0-2 EquipmentPolicy 未校验护甲固有部位

**状态：仍开放。**

- `globals/core/equipment_policy.gd:55-64`：显式 `slot_name` 只检查是否属于 `EquipmentLoadout.VALID_ARMOR_SLOTS`，没有要求等于 `meta.armor_slot`。
- `tests/gdunit/equipment_policy_test.gd:49-67`：覆盖默认槽、正确显式槽和非法槽名，但没有头盔进 body、胸甲进 head 的反例。
- 因此 `leather_cap (armor_slot=head)` 仍可被请求放入 `body`，污染权威 loadout、存档、属性与外观。

**最小整改边界**：`target_name` 严格等于 `meta.armor_slot`；若未来有多部位装备，注册表需显式声明 `allowed_armor_slots:Array`。EquipmentPolicy 与 SessionRoot 各补一层反例。

---

## P1 — 高优先级架构债

### P1-1 远端没有可信服务器存档来源

`globals/core/network_manager.gd:575-586` 已正确忽略客户端自报 `save_state`，但远端 spawn 仍以空状态创建默认 inventory/loadout/spell_state。安全边界正确，可玩性/持久化闭环未完成。应接服务器账户/存档仓，不要重新信任客户端字典。

### P1-2 性能分档与灯光系统未统一协调

`globals/perf/performance_budget_controller.gd:102-113` 主要只改变 3D FSR scale 与信号；`globals/lighting/lighting_controller.gd:47-67` 收到质量信号后只更新 `_quality_tier`，火把范围在 `apply_tavern_profile()` 的 `91-119` 一次性应用。运行中降档不会重应用已存在 OmniLight3D 的范围/能量，阴影、粒子、雾、反射、法术 FX 与 LOD 也没有统一质量协调器。建议建立 `VisualQualityCoordinator`，集中映射并在变档时重应用现存资源。

### P1-3 多人领域逻辑仍混用单玩家全局状态

`scenes/expedition/dungeon_runtime.gd:148,214,502,549`、`scenes/expedition/procedural_dungeon.gd:160,225`、`scenes/expedition/extraction_portal.gd:193`、`scenes/characters/enemies/enemy.gd:306,684,745` 仍读取 `GameState.current_player`。多人撤离、目标选择、地牢交互和部分击杀回退可能落到房主/本地玩家，需改为 peer/player context 注入。

### P1-4 专服 collision-only 缺真实地牢端到端门禁

`scenes/multiplayer/dungeon_session_controller.gd:54-72` 已提供 `build_authority_collision_only()`；但现有 `server_character_motor_test.gd` 仍使用人工墙体，未见真实 seed 地牢 + authority collision + 30/60/120Hz 输入一致性的完整门禁。

---

## P2 — 中优先级质量债

### P2-1 Shader Inspector 参数提示不完整

`scenes/tavern/materials/tavern_atlas_world_32px.gdshader:8-24` 的 artist-facing 标量 uniform 缺 `hint_range`，包括 tile size、meters per tile、roughness、metallic、noise/decal 参数。当前证据未发现新增 `SCREEN_TEXTURE`、`DEPTH_TEXTURE`、`discard` 的移动端发布阻断，但应补齐 hint 并做 Forward+/Mobile 兼容审计。

### P2-2 法术源码字符串测试过时

`tests/gdunit/spell_world_executor_test.gd:37-41` 仍断言源码包含 `_world_executor.execute`，而实现已改为局部 `executor.execute`。这类源码字符串门禁不是行为证明；应改为注入执行器并验证真实 execute 调用/结果。

### P2-3 `tools/load_check.gd` 会误报依赖编译错误为成功

`tools/load_check.gd:18-30` 只检查 `load(path) != null`。Godot 可在依赖脚本编译错误时仍返回 GDScript 资源，导致日志已有 Compile Error 时继续输出 `OK` 与 `All files compiled successfully.`。不能将该脚本的成功文案当作解析门禁；应在完整 project/autoload 上下文扫描并让依赖编译错误阻断。

### P2-4 工作树混合变更规模过大

当前工作树同时含大量 GLB、纹理、shader、网络、战斗、法术、UI、文档和测试变更，以及大量未跟踪文件。架构修复与资产生产混在同一快照，增加误提交和回归定位成本。建议按领域拆分提交、建立干净测试基线，禁止盲目 `git add -A`。

---

## 已确认保持关闭/改善（相对上轮）

1. 身份唯一性、固定 tick 输入、专服 collision-only 生产入口、攻击上下文/硬冷却/流派伤害倍率、库存默认容量单一常量均保持已改善。
2. 材料/符文/未知类别拒绝、武器/护甲类别、双手/盾互斥已由 `EquipmentPolicy` 统一；但护甲固有部位仍是漏洞。
3. SpellAuthority 世界执行器已为会话实例；预算失败可在 commit 前回滚资源。
4. SessionRoot 上轮记录为 69/69、0 orphan、exit 0。

## 本轮未能可信验证

- Godot 可执行文件不在 PATH，未重复运行 gdUnit4、真实 ENet 双客户端/重连、专服真实地牢碰撞、远端自目标法术、projectile 命中、field/summon 异步复制、Windows/Android 实际导出、Android 真机 GPU/热稳定性、窗口视觉验收或全量测试。
- 三个并行审查代理均以 WorkBuddy 客户端鉴权 403 失败，未产出分析。

## 建议整改顺序

1. 先建 SessionRoot `SpellEffectPort + event outbox`，收口远端玩家状态、projectile 和持续事件复制。
2. 严格校验护甲固有部位并补两层反例。
3. 修复过时法术行为测试与解析门禁，确保失败真的阻断。
4. 增加专服真实 seed collision-only 端到端测试。
5. 接服务器可信远端存档仓。
6. 建立统一视觉质量协调器并重应用现存资源。
7. 清理多人领域中的 `GameState.current_player` 回退。
8. 按领域拆分当前巨型工作树，再做发布候选验证。
