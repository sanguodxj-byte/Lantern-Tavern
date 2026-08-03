# Lantern Tavern 架构审查（2026-08-03 04:11）

## 执行结论

本轮为相对 `outputs/architecture_review_2026-08-03-0306.md` 的增量只读复审。结论没有反转：上一轮 **4 个 P0 全部仍未关闭**，当前仍不建议进入多人发布、专用服务器发布或 Android 发布。

- P0：4 项，证据链无实质变化。
- P1：8 项；除既有架构债外，本轮补充确认运行时存在两套未协调的质量分级系统。
- Godot 4.7 全项目解析扫描退出 0；扫描过程仍报告旧测试报告图标缺失和 EditorSettings 初始化告警。
- 专项测试 146/146 用例通过，但 `session_root_test.gd` 仍有 4 orphan，进程退出 101，并报告 35 个 ObjectDB 实例和 15 个资源泄漏。
- 本轮未修改业务代码、场景、资产或项目配置。

---

## P0 — 发布阻断

### P0-1 大厅固定 GUID 与在线重复身份覆盖

**证据**

- `scenes/ui/lobby_menu.gd:218-225` 加入房间只传地址和端口。
- `globals/multiplayer/multiplayer_session.gd:79-90` 默认 `player_guid="client"`。
- `globals/multiplayer/session_root.gd:170-195` 先创建状态节点、上下文、基线并注册玩家，之后才调用 `register_online()`，不存在重复身份预检或失败回滚。
- `globals/multiplayer/connection_authority.gd:35-45` 的 `register_online()` 返回 `void`，同 GUID 直接覆盖 `_guid_to_peer`。
- `globals/multiplayer/save_authority.gd:8,23-24,40-64` 以 GUID 作为结算幂等账本主键。
- `tests/gdunit/connection_authority_test.gd:31-270` 的 29 个用例仍没有“第二个 ONLINE peer 使用同 GUID 必须失败”的覆盖。

**影响**

多个真实远端客户端默认共用 `client` 身份；后加入者可覆盖身份索引，导致错误重连、状态接管和跨玩家结算串账。

**最小修复边界**

客户端持久化随机 GUID；服务器在创建任何节点/上下文前执行在线唯一性预检；`register_online()` 返回结构化结果；仅允许 token 匹配的 GRACE 身份迁移；补重复身份、重连隔离与结算隔离集成测试。

### P0-2 专服移动仍按 RPC 频率加速且无墙体裁决

**证据**

- `globals/core/network_manager.gd:559-567` 每条可靠输入 RPC 都立即进入命令处理，无 per-peer 最新输入缓冲和固定服务器 tick 消费。
- `globals/multiplayer/session_root.gd:97-98,590-600` 每次命令都用固定 `SERVER_TICK_DT=1/30` 结算。
- `scenes/multiplayer/dungeon_session_controller.gd:38-52` 的 `build_authority_only()` 只生成 layout 和出生点；墙体/地板碰撞只在 `54-76` 的完整场景构建路径产生。
- `globals/multiplayer/movement_authority.gd:64-80` 未绑定有效碰撞体时回退纯数学积分。
- 现有 47 个身份/移动用例通过，但没有 30/60/120Hz 等时位移一致性、输入洪泛限频或 authority-only 地牢穿墙测试。

**影响**

客户端提高合法递增 sequence 的发送频率即可获得更多次固定步长位移；专用服务器没有静态墙体碰撞，无法裁决穿墙。

**最小修复边界**

RPC 只更新最新输入；服务器 `_physics_process` 每 peer 每 tick 最多消费一次；专服生成仅碰撞地牢表示；增加频率不变性、洪泛和真实墙体阻挡测试。

### P0-3 联机法术绕过权威实体仓，失败事务仍被包装为成功

**证据**

- `globals/multiplayer/session_root.gd:680-704` 先扣法力、提交冷却，再执行 `spell_auth.execute()`；没有检查 `authority_execution.ok` 或嵌套的 `world_execution.ok`，固定发布 `EVT_SPELL_RESOLVED` 并返回成功。
- 同文件普通攻击在 `520-535` 写回 `_entities`、死亡、掉落和复制事件；法术路径没有等价实体写回。
- `globals/combat/spell_authority.gd:46-59` 将 ray/area/ground/summon 交给场景执行器。
- `globals/combat/spell_world_executor.gd:25-67,105-148` 直接查询场景节点并调用 `try_receive_hit`/`health.take_damage`，不经过 `SessionRoot._entities`。
- `globals/combat/spell_world_executor.gd:34-50` 在场或召唤预算满时返回 `ok=false`。
- `tests/gdunit/spell_session_atomicity_test.gd:64-79` 只确认资源提交和成功事件；没有验证 `_entities` 生命写回，也没有预算失败回滚测试。

