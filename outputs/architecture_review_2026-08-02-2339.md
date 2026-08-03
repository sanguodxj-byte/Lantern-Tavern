# Lantern Tavern 架构审查（2026-08-02 23:39）

## 结论

当前分支相较 22:19 复审已实质关闭多项旧 P0：远端 spawn 存档注入、客户端伪报 `attack_type`、攻击上下文分叉、攻击冷却三套公式、法术 caster 未绑定先扣资源、法术资格缺失、listen-server 移动穿墙、桌面/Android 导出预设缺失、Android renderer 配置错误。

但仍不建议进入多人发布或 Android 发布。当前仍有 **4 个 P0、6 个 P1**；其中最高风险集中在身份、专用服务器移动、联机法术权威世界、装备事务。

---

## P0 — 必须先修

### P0-1 真实大厅仍给所有远端客户端同一个 `player_guid="client"`

**证据**

- `scenes/ui/lobby_menu.gd:218-225` 调用 `ms.join_room(addr, port)`，没有传入存档身份。
- `globals/multiplayer/multiplayer_session.gd:79-90` 的缺省参数仍是 `player_guid: String = "client"`，随后原样发给服务器。
- `globals/multiplayer/session_root.gd:186-195` 直接用该 GUID 创建 `PlayerContext` 并注册连接。
- `globals/multiplayer/connection_authority.gd:35-45` 对 `_guid_to_peer[player_guid]` 直接覆盖，没有重复 GUID 拒绝或接管规则。
- `globals/multiplayer/session_root.gd:845-862` 出征结算继续以 GUID 作为幂等主键。

**故障链**

第二个远端玩家加入时覆盖 `"client" -> peer_id` 索引；之后重连可能定位到错误玩家，两个玩家的出征结算也会共用同一幂等键，出现错误接管或跨玩家“已结算”。

**建议**

- GUID 必须来自本地存档/账号生成并持久化，禁止大厅使用固定默认值。
- `register_online()` 返回明确结果；同 GUID 已 ONLINE 时拒绝新 spawn，只有合法 token 的 GRACE 重连可迁移。
- 增加真实行为测试：两个不同 peer 用同 GUID，第二个 spawn 必须失败，结算账本不得串键。

### P0-2 专用服务器仍采用“无几何纯积分”，可穿墙且高频输入可加速

**证据**

- `scenes/multiplayer/dedicated_server.gd:13-14,97-100` 明确只构建 layout、不构建碰撞几何。
- `scenes/multiplayer/dungeon_session_controller.gd:38-51` 的 `build_authority_only()` 只生成布局与出生点。
- 远端 avatar 虽由桥接层生成，但专用服务器路径没有真实地牢碰撞体与墙面可供 `move_and_slide()` 裁决。
- `globals/multiplayer/movement_authority.gd:64-80` 在 body 不可用时每收到一条合法命令就按固定 `dt` 积分。
- `globals/multiplayer/session_root.gd:97-99,594-600` 固定 `SERVER_TICK_DT=1/30`，每次 RPC 都立即消费一次，没有 per-peer 输入频率/服务器 tick 缓冲门。
- `globals/multiplayer/player_session.gd` 虽有 `last_input_tick`，但当前权威链未使用。

**故障链**

专用服务器没有世界碰撞，客户端持续提交合法方向即可穿过墙；客户端若高于 30Hz 发送严格递增 sequence，每条都获得一次 1/30 秒位移，可获得倍速。

**建议**

- 专服必须构建服务器碰撞表示，至少包含地形/门/阻挡体，不必构建可见 Mesh。
- RPC 只更新“最新输入状态”；位移仅在服务器固定 `_physics_process` tick 中每 peer 消费一次。
- 增加专服模式穿墙测试和 30/60/120Hz 输入等时位移一致性测试。

### P0-3 联机世界法术没有修改 `SessionRoot` 权威实体，法术事件可能成功但敌人 HP 不变

**证据**

- 联机普通攻击通过 `globals/multiplayer/session_root.gd:510-535` 结算后写回 `_entities` 并产生 snapshot/despawn。
- 法术则在 `globals/multiplayer/session_root.gd:680-704` 先扣法力、提交冷却，再调用 `SpellAuthority.execute()`；没有检查 `authority_execution.ok`，也没有把法术伤害写回 `_entities`。
- `globals/combat/spell_world_executor.gd:25-67,105-111,127-148` 只对场景中的 Node 调 `try_receive_hit`/`health.take_damage`。
- `scenes/multiplayer/multiplayer_entity.gd:1-68` 是纯表现节点，没有 `try_receive_hit`，且服务器权威敌人目前主要存在于 `SessionRoot._entities` 字典。
- `globals/multiplayer/session_root.gd:687-704` 无论执行器返回失败还是未命中，仍发布 `EVT_SPELL_RESOLVED` 并返回 success。

