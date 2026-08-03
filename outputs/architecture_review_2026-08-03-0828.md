# Lantern Tavern 架构审查（2026-08-03 08:28）

## 执行结论

本轮为相对 `outputs/architecture_review_2026-08-03-0630.md` 的增量只读复审。结论未反转：**4 个 P0 发布阻断项全部仍未关闭**。当前磁盘快照不建议进入多人、专用服务器或 Android 发布候选。

- P0：4 项，身份、专服移动、法术事务/实体写回、装备策略仍未闭环。
- P1：8 项，跨会话法术执行器、可信远端存档、流派倍率、库存默认值、质量分档、测试生命周期、单玩家全局依赖和 shader 参数规范债。
- 7 组专项测试共 **73/73** 通过、0 orphan、runner 退出 0。
- `session_root_test.gd` 为 **63/63**，但仍有 **4 orphan**，runner 退出 **101**，不满足严格门禁。
- 全项目 editor 扫描未形成可信结果：Godot 仅输出版本信息或报 `EditorSettings not instantiated yet`，未产生可核验的正常完成退出码；本轮不把解析扫描计为通过。
- 本轮未修改业务代码、场景、资产或项目配置；仅生成审查报告和执行记录。

> 基线风险：工作树仍有大量已修改和未跟踪文件。本报告只描述 2026-08-03 08:28 的当前磁盘快照，不代表干净提交或可复现发布候选。

---

## P0 — 发布阻断

### P0-1 大厅默认固定 GUID，服务器允许在线重复身份覆盖

**状态：未关闭。**

**证据**

- `globals/multiplayer/multiplayer_session.gd:79-90`：`join_room()` 默认 `player_guid = "client"`。
- `globals/multiplayer/session_root.gd:170-198`：生成流程先创建 per-peer 状态并注册玩家，最后直接调用 `connection_auth.register_online()`；没有重复 GUID 预检或失败回滚。
- `globals/multiplayer/connection_authority.gd:35-45`：`register_online()` 返回 `void`；相同 GUID 会直接覆盖 `_guid_to_peer[player_guid]`。
- `tests/gdunit/connection_authority_test.gd` 29/29 通过，但没有“第二个 ONLINE peer 使用相同 GUID 必须拒绝”的反例门禁。

**风险机制**

多个真实客户端可默认共用 `client`。后加入连接覆盖身份索引后，可造成错误重连、身份状态覆盖及以 GUID 为键的结算账本串账。

**最小修复边界**

1. 客户端持久化生成稳定随机 GUID，删除固定默认值。
2. SessionRoot 在创建任何玩家子对象前执行在线 GUID 唯一性预检。
3. `register_online()` 返回结构化结果；ONLINE 冲突必须拒绝，只有 token 匹配的 GRACE 身份允许迁移。
4. 增加双客户端重复 GUID、重连隔离和结算隔离测试。

### P0-2 专服移动按 RPC 次数固定积分，authority-only 世界没有墙体裁决

**状态：未关闭。**

**证据**

- `globals/core/network_manager.gd:559-567`：每条可靠输入 RPC 都立即调用 `_server_handle_command()`；没有 per-peer 最新输入缓冲与固定服务器 tick 消费。
- `globals/multiplayer/session_root.gd:590-613`：每条命令都用固定 `SERVER_TICK_DT = 1/30` 调用移动权威。
- `globals/multiplayer/movement_authority.gd:64-80`：无有效 `CharacterBody3D` 时回退纯数学积分。
- `scenes/multiplayer/dedicated_server.gd:88-100`：专服调用 `build_authority_only()`。
- `scenes/multiplayer/dungeon_session_controller.gd:38-52`：authority-only 只生成 layout 和出生点；不生成地板/墙体碰撞。
- `movement_authority_test.gd` 12/12 通过，但未覆盖 30/60/120Hz 等时位移一致性、输入洪泛限频或专服真实墙体阻挡。

**风险机制**

客户端提高合法递增 sequence 的发送频率，即可让服务器重复执行 1/30 秒位移；专服又没有静态墙体碰撞，因此速度作弊与穿墙同时成立。

**最小修复边界**

RPC 仅更新 per-peer 最新输入；服务器固定物理 tick 每 peer 最多消费一次；专服生成轻量仅碰撞地牢；增加输入频率无关性、洪泛限频与真实墙体阻挡测试。

### P0-3 法术事务仍是先提交资源再执行，执行失败未回滚且不写回权威实体仓

**状态：部分预检已完成，核心闭环未关闭。**

