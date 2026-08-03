# Lantern Tavern 架构审查（2026-08-03 02:03）

## 结论

本轮为相对 `outputs/architecture_review_2026-08-03-0055.md` 的增量只读复审。上一轮的 4 个 P0 **全部仍未关闭**。Windows/Android 导出预设、Mobile renderer、远端 spawn 存档注入防护、客户端攻击类型拒绝、统一攻击冷却、基础法术资格与 caster 预检仍保持有效。

当前仍不建议进入多人发布、专用服务器发布或 Android 发布。多人阻断项集中在稳定身份、专服移动、法术统一权威实体仓、装备事务；另有 7 个 P1 需要在发布门禁前收口。

---

## P0 — 必须先修

### P0-1 大厅客户端仍共用固定 GUID，服务器仍允许在线重复 GUID 覆盖

**证据**

- `scenes/ui/lobby_menu.gd:218-225` 调用 `join_room(addr, port)`，未传本地持久化身份。
- `globals/multiplayer/multiplayer_session.gd:79-90` 的默认参数仍为 `player_guid="client"`。
- `globals/multiplayer/session_root.gd:170-194` 创建上下文后直接注册该 GUID。
- `globals/multiplayer/connection_authority.gd:35-45` 的 `register_online()` 返回 `void`，并直接覆盖 `_guid_to_peer[player_guid]`，没有拒绝同 GUID 的第二个 ONLINE peer。
- `globals/multiplayer/save_authority.gd:8,23` 的结算幂等账本仍以 GUID 为键。
- 身份专项 29/29 通过，但没有“两个在线 peer 使用同 GUID，第二个必须失败”的测试。

**故障链**

两个真实远端玩家默认均以 `client` 加入；后加入者覆盖稳定身份索引。后续重连接管可能绑定错误上下文，出征结算也可能共享幂等键。

**建议**

1. 客户端首次运行生成并持久化 GUID，Lobby 明确传入。
2. `register_online()` 返回结构化结果；同 GUID 已 ONLINE 时拒绝 spawn，只有匹配 token 的 GRACE 状态可迁移。
3. 增加重复 GUID、结算隔离和唯一接管集成测试。

### P0-2 专用服务器仍无地牢碰撞，且移动按每条 RPC 固定 1/30 秒执行

**证据**

- `scenes/multiplayer/dedicated_server.gd:13-14,94-100` 明确使用 `build_authority_only()`，不构建地牢几何或碰撞。
- `scenes/multiplayer/dungeon_session_controller.gd:38-52` 只生成 layout 和出生点；碰撞只在 `build_and_enter()` → `DungeonSceneBuilder.build()` 路径创建（`54-76`）。
- `globals/core/network_manager.gd:559-567` 每条可靠 `rpc_client_command` 都立即执行服务器命令，没有 per-peer 最新输入缓冲。
- `globals/multiplayer/session_root.gd:590-600` 每条 `CMD_INPUT` 固定传 `SERVER_TICK_DT=1/30`。
- `globals/multiplayer/movement_authority.gd:64-80` 无有效 `CharacterBody3D` 时直接纯积分。
- 专服虽然会生成远端 avatar 并绑定物理体（`multiplayer_scene_bridge.gd:85-121`），但世界没有墙体碰撞，因此仍不能裁决穿墙。
- 现有移动 47/47 通过，只验证纯积分和有墙体马达；没有专服 30/60/120Hz 输入频率不变性或专服穿墙测试。

**故障链**

客户端提高合法输入 RPC 频率，每条请求都得到一次固定 1/30 秒位移，速度随发送频率增加；专服没有静态墙体碰撞，角色可直接穿越布局墙格。

**建议**

1. 专服构建仅碰撞地牢表示，不加载 Mesh/材质/灯光。
2. RPC 只更新 per-peer 最新输入；服务器在固定 `_physics_process` 中每 peer 每 tick 消费一次。
3. 增加 30/60/120Hz 等时位移一致性和专服墙体阻挡集成测试。

### P0-3 联机法术仍绕过 `SessionRoot._entities`，且世界执行失败后仍作为成功提交

