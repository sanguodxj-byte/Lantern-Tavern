# Lantern Tavern 架构审查（2026-08-03 12:15）

## 执行结论

本轮为相对 `outputs/architecture_review_2026-08-03-1059.md` 的增量只读复审。上轮 2 个 P0 均未关闭，且法术闭环的证据更明确：当前实现能写回服务器实体字典，但没有可靠发布实体事件；远端自目标状态与位移仍写在临时 avatar 上；projectile 路径仍绕过会话实体仓。

- **P0：2 项**：联机法术统一权威事务/复制闭环未完成；EquipmentPolicy 未校验护甲固有部位。
- **P1：4 项**：远端可信存档缺失；性能分档只部分接通；多人地牢仍依赖 `GameState.current_player`；专服 collision-only 缺真实地牢端到端门禁。
- **P2：4 项**：shader uniform hints 不完整；法术源码字符串测试过时；`tools/load_check.gd` 会把依赖编译错误误报为成功；工作树规模过大且混合大量源码/资产/测试变更。
- 专项合计 **145/146**：SessionRoot 69/69、核心 43/43、装备策略 13/13、法术 20/21；全部 0 orphan。唯一失败仍是过时源码字符串断言。
- 本轮未修改业务源码、场景、资产或配置。
- **代理执行说明**：联机、渲染与核心三个审查代理最终均因 WorkBuddy 客户端鉴权 403 失败；联机代理此前还出现过一次代理/TLS 502 建连失败。以下报告完全来自主流程直接读取源码、检查行号和运行专项测试，未使用或虚构失败代理的分析结果。

> 基线风险：当前工作树包含大量修改和未跟踪文件。本报告描述当前磁盘快照，不代表干净提交或可复现发布候选。
>
> 执行透明性：本轮并行审查代理未产出可用结果。`network-reviewer` 因代理/TLS 连接失败（502），`render-reviewer` 与 `core-reviewer` 因客户端鉴权限制（403）失败。报告中的证据、结论与测试统计均来自主流程直接读取源码和运行本地验证，不包含或冒充上述失败代理的分析。

---

## P0 — 发布阻断

### P0-1 联机法术仍未形成统一玩家状态、投射物和实体事件复制闭环

**状态：仍开放。**

#### 1. 远端 heal/barrier/buff/movement 仍作用于位置代理，而非 PlayerContext 权威状态

- `globals/multiplayer/multiplayer_scene_bridge.gd:111-121` 把远端 avatar 绑定为 `ctx.player_node`，并明确其只是位置代理、没有真实 `health/buffs`。
- `globals/combat/spell_authority.gd:49-66` 在缺组件时仍返回 `ok=true`；heal/barrier/buff 只是跳过修改，movement 直接改 avatar `global_position`。
- `globals/multiplayer/session_root.gd:762-793` 只要 `authority_execution.ok` 就扣法力、提交冷却并广播成功；没有把自目标状态写回 `PlayerContext`，movement 也未更新 `_live_state[peer_id].position`。

**后果**：远端治疗/护盾/增益可消耗法力并进入冷却但没有权威效果；位移法术可能短暂移动 avatar，随后被 `_live_state` 快照拉回。

#### 2. projectile 路径仍绕过 SessionRoot 权威实体仓，而且服务缺失/生成失败仍可成功 commit

- `globals/combat/spell_authority.gd:67-74` 直接调用 `/root/ProjectileService.spawn()`；service 不存在或 `spawn()` 返回 null 时没有转成 `ok=false`。
- 该路径没有接入 `SpellWorldExecutor.damage_entity_port`，也没有基于 `SessionRoot._entities` 做目标查询/伤害写回。

**后果**：专服 projectile 法术可能只生成场景节点或什么也不生成，却仍扣法力、提交冷却；对会话权威敌人没有可信结算闭环。

#### 3. ray/field/summon 虽写回 `_entities`，但产出的实体事件没有可靠网络出口

