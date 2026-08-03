# Lantern Tavern 架构审查（2026-08-03 22:18 · 增量复核）

**性质**：只读架构审查；基于 21:24 报告继续复核联机会话、法术世界执行、实体复制与测试门禁。  
**结论**：**C+（仍有发布阻断）**。21:24 报告中的“权威敌人物理体缺失”和“远端自目标法术直接失败”已经完成代码收口；但这轮进一步确认：远端 heal/barrier/buff 目前只是写入一份不参与生命、伤害和状态结算的摘要字典，召唤物也无法发现生产联机敌人。因此法术垂直切片仍未真正闭环。

---

## 1. 已关闭：服务器敌人已有可命中的权威物理体

### 证据

- `globals/multiplayer/multiplayer_scene_bridge.gd:206-225` 在服务器侧生成实体后调用 `_attach_authoritative_entity_body()`。
- `multiplayer_scene_bridge.gd:228-251` 为 `kind == "enemy"` 创建 `StaticBody3D + CapsuleShape3D`，使用 `PhysicsSetup.LAYER_ENEMY`，并在碰撞体上写入 `entity_id` meta。
- `globals/combat/spell_world_executor.gd:110-138` 的 ray 命中后可沿祖先查找 `entity_id`，经会话伤害端口写回 `_entities`。
- `scenes/equipment/projectile_entity.gd:264-312` 的 projectile 碰撞路径使用相同祖先查找与 `damage_port`。

### 验证

`multiplayer_entity_authority_test.gd` 4/4 通过，确认生产桥接装配路径、碰撞层、胶囊形状和祖先身份查找。

> 注意：该测试运行时仍输出“节点不在活动场景树”错误，但断言结果通过；这是测试夹具问题，见第 6 节。

---

## 2. P0：远端 heal/barrier/buff 只是“记账成功”，没有进入权威战斗状态

### 证据链

1. `globals/multiplayer/session_root.gd:862-881` 的 `_apply_self_effect()` 对远端无组件 avatar 只调用 `ctx.record_spell_effect()`；节点没有 `health/buffs` 时不会产生真实生命或状态副作用。
2. `globals/core/player_context.gd:43-58` 的 `spell_effect_state` 仅保存：
   - `healed_total`（累计治疗量，不是当前生命）；
   - `absorb`；
   - `buff_duration`；
   - `last_effects` / `updated_at`。
3. 全项目没有伤害结算、生命系统或法术倍率读取 `spell_effect_state`；`SessionRoot._live_state` 也只维护 `is_alive/position/facing`，没有权威 `current_life/max_life`。
4. `PlayerContext.serialize_spell_state()`（`player_context.gd:60-67`）不包含 `spell_effect_state`，因此屏障/增益摘要不会进入服务器存档或重连快照。
5. `spell_session_atomicity_test.gd:169-197` 只断言字典值增加，未验证治疗改变当前 HP、护盾抵扣后续伤害、增益影响法术结算或持续时间到期。

### 影响

- 远端治疗可以扣蓝、进冷却、广播 FX，但没有可被后续伤害读取的当前生命值，等价于视觉/日志成功。
- 远端屏障不会抵扣任何攻击；增益不会改变法术伤害或其他权威公式，也没有权威过期推进。
- 重连后效果状态丢失；房主真实 Player 与远端 PlayerContext 继续存在两套语义。

### 建议

建立单一 `PlayerCombatState`（每 peer）：至少包含 `current_life/max_life`、物理/魔法护盾、带过期时间的 buff 列表。玩家伤害、治疗、屏障、增益、死亡、重连快照与事件复制全部只读写该状态；真实 Player/远端 avatar 仅消费状态做表现。删除“累计 healed_total 即治疗完成”的替代语义。

---

## 3. P0：召唤物无法发现生产联机敌人

### 证据链

- `globals/combat/spell_world_executor.gd:232-240` 的 `SpellSummon._nearest_enemy()` 只扫描场景组 `"enemies"`。
- 生产联机敌人由 `MultiplayerSceneBridge._spawn_entity_local()` 物化；`multiplayer_scene_bridge.gd` 未将实体根或 `AuthoritativeBody` 加入 `"enemies"` 组。
- `scenes/multiplayer/multiplayer_entity.gd` 同样没有入组逻辑。
- 因此专服/listen-server 的会话敌人即使已有碰撞体，也不会被召唤物选为目标；`damage_port` 永远没有调用机会。
- 当前 `spell_world_executor_test.gd` 只验证召唤节点被创建和预算受限，没有使用生产桥接实体验证自动寻敌与写回。

### 影响

召唤类法术会成功提交法力和冷却、生成有限时节点，但在真实联机会话中不攻击任何权威敌人。

### 建议

不要用表现层 group 作为权威目标索引。向 `SpellWorldExecutor` 注入会话级 `query_targets_port(origin, range, filters)`；查询 `SessionRoot._entities` 并返回实体 ID/位置，再由 `damage_entity_port` 结算。若短期保留 group，至少由服务器桥接层为权威实体入组并补生产接缝测试，但这只是过渡方案。

