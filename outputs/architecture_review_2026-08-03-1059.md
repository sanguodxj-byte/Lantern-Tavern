# Lantern Tavern 架构审查（2026-08-03 10:59）

## 执行结论

本轮为相对 `outputs/architecture_review_2026-08-03-0828.md` 的增量只读复审。结论发生明显变化：此前 4 个 P0 中，**身份唯一性、专服输入频率/碰撞、装备类别基础策略已实质收口**；但法术闭环仍有发布阻断，装备护甲部位兼容仍有策略缺口。

- **P0：2 项**：联机法术仍未形成统一的玩家/实体事务与复制闭环；护甲可被放入错误的有效护甲槽。
- **P1：4 项**：远端可信存档缺失、性能分档只部分接入、多人地牢仍有单玩家全局依赖、专服碰撞链缺端到端门禁。
- **P2：3 项**：shader Inspector 参数提示不统一、法术旧源码契约测试失效、并行 gdUnit 报告目录冲突。
- 关键专项共 **209/210** 通过，0 orphan；唯一失败为 `spell_world_executor_test.gd` 的过时源码字符串断言。
- `session_root_test.gd` 已从此前 63/63 + 4 orphan 改善为 **69/69、0 orphan、退出 0**。
- Godot editor 完成项目扫描，未见 Parse Error；退出阶段仍报 `EditorSettings not instantiated yet`，因此不能算“零诊断”的严格门禁。

> 基线风险：工作树包含大量已修改与未跟踪源码、资产和测试。本报告描述当前磁盘快照，不代表干净提交或可复现发布候选。

---

## P0 — 发布阻断

### P0-1 联机法术仍不是统一权威事务：玩家自目标、位移、投射物和复制链各自分叉

**状态：旧问题部分关闭，但核心发布闭环仍未关闭。**

#### 已关闭部分

- `globals/multiplayer/session_root.gd:720-793` 已改为 `execute -> verify -> commit -> publish`，世界执行失败时不扣法力、不提交冷却。
- `globals/combat/spell_authority.gd:15-32` 的世界执行器已由实例持有，不再是跨会话 `static var`。
- `session_root.gd:795-831` 与 `spell_world_executor.gd:15-17` 已建立 `damage_entity_port`，ray/field/summon 可写回 `_entities`。
- `spell_session_atomicity_test.gd` 的预算失败回滚、实体生命/死亡/掉落写回和会话隔离测试均通过。

#### 仍阻断发布的证据

1. **远端玩家自目标法术会“成功但无效果”**
   - `globals/multiplayer/multiplayer_scene_bridge.gd:111-114` 明确说明服务器远端 avatar 只是位置代理，没有真实 `health/buffs`。
   - `scenes/multiplayer/multiplayer_avatar.gd:12-38` 仅保存 peer、位置和朝向。
   - `globals/combat/spell_authority.gd:49-66` 对 heal/barrier/buff 只在组件存在时修改，但组件不存在仍保持 `ok=true`；movement 直接改 avatar `global_position`。
   - `session_root.gd:766-793` 看到 `ok=true` 就扣法力、提交冷却并广播成功。结果是专服远端治疗/护盾/增益可消耗资源却不改变权威 PlayerContext；位移法术也未写回 `_live_state`，会被后续玩家快照覆盖。

2. **projectile 法术绕过 SessionRoot 权威实体仓**
   - `spell_authority.gd:67-74` 直接调用全局 `ProjectileService.spawn()`；spawn 返回 null 也不会转成失败。
   - `scenes/equipment/projectile_entity.gd:263-328` 只对真实 `Enemy` 或带 `try_receive_hit` 的节点结算。
   - `scenes/multiplayer/multiplayer_entity.gd:1-68` 是无碰撞、无 `try_receive_hit` 的表现节点；服务器真正敌人仍只是 `SessionRoot._entities` 字典。
   - 因此专服/联机的主要 projectile 法术没有可信命中与 `_entities` 写回路径，可能只生成视觉/物理节点后结算不到权威敌人。

3. **ray/field/summon 的实体事件没有进入网络复制出口**
   - `session_root.gd:811-831` 返回 `entity_snapshot/entity_despawned/entity_spawned/progression` 事件数组，但自身不发布。
   - `spell_world_executor.gd:45-48,86-90,141-147` 调用伤害端口后，field/summon 忽略返回事件；ray 只把它嵌在 `port_result`。
   - `NetworkManager._server_handle_command()` 只分发顶层 `event` 与 `extra_events`（`globals/core/network_manager.gd:255-266`），而 `_handle_cast_spell()` 没有返回 `extra_events`。
   - 结果：服务器 `_entities` 可能已扣血/死亡，但客户端收不到对应实体快照、死亡、掉落和成长事件。

