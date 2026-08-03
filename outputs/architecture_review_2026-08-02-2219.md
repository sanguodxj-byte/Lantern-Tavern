# Lantern Tavern 增量架构审查（2026-08-02 22:19）

**性质**：只读增量复审；未修改业务代码、场景、资产或项目配置。  
**基线**：当前工作树有 **1928 个脏路径**（387 个已跟踪变更、1541 个未跟踪路径），跨代码、模型、纹理、文档、测试与生成物；结论只对应当前机器状态，不是可复现发布基线。  
**总体评级**：**D（新增确认默认共享 player_guid 可造成联机身份与结算账本碰撞；移动、攻击、法术、平台与门禁阻断项仍未关闭）**。

## 1. 本轮验证

- 已完整读取 `docs/术语表.md` 与上一轮 21:19 报告。
- Godot 4.7 Mono headless editor 扫描完成，未见脚本解析错误；由于 `--quit-after 4` 在首次扫描尚未完全结束时退出，打印 `Scan thread aborted` 警告，因此不能替代完整导入/编辑器启动验收。
- `session_root_test.gd`：**62/62 断言通过，但 4 orphan，退出 101；33 个 ObjectDB 实例和 14 个资源泄漏**。
- `movement_authority_test.gd`：**12/12，通过，0 orphan**。
- `spell_network_completion_test.gd`：**4/4，通过，0 orphan**；测试仍主要检查源码片段形状。
- `performance_budget_controller_test.gd`：**4/4，通过，0 orphan**；报告清理阶段无法删除旧 `reports/report_3644`，打印多条文件删除错误但进程仍退出 0。
- 未运行全量套件、真实 ENet 双进程、窗口 3D、Android 真机与 Windows/Android 导出。

## 2. 相对 21:19 审查的新增结论

### P0-新增：真实大厅默认复用固定 `player_guid`，身份与结算账本可发生跨玩家碰撞

**证据**：

- `globals/multiplayer/multiplayer_session.gd:47` 房主默认 `player_guid="host"`；`:75` 客户端默认 `player_guid="client"`。
- `scenes/ui/lobby_menu.gd:213,225` 真实大厅调用 `host_room()` / `join_room()` 时都没有传入持久且唯一的玩家身份，因此所有客户端默认使用同一个 `"client"`。
- `globals/multiplayer/connection_authority.gd:35-45` 注册时直接执行 `_guid_to_peer[player_guid] = peer_id`，没有重复 GUID 拒绝或在线占用检查，后加入者覆盖稳定身份索引。
- `globals/multiplayer/save_authority.gd:23-24,39-56` 出征结算幂等账本以 `player_guid` 为唯一键。
- `globals/multiplayer/session_root.gd:760-776` 结算直接以 `_peer_guid()` 查询/写入该账本。

**影响**：两个正常客户端通过大厅加入同一房间时会共享 `"client"` 身份。后加入者覆盖 GUID→peer 索引；任意一个先结算后，另一个会被判定为 `already_settled` 并拿到前者的 settlement 快照。断线重连按 GUID 反查时也可能锚到错误玩家。该问题不需要恶意客户端，第二个正常客户端即可触发。

**整改**：大厅必须从本地存档/账号层读取不可变、随机生成且持久化的 UUID；服务器 spawn 时拒绝空 GUID、默认字面量和“已被在线 peer 占用”的 GUID。`ConnectionAuthority.register_online()` 应返回可失败结果并保持双向唯一约束；结算账本主键使用服务器签发的 session identity，而不是客户端任意字符串。补真实两客户端测试：不同身份独立结算；相同 GUID 的第二次 spawn 被拒；断线重连只能接管对应 token 的旧上下文。

## 3. 仍未关闭的 P0

### P0-1 服务器移动仍由命令到达次数驱动，并绕过碰撞

- `globals/multiplayer/session_root.gd:92` 固定每条输入使用 `1/30s`；`:543-560` 每次 `CMD_INPUT` 立即积分并写位置。
- `globals/core/network_manager.gd:545-551` 每个 reliable RPC 都立即进入 `_server_handle_command()`，没有 per-peer 最新输入缓存、每 tick 最多消费一次或速率门禁。
- `globals/multiplayer/movement_authority.gd:51-71` 只有 `old_pos + dir * speed * dt`，没有 `CharacterBody3D`、physics sweep 或地牢阻挡验证。
- `tests/gdunit/movement_authority_test.gd:79-105` 仅验证数学距离，不覆盖命令洪泛、墙体或固定服务器 tick。

**影响**：高频发送合法递增序列即可加速；所有移动可穿墙、穿门、越过地形阻挡。