**故障链**

联机玩家施放 ray/area/ground/summon：服务端消耗法力并进入冷却、客户端播放 FX，但执行器找不到可受击权威敌人；即使找到表现节点，也绕开 `_entities` 与实体快照链。最终出现“施法成功、视觉命中、服务器敌人血量没变”。

**建议**

- 为法术世界执行器注入 `WorldCombatPort`/`EntityRepository`，目标选择和伤害都落到 `SessionRoot` 权威实体。
- 所有持续场/召唤由会话实例持有，不得直接以普通场景 Node 作为权威状态。
- `authority_execution.ok == false` 时不得提交资源；若执行阶段仍可能失败，需要 prepare/reserve/execute/commit 或补偿回滚。
- 增加真实测试：施放射线/区域后 `_entities[target].current_life` 降低且产生 snapshot/despawn。

### P0-4 装备命令只校验“背包拥有”，不校验类别、装备定义和槽位兼容

**证据**

- `globals/multiplayer/session_root.gd:747-782` 将 `materials/runes/equipment` 任一字典中存在的 ID 都视为 owned。
- 整数槽直接 `set_weapon_slot()`，字符串槽直接 `set_armor_slot()`；`globals/core/state/equipment_loadout.gd:19-34` 只校验槽索引/槽名，不校验物品类型。
- `scenes/multiplayer/client_command_driver.gd:231-244` 的 `slot` 类型标成 `String`，但服务端武器槽分支要求 `int`，协议形状也没有统一。

**故障链**

客户端可以把材料或符文 ID 写进武器/护甲槽，也能把武器写进错误护甲槽。后续 AttackContext、法术资格、存档序列化都会消费被污染的 loadout。

**建议**

建立唯一 `EquipmentPolicy`：服务器从注册表解析 item kind、weapon class、armor slot、双手占槽规则，并用库存移除 + loadout 写入 + 原装备返包的事务完成装备切换。禁止直接写 loadout。

---

## P1 — 高优先级架构债

### P1-1 法术世界执行器仍是静态跨会话共享实例

`globals/combat/spell_authority.gd:9,56-59` 使用 `static var _world_executor`。同进程先后创建多个 SessionRoot/世界时，预算、场和召唤可能跨会话残留或挂在旧世界。应改为 `SpellAuthority` 实例字段或由 SessionRoot 显式拥有。

### P1-2 法术事务只做“类型预检”，没有做预算/世界可执行性预检

`SessionRoot` 在 `680-687` 已提交法力/冷却；而 `SpellWorldExecutor` 可能在 `32-50` 因 `field_budget` / `summon_budget` 返回失败。当前仍会发布 success。预算、世界存在、目标合法性必须进入 commit 前 prepare 阶段。

### P1-3 远端玩家没有权威存档来源，法术与装备状态默认空

- `globals/core/network_manager.gd:408-413,530-541` 正确忽略远端客户端自报存档，关闭了旧注入漏洞。
- 但当前没有账号/服务器存档仓；远端 `send_spawn()` 永远发送空状态。
- 只有房主 `globals/multiplayer/multiplayer_session.gd:53-57` 从本地 `GameState` 注入可信摘要。

结果是远端玩家进入多人地牢后默认空装备、空法术装配，正常玩法能力不对等。需要服务器持久化仓或经过认证的存档导入协议，而不是恢复信任客户端字典。

### P1-4 已决定的流派武器伤害倍率仍未进入统一结算

- `globals/combat/damage_resolver.gd:33-65` 的 `STYLE_META` 仅双手含占位 `damage_mult=1.0`，其余已决定倍率缺失。
- `globals/combat/attack_context_factory.gd:52-73,135-157` 只注入武器自身倍率，没有按 style/hand 应用已决定的单手1.00、持盾0.80、双手1.35、双持主1.00/副0.60、徒手0.80、远程1.00、法系武器0.50。

