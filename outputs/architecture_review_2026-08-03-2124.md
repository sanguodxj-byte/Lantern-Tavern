# Lantern Tavern 架构审查（2026-08-03 21:24 · 增量复核）

**性质**：只读审查；复核 19:10 法术/装备整改和 20:40 独立复核结论。  
**结论**：**C+（发布阻断尚未清零）**。装备固有部位、法术事务原子性、ray 单次伤害端口、异步 outbox 已真实关闭；但当前联机垂直切片的“权威实体”仍只是无碰撞的表现代理，导致 ray / projectile 的真实命中链在生产场景无法到达权威实体端口。另有远端自目标法术组件缺失，属于功能阻断。

---

## 1. P0：联机法术没有可命中的权威实体物理节点

### 证据链

1. `scenes/multiplayer/dungeon_session_controller.gd:135-170` 只把敌人写入 `SessionRoot._entities` 字典，并经 `NetworkManager.server_spawn_entity()` 广播。
2. `globals/multiplayer/multiplayer_scene_bridge.gd:205-220` 将其物化为 `multiplayer_entity.tscn`。
3. `scenes/multiplayer/multiplayer_entity.tscn:14-30` 根节点是 `Node3D`，只有 `MeshInstance3D` 与 `Label3D`，**没有 StaticBody3D/CharacterBody3D/Area3D，也没有 CollisionShape3D**。
4. `scenes/multiplayer/multiplayer_scene_bridge.gd:212-220` 仅设置脚本字段 `ent.entity_id`，没有 `set_meta("entity_id", ...)`。
5. `globals/combat/spell_world_executor.gd:111-117` 的 ray 使用物理空间 `intersect_ray()`；无碰撞节点时目标永远不可命中。
6. `scenes/equipment/projectile_entity.gd:263-275` 依赖 `body_entered`，且只有碰撞体带 `entity_id` meta 才进入会话伤害端口；当前代理两项都不满足。

### 影响

- ray 类法术可返回 `ok=true`、扣法力并提交冷却，但 `target=null`、`damage_applied=0`。
- projectile 会飞过字典代理/可见胶囊，不触发 `body_entered`，因此不会写回 `_entities`、不会生成 HP/死亡/掉落复制事件。
- 现有测试 `spell_session_atomicity_test.gd:178-201` 直接调用 outbox 端口，不经过真实投射物碰撞；`spell_world_executor_test.gd:49-76` 手工创建带 meta 的 Node3D，也不代表生产场景。

### 建议

建立服务器侧 `AuthoritativeEntityBody`：每个 `_entities` 中可受击实体必须对应有碰撞体的 Node3D/PhysicsBody3D，并在碰撞根节点上设置 `entity_id` meta；spawn/update/despawn 与实体仓同事务维护。客户端可以继续使用纯表现代理，但服务器不可把表现代理当权威碰撞体。

---

## 2. P0：远端 heal / barrier / buff 在正常 avatar 上必定失败

### 证据链

- 远端玩家 caster 绑定到 `multiplayer_avatar.tscn`：`multiplayer_scene_bridge.gd:111-121`。
- 该 avatar 只有 `CharacterBody3D + Mesh + CollisionShape + Label`，见 `multiplayer_avatar.tscn:15-32`，没有 `health`、`buffs`、`mana` 组件。
- `SpellAuthority.execute()` 对 heal 要求 `caster.health.heal`（`spell_authority.gd:51-55`），对 barrier/buff 要求 `caster.buffs.add`（`58-61`, `67-71`）；缺失即返回失败。
- `SessionRoot._handle_cast_spell()` 会在执行失败时拒绝且不扣资源（`session_root.gd:776-779`），事务安全是对的，但远端玩家功能不可用。

### 影响

远端玩家的治疗、屏障、增益三类法术无法施放；房主真实 Player 可用，形成 host/client 行为分叉。

### 建议