**整改**：NetworkManager 只缓存每 peer 最新输入；服务器固定 30Hz 消费一次；由服务器碰撞世界中的 `ServerCharacterMotor` 计算位置。补 120Hz 输入洪泛不提速、撞墙不穿透、关闭门不可通过的双进程测试。

### P0-2 联机攻击仍信任客户端 `attack_type`，且权威 AttackInput 不完整

- `scenes/multiplayer/client_command_driver.gd:114-130` 客户端上送 `attack_type`。
- `globals/multiplayer/session_root.gd:423-430` 用客户端类型选择 18m/2.5m，并把任意非空武器视为可支撑远程。
- `session_root.gd:462-470` 只填六维属性并再次复制客户端 `attack_type`；未从权威武器构造武器骰、平伤、流派、手位、熟练度、元素、词缀与被动。
- `globals/multiplayer/combat_authority.gd:75-82` 已有武器归属辅助方法，但主链未调用。

**影响**：客户端可伪报远程；联机伤害退化为 `DamageResolver.AttackInput` 默认武器数据，与单机装备规则分叉。

**整改**：移除协议中的 `attack_type`；新增唯一的 `AttackContextFactory(ctx.loadout + WeaponRegistry + attributes + skills)`，由服务器同时产出攻击类型、射程、完整 AttackInput 与表现标签。

### P0-3 攻击冷却仍是多套规则

- `globals/combat/combat_engine.gd:33,55-57`：已裁定公式 `1.0 / (style_mult * dex_mult)`。
- `globals/multiplayer/session_root.gd:94-95,476-477`：服务端固定 0.4 秒。
- `scenes/multiplayer/client_command_driver.gd:25-27,119-121`：客户端固定 0.5 秒发送门。
- 单机玩家另由 `PlayerCombatRuntime` 的物理 tick 推进动作节奏。

**影响**：同一装备在单机、房主、远端客户端具有不同 DPS/手感；服务端固定冷却没有落实已裁定的硬锁语义。

**整改**：建立纯逻辑 `AttackCadencePolicy`，由权威攻击上下文计算冷却；单机与服务端共用，客户端节流仅作为防洪，HUD 只显示权威剩余时间。

### P0-4 法术可先扣资源、提交冷却，再因 caster 未绑定而“假成功”

- `globals/multiplayer/session_root.gd:606-611` 先提交权威冷却并扣法力。
- `session_root.gd:616-618` 仅 `ctx.player_node != null` 时才执行世界效果；否则仍构造成功事件。
- `session_root.gd:184-185` 正常 spawn 的 `PlayerContext` 明确以 `player_node=null` 创建。
- 全仓仅单机 `GameState` 会写 `player_node`；联机地牢控制器没有 `bind_player_entity(peer_id, player)` 路径。

**影响**：真实联机可出现法力减少、冷却生效、事件广播成功，但世界没有任何效果。

**整改**：服务器必须先完成 peer→PlayerEntity 绑定；施法采用 validate/prepare → execute → commit → publish 的事务顺序。caster、资格或执行失败时不得扣资源与提交冷却。

### P0-5 正常多人入口没有权威 `spell_state` 来源，服务端也不验证施法资格

- `globals/multiplayer/multiplayer_session.gd:53,86` 真实房主/客户端 spawn 都传空状态。
- `globals/core/network_manager.gd:408-413,530-541` 远端客户端存档被正确忽略，但当前没有服务器身份仓库补充该玩家的权威装配。
- `globals/multiplayer/session_root.gd:194-198` `_apply_save_state()` 只恢复 materials/loadout，不恢复 spell state。
- `globals/core/player_context.gd:34-37` 每个 peer 默认空法术装配、100 法力。
- `session_root.gd:595-635` 没有调用 `SpellAccessPolicy` 验证法杖、魔导书或“奥法之剑”资格。

**影响**：真实入口通常无法获得已装配法术；若通过其他路径填入装配，又可绕过武器/被动施法资格。

**整改**：服务器身份仓库加载统一 `DungeonPlayerSnapshot`（背包、装备、法术装配、法力、资格相关被动）；服务端用权威装备元数据调用同一纯逻辑 `SpellAccessPolicy`。

### P0-6 库存 UI 仍读取不存在的 `GameState` 常量

- `scenes/ui/tavern_equipment_panel.gd:1514,1522-1523` 读取 `GameState.MATERIAL_SPACE_PER_ITEM/RUNE_SPACE_PER_ITEM`。
- 常量实际位于 `globals/core/state/expedition_inventory.gd:7-8`。

