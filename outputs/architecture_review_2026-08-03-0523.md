# Lantern Tavern 架构审查（2026-08-03 05:23）

## 执行结论

本轮为相对 `outputs/architecture_review_2026-08-03-0411.md` 的增量只读复审。结论没有反转：上一轮 **4 个 P0 全部仍未关闭**，当前仍不建议进入多人发布、专用服务器发布或 Android 发布。

- P0：4 项，关键实现与测试证据均未形成闭环。
- P1：8 项，质量系统、测试生命周期、流派倍率、库存默认值和单玩家全局依赖仍在。
- Godot 4.7 headless editor 全项目解析扫描退出 0。
- `session_root_test.gd` 63/63 断言通过，但仍有 4 orphan、35 个 ObjectDB 实例和 15 个资源泄漏，runner 退出 101。
- 本轮未修改业务代码、场景、资产或项目配置；仅生成审查报告与执行记录。

> 基线风险：工作树包含大量已修改与未跟踪文件。本文只描述 2026-08-03 05:23 当前磁盘快照，不代表干净提交或可复现发布候选。

---

## P0 — 发布阻断

### P0-1 大厅固定 GUID 与在线重复身份覆盖

**证据**

- `scenes/ui/lobby_menu.gd:218-225` 加入房间只传地址和端口。
- `globals/multiplayer/multiplayer_session.gd:79-90` 的默认 `player_guid` 仍为固定字符串 `"client"`。
- `globals/multiplayer/session_root.gd:170-198` 先创建属性、技能、库存、装备、基线与玩家注册，再调用 `connection_auth.register_online()`；没有在线重复 GUID 预检，也没有失败回滚。
- `globals/multiplayer/connection_authority.gd:35-45` 的 `register_online()` 返回 `void`，相同 GUID 直接覆盖 `_guid_to_peer`。
- `globals/multiplayer/save_authority.gd:8-24,39-64` 仍以 GUID 作为出征结算幂等账本主键。
- `tests/gdunit/connection_authority_test.gd:31-36` 只覆盖单个身份登记；全测试搜索未发现“第二个 ONLINE peer 使用同 GUID 必须拒绝”的行为测试。

**影响**

多个真实远端客户端默认共用 `client` 身份。后加入者可覆盖身份索引，导致重连状态接管、错误玩家恢复和跨玩家结算串账。

**最小修复边界**

1. 客户端持久化生成随机 GUID，不再使用固定默认值。
2. SessionRoot 在创建任何玩家节点、上下文和库存基线前执行在线唯一性预检。
3. `register_online()` 返回结构化成功/失败结果；ONLINE 冲突必须拒绝，只有 token 匹配的 GRACE 身份允许迁移。
4. 增加重复在线 GUID、重连隔离和结算账本隔离集成测试。

### P0-2 专服移动按 RPC 频率加速，authority-only 世界没有墙体裁决

**证据**

- `globals/core/network_manager.gd:559-567` 每条可靠 `rpc_client_command` 都立即进入 `_server_handle_command()`；没有 per-peer 最新输入缓冲与固定服务器 tick 消费。
- `globals/multiplayer/session_root.gd:97-98,590-613` 每次输入命令都使用固定 `SERVER_TICK_DT = 1/30` 积分。
- `scenes/multiplayer/dungeon_session_controller.gd:38-52` 的 `build_authority_only()` 只生成 layout 与出生点；真正地板/墙/天花板碰撞只在 `54-76` 的完整场景构建路径产生。
- `globals/multiplayer/movement_authority.gd:64-80` 在没有有效 `CharacterBody3D` 时回退为纯数学积分。
- `tests/gdunit/server_character_motor_test.gd:15-109` 能证明“人工构造墙体 + 已绑定 body”可阻挡，但没有证明 dedicated authority-only 地牢自身存在碰撞。
- `tests/gdunit/movement_authority_test.gd` 未覆盖 30/60/120Hz 等时位移一致性或输入洪泛限频。

**影响**

客户端只需提高合法递增 sequence 的发送频率，就能让服务器多执行若干次固定 1/30 秒位移；专用服务器的 authority-only 世界又没有静态墙体，无法裁决穿墙。

**最小修复边界**

RPC 只更新 per-peer 最新输入；服务器 `_physics_process` 每个固定 tick 每 peer 最多消费一次；专服生成轻量“仅碰撞地牢”；补 30/60/120Hz 等时位移、洪泛限频和 authority-only 真实墙体阻挡测试。

### P0-3 联机法术绕过 SessionRoot 权威实体仓，失败事务仍被包装为成功