- `globals/multiplayer/session_root.gd:811-831` 的 `_spell_damage_entity()` 生成 `entity_snapshot/entity_despawned/entity_spawned/progression` 事件并放入 `events`。
- `globals/combat/spell_world_executor.gd:42-48` 的 ray 把端口结果放在 `world_execution.port_result`；field/summon 在 `145`、`179` 行直接调用端口并丢弃返回值。
- `globals/multiplayer/session_root.gd:770-793` 没有把上述 `events` 提升为返回结果的 `extra_events`。
- `globals/core/network_manager.gd:255-266` 只广播顶层 `event` 和 `extra_events`。

**后果**：服务器敌人生命/死亡/掉落可能已改变，但客户端收不到对应实体快照或 despawn/spawn；持续场与召唤 tick 更没有异步 outbox。

#### 最小修复边界

1. 建立 SessionRoot 持有的 `SpellEffectPort`：自目标效果只写 `PlayerContext`，位移同时写 `_live_state` 并驱动服务器物理体。
2. projectile 进入会话级权威模拟；spawn/服务失败必须令整个施法失败且不 commit。
3. 建立会话事件 outbox；即时 ray、持续 field、summon tick 产生的实体事件都由 NetworkManager flush。
4. 补远端 heal/barrier/buff/movement、projectile 命中、field/summon 异步伤害及客户端复制端到端测试。

### P0-2 EquipmentPolicy 仍允许护甲进入错误的“有效护甲槽”

**状态：仍开放。**

- `globals/core/equipment_policy.gd:55-64`：显式 `slot_name` 只需属于 `EquipmentLoadout.VALID_ARMOR_SLOTS`，没有要求等于 `meta.armor_slot`。
- `tests/gdunit/equipment_policy_test.gd:49-67` 只覆盖默认槽、正确显式槽和非法槽名；没有“头盔进 body / 胸甲进 head 必须拒绝”的反例。
- 因此 `leather_cap(armor_slot=head)` 仍可被放入 `body`，污染权威 loadout、存档、属性与外观。

**修复边界**：`target_name` 必须严格等于 `meta.armor_slot`；如确有多部位装备，注册表显式声明 `allowed_armor_slots:Array`。补 EquipmentPolicy 与 SessionRoot 两层反例。

---

## P1 — 高优先级架构债

### P1-1 远端玩家没有可信服务器存档来源

`globals/core/network_manager.gd:575-586` 正确忽略客户端自报 `save_state`；但远端 spawn 仍以空状态创建默认 inventory/loadout/spell_state。安全边界正确，可玩性闭环未完成。应接服务器账户/存档仓，不能重新信任客户端字典。

### P1-2 性能分档只部分接入，现存资源不会完整重应用

- `globals/perf/performance_budget_controller.gd:102-113` 实际消费者主要是 3D FSR scale 与信号。
- `globals/lighting/lighting_controller.gd:47-67` 已订阅质量信号，但回调只更新 `_quality_tier`。
- 火把范围只在 `apply_tavern_profile()` 的 `91-119` 行一次性应用；运行中降档不会重设已存在的 `omni_range`。
- 阴影、粒子、雾、反射、法术 FX 与 LOD 仍没有统一协调器。

建议建立 `VisualQualityCoordinator`，集中映射 render scale、灯光、阴影、粒子、雾、反射与 FX 上限，并在变档时重应用现存资源。

### P1-3 多人领域逻辑仍混用单玩家全局状态

`scenes/expedition/dungeon_runtime.gd:148,214,502,549`、`procedural_dungeon.gd:160,225`、`extraction_portal.gd:193`、`scenes/characters/enemies/enemy.gd:306,684,745` 仍读取 `GameState.current_player`。联机主链虽已 per-peer，但撤离、目标选择、地牢交互和部分击杀回退仍可能落到房主/本地玩家。

### P1-4 专服 collision-only 已实现，但缺真实地牢端到端门禁

`scenes/multiplayer/dungeon_session_controller.gd:54-72` 已提供 `build_authority_collision_only()`；现有 `server_character_motor_test.gd` 只使用人工墙体。本轮测试搜索未发现真实 seed 地牢 + authority collision + 30/60/120Hz 输入一致性的完整门禁。

---

## P2 — 中优先级质量债

### P2-1 Shader Inspector 参数提示不完整