**影响**

服务器可能扣法力、进入冷却并播放成功 FX，但同步敌人生命不变；预算满或具体世界执行失败也会对客户端宣告成功。

**最小修复边界**

让法术统一通过会话拥有的实体仓/世界战斗端口；实现 `prepare -> execute -> commit -> publish`，世界失败不得提交资源；持续场与召唤必须由 SessionRoot 生命周期登记和清理；补实体写回、死亡/掉落和失败回滚测试。

### P0-4 装备命令仍允许材料/符文污染装备槽

**证据**

- `globals/multiplayer/session_root.gd:747-782` 只要物品存在于 `materials/runes/equipment` 任一字典就允许写入 loadout。
- `globals/core/state/equipment_loadout.gd:19-34` 只校验槽索引/槽名，不校验类别、护甲部位、盾牌、单双手占槽或互斥关系。
- `scenes/multiplayer/client_command_driver.gd:232-245` 把 `slot` 固定为 `String`；服务端武器槽分支要求 `slot is int`。
- `tests/gdunit/session_root_test.gd:615-625` 继续把材料 `iron_ore` 装进武器槽并断言成功，漏洞仍被固化为预期行为。

**影响**

客户端可污染权威装备状态，继而影响攻击上下文、法术资格、存档和结算；真实客户端协议又无法正确表达服务器武器槽整数。

**最小修复边界**

建立唯一 `EquipmentPolicy + EquipmentTransaction`；从权威注册表解析类别与允许槽位；原子处理返包、移除、双手/盾互斥和 loadout 更新；协议改为明确 `slot_kind + slot_index/slot_name`；删除材料装备成功测试。

---

## P1 — 高优先级架构债

### P1-1 法术世界执行器静态跨会话共享

`globals/combat/spell_authority.gd:9,56-59` 使用 `static var _world_executor`。字段、召唤预算和节点归属会跨 SessionRoot/场景重开共享。应改为会话实例拥有并显式释放。

### P1-2 远端玩家仍没有可信存档仓

`globals/core/network_manager.gd:546-555` 正确忽略客户端自报存档，但真实远端入口也没有服务器账号/存档仓，默认上下文无法恢复装备和法术装配。不能恢复信任客户端字典，应接服务器持久化或房主批准的会话配置。

### P1-3 已决定的流派武器伤害倍率仍未统一进入结算

- `globals/combat/damage_resolver.gd:33-65` 只有双手风格存在占位 `damage_mult=1.0`。
- `globals/combat/damage_resolver.gd:326-348` 最终基础伤害只乘 `AttackInput.weapon_damage_mult`。
- `globals/combat/attack_context_factory.gd:135-157` 只应用武器资源自己的 `damage_mult`。

项目已决定的单手/持盾/双手/双持/徒手/远程/法系武器倍率尚未作为单一策略进入结算；必须保证只作用于武器伤害，不影响法术卡伤害。

### P1-4 库存默认容量双真相

`globals/core/state/expedition_inventory.gd:10,20` 与 `globals/core/game_state.gd:32,451-455` 分别持有默认 30。应让库存模型独占默认值及 reset 语义。

### P1-5 两套运行时质量系统未协调，性能档位仍无真实成本消费者

- `project.godot:47,49` 同时 autoload `LightingController` 与 `PerformanceBudget`。
- `globals/perf/performance_budget_controller.gd:102-113` 只改变 3D FSR scale 并发信号。
- 全仓库只有信号定义与 emit，没有 `quality_tier_changed.connect(...)`。
- `globals/lighting/lighting_controller.gd:47-63` 另行按 renderer 初始化自己的 HIGH/MEDIUM/LOW 档位，未订阅 PerformanceBudget。

结果是分辨率会动态降级，但灯光、阴影、粒子、雾、反射、法术 FX 和 LOD 不随 GPU 压力变化；两个质量真相还可能长期漂移。Android 前应合并为单一质量配置源并接真实成本消费者。

### P1-6 SessionRoot 严格测试门禁仍失败

`session_root_test.gd` 为 63/63 通过，但有 4 orphan，Runner 退出 101；本轮还报告 35 个 ObjectDB 实例与 15 个资源仍在使用。CI 必须以进程退出码判定，不得只看断言通过数。