**证据**

- `globals/multiplayer/session_root.gd:680-704` 先扣法力、提交冷却，再调用 `spell_auth.execute()`；之后不检查 `authority_execution.ok` 或嵌套 `world_execution.ok`，无条件发布 `EVT_SPELL_RESOLVED` 并返回成功。
- 同文件普通攻击在 `520-535` 将生命、死亡、掉落与复制事件写回 `_entities`；法术路径没有等价权威实体写回。
- `globals/combat/spell_authority.gd:46-59` 把 projectile/ray/area/ground/summon 委托给场景执行器；`projectile` 即使服务不存在仍可保持 `execution.ok = true`。
- `globals/combat/spell_world_executor.gd` 直接查询场景节点并调用受击/生命组件，不经过 SessionRoot `_entities`。
- `tests/gdunit/spell_session_atomicity_test.gd:64-79` 只断言扣蓝、冷却和成功事件；没有验证 `_entities` 生命写回、死亡/掉落复制、执行失败回滚。
- 法术测试搜索未发现世界预算满、`world_execution.ok=false`、权威实体生命写回或 mana/cooldown rollback 覆盖。

**影响**

服务器可能扣蓝、进入冷却并播放成功 FX，但同步敌人生命不变；世界执行器预算满、服务缺失或具体执行失败，也会被包装成成功。

**最小修复边界**

让法术统一走会话拥有的实体仓/世界战斗端口；建立真正的 `prepare -> execute -> commit -> publish`，执行失败不得提交法力和冷却；持续场与召唤由 SessionRoot 生命周期登记；补生命写回、死亡/掉落和失败回滚端到端测试。

### P0-4 装备命令允许材料/符文污染装备槽，客户端协议与服务器槽位类型不一致

**证据**

- `globals/multiplayer/session_root.gd:747-782` 只要物品存在于 `materials/runes/equipment` 任一字典就允许写入 loadout。
- `globals/core/state/equipment_loadout.gd:19-34` 仅校验槽索引/名称，不验证物品类别、护甲部位、盾牌、双手占槽或互斥关系。
- `scenes/multiplayer/client_command_driver.gd:232-245` 把 `slot` 固定声明为 `String`；服务端武器槽分支要求 `slot is int`。
- `tests/gdunit/session_root_test.gd:615-625` 明确把材料 `iron_ore` 装进武器槽并断言成功，漏洞仍被固化为预期行为。

**影响**

客户端可污染权威装备状态，进而影响攻击上下文、施法资格、存档和结算；真实客户端还无法用当前接口正确表达服务器所需的整数武器槽。

**最小修复边界**

建立唯一 `EquipmentPolicy + EquipmentTransaction`；从权威注册表解析类别和允许槽位；原子处理返包、移除、双手/盾互斥和 loadout 更新；协议改为明确 `slot_kind + slot_index/slot_name`；删除材料装备成功测试并增加反例。

---

## P1 — 高优先级架构债

### P1-1 法术世界执行器静态跨会话共享

`globals/combat/spell_authority.gd:9,56-59` 使用 `static var _world_executor`。字段、召唤预算和节点归属可能跨 SessionRoot、测试和场景重开共享。应改为会话实例持有并显式释放。

### P1-2 远端玩家没有可信服务器存档仓

`globals/core/network_manager.gd:546-555` 正确忽略客户端自报存档，但真实远端入口也没有账号/服务器持久化仓，因此默认上下文无法恢复装备与法术装配。解决方案不是恢复信任客户端字典，而是接入服务器存档或房主批准的会话配置。

### P1-3 已决定的流派武器伤害倍率未统一进入结算

- `globals/combat/damage_resolver.gd:33-65` 只有双手风格带占位 `damage_mult = 1.0`，其余风格缺少已决定倍率。
- `globals/combat/damage_resolver.gd:330-348` 基础伤害最终只乘 `AttackInput.weapon_damage_mult`。
- `globals/combat/attack_context_factory.gd:135-157` 只应用武器资源自己的 `damage_mult`。

项目已决定的七流派武器伤害倍率仍未作为单一策略进入结算；必须保证只乘武器伤害，不影响法术卡伤害。

### P1-4 库存默认容量双真相

`globals/core/state/expedition_inventory.gd:10,20` 与 `globals/core/game_state.gd:32,451-455` 分别保存默认 30。库存模型应独占默认容量与 reset 语义。

### P1-5 两套运行时质量系统未协调，动态分档只有分辨率消费者