---

## 4. P1：周期实体基线仍实际走 unreliable，代码注释与行为相反

### 证据链

- `globals/core/network_manager.gd:413-419` 每 3 秒构造一次全量实体基线，并注释“reliable 通道”。
- 但它仍调用 `_dispatch_event(ev, 0)`。
- `_dispatch_event()`（`network_manager.gd:358-367`）会按事件类型路由；`_is_high_frequency_event()`（372-373）把所有 `EVT_ENTITY_SNAPSHOT` 一律发到 `rpc_server_event_unreliable`。

### 影响

周期重发提高了最终收敛概率，但不是可靠基线；网络持续丢包时仍无确定收敛保证，且代码注释会误导后续维护和测试。

### 建议

新增显式可靠出口，例如 `_dispatch_event_reliable()`，或给基线事件增加传输策略参数；不要仅凭相同事件名同时表达“高频增量”和“可靠基线”。测试应对 RPC 选择策略做断言，而不是只检查基线数组内容。

---

## 5. P1：投射物生命周期仍跨会话共享，SessionRoot 只持有悬空式引用

### 证据链

- `SpellAuthority` 仍从 autoload `/root/ProjectileService` 生成投射物（`spell_authority.gd:91-109`）。
- `ProjectileService.spawn()` 不接受显式 session parent，而是通过 `_get_spawn_parent()` 选择 `GameState.current_level/current_scene/root`（`projectile_service.gd:254-300, 389-402`）。
- 对象池是 autoload 全局数组（`projectile_service.gd:35-36, 349-379`）。
- `SessionRoot.track_projectile()` 只保存节点引用，投射物归池后不会从旧 session 列表注销；若同一池对象被后续会话复用，旧 session teardown 仍可能释放新会话正在使用的节点。

### 影响

单会话正常退出通常可清理，但边界不是严格的会话所有权；场景快速切换、重连/重建 session 或未来多会话专服会产生跨会话引用和错误回收风险。

### 建议

让 `ProjectileService.spawn()` 接受显式 owner/session token 与 parent；池按 session 隔离，或在归池时回调 owner 注销。SessionRoot teardown 只回收仍属于自己的 active projectile。

---

## 6. P1：权威实体测试“断言全绿但引擎报错”

`multiplayer_entity_authority_test.gd` 4/4、runner exit 0，但 stderr 出现：

- bridge 未进入活动场景树时使用绝对路径查 `/root/NetworkManager`；
- 实体容器未入树时写 `global_position`。

这说明当前门禁只看 gdUnit 断言和 exit code，会漏掉 Godot 引擎 ERROR。测试还残留 `DBG` 输出（`multiplayer_entity_authority_test.gd:25-27`）。

**建议**：测试夹具必须把 bridge 加入测试场景树并等待一帧，再走生产 `_ready()`；CI 将非白名单 `ERROR:` 视为失败，并移除调试打印。

---

## 7. 验证结果

| 验证项 | 结果 | orphan | runner exit | 备注 |
|---|---:|---:|---:|---|
| multiplayer_entity_authority_test | 4/4 | 0 | 0 | 有 Godot ERROR，断言仍通过 |
| spell_session_atomicity_test | 20/20 | 0 | 0 | 含预期的未注册 projectile warning |
| spell_world_executor_test | 8/8 | 0 | 0 | 通过 |
| spell_network_completion_test | 4/4 | 0 | 0 | 通过 |
| session_root_test | 72/72 | 0 | 0 | 通过 |
| **合计** | **108/108** | **0** | **0** | 不等于生产接缝完整 |

Godot 4.7 headless editor 解析扫描完成，exit 0；关闭阶段仍出现已知 `EditorSettings not instantiated yet` 诊断。未进行真实双进程 projectile/summon 行为测试，也未进行窗口模式视觉验收。

---

## 8. 当前优先级

1. **P0**：建立真正的 per-peer `PlayerCombatState`，让 heal/barrier/buff 进入生命、伤害、过期、死亡、快照与重连闭环。
2. **P0**：召唤物改用会话权威目标查询，补“生产桥接敌人 → 自动寻敌 → damage port → HP/死亡事件”的行为测试。
3. **P1**：为周期实体基线提供显式 reliable 发送路径。
4. **P1**：会话化 projectile parent、pool 与 owner 注销。
5. **P1**：CI 将 Godot `ERROR:` 纳入失败门禁，修正权威实体测试夹具。

## 9. 审查边界

- 本轮未修改业务代码。
- 审查开始时工作树为空；结束复核时出现 `scenes/multiplayer/dungeon_session_controller.gd`、`tools/dungeon_stress_perf_probe.gd` 的并发修改，以及 Godot 扫描生成的 `tests/gdunit/multiplayer_entity_authority_test.gd.uid`。本轮未触碰或清理这些文件；报告结论基于读取时版本。
- 并行探索代理因 WorkBuddy 客户端鉴权 403 未执行；结论由主流程逐文件复核。
