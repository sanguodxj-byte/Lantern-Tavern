# Lantern Tavern 架构审查（2026-08-03 06:30）

## 执行结论

本轮为相对 `outputs/architecture_review_2026-08-03-0523.md` 的增量只读复审。结论未反转：**4 个 P0 发布阻断项全部仍未关闭**。当前磁盘快照不建议进入多人发布、专用服务器发布或 Android 发布候选。

- P0：4 项，身份、专服移动、法术事务/实体写回、装备策略均未闭环。
- P1：8 项，包含跨会话法术执行器、可信远端存档、流派倍率、库存默认值、质量分档、测试生命周期、单玩家全局依赖和 shader 参数规范债。
- 六组专项测试共 65/65 通过，0 orphan，进程退出 0。
- `session_root_test.gd` 63/63 断言通过，但仍有 4 orphan，gdUnit runner 声明退出 101；外层 Godot 进程本轮异常返回 128，未形成可接受门禁。
- 新隔离编辑器缓存下的 Godot editor 扫描在帮助缓存初始化阶段返回 128；日志未出现 `Parse Error` / `SCRIPT ERROR`，但本轮**不把解析扫描计为通过**。
- 本轮未修改业务代码、场景、资产或项目配置；仅生成审查报告与执行记录。

> 基线风险：工作树仍有大量已修改和未跟踪文件，本报告只描述 2026-08-03 06:30 的当前磁盘快照，不代表干净提交或可复现发布候选。

---

## P0 — 发布阻断

### P0-1 大厅默认固定 GUID，服务器允许在线重复身份覆盖

**证据**

- `globals/multiplayer/multiplayer_session.gd:79-90`：`join_room()` 默认 `player_guid = "client"`。
- `globals/multiplayer/session_root.gd:170-198`：先创建属性、技能、库存、装备、基线并注册玩家，最后才调用 `connection_auth.register_online()`；没有重复 GUID 预检和失败回滚。
- `globals/multiplayer/connection_authority.gd:35-45`：`register_online()` 返回 `void`，相同 GUID 直接覆盖 `_guid_to_peer`。
- `globals/multiplayer/save_authority.gd` 的出征结算幂等账本仍以 GUID 为身份键；重复身份会把重连和结算问题放大为跨玩家串账。
- `connection_authority_test.gd` 本轮 29/29 通过，但未建立“第二个 ONLINE peer 使用相同 GUID 必须拒绝”的发布门禁。

**影响**

多个真实远端客户端可默认共用 `client` 身份。后加入连接覆盖身份索引后，可能接管重连锚、错误恢复状态或污染结算幂等账本。

**最小修复边界**

1. 客户端首次启动持久化生成随机 GUID，禁止固定默认值。
2. SessionRoot 在创建任何玩家子对象或库存基线前执行在线唯一性预检。
3. `register_online()` 返回结构化结果；ONLINE 冲突必须拒绝，仅 token 匹配的 GRACE 身份允许迁移。
4. 增加重复在线 GUID、重连隔离、结算账本隔离的真实双客户端测试。

### P0-2 专服移动按 RPC 次数积分，authority-only 地牢没有墙体裁决

**证据**

- `globals/core/network_manager.gd:559-567`：每条可靠输入 RPC 立即进入 `_server_handle_command()`，没有 per-peer 最新输入缓冲和固定服务器 tick 消费。
- `globals/multiplayer/session_root.gd:590-613`：每次命令都以固定 `SERVER_TICK_DT = 1/30` 调用移动权威。
- `scenes/multiplayer/dedicated_server.gd:88-100`：专服明确调用 `build_authority_only()`。
- `scenes/multiplayer/dungeon_session_controller.gd:38-52`：authority-only 路径只建立布局/出生信息；真实地板、墙与天花板碰撞来自完整场景构建路径。
- `globals/multiplayer/movement_authority.gd:64-80`：没有有效 `CharacterBody3D` 时回退纯数学积分。
- `movement_authority_test.gd` 本轮 12/12 通过，但未覆盖 30/60/120Hz 等时位移一致性、合法输入洪泛限频或 authority-only 真实墙体阻挡。

**影响**

客户端提高合法递增 sequence 的发送频率即可让服务器重复执行固定 1/30 秒位移；专服地牢又没有静态墙碰撞，无法权威阻止穿墙。

**最小修复边界**

RPC 只更新 per-peer 最新输入；服务器固定物理 tick 每 peer 最多消费一次；专服生成轻量仅碰撞地牢；补输入频率无关性、洪泛限频和真实墙体阻挡测试。

### P0-3 联机法术未形成权威实体事务，世界执行失败仍被包装为成功