- `project.godot:47-49` 同时 autoload `LightingController` 与 `PerformanceBudget`。
- `globals/perf/performance_budget_controller.gd:102-113` 只改变 3D FSR scale 并发出信号。
- 全仓库业务代码没有 `quality_tier_changed.connect(...)`。
- `globals/lighting/lighting_controller.gd:47-66` 按 renderer 初始化独立 HIGH/MEDIUM/LOW 档位，不订阅 PerformanceBudget。

GPU 压力升高时只有渲染分辨率降级，灯光、阴影、粒子、雾、反射、法术 FX 与 LOD 不跟随；两个质量真相可能长期漂移。

### P1-6 SessionRoot 严格测试门禁失败

本轮实跑 `session_root_test.gd`：63/63 断言通过，但 4 orphan，runner 退出 101，并报告 35 个 ObjectDB 实例和 15 个资源仍在使用。CI 必须依据进程退出码，而不是只读取断言通过数。

### P1-7 地牢与敌人逻辑仍依赖单玩家全局引用

- `scenes/expedition/dungeon_runtime.gd:148,214,502,548-549`
- `scenes/expedition/procedural_dungeon.gd:159-160,225`
- `scenes/expedition/extraction_portal.gd:193`
- 既有敌人目标/归属路径仍有 `GameState.current_player` 依赖。

联机已经有 per-peer `PlayerContext/PlayerRegistry`，但地牢压力、撤离、交互、击杀归属和目标回退仍可能默认落到本地/房主玩家。

### P1-8 Shader Inspector 参数规范仍不统一

本轮未发现 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 的当前移动端发布阻断用法；但 artist-facing uniform 仍存在 Inspector hint 债：

- `shaders/liquid.gdshader:3-4` 的纹理与滚动速度缺少明确参数约束；shader 体内还硬编码酸液颜色与混合系数（`18-19`），不利于艺术调参。
- `assets/shaders/dungeon_terrain.gdshader:11-21` 的图集坐标、跨度、网格与重复参数无范围提示。
- `scenes/tavern/materials/tavern_atlas_world_32px.gdshader:6-24` 多数图集、材质、噪声与 decal 参数无 `hint_range`。

这不是当前 P0，但违反 shader 参数规范，容易造成越界配置和艺术交接失控。

---

## 已确认保持有效

1. 远端 spawn RPC 继续忽略客户端自报 `save_state`（`network_manager.gd:546-555`）。
2. 客户端伪报 `attack_type` 继续被字段白名单拒绝；普通攻击上下文与冷却由服务器权威 loadout 派生（`session_root.gd:446-519`）。
3. 普通攻击继续写回 `_entities`，并产生生命、死亡与掉落复制事件（`session_root.gd:520-535`）。
4. Windows 与 Android 导出预设仍存在；Android 只启用 arm64（`export_presets.cfg:51-179`）。
5. 桌面 `forward_plus`、移动 `mobile` 配置保持正确（`project.godot:177-181`）。
6. 当前 shader 扫描未发现 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 的移动后端阻断用法。

---

## 验证结果

- Godot 4.7 headless editor 全项目解析扫描：退出 0，无脚本解析错误输出。
- `session_root_test.gd`：63/63 断言通过；4 orphan；35 ObjectDB/15 resources leaked；runner 退出 101。
- 其他专项套件第一次批量运行只产生引擎横幅，没有可信 gdUnit runner 统计，因此**未计为通过**；不沿用上一轮数字冒充本轮结果。
- 多代理并行审查因运行环境返回 403 未执行，主代理已完成全部证据复核；该失败不影响代码证据，但降低了独立复核冗余。

未执行：全量 gdUnit4、真实 ENet 双客户端、重复 GUID 在线冲突集成、专服 30/60/120Hz 输入压测、authority-only 地牢墙体碰撞、法术对 `_entities` 的端到端写回与失败回滚、实际 Windows/Android 导出、Android 真机 GPU/热稳定性和窗口视觉验收。

---

## 建议整改顺序

1. 唯一 GUID、在线重复身份拒绝、重连/结算隔离。
2. 专服固定 tick 输入缓冲与仅碰撞地牢表示。
3. 法术统一权威实体仓与真正原子事务。
4. 装备策略、协议与库存/loadout 原子事务。
5. 清除 SessionRoot orphan/leak，并将退出 101 作为 CI 失败。
6. 接入已决定的流派武器伤害倍率。
7. 合并质量分级真相并接通灯光、阴影、粒子、法术 FX 与 LOD 消费者。
8. 移除库存容量双真相、地牢单玩家全局依赖，并补齐 shader uniform hints。