**影响**：对应转移路径可能产生无效成员访问；UI 仍直接承担库存事务、容量与刷新逻辑。

**整改**：建立 `InventoryTransferService`，统一容量校验、类别、原子回滚和错误码；UI 只提交意图和刷新视图。

### P0-7 Android renderer 与目标平台导出仍未闭环

- `project.godot:177-180` 仍为 `renderer/rendering_method.mobile="forward_plus"`，未使用目标 `gl_compatibility`/Mobile 分档中的 Mobile renderer 配置。
- `export_presets.cfg:1-49` 只有 Web preset，没有 Windows/Android。

**影响**：现代 Android 目标没有受控的 Mobile renderer 与发布配置，桌面/Android 都无法通过项目内 preset 做可复现导出。

**整改**：将移动端明确配置为 Godot 4 Mobile renderer，补 Windows/Android presets 与 export dry-run；在 Android 真机记录 GPU 帧时、温升、峰值内存和材质降级。

## 4. 仍未关闭的 P1/P2

1. **装备命令不验证物品类型与槽位兼容**：`session_root.gd:672-686` 接受 materials/runes/equipment 任一字典中的 ID；`equipment_loadout.gd:19-33` 是纯字符串容器。现有测试 `session_root_test.gd:604-612` 甚至把 `iron_ore` 装入武器槽并断言成功，已把漏洞固化为“正确行为”。应新增 `EquipmentPolicy/LoadoutTransaction` 并改为负向测试。
2. **SpellAuthority 静态持有世界节点**：`globals/combat/spell_authority.gd:9,46-49` 的 `static var _world_executor` 让多个会话/世界共享节点与预算；应由 Session/World composition root 每世界持有并注入。
3. **流派武器伤害倍率未按已决定值统一**：`globals/combat/damage_resolver.gd:33-65` 仍含占位值，双手 `damage_mult` 为 1.0；联机 AttackInput 也未设置 style。法术不得乘流派武器倍率。
4. **规则层仍依赖 `GameState.current_player`**：`procedural_dungeon.gd`、`dungeon_runtime.gd`、`extraction_portal.gd`、`enemy.gd` 等仍有单玩家回退，多人 Listen/Dedicated 边界不稳。
5. **世界法术实体未进入复制真相源**：`SpellWorldExecutor` 直接创建 Area3D/Node3D 并直接伤害节点；晚加入、重连与服务器恢复无法重建持续场/召唤。
6. **PerformanceBudget 没有真正的分档消费者**：`globals/perf/performance_budget_controller.gd:102-113` 只改 FSR scale；全仓没有 `quality_tier_changed.connect`，灯光、阴影、粒子、后处理各自为政。
7. **CI 把 orphan 当绿色**：`run_ci.ps1:9-15,40-42` 将退出 101 转成 0；本轮 SessionRoot 仍稳定复现 4 orphan、33 ObjectDB、14 资源泄漏。
8. **测试报告目录与并行执行相互污染**：多个并行测试都写 `reports/report_3664`，性能测试清理旧 `report_3644` 失败但仍退出 0。报告目录应按进程唯一或放项目外，并将报告清理错误纳入门禁。
9. **工作树不可审计**：1928 个脏路径使专项通过不能等同于可复现基线；禁止盲目 `git add -A`。

## 5. 建议执行顺序

1. **先修身份与移动权威**：唯一服务器身份、重复 GUID 拒绝、固定 tick 输入缓存、服务器碰撞 motor。
2. **统一攻击上下文与节奏**：`AttackContextFactory + AttackCadencePolicy`，删除客户端 attack_type。
3. **修法术事务与所有权**：实体绑定、服务器资格、权威状态加载、execute-before-commit、每世界 executor、持续实体注册复制。
4. **建立装备/库存领域服务**：`EquipmentPolicy + LoadoutTransaction + InventoryTransferService`，删除“材料可装备”测试。
5. **完成平台闭环**：Mobile renderer、Windows/Android presets、统一 RenderingProfile 消费者。
6. **收紧测试门禁**：orphan 101 改红或严格 allowlist；测试报告目录进程隔离；源码字符串测试替换为真实行为和双进程测试。
7. **从干净主题分支复跑**：全量 gdUnit4、真实 ENet 两客户端、窗口 3D、Windows/Android export dry-run 与 Android 真机。

## 6. 范围声明

本轮未修改业务实现。专项测试通过只说明现有纯逻辑或源码形状满足测试，不证明身份隔离、服务器碰撞、输入频率权威、真实装备攻击、法术事务、持续实体复制、渲染或 Android 发布正确。上述 P0 应按发布阻断处理。