**证据**

- `globals/multiplayer/session_root.gd:644-704`：实现顺序仍是扣法力、提交冷却、调用 `spell_auth.execute()`，随后无条件广播 `EVT_SPELL_RESOLVED` 并返回成功；没有检查 `authority_execution.ok` 或嵌套 `world_execution.ok`。
- 同文件普通攻击在 `520-535` 会把生命、死亡、掉落与复制事件写回 `_entities`；法术路径没有等价写回。
- `globals/combat/spell_authority.gd:46-59`：projectile 服务缺失时仍可保持执行成功；ray/area/ground/summon 委托给 `_world_executor`。
- `globals/combat/spell_world_executor.gd:14-67`：直接查询场景物理目标并调用目标节点受击/生命组件，不经过 SessionRoot `_entities`；字段/召唤预算满时会返回 `ok=false`。
- `spell_network_completion_test.gd` 4/4、`spell_world_executor_test.gd` 4/4 通过，但没有覆盖 `_entities` 生命写回、死亡/掉落复制、预算失败后的 mana/cooldown 回滚。

**影响**

服务端可能扣蓝、进入冷却并广播成功 FX，但同步实体生命不变；字段或召唤预算满、服务缺失、具体执行失败也可能被包装成成功。

**最小修复边界**

建立会话拥有的法术世界端口，统一落到 SessionRoot 权威实体仓；改为 `prepare -> execute -> verify -> commit -> publish`；任何执行失败不得提交法力和冷却；持续场与召唤纳入会话生命周期及复制；补写回、死亡、掉落、失败回滚端到端测试。

### P0-4 装备命令允许非装备污染槽位，客户端与服务器槽位协议不一致

**证据**

- `globals/multiplayer/session_root.gd:747-782`：只要 ID 存在于 `materials/runes/equipment` 任一字典就被视为 owned，随后直接写 loadout。
- `globals/core/state/equipment_loadout.gd:19-34`：只检查槽索引/槽名，不检查物品类别、护甲部位、盾牌/双手互斥或武器占槽规则。
- `scenes/multiplayer/client_command_driver.gd:232-245`：客户端 `send_equip()` 把 `slot` 固定声明为 `String`；服务端武器槽分支要求 `slot is int`。
- `tests/gdunit/session_root_test.gd` 仍明确把材料 `iron_ore` 装入武器槽并断言成功，漏洞被测试固化为预期行为。

**影响**

客户端可污染权威装备状态，继续影响攻击上下文、施法资格、存档和结算；真实客户端接口又不能正确表达服务端整数武器槽。

**最小修复边界**

建立唯一 `EquipmentPolicy + EquipmentTransaction`；从权威注册表解析类别、槽位兼容和占槽关系；原子处理返包、移除、双手/盾互斥；协议改为明确 `slot_kind + slot_index/slot_name`；把材料装备成功测试改成拒绝反例。

---

## P1 — 高优先级架构债

### P1-1 法术世界执行器静态跨会话共享

`globals/combat/spell_authority.gd:9,56-59` 使用 `static var _world_executor`。字段/召唤预算、节点归属和生命周期可能跨 SessionRoot、场景重开及测试共享。应由会话实例持有并显式释放。

### P1-2 远端玩家仍没有可信服务器存档仓

`globals/core/network_manager.gd:546-555` 正确忽略客户端自报 `save_state`；`session_root.gd:200+` 已能应用服务器可信 `spell_state`，但真实远端入口没有账号或服务器持久化仓向其提供可信材料、装备和法术装配。不能通过恢复信任客户端字典解决。

### P1-3 已决定的流派武器伤害倍率未统一进入结算

- `globals/combat/damage_resolver.gd:33-65` 的 `STYLE_META` 只有双手风格显式 `damage_mult = 1.0`，仍是占位值。
- `globals/combat/attack_context_factory.gd:135-157` 只将武器资源自己的 `damage_mult` 乘入 `AttackInput.weapon_damage_mult`。
- 已决定的七流派倍率尚未成为单一策略；必须只乘武器伤害，不得乘法术伤害。

### P1-4 库存默认容量双真相

`globals/core/state/expedition_inventory.gd` 持有 `DEFAULT_LIMIT := 30`，`globals/core/game_state.gd` 又持有 `DEFAULT_CARRIED_SPACE_LIMIT := 30`。默认容量与 reset 语义应由库存模型独占。

### P1-5 两套质量系统未协调，动态分档只有分辨率消费者

