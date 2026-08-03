# Lantern Tavern 架构审查（2026-08-03 03:06）

## 结论

本轮为相对 `outputs/architecture_review_2026-08-03-0203.md` 的增量只读复审。上一轮 4 个 P0 **全部仍未关闭**，且证据链没有实质变化：

1. 远端大厅客户端仍默认共用固定 GUID `client`，服务器仍允许在线重复 GUID 覆盖。
2. 专用服务器仍只构建 layout，不构建静态碰撞；每条输入 RPC 仍立即按固定 `1/30s` 积分。
3. 联机法术仍绕过 `SessionRoot` 权威实体仓，并在世界执行失败后仍扣法力、提交冷却、发布成功事件。
4. 装备命令仍允许材料/符文写入装备槽，且客户端槽位协议无法表达服务端武器槽整数。

当前仍不建议进入多人发布、专用服务器发布或 Android 发布。Windows/Android 导出配置与 Mobile renderer 已保持正确，但它们只说明“能导出到目标”，不代表多人权威链路和移动端性能已经达标。

---

## P0 — 发布阻断

### P0-1 固定 GUID + 在线重复身份覆盖仍存在

**证据**

- `scenes/ui/lobby_menu.gd:218-225` 加入房间时只传地址和端口。
- `globals/multiplayer/multiplayer_session.gd:79-90` 默认 `player_guid="client"`。
- `globals/multiplayer/session_root.gd:170-195` 先创建并注册玩家上下文，再调用 `register_online()`，没有重复身份预检或回滚。
- `globals/multiplayer/connection_authority.gd:35-45` 的 `register_online()` 返回 `void`，直接覆盖 `_guid_to_peer[player_guid]`。
- `globals/multiplayer/save_authority.gd:8,23-24,40-64` 以 `player_guid` 作为结算幂等账本主键。
- `tests/gdunit/connection_authority_test.gd` 29 个测试仍没有“两个 ONLINE peer 使用同 GUID，第二个必须失败”的用例。

**影响**

两个真实远端客户端默认都以 `client` 上线，后加入者覆盖身份索引。重连接管可能迁移错误玩家，出征结算可能共享同一幂等键，形成跨玩家串账。

**建议**

- 客户端首次运行生成并持久化随机 GUID，Lobby 显式传入。
- 将 `register_online()` 改成返回结构化结果；同 GUID 已 ONLINE 时拒绝 spawn，仅允许匹配 token 的 GRACE 条目迁移。
- `SessionRoot.handle_spawn_request()` 必须在创建节点、上下文和基线前完成身份预检，失败无副作用。
- 增加重复 GUID、重连隔离、结算隔离的真实集成测试。

### P0-2 专服移动仍可按输入频率加速并穿墙

**证据**

- `scenes/multiplayer/dedicated_server.gd:88-100` 调用 `build_authority_only()`。
- `scenes/multiplayer/dungeon_session_controller.gd:38-52` 只生成 layout 和出生点；真正墙体/地板碰撞只在 `54-76` 的 `DungeonSceneBuilder.build()` 路径生成。
- `globals/core/network_manager.gd:559-567` 每条可靠输入 RPC 都立即调用服务器命令处理，没有 per-peer 最新输入缓冲或服务器固定 tick 消费。
- `globals/multiplayer/session_root.gd:590-600` 每次命令固定传 `SERVER_TICK_DT=1/30`。
- `globals/multiplayer/movement_authority.gd:64-80` 无有效碰撞体时回退纯数学积分。
- `tests/gdunit/movement_authority_test.gd` 与 `server_character_motor_test.gd` 共 18/18 通过，但没有专服 30/60/120Hz 输入频率不变性，也没有 authority-only 地牢穿墙测试。

**影响**

客户端提高合法输入 RPC 频率即可获得更多次固定步长位移；专服权威世界没有墙体碰撞，无法裁决穿墙。序列号只防重放，不限制合法高频输入。

**建议**

- 专服增加“只碰撞地牢构建器”：生成 StaticBody3D/CollisionShape3D，不加载 Mesh、材质、灯光与音频。
- RPC 只更新 per-peer 最新输入；在服务器 `_physics_process` 固定频率每 peer 每 tick 消费一次。
- 增加 30/60/120Hz 等时位移一致性、墙体阻挡和输入洪泛测试。

