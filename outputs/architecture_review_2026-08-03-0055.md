# Lantern Tavern 架构审查（2026-08-03 00:55）

## 结论

本轮为相对 `outputs/architecture_review_2026-08-02-2339.md` 的增量只读复审。上一轮确认的 4 个 P0 **全部仍存在**，没有看到权威边界层面的实质关闭；Windows/Android 导出预设与 Mobile renderer 修复仍保持有效。

当前不建议进入多人发布、专用服务器发布或 Android 发布。阻断项仍集中在：稳定身份、专服移动、联机法术世界写回、装备事务。另有 7 个 P1 需要在发布门禁前收口。

---

## P0 — 必须先修

### P0-1 真实大厅仍使用固定默认 GUID，服务器仍允许在线重复 GUID 覆盖

**证据**

- `scenes/ui/lobby_menu.gd:218-225` 调用 `join_room(addr, port)`，没有传入本地持久化身份。
- `globals/multiplayer/multiplayer_session.gd:79-90` 默认 `player_guid="client"`，并将其发给服务器。
- `globals/multiplayer/session_root.gd:170-194` 在创建 `PlayerContext` 后直接注册该 GUID。
- `globals/multiplayer/connection_authority.gd:35-45` 的 `register_online()` 返回 `void`，对 `_guid_to_peer[player_guid]` 直接覆盖，不拒绝已 ONLINE 的同 GUID。
- `globals/multiplayer/save_authority.gd:8,23` 与 `session_root.gd:845-880` 继续以 GUID 作为结算/幂等身份锚。
- `connection_authority_test.gd` 现有 29 例没有“两个在线 peer 使用同 GUID，第二个必须失败”的行为测试。

**故障链**

两个真实远端玩家均以 `client` 加入时，第二次注册覆盖稳定身份索引；重连可能接管错误上下文，出征结算也会共享幂等键。

**建议**

- GUID 必须由本地存档/账号生成并持久化，Lobby 明确传入。
- `register_online()` 返回结果；同 GUID 已 ONLINE 时拒绝 spawn，只有合法 token 的 GRACE 状态允许迁移。
- 新增重复 GUID、结算隔离、重连唯一接管测试。

### P0-2 专用服务器仍是无碰撞的逐 RPC 固定积分，可穿墙且可按发送频率加速

**证据**

- `scenes/multiplayer/dedicated_server.gd:13-14,94-100` 明确使用 `build_authority_only()`，不构建碰撞几何。
- `scenes/multiplayer/dungeon_session_controller.gd:38-52` 只生成 layout 和出生点；真实碰撞只在 `build_and_enter()` 的 `DungeonSceneBuilder.build()` 路径生成（`54-76`）。
- `globals/multiplayer/session_root.gd:590-600` 每收到一条 `CMD_INPUT` 就立刻调用移动结算，固定传入 `SERVER_TICK_DT=1/30`。
- `globals/multiplayer/movement_authority.gd:64-80` 无有效 `CharacterBody3D` 时按固定 `dt` 积分。
- `globals/core/network_manager.gd:561-567` 每条可靠 RPC 都立即执行 `_server_handle_command()`；`tick()` 只推进时钟、快照和心跳（`366-379`），没有 per-peer 最新输入缓冲或固定服务器移动步进。
- `movement_authority_test.gd` 与 `server_character_motor_test.gd` 验证了纯积分和有墙马达，但没有专服模式、30/60/120Hz 等时位移一致性测试。

**故障链**

专服没有墙体裁决，合法方向输入可穿墙；客户端以 60/120Hz 发送递增 sequence 时，每条 RPC 都获得一次 1/30 秒位移，速度可按发送频率放大。

**建议**

- 专服构建仅碰撞的服务器地牢表示，不需要 Mesh/材质。
- RPC 只覆盖 per-peer 最新输入；位移仅在服务器固定 `_physics_process` 中每 peer 消费一次。
- 增加专服穿墙和输入频率不变性集成测试。

### P0-3 联机法术仍不写回 `SessionRoot._entities`，并在世界执行失败后仍提交资源与成功事件

**证据**

