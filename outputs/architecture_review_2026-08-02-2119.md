# Lantern Tavern 增量架构审查（2026-08-02 21:19）

**性质**：只读增量复审；未修改业务代码、场景、资产或项目配置。  
**基线**：当前工作树仍有约 **1926 个脏路径**，跨代码、模型、纹理、文档、测试与生成物；结论只对应当前机器状态，不是可复现发布基线。  
**总体评级**：**D（新增确认服务器移动可按 RPC 到达速率加速且无碰撞；既有战斗、法术、平台与门禁阻断项仍未关闭）**。

## 1. 本轮验证

- 已完整读取 `docs/术语表.md` 和项目约束。
- Godot 4.7 Mono 控制台版 headless editor 扫描完成；脚本扫描未报解析错误，但报告目录存在一条过期资源：`reports/report_3642/css/logo.png.import` 指向缺失 `logo.png`，编辑器扫描打印导入错误。
- `session_root_test.gd`：**62/62 断言通过，但 4 orphan，退出 101；33 个 ObjectDB 实例和 14 个资源泄漏**。
- `spell_end_to_end_test.gd`：**4/4，通过，0 orphan**。
- `spell_network_completion_test.gd`：**4/4，通过，0 orphan**。
- `spawn_save_state_security_test.gd`：**3/3，通过，0 orphan**。
- `performance_budget_controller_test.gd`：**4/4，通过，0 orphan**。
- `movement_authority_test.gd`：**12/12，通过，0 orphan**；但该测试只验证纯数学积分，不覆盖碰撞或输入速率上限。
- 未运行全量套件、真实 ENet 双进程、窗口 3D、Android 真机和平台导出。

## 2. 相对 19:52 审查的新增结论

### P0-新增：服务器移动速度由“命令到达次数”决定，可加速且可穿墙

**证据**：

- `globals/multiplayer/session_root.gd:91-95` 固定每条输入命令使用 `SERVER_TICK_DT = 1/30`，而不是按服务器固定模拟 tick 消费最新输入。
- `globals/core/network_manager.gd:545-551` 每收到一次可靠 `rpc_client_command` 就立即调用 `_server_handle_command()`，没有 per-peer 输入速率限制、时间戳窗口或“每 tick 最多消费一次”队列。
- `globals/multiplayer/session_root.gd:543-550` 每条合法 `CMD_INPUT` 都调用 `movement_auth.resolve_input_frame(..., SERVER_TICK_DT)` 并立即写入新位置。
- `globals/multiplayer/movement_authority.gd:51-57,61-80` 仅执行 `old_pos + dir * speed * dt`，没有 `CharacterBody3D.move_and_slide()`、物理 sweep、导航可行性或地牢阻挡校验。
- `tests/gdunit/movement_authority_test.gd:80-105` 只断言数学距离，没有墙体、门、坡差、命令洪泛或固定 tick 行为测试。

**影响**：客户端即使不直接上报坐标，也可通过高频发送严格递增序列的合法输入帧，使服务器每条命令都前进 `speed/30` 米；实际速度取决于 RPC 到达频率，而不是服务器时间。同时移动完全绕过墙、门和地形碰撞。这比“仅无碰撞”更严重：它同时破坏速度权威和空间权威。

**整改**：NetworkManager 只缓存每个 peer 最新输入；服务器固定 30Hz tick 每 peer 最多消费一次。最终位移必须由 `ServerCharacterMotor` 在服务器碰撞世界中计算；Dedicated Server 加载简化碰撞场景。补双进程行为测试：120Hz 命令洪泛不提速、持续撞墙不穿透、关闭门不可通过。

### P1-新增：装备命令只验证“任意库存类别持有”，不验证装备类型与槽位兼容

**证据**：

- `globals/multiplayer/session_root.gd:672-686` 将 `materials/runes/equipment` 任一字典中存在的 `item_id` 都视为 owned，然后允许写入武器槽或护甲槽。
- `globals/core/state/equipment_loadout.gd:19-33` 是纯字符串容器，不验证 WeaponRegistry 类型、双手占位、盾牌、副手、护甲部位或互斥规则。