### P0-3 联机法术事务仍非原子，且绕过权威实体仓

**证据**

- `globals/multiplayer/session_root.gd:680-704` 先扣法力、提交冷却，再执行 `spell_auth.execute()`；没有检查 `authority_execution.ok` 或 `world_execution.ok`，固定发布 `EVT_SPELL_RESOLVED` 并返回成功。
- 同文件普通攻击在 `510-535` 通过 `update_entity()` 写回 `_entities`；法术路径没有修改 `_entities[target].current_life`、没有统一死亡/掉落/snapshot/despawn。
- `globals/combat/spell_authority.gd:46-59` projectile/ray/area/ground/summon 走场景服务或世界执行器。
- `globals/combat/spell_world_executor.gd:25-67,105-148` 直接查询场景节点并调用 `try_receive_hit`/`health.take_damage`，不经过 `SessionRoot` 实体仓。
- `globals/combat/spell_world_executor.gd:34-50` 在场/召唤预算满时会返回 `ok=false`，但 SessionRoot 已经提交资源且忽略失败。
- 法术专项 16/16 通过；`spell_session_atomicity_test.gd:64-79` 只断言资源被提交和事件成功，没有断言 `_entities` 生命写回或世界执行失败时回滚。

**影响**

法术可能消耗法力、进入冷却并播放成功 FX，但服务器同步的敌人生命不变；预算满、射线无有效目标或世界执行失败也可被包装为成功。客户端看到的表现与服务器权威状态分叉。

**建议**

- 让法术通过与普通攻击相同的 `EntityRepository/WorldCombatPort` 修改实体生命、死亡、掉落和快照。
- 实现真正的 `prepare -> execute -> commit -> publish`；世界执行失败不得扣资源或发布成功事件。
- 持续场与召唤必须以稳定实体 ID/会话 ID 登记，由会话生命周期拥有并清理。
- 增加 ray/area/ground/summon 对 `_entities` 的写回、预算失败和目标失效原子性测试。

### P0-4 装备命令仍缺类别、槽位兼容和原子事务

**证据**

- `globals/multiplayer/session_root.gd:747-782` 只要 item 出现在 `materials/runes/equipment` 任一字典就允许写入装备槽。
- `globals/core/state/equipment_loadout.gd:19-34` 仅校验槽索引/名称，不校验物品类别、护甲部位、盾牌、单双手占槽或武器类型。
- `scenes/multiplayer/client_command_driver.gd:232-245` 把 `slot` 固定为 `String`；服务端武器分支要求 `slot is int`。
- `tests/gdunit/session_root_test.gd:615-625` 把材料 `iron_ore` 装入武器槽并断言成功，漏洞被固化为预期行为。
- `equipment_loadout_test.gd` 4/4 只覆盖基本存取和序列化。

**影响**

客户端可污染权威 loadout，继而影响攻击类型、法术资格、存档和结算；真实客户端协议又无法正常表达武器槽整数。

**建议**

建立唯一 `EquipmentPolicy + EquipmentTransaction`：从权威物品注册表解析类别和允许槽位，原子处理旧装备返包、新装备移除、双手/盾互斥与 loadout 更新。协议改为明确的 `slot_kind + slot_index/slot_name`，并删除把材料装备成功当正确行为的测试。

---

## P1 — 高优先级架构债

### P1-1 `SpellAuthority` 的世界执行器仍静态跨会话共享

`globals/combat/spell_authority.gd:9,56-59` 使用 `static var _world_executor`。字段、召唤预算及节点归属会跨 SessionRoot/世界重开共享。应改为实例字段，由会话创建、注入和释放。

### P1-2 远端玩家仍没有可信存档来源

`globals/core/network_manager.gd:546-555` 正确忽略客户端自报 save_state，但真实远端入口没有服务器账号/存档仓，默认获得空装备和空法术状态。不能恢复信任客户端字典，应接服务器持久化或房主批准的会话配置。

### P1-3 已决定的流派武器伤害倍率仍未统一进入结算

- `globals/combat/damage_resolver.gd:33-65` 仅双手风格含占位 `damage_mult=1.0`，未体现已决定的七流派倍率。
- `globals/combat/attack_context_factory.gd:135-153` 只应用武器数据自身 `damage_mult`。