- 普通攻击在 `session_root.gd:510-535` 将伤害写回 `_entities`，产生 snapshot/despawn。
- 法术在 `session_root.gd:683-707` 先扣法力、提交冷却，再调用 `SpellAuthority.execute()`；没有检查 `authority_execution.ok` 或 `world_execution.ok`，也没有更新 `_entities`。
- `globals/combat/spell_world_executor.gd:25-67,105-148` 只查询场景 Node 并调用 `try_receive_hit`/`health.take_damage`。
- `globals/combat/spell_authority.gd:53-59` 产生/执行场景世界请求，未注入 `EntityRepository`/`WorldCombatPort`。
- `spell_session_atomicity_test.gd`、`spell_world_executor_test.gd`、`spell_network_completion_test.gd` 共 16 例通过，但没有断言施法后 `SessionRoot._entities[target].current_life` 下降；现有测试只覆盖资源、协议、预算结构和视觉消费。

**故障链**

ray/area/ground/summon 可消耗法力并进入冷却、广播成功 FX，但权威敌人字典不变；字段/召唤预算失败也会被包装为成功施法。

**建议**

- 将会话级 `EntityRepository/WorldCombatPort` 注入法术执行器，所有目标选择、伤害、死亡、掉落、snapshot 都走与普通攻击同一实体仓。
- 世界/预算/目标可执行性在资源 commit 前 prepare；执行失败必须回滚或拒绝，不得发布成功事件。
- 新增 ray/area/ground/summon 对 `_entities` 的真实写回测试。

### P0-4 装备命令仍允许材料/符文污染装备槽，且协议槽位类型不一致

**证据**

- `session_root.gd:750-785` 只检查 item 是否存在于 `materials/runes/equipment` 任一字典，然后直接 `set_weapon_slot()` / `set_armor_slot()`。
- `globals/core/state/equipment_loadout.gd:19-34` 仅校验槽索引或槽名，不校验物品类型、护甲部位、武器类别、双手占槽。
- `scenes/multiplayer/client_command_driver.gd:232-245` 将 `slot` 固定为 `String`，而服务端武器槽分支要求 `slot is int`。
- `tests/gdunit/session_root_test.gd:615-621` 的“成功装备”测试故意把 `iron_ore` 材料装入武器槽，实际把漏洞固化为预期行为。
- `InventoryTransferService` 只负责库存字典整堆转移（`globals/core/inventory_transfer_service.gd:19-67`），没有被装备事务使用。

**故障链**

客户端可把材料/符文/错误类别装备写入 loadout，污染攻击类型、法术资格、存档与后续结算；真实客户端又无法用 String 参数表达服务端期望的 int 武器槽。

**建议**

建立唯一 `EquipmentPolicy + EquipmentTransaction`：从权威注册表解析 item kind、槽位兼容、双手/盾规则，并原子处理背包移除、旧装备返包、loadout 更新；协议使用明确的 `slot_kind + slot_index/slot_name` 联合结构。

---

## P1 — 高优先级架构债

### P1-1 `SpellAuthority` 的世界执行器仍静态跨会话共享

`globals/combat/spell_authority.gd:9,56-59` 使用 `static var _world_executor`。同进程多个会话或重开世界时，字段/召唤预算与节点归属可能串到旧世界。应由 `SessionRoot` 实例持有并释放。

### P1-2 远端玩家仍没有可信存档来源

`network_manager.gd:546-555` 正确忽略远端客户端 save_state，关闭了注入漏洞；但 `multiplayer_session.gd:79-90` 只发送固定 GUID 和空状态。服务器没有账号/存档仓，远端默认空装备、空法术装配。不能恢复信任客户端字典，应建立认证后的服务器持久化来源。

### P1-3 已决定的流派武器伤害倍率仍未进入统一结算

- `damage_resolver.gd:33-65` 仅双手有占位 `damage_mult=1.0`；其余已决定倍率缺失。
- `attack_context_factory.gd:52-73,135-157` 只应用武器资源自己的 `damage_mult`，没有按 style/hand 应用文档已决定倍率。

该倍率只能乘武器伤害，不能乘法术伤害。

### P1-4 库存默认容量仍有双真相