**已完成部分**

- `globals/multiplayer/session_root.gd:651-679` 已在 commit 前校验序列、槽位、配方、施法资格、caster、法力、冷却和实施类型。
- `spell_session_atomicity_test.gd` 8/8 证明 caster/资格/法力/冷却等前置失败不会扣资源。

**仍缺失的核心证据**

- `session_root.gd:680-704` 仍先扣法力并提交冷却，再调用 `spell_auth.execute()`；随后不检查 `authority_execution.ok` 或嵌套 `world_execution.ok`，无条件广播 `EVT_SPELL_RESOLVED` 并返回成功。
- `globals/combat/spell_authority.gd:46-59`：projectile service 缺失时仍可保持 `ok=true`；ray/area/ground/summon 的世界结果仅塞入 `world_execution`。
- `globals/combat/spell_authority.gd:9,56-59`：世界执行器仍是 `static var _world_executor`，跨 SessionRoot/场景/测试共享。
- 法术路径没有普通攻击那样把生命、死亡、掉落和复制事件写回 SessionRoot `_entities`。
- `spell_session_atomicity_test.gd` 没有世界执行返回 `ok=false`、字段/召唤预算失败、mana/cooldown 回滚、`_entities` 生命写回等测试。

**风险机制**

服务端可能扣蓝、进入冷却并播放成功 FX，但同步实体生命不变；预算满、服务缺失或具体世界执行失败也会被包装成成功。静态执行器还可能让跨会话预算和节点生命周期互相污染。

**最小修复边界**

建立 SessionRoot 拥有的法术世界端口并统一写入权威实体仓；改成 `prepare -> execute -> verify -> commit -> publish`；失败不得提交 mana/cooldown；持续场和召唤纳入会话生命周期及复制；增加失败回滚、生命/死亡/掉落写回和跨会话隔离测试。

### P0-4 装备命令允许非装备污染槽位，客户端/服务器槽位协议不一致

**状态：未关闭。**

**证据**

- `globals/multiplayer/session_root.gd:747-782`：只要 ID 位于 `materials/runes/equipment` 任一字典就视为 owned，之后直接写 loadout。
- `globals/core/state/equipment_loadout.gd:19-34`：只校验槽索引或槽名，不校验物品类别、护甲部位、盾牌/双手互斥和占槽规则。
- `scenes/multiplayer/client_command_driver.gd:232-245`：客户端 `send_equip()` 把 `slot` 固定为 `String`；服务端武器槽要求 `slot is int`。
- `tests/gdunit/session_root_test.gd:615-625` 仍把材料 `iron_ore` 装入武器槽并断言成功，漏洞被固化为预期行为。

**风险机制**

客户端可污染权威 loadout，继续影响攻击上下文、施法资格、存档和结算；真实客户端接口又无法正确表达服务端整数武器槽。

**最小修复边界**

建立唯一 `EquipmentPolicy + EquipmentTransaction`；从权威注册表解析物品类别、槽位兼容和占槽关系；原子处理返包、移除、双手/盾互斥；协议改为明确 `slot_kind + slot_index/slot_name`；把材料装备成功测试改成拒绝反例。

---

## P1 — 高优先级架构债

### P1-1 远端玩家没有可信服务器存档仓

客户端自报 `save_state` 已被 `network_manager.gd:546-555` 正确忽略；但真实远端入口仍没有账号/服务器持久化仓提供可信材料、装备和 `spell_state`。不能通过恢复信任客户端字典解决。

### P1-2 已决定的七流派武器伤害倍率未统一进入结算

- `globals/combat/damage_resolver.gd:33-64`：仅双手显式 `damage_mult = 1.0`，其余没有已决定倍率。
- `globals/combat/attack_context_factory.gd:141-153`：只乘武器资源自己的 `damage_mult`。

应建立单一流派策略，只乘武器伤害，不得乘法术伤害。

### P1-3 库存默认容量双真相

- `globals/core/state/expedition_inventory.gd:10,20`：`DEFAULT_LIMIT := 30`。
- `globals/core/game_state.gd:32,455`：另有 `DEFAULT_CARRIED_SPACE_LIMIT := 30` 并写回库存。

默认容量与 reset 语义应由库存模型独占。

### P1-4 性能分档与光照分档是两套未协调真相

- `globals/perf/performance_budget_controller.gd:102-113`：动态分档只设置 Viewport FSR scale 并发出 `quality_tier_changed`。
- 全仓未找到业务侧 `quality_tier_changed.connect(...)`。
- `globals/lighting/lighting_controller.gd:47-66`：独立按 renderer 选择 HIGH/MEDIUM，不订阅性能预算。