不要把组件状态寄托在表现 avatar 上。引入 per-peer `SpellEffectPort` / `PlayerEffectState`，让 heal/barrier/buff 写入 `PlayerContext` 权威生命/护盾/增益状态，再同步到真实 Player/avatar；caster Node3D 仅提供空间变换和物理载体。

---

## 3. P1：entity_snapshot 采用不可靠传输但缺少周期基线追平

- `NetworkManager._is_high_frequency_event()` 把 `EVT_ENTITY_SNAPSHOT` 归为 unreliable（`network_manager.gd:351-369`）。
- 非致死伤害只产生一次 entity_snapshot；丢包后，如果该实体不再变化，客户端 HP 可永久停留在旧值。
- 现有全量 `session_snapshot` / reconcile 只在重连或显式调用时追平，不是周期状态基线。

**建议**：HP/关键状态使用 reliable ordered，或保留 unreliable 但每 0.5~1 秒发送完整/增量权威基线并带 revision；死亡/despawn 继续 reliable。

---

## 4. P1：projectile 生命周期仍属于全局场景/全局对象池，不属于 SessionRoot

- `SpellAuthority` 通过 autoload `/root/ProjectileService` 生成投射物（`spell_authority.gd:72-89`）。
- `ProjectileService._get_spawn_parent()` 优先 `GameState.current_level` / `SceneTree.current_scene`（`projectile_service.gd:389-402`），不是会话 world。
- 对象池是 autoload 全局池（`projectile_service.gd:35-36, 349-379`），场景/会话切换若未显式 `clear_pool()`，投射物状态和 Callable 端口可能跨会话残留。

**建议**：为联机法术增加会话级 ProjectileSpawner/Pool，或至少让 `spawn()` 接受显式 parent/session token，并在 SessionRoot teardown 时统一回收和清空端口。

---

## 5. 已关闭项确认

- EquipmentPolicy 护甲固有部位与显式多部位数组校验已闭合。
- ray 实体伤害端口只调用一次；端口拒绝会使世界执行失败。
- world executor 为 SessionRoot 实例持有，不再 static 跨会话共享。
- field/summon/projectile 的异步实体事件进入 outbox；`NetworkManager.tick()` 会排空并广播。
- caster 未绑定、资格不符、法力不足、冷却中、projectile spawn 失败、field 预算满均在资源 commit 前拒绝。

---

## 6. 本轮验证

| 套件 | 结果 | orphan | runner exit |
|---|---:|---:|---:|
| spell_world_executor_test | 8/8 | 0 | 0 |
| spell_session_atomicity_test | 15/15 | 0 | 0 |
| equipment_policy_test | 15/15 | 0 | 0 |
| spell_network_completion_test | 4/4 | 0 | 0 |
| session_root_test | 72/72 | 0 | 0 |
| **合计** | **114/114** | **0** | **0** |

说明：这些测试证明纯逻辑端口与事务边界正确，但没有覆盖“生产实体代理具备可命中物理体”以及“远端 avatar 具备权威自目标状态”这两个真实接缝，因此全绿不能消除上述 P0。

---

## 7. 工作树与审查边界

- 本轮未修改业务代码。
- 当前工作树存在用户既有 WIP：`tools/enemy_attack_action_capture.gd` 已修改，另有其 `.uid` 未跟踪；本轮未触碰。
- 两个并行只读审查代理均因 403 鉴权失败，结论由主流程逐文件复核。

## 8. 下一步优先级

1. **P0**：建立服务器权威实体物理节点映射（碰撞体 + entity_id meta + spawn/update/despawn 生命周期）。
2. **P0**：建立 per-peer 自目标效果状态端口，消除真实 Player 与远端 avatar 的组件分叉。
3. 增加真实行为测试：ray `intersect_ray` 命中生产实体场景、ProjectileEntity `body_entered` 写回、远端 heal/barrier/buff 成功且事件同步。
4. **P1**：修复 entity_snapshot 丢包后无周期收敛；会话化 projectile 生成与对象池。