**证据**

- 普通攻击在 `session_root.gd:510-535` 把扣血/死亡写回 `_entities`，并生成 snapshot/despawn。
- 法术在 `session_root.gd:680-704` 先扣法力、提交冷却，再调用 `spell_auth.execute()`；之后不检查 `authority_execution.ok` 或嵌套 `world_execution.ok`，直接广播成功事件。
- 法术路径没有调用 `update_entity()`、`remove_entity()` 或修改 `_entities[target].current_life`。
- `globals/combat/spell_world_executor.gd:25-67,108-145` 查询场景节点并调用 `try_receive_hit` / `health.take_damage`，不是会话权威实体仓。
- `spell_session_atomicity_test`、`spell_world_executor_test`、`spell_network_completion_test` 共 16/16 通过，但没有断言施法后 `SessionRoot._entities[target].current_life` 下降，也没有世界执行失败后的资源回滚/拒绝测试。

**故障链**

ray/area/ground/summon 可以消耗法力、进入冷却并播放成功 FX，但服务器同步实体字典的敌人生命不变；预算、场景节点或具体执行失败也可能被包装成成功施法。

**建议**

1. 向会话法术执行器注入 `EntityRepository/WorldCombatPort`，目标选择、伤害、死亡、掉落、snapshot 与普通攻击共用同一实体仓。
2. 使用 prepare → execute → commit → publish；执行失败不得扣资源或发布成功事件。
3. 增加 ray/area/ground/summon 对 `_entities` 的真实写回和失败原子性测试。

### P0-4 装备命令仍允许材料/符文进入装备槽，协议槽位类型仍不一致

**证据**

- `session_root.gd:747-782` 只验证 item 存在于 `materials/runes/equipment` 任一字典，随后直接写武器或护甲槽。
- `globals/core/state/equipment_loadout.gd:19-34` 只校验槽索引/槽名，不校验 item kind、护甲部位、武器类别、盾牌或双手占槽规则。
- `scenes/multiplayer/client_command_driver.gd:232-245` 把 `slot` 固定为 `String`；服务端武器分支要求 `slot is int`。
- `tests/gdunit/session_root_test.gd:615-625` 明确把材料 `iron_ore` 装入武器槽并断言成功，漏洞被固化为预期行为。
- `equipment_loadout_test.gd` 4/4 仅覆盖基本存取和序列化，不覆盖兼容策略与库存事务。

**故障链**

客户端可把材料、符文或错误部位装备写入 loadout，污染攻击类型、法术资格、存档与结算；真实客户端又无法用当前 String 参数表达武器槽 int。

**建议**

建立唯一 `EquipmentPolicy + EquipmentTransaction`：从权威注册表解析物品类别和槽位兼容，原子处理背包移除、旧装备返包、双手/盾规则与 loadout 更新；协议改为明确的 `slot_kind + slot_index/slot_name`。

---

## P1 — 高优先级架构债

### P1-1 `SpellAuthority` 世界执行器仍静态跨会话共享

`globals/combat/spell_authority.gd:9,56-59` 使用 `static var _world_executor`。即使 `SessionRoot` 每实例创建 `spell_auth`，世界执行器仍在类级共享，字段/召唤预算和节点归属可能跨会话或跨重开世界串联。应改为实例字段并由会话生命周期持有、释放。

### P1-2 远端玩家仍没有可信存档来源

`network_manager.gd:546-555` 正确忽略远端客户端 save_state，但 `multiplayer_session.gd:79-90` 只发送 GUID 和空状态；服务器尚无账号/存档仓。远端默认空装备与空法术状态。不能恢复信任客户端字典，应接认证后的服务器持久化来源。

### P1-3 已决定的流派武器伤害倍率仍未统一进入结算

- `globals/combat/damage_resolver.gd:33-65` 只有双手风格带占位 `damage_mult=1.0`，其余已决定倍率缺失。
- `globals/combat/attack_context_factory.gd:139-153` 只应用武器资源自身 `damage_mult`。

文档已决定的倍率必须只乘武器伤害，不得影响法术；当前尚未形成单一策略入口。