`scenes/tavern/materials/tavern_atlas_world_32px.gdshader:8-24` 的 artist-facing 标量 uniform 缺 `hint_range`，包括 tile size、meters per tile、roughness、metallic、noise/decal 参数。当前未发现新增 `SCREEN_TEXTURE`、`DEPTH_TEXTURE`、`discard` 的移动端发布阻断。

### P2-2 法术源码字符串测试过时

`tests/gdunit/spell_world_executor_test.gd:37-41` 仍断言源码包含 `_world_executor.execute`；实现已改为局部 `executor.execute`。该断言是本轮唯一失败，应改为行为/接口测试。

### P2-3 `tools/load_check.gd` 会把依赖编译错误误报成成功

- 扫描日志出现 `AudioManager`、`PhysicsSetup` 未注册导致的 Compile Error，但脚本随后仍打印对应文件 `OK`，最终打印 `All files compiled successfully.`。
- 根因是 `load(path)` 可返回 GDScript 资源，即使依赖编译阶段报错；`tools/load_check.gd:18-30` 只检查 `script == null`。

这不是稳定的全项目解析门禁。应在完整 project/autoload 上下文运行编辑器扫描，或显式检查脚本 reload/错误日志，不能把该脚本的最终成功文案当证据。

### P2-4 工作树混合变更规模过大

当前工作树同时包含大量 GLB、纹理、shader、网络、战斗、法术、UI、文档和测试变更，以及大量未跟踪文件。架构修复与资产生产混在同一快照，显著提高误提交、回归定位和发布复现成本。建议按领域拆分提交并建立可复现测试基线，禁止盲目 `git add -A`。

---

## 已确认保持关闭/改善

1. 身份唯一性：稳定 ClientIdentity + 在线重复 GUID 拒绝。
2. 移动频率作弊：per-peer 最新输入缓冲 + 服务器固定 tick。
3. 专服轻量碰撞链已接入生产入口。
4. 攻击上下文、硬冷却和七流派武器伤害倍率已统一进入策略层。
5. 库存默认容量已引用单一常量。
6. 装备材料/符文/未知类别拒绝、武器/护甲类别、双手/盾互斥已落地。
7. SessionRoot 测试为 69/69、0 orphan、退出 0。
8. `forward_plus + mobile` 与 Windows/Android presets（Android arm64）保持有效。
9. SpellAuthority 世界执行器为会话实例，预算失败时资源原子回滚有效。

---

## 验证结果

### gdUnit4

- `session_root_test.gd`：**69/69**，0 orphan，exit 0。
- 身份/输入缓冲/服务器马达/攻击上下文/攻击冷却/性能预算：**43/43**，0 orphan，exit 0。
- `equipment_policy_test.gd`：**13/13**，0 orphan，exit 0。
- 法术网络/事务/世界执行：**20/21**，0 orphan，exit 100。
  - 唯一失败：`spell_world_executor_test.gd::test_spell_authority_connects_world_executor`，过时源码字符串断言。

合计：**145/146，0 orphan**。

### 加载扫描

`tools/load_check.gd` 进程结束，但日志包含多项依赖 Compile Error，同时脚本错误地打印“全部成功”。因此本轮不把它计为解析通过。

### 未执行

真实 ENet 双客户端/重连、专服真实地牢碰撞端到端、远端自目标法术、projectile 命中、field/summon 异步事件复制、Windows/Android 实际导出、Android 真机 GPU/热稳定性、窗口视觉验收、全量 gdUnit4。

---

## 建议整改顺序

1. 先建立 SessionRoot `SpellEffectPort + event outbox`，关闭远端玩家状态、projectile 与持续事件复制。
2. 严格校验护甲固有部位并补两层反例。
3. 修复过时法术测试与解析门禁，保证失败真的能阻断。
4. 增加专服真实 seed collision-only 端到端测试。
5. 接服务器可信远端存档仓。
6. 建立统一视觉质量协调器并重应用现存资源。
7. 清理多人领域中的 `GameState.current_player` 回退。
8. 按领域拆分当前巨型工作树，再做发布候选验证。