GPU 压力上升时灯光、阴影、粒子、雾、反射、法术 FX 与 LOD 不跟随，仅降分辨率。

### P1-5 地牢与敌人逻辑仍依赖单玩家全局引用

`dungeon_runtime.gd`、`procedural_dungeon.gd`、`extraction_portal.gd`、`enemy.gd` 仍多处读取或回退 `GameState.current_player`。联机已有 per-peer PlayerContext/PlayerRegistry，但地牢压力、撤离、交互、击杀归属和敌人目标仍可能默认落到本地/房主玩家。

### P1-6 Shader Inspector 参数规范不统一

- `shaders/liquid.gdshader:3-4`：纹理滚动参数无范围/分组提示；`18-19` 的酸液颜色和混合系数仍是硬编码。
- `assets/shaders/dungeon_terrain.gdshader:11-21`：图集坐标、跨度、网格和重复参数无 `hint_range`。
- 本轮搜索未发现 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 形成新的 mobile renderer 阻断。

### P1-7 SessionRoot 测试生命周期门禁失败

`session_root_test.gd` 为 63/63，但有 4 orphan，gdUnit runner 明确退出 101。CI 必须以零 orphan 和退出 0 为门禁，不能只看断言全绿。

### P1-8 全项目解析门禁当前不可靠

本轮两次隔离 editor 扫描未形成可信正常结束：一次只留下版本信息；一次报 `EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit"`。未观察到脚本 Parse Error 不等于扫描通过，应修复运行环境/命令链并恢复稳定退出码。

---

## 已确认保持有效

1. 远端 spawn RPC 继续忽略客户端自报 `save_state`。
2. 普通攻击继续拒绝客户端伪报攻击类型/伤害字段，并由服务端构造权威 AttackContext。
3. 普通攻击继续写回 `_entities`，玩家攻击冷却继续走 `AttackCadencePolicy`。
4. `project.godot:179-180` 为桌面 `forward_plus`、移动 `mobile`。
5. `export_presets.cfg` 包含 Web、Windows Desktop、Android；Android arm64 启用。
6. 当前 shader 搜索未发现 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 的新发布阻断。

---

## 验证结果

### 通过

- `connection_authority_test.gd`：29/29，0 orphan，runner 退出 0。
- `movement_authority_test.gd`：12/12，0 orphan，runner 退出 0。
- `spell_network_completion_test.gd`：4/4，0 orphan，runner 退出 0。
- `spell_world_executor_test.gd`：4/4，0 orphan，runner 退出 0。
- `spell_session_atomicity_test.gd`：8/8，0 orphan，runner 退出 0。
- `performance_budget_controller_test.gd`：4/4，0 orphan，runner 退出 0。
- `attack_context_factory_test.gd`：12/12，0 orphan，runner 退出 0。

合计：**73/73，0 orphan**。

### 未通过门禁

- `session_root_test.gd`：63/63，4 orphan，runner 退出 101。
- Godot editor 全项目扫描：运行环境/EditorSettings 初始化异常，未形成可接受的正常退出证据。

### 未执行

真实 ENet 双客户端重复 GUID、专服 30/60/120Hz 输入压测、authority-only 真实墙体碰撞、法术 `_entities` 写回/世界失败回滚、装备策略端到端、Windows/Android 实际导出、Android 真机 GPU/热稳定性、窗口视觉验收和全量 gdUnit4。

---

## 建议整改顺序

1. 唯一 GUID、在线重复身份拒绝、重连/结算隔离。
2. 专服固定 tick 输入缓冲与仅碰撞地牢表示。
3. 法术统一权威实体仓、执行失败回滚和会话级执行器生命周期。
4. 装备策略、协议与库存/loadout 原子事务。
5. 清除 SessionRoot orphan，并恢复可靠全项目解析门禁。
6. 接入已决定的七流派武器伤害倍率。
7. 合并质量分档真相，接通灯光、阴影、粒子、法术 FX 与 LOD 消费者。
8. 移除库存容量双真相、地牢单玩家全局依赖，并补齐 shader uniform hints。

---

## 执行限制

本轮曾尝试并行启动网络、权威、渲染和测试审查代理，但四个代理均因认证层 403（仅允许 WorkBuddy 客户端）在开始执行前失败。上述分析与测试均由主审查流程直接完成，未伪造或代填失败代理的结果。若后续需要并行复核，可在代理认证恢复后重试。