### P1-4 库存默认容量仍有双真相

`globals/core/state/expedition_inventory.gd:10,20` 定义 `DEFAULT_LIMIT=30`；`globals/core/game_state.gd:32,455` 又定义 `DEFAULT_CARRIED_SPACE_LIMIT=30` 并直接写模型字段。应由库存模型单一持有默认值并提供 reset API。

### P1-5 性能分档仍只有 3D render scale，没有真实成本消费者

`globals/perf/performance_budget_controller.gd:102-113` 只设置 Viewport FSR scale 并发 `quality_tier_changed`；全仓库没有连接该信号。粒子、动态灯、阴影、雾、法术 FX、LOD 和反射成本不会随档位降级。

### P1-6 `SessionRoot` 测试仍有 4 orphan，严格门禁退出 101

`session_root_test.gd` 为 63/63 断言通过，但日志报告 4 orphan、退出 101。若流水线只看测试断言数，会把生命周期泄漏误判为绿色。

### P1-7 地牢运行时继续依赖单玩家全局 `GameState.current_player`

`dungeon_runtime.gd:148,214,469,502,523,548-549`、`procedural_dungeon.gd:159-160,225`、`extraction_portal.gd:193` 仍从全局单玩家引用取对象。联机已经使用 per-peer `PlayerContext`，但表现、撤离和压力逻辑仍是单玩家所有权语义，后续多人整合容易错控房主或本地玩家。

---

## 已确认保持关闭/有效

1. 远端 spawn 客户端存档注入仍被忽略；安全专项 3/3。
2. 客户端伪报 `attack_type` 仍被拒绝；攻击上下文专项 12/12。
3. 单机/联机攻击冷却仍共用 `AttackCadencePolicy`；专项 9/9。
4. listen-server 在绑定 `CharacterBody3D` 且存在碰撞几何时仍走真实碰撞马达；专项 6/6。
5. caster 未绑定、施法资格、法力和冷却预检仍在基础资源 commit 前拒绝；法术专项 16/16。
6. `project.godot:179-180` 为桌面 `forward_plus`、移动 `mobile`。
7. `export_presets.cfg:53-179` 包含 Windows Desktop 与 Android arm64 预设。
8. Godot 4.7 headless 编辑器全项目解析扫描退出 0。

---

## 验证结果

- Godot 4.7 headless editor 全项目解析扫描：退出 0，无脚本解析错误。
- `session_root_test.gd`：63/63 通过，**4 orphan，退出 101**。
- 身份与移动：29/29 + 12/12 + 6/6 = **47/47**，0 orphan，退出 0。
- 法术：8/8 + 4/4 + 4/4 = **16/16**，0 orphan，退出 0。
- spawn 安全、攻击上下文、冷却、性能、装备模型：3/3 + 12/12 + 9/9 + 4/4 + 4/4 = **32/32**，0 orphan，退出 0。
- 本轮专项合计：**158 个断言用例通过**；其中 SessionRoot 仍因 orphan 严格失败。

未执行：全量 gdUnit4、真实 ENet 双客户端、专服 30/60/120Hz 输入压测、专服墙体碰撞集成、实际 Windows/Android 导出、Android 真机 GPU/热稳定性、窗口 3D 视觉验收。

---

## 建议整改顺序

1. 唯一 GUID + 在线重复身份拒绝 + 重连/结算隔离测试。
2. 专服固定 tick 输入缓冲 + 仅碰撞地牢表示。
3. 法术统一权威实体仓，并改为 prepare/execute/commit/publish 原子事务。
4. 装备策略与库存/loadout 原子事务，修正槽位协议。
5. 将已决定的流派 `damage_mult` 仅接入武器伤害路径。
6. 清除 SessionRoot orphan，并把退出 101 作为 CI 失败。
7. 接通性能档位消费者，移除库存容量双真相与地牢全局玩家依赖。

## 工作树风险

当前工作树仍包含大规模已修改和未跟踪文件，且关键架构文件本身正在持续变化。本审查基于当前磁盘状态，不代表可复现的干净提交。审查期间未修改业务代码、场景、资产或项目配置。