`globals/core/state/expedition_inventory.gd:10,20` 定义 `DEFAULT_LIMIT=30`；`globals/core/game_state.gd:32,455` 又定义并写入 `DEFAULT_CARRIED_SPACE_LIMIT=30`。应由库存模型单一持有默认值，GameState 调模型 reset API。

### P1-5 性能分档仍只有 3D render scale，灯光与 FX 无消费者

- `performance_budget_controller.gd:102-113` 只设置 Viewport FSR scale 并发 `quality_tier_changed`。
- 全仓库没有该信号的连接；`perf_monitor.gd:73-77` 仅读取显示。
- `lighting_controller.gd:47-63` 自行按 renderer 检测独立三档，未与 PerformanceBudget 的四档联动。

结果是粒子、动态灯、阴影、雾、法术 FX、LOD 和反射成本不会随实时性能降级。

### P1-6 `SessionRoot` 仍有 4 orphan，测试门禁退出 101

`session_root_test.gd` 63/63 断言通过，但检测 4 orphan，gdUnit 退出 101。现有工作流如果只看断言数会误判绿色；必须定位并清理生命周期泄漏，CI 应将 101 视为失败。

### P1-7 地牢运行时仍以 `GameState.current_player` 表达单玩家全局所有权

`scenes/expedition/dungeon_runtime.gd:148,214,469,502,523,548-549`、`procedural_dungeon.gd:159-160,225`、`extraction_portal.gd:193` 仍从全局单玩家引用取对象。当前联机另有 `PlayerContext`，但表现/流式/撤离逻辑继续依赖全局单玩家语义，后续多人整合容易错控房主或本地玩家。建议显式注入 local player/session player resolver。

---

## 已确认保持关闭/有效

1. 远端 spawn 客户端存档注入仍被忽略；安全专项 3/3。
2. 客户端伪报 `attack_type` 仍被白名单拒绝；攻击上下文专项 12/12。
3. 单机/联机攻击冷却仍共用 `AttackCadencePolicy`；专项 9/9。
4. listen-server 在绑定 `CharacterBody3D` 时仍走真实碰撞马达；专项 6/6。专服问题不因此关闭。
5. caster 未绑定和基础资格/法力/冷却预检仍在资源提交前拒绝；法术原子性专项 8/8。
6. `project.godot:177-181` 仍为桌面 `forward_plus`、移动 `mobile`。
7. `export_presets.cfg:51-179` 仍包含 Windows Desktop 与 Android arm64 预设。

---

## 验证结果

- Godot 4.7 headless editor 全项目解析扫描：退出 0，无脚本解析错误。
- `session_root_test.gd`：63/63 通过，**4 orphan，退出 101**。
- 身份与移动：`connection_authority_test` 29/29、`movement_authority_test` 12/12、`server_character_motor_test` 6/6；合计 47/47，0 orphan，退出 0。
- 法术：`spell_session_atomicity_test` 8/8、`spell_world_executor_test` 4/4、`spell_network_completion_test` 4/4；合计 16/16，0 orphan，退出 0。
- 性能/光照：4/4 + 12/12；合计 16/16，0 orphan，退出 0。
- spawn 安全/攻击上下文/冷却：3/3 + 12/12 + 9/9；合计 24/24，0 orphan，退出 0。

未执行：全量 gdUnit4、真实 ENet 双客户端/专服集成、30/60/120Hz 输入压测、实际 Windows/Android 导出、Android 真机 GPU/热稳定性、窗口 3D 视觉验收。

---

## 建议整改顺序

1. 唯一 GUID + 在线重复身份拒绝 + 重连接管行为测试。
2. 专服固定 tick 输入缓冲 + 仅碰撞地牢表示。
3. 法术注入会话实体仓，prepare/execute/commit 原子化。
4. 装备策略与库存/loadout 原子事务，修正协议槽位类型。
5. 将已决定 `damage_mult` 仅接入武器伤害路径。
6. 清除 SessionRoot orphan；将退出 101 纳入严格失败门禁。
7. 接通 RenderingProfile/PerformanceBudget 消费者并做 Android 真机验证。

## 工作树风险

当前工作树仍包含大量已修改和未跟踪文件；本审查基于当前磁盘状态，不代表可复现的干净提交。审查期间未修改业务代码、场景、资产或项目配置。