应建立只作用于武器伤害的单一风格倍率策略，严禁影响法术伤害。

### P1-4 库存默认容量仍有双真相

`globals/core/state/expedition_inventory.gd:10,20` 与 `globals/core/game_state.gd:32,455` 各自定义默认容量 30。应由库存模型单一持有默认值，并由 `reset()` 恢复。

### P1-5 性能分档仍只有 3D render scale，无真实成本消费者

`globals/perf/performance_budget_controller.gd:102-113` 只设置 FSR scale 并发信号；全仓库没有 `quality_tier_changed.connect(...)`。粒子、动态灯、阴影、雾、反射、法术 FX 和 LOD 均不随档位降级。Android 发布前必须接通至少灯光/阴影/粒子/法术 FX/反射的分档策略，并在真机验证 GPU 时间与热稳定性。

### P1-6 `SessionRoot` 测试仍有 4 orphan，严格门禁退出 101

`session_root_test.gd` 为 63/63 断言通过，但日志报告 4 orphan，Runner 退出 101。CI 必须按进程退出码判定，不能只读取“测试用例通过数”。

### P1-7 地牢运行时仍依赖单玩家全局引用

`scenes/expedition/dungeon_runtime.gd:148,214,502,549`、`procedural_dungeon.gd:159-160,225`、`extraction_portal.gd:193` 继续读取 `GameState.current_player`；敌人也仍有回退路径。联机已经有 per-peer `PlayerContext/PlayerRegistry`，地牢压力、撤离、交互和目标选择仍可能默认控制本地/房主玩家。应改为显式玩家/peer 依赖注入。

---

## 已确认保持关闭或有效

1. 远端 spawn RPC 继续忽略客户端 save_state（`network_manager.gd:546-555`）。
2. 客户端伪报 `attack_type` 的命令仍被拒绝，攻击上下文仍由服务器派生。
3. 单机/联机攻击节奏仍共用 `AttackCadencePolicy`，本轮未发现回退。
4. listen-server 在真实碰撞世界和已绑定 `CharacterBody3D` 时仍走 `ServerCharacterMotor`。
5. 未绑定 caster、施法资格、法力与冷却预检仍在资源提交前拒绝。
6. `project.godot:179-180` 仍为桌面 `forward_plus`、移动 `mobile`。
7. `export_presets.cfg:53-179` 仍有 Windows Desktop 与 Android arm64 预设。
8. Godot 4.7 headless 编辑器全项目解析扫描退出 0。

---

## 验证结果

- Godot 4.7 headless editor 全项目解析扫描：退出 0，无脚本解析错误。
- `session_root_test.gd`：63/63 通过，**4 orphan，退出 101**。
- 身份：29/29 通过，0 orphan，退出 0。
- 移动：12/12 + 6/6 = 18/18 通过，0 orphan，退出 0。
- 法术：8/8 + 4/4 + 4/4 = 16/16 通过，0 orphan，退出 0。
- 装备模型、性能控制器、攻击上下文：4/4 + 4/4 + 12/12 = 20/20 通过，0 orphan，退出 0。
- 本轮专项合计：**146 个测试用例通过**；其中 SessionRoot 因 orphan 严格失败。

未执行：全量 gdUnit4、真实 ENet 双客户端、重复 GUID 在线冲突集成、专服 30/60/120Hz 输入压测、authority-only 墙体碰撞、法术对 `_entities` 的端到端伤害写回、实际 Windows/Android 导出、Android 真机 GPU/热稳定性、窗口 3D 视觉验收。

---

## 建议整改顺序

1. 唯一 GUID、在线重复身份拒绝、重连/结算隔离。
2. 专服固定 tick 输入缓冲与只碰撞地牢表示。
3. 法术统一权威实体仓及真正的事务顺序。
4. 装备策略、协议与库存/loadout 原子事务。
5. 清除 SessionRoot orphan，并把退出 101 作为 CI 失败。
6. 接入已决定的流派武器伤害倍率。
7. 接通移动端性能分档消费者，移除库存容量双真相和单玩家全局依赖。

## 工作树风险

当前工作树包含大规模已修改和未跟踪文件，高风险架构文件仍在持续变化。本报告审查的是当前磁盘快照，不代表可复现的干净提交。审查期间未修改业务代码、场景、资产或项目配置；只新增本报告与执行记录。