### P1-7 地牢与敌人逻辑仍依赖单玩家全局引用

- `scenes/expedition/dungeon_runtime.gd:148,214,502,548-549`
- `scenes/expedition/procedural_dungeon.gd:159-160,225`
- `scenes/expedition/extraction_portal.gd:193`
- `scenes/characters/enemies/enemy.gd:306,612,684,745`

这些路径继续读取 `GameState.current_player`。联机已经有 per-peer `PlayerContext/PlayerRegistry`，地牢压力、撤离、交互、击杀归属和目标回退仍可能默认落到本地/房主玩家。

### P1-8 Shader Inspector 参数规范不统一

本轮没有发现 `SCREEN_TEXTURE`/`DEPTH_TEXTURE`/`discard` 的移动端发布阻断；现有显式火焰/炼金 shader 也记录了 Mobile 安全边界。但多份已出货 shader 的 artist-facing uniform 缺少 Inspector hint：

- `shaders/liquid.gdshader:3-4` 的纹理/滚动速度无明确语义 hint。
- `scenes/tavern/materials/tavern_atlas_world_32px.gdshader:6-12,14-24` 大量范围参数无 `hint_range`。
- `assets/shaders/dungeon_terrain.gdshader:11-21` 图集参数无范围 hint。

这不是当前发布阻断，但违反 shader 参数规范，容易造成越界配置与艺术交接失控。应为颜色、法线、范围和开关补齐 `source_color`、`hint_normal`、`hint_range` 等 Inspector 约束。

---

## 已确认保持有效

1. 远端 spawn RPC 继续忽略客户端自报 save_state（`network_manager.gd:546-555`）。
2. 客户端伪报 `attack_type` 继续被白名单拒绝；攻击类型、射程、冷却和伤害输入由权威 loadout 派生（`session_root.gd:446-519`）。
3. 普通攻击继续写回 `_entities` 并产生伤害/死亡复制事件（`session_root.gd:520-535`）。
4. Windows/Android 导出预设仍存在，Android arm64 已开启（`export_presets.cfg:51-179`）。
5. 桌面 `forward_plus`、移动 `mobile` 配置保持正确（`project.godot:177-181`）。
6. 当前 shader 扫描未发现 `SCREEN_TEXTURE`、`DEPTH_TEXTURE` 或 `discard` 的移动后端阻断用法。

---

## 验证结果

- Godot 4.7 headless editor 全项目解析扫描：退出 0；扫描时报告旧 `reports/report_3690/css/logo.png` 缺失和 EditorSettings 初始化告警，无脚本解析错误。
- `session_root_test.gd`：63/63，通过；4 orphan；35 ObjectDB/15 resources leaked；退出 101。
- 身份/移动：29 + 12 + 6 = 47/47，通过；0 orphan；退出 0。
- 法术：8 + 4 + 4 = 16/16，通过；0 orphan；退出 0。
- 装备/性能/攻击上下文：4 + 4 + 12 = 20/20，通过；0 orphan；退出 0。
- 专项合计：**146/146 用例通过**；严格门禁仍因 SessionRoot 生命周期泄漏失败。

未执行：全量 gdUnit4、真实 ENet 双客户端、重复 GUID 在线冲突集成、专服 30/60/120Hz 输入压测、authority-only 地牢墙体碰撞、法术对 `_entities` 的端到端写回、实际 Windows/Android 导出、Android 真机 GPU/热稳定性和窗口视觉验收。

---

## 建议整改顺序

1. 唯一 GUID、在线重复身份拒绝、重连/结算隔离。
2. 专服固定 tick 输入缓冲与仅碰撞地牢表示。
3. 法术统一权威实体仓和真正原子事务。
4. 装备策略、协议与库存/loadout 原子事务。
5. 清除 SessionRoot orphan/leak，并将退出 101 作为 CI 失败。
6. 接入已决定的流派武器伤害倍率。
7. 合并质量分级真相，接通灯光/阴影/粒子/法术 FX/LOD 消费者。
8. 移除库存容量双真相、地牢单玩家全局依赖，并补齐 shader uniform hints。

## 工作树风险

当前工作树仍包含大规模已修改和未跟踪文件。本报告只代表 2026-08-03 04:11 的当前磁盘快照，不代表干净提交或可复现发布候选。解析扫描触发了 Godot 资源扫描/导入，但本轮没有主动修改业务源码、场景、资产或项目配置。