#### 最小修复边界

建立 SessionRoot 拥有的统一 `SpellEffectPort`：

1. heal/barrier/buff/movement 只修改 `PlayerContext + _live_state`，不直接依赖 avatar 组件。
2. projectile 进入会话级权威投射物模拟，目标查询和伤害都基于 `_entities`/服务器碰撞代理；`spawn == null` 必须失败且不 commit。
3. 所有即时/持续伤害返回的实体事件进入统一 outbox，由 NetworkManager 分发；持续场和召唤 tick 也必须可异步 flush。
4. 补专服远端 heal/barrier/movement、projectile 命中、field tick、死亡掉落与客户端复制端到端测试。

### P0-2 EquipmentPolicy 未校验护甲固有部位，任意有效护甲槽可被错误覆盖

**状态：类别与武器占槽已关闭，但护甲部位兼容未关闭。**

**证据**

- `globals/core/equipment_policy.gd:55-64`：护甲请求若显式传入 `slot_name`，只检查其是否属于 `VALID_ARMOR_SLOTS`，没有要求它等于物品元数据 `armor_slot`。
- 因此 `leather_cap(armor_slot=head)` 可被请求放入 `body`；这仍会污染权威 loadout，影响存档、属性与表现。
- `tests/gdunit/equipment_policy_test.gd:49-67` 只测了正确部位和非法槽名，没有“头盔进 body / 胸甲进 head 必须拒绝”的反例。

**最小修复边界**

`target_name` 必须严格等于注册表 `meta.armor_slot`；如允许多部位装备，元数据应显式提供 `allowed_armor_slots:Array`，不能由客户端自由选择任一有效槽。补 SessionRoot 端到端反例。

---

## P1 — 高优先级架构债

### P1-1 远端玩家仍没有可信服务器存档来源

`globals/core/network_manager.gd:575-586` 正确忽略客户端自报存档；但 dedicated server 的远端 spawn 仍以空存档创建默认 inventory/loadout/spell_state。当前安全性正确、可玩性未闭环。应接账号/服务器存档仓，绝不能重新信任客户端字典。

### P1-2 性能预算只接通 LightingController 的“档位变量”，没有完整视觉成本消费者

- `globals/lighting/lighting_controller.gd:47-67` 已订阅 `PerformanceBudget.quality_tier_changed`，此前“两套完全断开的真相”已部分关闭。
- 但回调只修改 `_quality_tier`；既有火把的 `omni_range` 在 `apply_tavern_profile()` 时一次性写入（`91-119`），降档后不会重应用范围。
- 阴影、粒子、雾、反射、法术 FX、LOD 仍没有统一消费者；当前动态预算主要是 FSR scale + 闪烁幅度变化。

建议建立 `VisualQualityCoordinator`，集中映射 render scale、灯光范围/阴影、粒子预算、雾、反射和 FX 上限；变档时立即重应用现存资源。

### P1-3 多人领域逻辑仍混用 `GameState.current_player`

`scenes/expedition/dungeon_runtime.gd`、`procedural_dungeon.gd`、`extraction_portal.gd` 和 `scenes/characters/enemies/enemy.gd` 仍多处读取全局 `current_player`。联机战斗主链已转 per-peer context，但撤离、敌人目标、地牢交互及部分击杀回退仍可能落到本地/房主玩家。

建议将地牢领域接口改为显式 `peer_id/PlayerContext/player_node`，只允许单机适配层读取 GameState。

### P1-4 专服碰撞实现存在，但缺真正 authority-collision 端到端门禁

- `dedicated_server.gd:89-103` 已调用 `build_authority_collision_only()`。
- `dungeon_session_controller.gd:54-72` 已构建仅静态碰撞地牢。
- `NetworkManager.tick()` + `SessionRoot.queue_input()/consume_input_tick()` 已把移动与 RPC 频率解耦。
- 但测试仓未找到 `build_authority_collision_only()` 的实际测试；现有 `server_character_motor_test` 只用人工墙体验证马达。

建议新增真实 seed 地牢、服务器 avatar、连续撞墙、30/60/120Hz 输入一致性的端到端测试，并验证碰撞层/掩码。

---