冷却已统一，但伤害仍未对齐权威设计文档。注意该倍率只乘武器伤害，不得乘法术卡伤害。

### P1-5 `GameState` 与 `ExpeditionInventory` 重复定义默认容量

- `globals/core/game_state.gd:32` `DEFAULT_CARRIED_SPACE_LIMIT=30`。
- `globals/core/state/expedition_inventory.gd:10,20` `DEFAULT_LIMIT=30`。

旧悬空常量问题已消失，但双真相仍会漂移。保留库存模型内的默认值，GameState 通过模型 API reset。

### P1-6 性能分档只有 3D render scale，其他系统无人消费

- `globals/perf/performance_budget_controller.gd:7-20,102-113` 档位变化只设置 Viewport FSR scale 并发信号。
- 全仓库没有 `quality_tier_changed.connect` 消费者；只有 `globals/perf/perf_monitor.gd:73-77` 读取并显示。

因此粒子、动态灯、阴影、法术 FX、雾、LOD、反射等成本不会随档位变化，移动端紧急档的收益有限。建议引入 `RenderingProfile` 或按职责订阅信号，且不得改变 AI/敌人数/联机频率。

---

## 已确认关闭的旧问题

1. **远端 spawn 存档注入已关闭**：`network_manager.gd:530-541` 丢弃客户端 save_state；安全测试 3/3。
2. **客户端伪报 `attack_type` 已关闭**：`session_root.gd:102-104,470-494` 使用白名单与 `AttackContextFactory`；攻击上下文测试 12/12。
3. **攻击冷却公式已收口**：`AttackCadencePolicy` 被单机 `PlayerCombatRuntime` 与联机 `SessionRoot` 共用；专项 9/9。
4. **listen-server 移动已有真实碰撞马达**：远端 avatar 为 CharacterBody3D，绑定后走 `move_and_slide()`；专项 6/6。注意专服问题仍在。
5. **法术 caster 未绑定先扣资源已关闭**：`session_root.gd:666-680` commit 前拒绝；法术事务测试 8/8。
6. **法术资格校验已接入**：`session_root.gd:662-665,706-720` 从权威 loadout/被动重新判断。
7. **Android renderer 与目标导出预设已补**：`project.godot:177-181` 为桌面 `forward_plus`、移动 `mobile`；`export_presets.cfg` 已含 Windows Desktop 与 Android arm64。
8. **旧库存悬空常量调用已移除**：库存容量调用已转向 `ExpeditionInventory`。

---

## 验证结果

- Godot 4.7 headless editor 全项目解析扫描：退出 0，无脚本解析错误。
- `session_root_test.gd`：63/63 通过，但 **4 orphan，退出 101**。这仍不是干净门禁。
- `spawn_save_state_security_test.gd`：3/3，0 orphan，退出 0。
- `spell_session_atomicity_test.gd`：8/8，0 orphan，退出 0。
- `movement_authority_test.gd`：12/12，0 orphan，退出 0。
- `server_character_motor_test.gd`：6/6，0 orphan，退出 0。
- `attack_context_factory_test.gd`：12/12，0 orphan，退出 0。
- `attack_cadence_policy_test.gd`：9/9，0 orphan，退出 0。
- `spell_world_executor_test.gd`：4/4，0 orphan，退出 0；该套件主要验证结构/预算存在，未验证 SessionRoot 权威敌人 HP 写回。
- `performance_budget_controller_test.gd`：4/4，0 orphan，退出 0。

未执行：全量 gdUnit4、真实 ENet 双客户端/专服联调、窗口 3D 视觉、Windows/Android 实际导出、Android 真机 GPU/热稳定性。

---

## 建议整改顺序

1. **身份**：持久化唯一 GUID + 服务器重复 GUID 拒绝 + 重连唯一接管。
2. **专服移动**：固定服务器 tick 输入缓存 + 碰撞代理世界。
3. **法术权威世界**：统一 EntityRepository/WorldCombatPort，资源提交与执行结果原子化。
4. **装备事务**：EquipmentPolicy + InventoryTransferService + 槽位兼容。
5. **数值对齐**：将已决定 `damage_mult` 只接入武器伤害路径。
6. **发布门禁**：清除 session 4 orphan，跑全量、ENet、实际导出与 Android 真机。

## 工作树风险

当前工作树包含大量已修改与未跟踪文件；本报告基于当前磁盘状态，不代表可复现的干净提交。审查期间未修改业务代码、场景或资产。