**影响**：客户端可以把材料或符文 ID 装入武器/护甲槽；也可以把错误部位装备写入任意槽。当前战斗尚未正确消费装备，因此破坏暂时被掩盖；一旦服务端 AttackContext 接入 loadout，这会直接污染权威战斗上下文。

**整改**：新增 `EquipmentPolicy`/`LoadoutTransaction`，服务器按权威 ItemRegistry 元数据校验 item kind、slot compatibility、双手/副手互斥和数量，再原子写入；EquipmentLoadout 保持纯数据容器，不承担规则。

### P1-新增：法术执行器使用进程级静态世界执行器，跨会话/世界污染风险

**证据**：

- `globals/combat/spell_authority.gd:9` 定义 `static var _world_executor`。
- `spell_authority.gd:46-49` 首次执行后把它挂到 caster/world 下；后续所有 `SpellAuthority` 实例共用这一静态节点。
- `globals/combat/spell_world_executor.gd:7-12` 在实例内维护全局场/召唤预算数组。

**影响**：单机、Listen Server、测试和场景切换可能共享同一个 executor/预算；旧世界节点失效后才重建，且多个会话无法获得独立预算和生命周期所有权。Dedicated Server 多房间时尤其不可接受。

**整改**：由 Session/World composition root 持有每世界一个 `SpellWorldExecutor`，显式注入 `SpellAuthority`；禁止静态 Node 所有权。

## 3. 仍未关闭的 P0

### P0-1 联机攻击仍信任客户端 `attack_type`，服务端 AttackInput 不完整

- `scenes/multiplayer/client_command_driver.gd:114-130` 客户端提交 `attack_type`。
- `globals/multiplayer/session_root.gd:423-430` 用客户端类型决定 18m/2.5m；任意非空武器都能支撑远程。
- `session_root.gd:462-475` 只填六维属性和客户端类型，未填武器骰、平伤、武器倍率、流派、手位、熟练度、元素、词缀和被动。
- `globals/multiplayer/combat_authority.gd:75-82` 已有归属校验，但主链没有调用。

**结论**：客户端可伪报远程；联机伤害退化为 DamageResolver 默认输入，与单机装备规则分叉。应由 `AttackContextFactory(ctx.loadout + WeaponRegistry + attributes + skills)` 唯一构造攻击类型、射程、伤害输入和表现标签。

### P0-2 攻击冷却仍是多套规则

- `globals/combat/combat_engine.gd:33,55-57`：已裁定公式 `1.0 / (style_mult * dex_mult)`。
- `globals/multiplayer/session_root.gd:94-100,476-477`：服务端固定 0.4 秒。
- `scenes/multiplayer/client_command_driver.gd:25-27,119-121`：客户端固定 0.5 秒发送门。
- 单机 PlayerCombatRuntime 仍有独立动作节奏。

**结论**：建立纯逻辑 `AttackCadencePolicy`，单机、服务端和 HUD 共用；客户端节流只防洪，不是玩法冷却。

### P0-3 法术先提交资源，caster 缺失时仍返回成功

- `session_root.gd:606-611` 先 commit 冷却并扣法力。
- `session_root.gd:617-618` 仅 `ctx.player_node != null` 时执行世界效果。
- `session_root.gd:184-185` 正常 spawn 创建的 context 中 player 为 null。
- `scenes/multiplayer/dungeon_session_controller.gd:94-107` 创建真实 Player 后没有绑定回 SessionRoot context。

**结论**：新增 `bind_player_entity(peer_id, player)`；caster/资格/世界执行任一失败必须在 commit 前拒绝。施法改为 prepare → execute/validate → commit → publish，或完整回滚。

### P0-4 正常多人入口没有权威 `spell_state` 来源，服务端不验证施法资格

- `session_root.gd:194-198` `_apply_save_state()` 只恢复 materials/loadout，不恢复 spell_state。
- `globals/core/player_context.gd:34-37` 默认空 SpellLoadout、100 法力。
- `session_root.gd:595-635` 未调用 `SpellAccessPolicy` 验证法杖、魔导书或奥法之剑。