- `project.godot` 同时 autoload `LightingController` 与 `PerformanceBudget`。
- `globals/perf/performance_budget_controller.gd:102-113` 只改变 3D FSR scale 并发出 `quality_tier_changed`。
- 全仓未发现业务侧 `quality_tier_changed.connect(...)`。
- `globals/lighting/lighting_controller.gd:47-66` 独立按 renderer 初始化 HIGH/MEDIUM，不订阅性能预算。

GPU 压力升高时灯光、阴影、粒子、雾、反射、法术 FX 与 LOD 不跟随；两个画质真相会漂移。

### P1-6 SessionRoot 严格测试门禁仍失败

本轮 `session_root_test.gd` 为 63/63 断言通过，但报告 4 orphan，runner 明确声明退出 101；外层 Godot 进程返回 128。CI 必须以干净退出码和零 orphan 为门禁，不能只看断言数。

### P1-7 地牢和敌人逻辑仍依赖单玩家全局引用

`scenes/expedition/dungeon_runtime.gd`、`procedural_dungeon.gd`、`extraction_portal.gd` 与 `scenes/characters/enemies/enemy.gd` 仍存在 `GameState.current_player` 读取或回退。联机已有 per-peer PlayerContext/PlayerRegistry，但地牢压力、撤离、交互、击杀归属和敌人目标仍可能默认落到本地/房主玩家。

### P1-8 Shader Inspector 参数规范仍不统一

- `shaders/liquid.gdshader:3-4` 的纹理滚动参数缺范围/分组约束，且 shader 体内仍有酸液颜色和混合系数硬编码。
- `assets/shaders/dungeon_terrain.gdshader:11-14` 的图集坐标、跨度、网格和重复参数无范围提示。
- 酒馆 atlas shader 仍有大量图集、材质、噪声与 decal 参数缺 `hint_range`。

当前扫描未发现 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 构成新的移动后端阻断，但 Inspector 参数债仍违反项目 shader 交付规范。

---

## 已确认保持有效

1. 远端 spawn RPC 继续忽略客户端自报 `save_state`（`network_manager.gd:546-555`）。
2. 普通攻击继续拒绝客户端伪报攻击类型/伤害字段，并由服务器权威 loadout 构造 AttackContext（`session_root.gd:446-519`）。
3. 普通攻击继续写回 `_entities` 并产生生命、死亡与掉落复制事件（`session_root.gd:520-535`）。
4. 玩家攻击冷却已统一调用 `AttackCadencePolicy`（`session_root.gd:515-519`）；本轮没有重新列为 P0。
5. Windows 与 Android 导出预设存在，Android 仅启用 arm64。
6. 桌面 `forward_plus`、移动 `mobile` 配置正确（`project.godot` rendering 段）。
7. 当前 shader 搜索未发现 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 的移动后端发布阻断用法。

---

## 验证结果

### 通过

- `connection_authority_test.gd`：29/29，0 orphan，退出 0。
- `movement_authority_test.gd`：12/12，0 orphan，退出 0。
- `spell_network_completion_test.gd`：4/4，0 orphan，退出 0。
- `spell_world_executor_test.gd`：4/4，0 orphan，退出 0。
- `performance_budget_controller_test.gd`：4/4，0 orphan，退出 0。
- `attack_context_factory_test.gd`：12/12，0 orphan，退出 0。

合计：65/65，0 orphan。

### 未通过门禁

- `session_root_test.gd`：63/63 断言通过，但 4 orphan；gdUnit runner 声明退出 101，外层进程返回 128。
- Godot editor 全项目扫描：新隔离缓存下在编辑器帮助缓存初始化阶段返回 128；日志未出现脚本解析错误，但未正常完成，故不计为通过。

### 未执行

真实 ENet 双客户端重复 GUID 冲突、专服 30/60/120Hz 输入压测、authority-only 真实墙体碰撞、法术 `_entities` 写回/失败回滚、装备策略端到端、Windows/Android 实际导出、Android 真机 GPU/热稳定性、窗口视觉验收和全量 gdUnit4。

---

## 建议整改顺序

1. 唯一 GUID、在线重复身份拒绝、重连/结算隔离。
2. 专服固定 tick 输入缓冲与仅碰撞地牢表示。
3. 法术统一权威实体仓与真正原子事务。
4. 装备策略、协议和库存/loadout 原子事务。
5. 清除 SessionRoot orphan/异常退出并恢复可靠全项目解析门禁。
6. 接入已决定的七流派武器伤害倍率。
7. 合并质量分档真相，接通灯光、阴影、粒子、法术 FX 与 LOD 消费者。
8. 移除库存容量双真相、地牢单玩家全局依赖，并补齐 shader uniform hints。