## P2 — 中优先级质量债

### P2-1 Shader Inspector 参数提示仍不统一

- `scenes/tavern/materials/tavern_atlas_world_32px.gdshader:6-24` 多个 artist-facing float 无 `hint_range`。
- `liquid.gdshader` 已把颜色/混合系数和标量参数提示补齐；vec2 无 `hint_range` 是 Godot 语法限制，不应继续误报。
- 当前未发现 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 的移动端阻断。

### P2-2 法术源码契约测试已过时

`tests/gdunit/spell_world_executor_test.gd:37-41` 仍断言源码包含 `_world_executor.execute`；实现已重构为局部 `executor.execute`，行为测试已证明实例执行器工作。该测试本轮唯一失败，属于脆弱字符串测试，不是运行时功能回归。

### P2-3 并行 gdUnit 报告目录冲突

并行批次多次写入同一 `reports/report_3790`/`report_3792`，HTML/XML 报告可能互相覆盖。控制台统计可信，但报告归档不可信。CI 应为每个 runner 注入唯一报告目录或改为串行生成报告。

---

## 已确认关闭/改善

1. **身份唯一性关闭**：`MultiplayerSession.join_room()` 使用 `ClientIdentity.load_or_create()`；`ConnectionAuthority.register_online()` 拒绝在线重复 GUID；SessionRoot spawn 前预检并失败回滚。
2. **移动频率作弊关闭**：RPC 仅覆盖 per-peer 最新输入，服务器固定 30Hz 消费；30Hz 与 120Hz 位移一致测试通过。
3. **专服轻量碰撞已接入**：dedicated server 使用 collision-only 地牢，远端 avatar 为 CharacterBody3D 并绑定 SessionRoot。
4. **攻击上下文/冷却/流派倍率收口**：AttackContextFactory、AttackCadencePolicy 和七流派 `damage_mult` 契约测试通过；流派倍率只乘武器伤害。
5. **库存默认容量单一真相**：GameState 已引用 `ExpeditionInventory.DEFAULT_LIMIT`，旧重复常量已移除。
6. **装备基础策略收口**：材料/符文/未知物品拒绝，武器/护甲类别、双手/盾互斥与协议字段已有独立策略和测试。
7. **SessionRoot 测试生命周期修复**：69/69、0 orphan、退出 0。
8. **桌面/Android 配置有效**：`forward_plus + mobile`，Windows/Android presets 存在，Android arm64 开启。

---

## 验证结果

### 通过（唯一测试计数）

- 身份与连接：39/39
- 输入缓冲、服务器移动马达、MovementAuthority：23/23
- 装备策略：13/13
- 性能预算与光照：18/18
- SessionRoot：69/69，0 orphan，退出 0
- 攻击上下文与冷却策略：24/24
- spawn 存档安全：3/3
- 法术专项：20/21

总计：**209/210，0 orphan**。

### 失败

- `spell_world_executor_test.gd::test_spell_authority_connects_world_executor`：源码字符串断言过时，runner 退出 100。

### 编辑器扫描

Godot 4.7 editor 完成 filesystem scan、autoload、plugin、reimport 和 editor layout，未见 Parse Error；关闭阶段报：

`EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit"`

因此记录为“解析扫描完成但退出诊断不干净”。

### 未执行

真实 ENet 双客户端/重连、专服真实地牢碰撞端到端、法术 projectile/持续场网络复制、Windows/Android 实际导出、Android 真机 GPU/热稳定性、窗口视觉验收、全量 gdUnit4。

---

## 建议整改顺序

1. 建立 SessionRoot 统一 SpellEffectPort 与异步事件 outbox，先修远端 heal/barrier/movement、projectile 和持续伤害复制。
2. 严格校验护甲固有部位，补错误有效槽反例。
3. 增加 dedicated collision-only 真实地牢端到端门禁。
4. 接入服务器可信远端存档仓。
5. 建立统一视觉质量协调器并重应用现存灯光/FX资源。
6. 清理多人领域中的 `GameState.current_player` 回退。
7. 把法术源码字符串测试改为行为/接口测试，隔离并行测试报告目录。
8. 补齐 shader artist-facing 标量 uniform hints。

---

## 执行限制

本轮尝试并行启动联机、战斗和渲染三名只读复核代理，三者均在执行前因认证层 403 失败；主审查流程已直接完成源码复核与测试，未伪造代理结论。本轮未修改业务源码、场景、资产或配置，只生成审查报告与执行记录。