**结论**：服务器身份仓库加载统一 `DungeonPlayerSnapshot`；服务端用权威装备/被动执行同一纯逻辑施法资格政策。

### P0-5 库存 UI 仍访问不存在的 GameState 常量

- `scenes/ui/tavern_equipment_panel.gd:1514,1522-1523` 读取 `GameState.MATERIAL_SPACE_PER_ITEM/RUNE_SPACE_PER_ITEM`。
- 常量实际位于 `globals/core/state/expedition_inventory.gd:7-8`。

**结论**：运行时可能无效成员访问。下沉 `InventoryTransferService`，统一容量检查、原子回滚和错误码。

### P0-6 Android renderer 与平台导出仍未闭环

- `project.godot:177-180`：`renderer/rendering_method.mobile="forward_plus"`，与目标 Mobile renderer 不符。
- `export_presets.cfg:1-49`：只有 Web，没有 Windows/Android。

**结论**：移动端改 Mobile renderer，补 Windows/Android preset 和 export dry-run；再做 Android 真机 GPU 帧时、温升和内存验收。

## 4. 仍未关闭的 P1/P2

1. **流派武器伤害倍率未统一**：`damage_resolver.gd:33-65` 仍未完整表达已决定的七流派 weapon-only `damage_mult`；双手仍为 1.0 占位。
2. **规则层仍依赖 `GameState.current_player`**：`procedural_dungeon.gd`、`dungeon_runtime.gd`、`extraction_portal.gd`、`enemy.gd` 等仍保留单玩家回退；Listen/Dedicated 多人不稳。
3. **世界法术实体未进入 SessionRoot 实体复制真相源**：`SpellWorldExecutor` 直接创建 Area3D/Node3D、直接伤害节点；晚加入和重连不能可靠恢复场与召唤。
4. **性能分档无消费者**：`performance_budget_controller.gd:102-113` 只改 FSR scale；全仓没有 `quality_tier_changed.connect`，LightingController 另有一套质量策略。
5. **CI 将 orphan 视为绿色**：`run_ci.ps1:9-15,40-42` 把退出 101 转 0；本轮 SessionRoot 再次稳定复现 4 orphan、33 ObjectDB、14 资源泄漏。
6. **测试过多验证源码形状而非行为**：法术联机与 spawn 安全专项虽绿，但不能证明真实大厅→spawn→绑定→施法事务或双进程行为。
7. **报告目录导入污染**：`.gitignore` 忽略整个 reports，但 Godot 仍扫描该目录；过期 HTML 报告的 `.import` 可制造编辑器导入错误。测试报告应输出到项目外或加 `.gdignore` 隔离。
8. **工作树不可审计**：大量跨主题未提交变更使“专项通过”不能等同于可复现基线；禁止盲目 `git add -A`。

## 5. 建议执行顺序

1. **先修移动权威**：固定 tick 输入缓存 + 服务器碰撞 motor；这是当前最高优先级安全问题。
2. **统一攻击上下文和节奏**：移除客户端 attack_type；`AttackContextFactory + AttackCadencePolicy` 同时服务单机和联机。
3. **修法术事务与所有权**：peer→PlayerEntity 绑定、资格校验、资源原子 commit、每世界 executor、场/召唤注册复制。
4. **建立 EquipmentPolicy 与 InventoryTransferService**：阻断非法槽位和 UI 领域事务泄漏。
5. **完成平台闭环**：Mobile renderer、Windows/Android presets、统一 RenderingProfile。
6. **收紧门禁**：orphan 101 改红或严格临时 allowlist；把核心源码字符串测试替换为真实行为/双进程测试。
7. **从干净主题分支复跑**：全量 gdUnit4、真实 ENet、窗口 3D、Windows/Android export dry-run 和 Android 真机。

## 6. 范围声明

本轮没有修改业务实现。专项测试通过只说明现有纯逻辑/源码契约满足测试，不证明服务器碰撞、输入频率权威、真实 Enemy、法术事务、渲染或 Android 发布正确。上述 P0 应按发布阻断处理。
