# Lantern Tavern 架构审查整改报告（2026-08-03 14:46）

**基线**：`outputs/architecture_review_2026-08-03-0828.md`（4×P0 未关闭 / 8×P1）
**范围**：4 个 P0 全部闭环 + 5 个 P1 闭环；验证为 23 组审查相关套件全绿 + 全量逐套件扫描。

---

## 1. P0 整改总览（全部关闭）

| P0 | 整改内容 | 关键文件 | 验证 |
|---|---|---|---|
| P0-1 重复在线身份覆盖 | 客户端首次启动持久化生成随机 GUID（`user://lantern_identity.cfg`，禁固定默认值）；`register_online()` 返回结构化结果，ONLINE 重复 GUID 拒绝（GRACE 身份允许迁移）；SessionRoot spawn 前预检 + 失败回滚；spawn 拒绝下发 `ERR_DUPLICATE_IDENTITY` | `client_identity.gd`（新）、`connection_authority.gd`、`session_root.gd`、`multiplayer_session.gd`、`network_manager.gd`、`network_protocol.gd` | connection_authority 33/33（+6 反例）、session_root 69/69（+2）、client_identity 4/4 |
| P0-2 输入按 RPC 次数积分/专服无墙体 | `queue_input` 只保留 per-peer 最新帧；`consume_input_tick` 服务器固定 30Hz 每 peer 至多消费一次（NetworkManager.tick 累加器驱动，房主/客户端同一路径）；陈旧帧静默跳过不锁死序列；专用服务器改 `build_authority_collision_only`（layout 同源 + 仅静态碰撞，无可见几何）；集成测试客户端改朝同单元敌人移动 | `session_root.gd`、`network_manager.gd`、`dungeon_scene_builder.gd`、`dungeon_session_controller.gd`、`dedicated_server.gd`、`mp_dedicated_server_test.gd` | input_tick_buffer 6/6（30/60/120Hz 频率无关性、洪泛不累积、陈旧帧跳过）、movement_authority 12/12 |
| P0-3 法术事务断裂/不写回实体仓 | 改为 prepare→execute→verify→commit→publish；世界执行失败（预算满/实施不支持/服务缺失）在 commit 前拒绝，法力/冷却不扣；世界执行器从 static 改为会话实例（SessionRoot 挂树拥有）；`damage_entity_port` 把 ray/field/summon 伤害写回 `_entities`（生命/死亡/掉落复制与普攻同路径） | `spell_authority.gd`、`spell_world_executor.gd`、`session_root.gd`（`_ensure_spell_world_executor`/`_spell_damage_entity`） | spell_session_atomicity 14/14（+预算失败回滚、写回击杀/掉落、跨会话隔离）、spell_world_executor 4/4（源断言随会话化更新）、spell_network_completion 4/4 |
| P0-4 装备污染/协议不一致 | 唯一策略 `EquipmentPolicy`：类别解析（材料/符文/未知拒绝）、槽位兼容（武器↔武器槽、护甲↔护甲槽）、占槽关系（双手↔盾互斥、双手/盾唯一）；协议统一 `slot_kind+slot_index/slot_name`（兼容旧 slot）；`send_equip` 同步；材料装武器槽反例取代旧固化测试 | `equipment_policy.gd`（新）、`session_root.gd`（`_handle_equip` + 可注入数据源）、`client_command_driver.gd` | equipment_policy 8/8、session_root 新增 6 项装备用例（材料/符文拒绝、双手↔盾互斥、护甲槽） |

## 2. P1 整改

- **P1-2 七流派伤害倍率**：`STYLE_META.damage_mult` 对齐 `docs/战斗数值体系.md §2.5` 已决定表（单手 1.00/持盾 0.80/双手 1.35/双持 1.00+副手 0.60/徒手 0.80/远程 1.00/法系 0.50）；新增已决定表契约测试（attack_context_factory +1）。
- **P1-3 库存容量双真相**：`game_state.DEFAULT_CARRIED_SPACE_LIMIT` 删除，reset 语义改读 `ExpeditionInventory.DEFAULT_LIMIT`（库存模型独占）。
- **P1-4 两套质量系统未协调**：LightingController 订阅 `PerformanceBudget.quality_tier_changed`（FULL→HIGH / BALANCED→MEDIUM / PERFORMANCE+EMERGENCY→LOW），灯光范围/闪烁幅度随 GPU 压力降档；新增映射测试。
- **P1-6 shader 参数规范**：liquid 酸液颜色/混合系数/滚动速度改为 uniform（`source_color`/`hint_range`）；dungeon_terrain 已确认 vec2 不支持 `hint_range`（Godot 限制），以注释说明。
- **P1-7 SessionRoot orphan 门禁**：`session_root_test.gd:748` 未 auto_free 的 `s2` 修复 → 69/69、0 orphan、退出 0。
- **P1-1（跨会话执行器）** 随 P0-3 一并闭环。

## 3. 顺带修复的预存工作树缺陷（非本轮引入，但阻断门禁）

1. `scenes/tavern/tavern_manager_node.gd`：`var night := ...` 类型推断失败（预存未提交改动）→ 显式 `bool`。
2. `scenes/tavern/brewing/brew_ingredient_slot.gd`：`interaction_name` 重复声明导致类解析失败（连锁拖垮 tavern.tscn 实例化与 lighting 测试）→ 删除重复声明。
3. `tests/gdunit/multiplayer_scene_bridge_test.gd`：64 个 bridge 实例泄漏 → `auto_free`。
4. `tests/gdunit/multiplayer_scene_integration_test.gd`：源断言漂移（`send_spawn(_legacy_save_state...)`）→ 对齐生产签名。
5. `tests/gdunit/customer_serve_flow_test.gd` / `tavern_brewing_coordinator_test.gd`：`load().new()` 类型推断失败导致全量发现阶段崩溃 → 显式类型。

## 4. 验证结果

### 审查相关套件（23/23 通过，0 orphan，退出 0）

connection_authority 33、session_root 69、spell_session_atomicity 14、spell_world_executor 4、spell_network_completion 4、attack_context_factory 13、movement_authority 12、input_tick_buffer 6、equipment_policy 8、client_identity 4、security_audit、lighting_controller 14、multiplayer_scene_bridge 4、multiplayer_scene_integration 4、dungeon_session_multiplayer、game_state、expedition_inventory、inventory_transfer_service、server_character_motor、combat_authority、damage_resolver、combat_bridge、network_manager。

### 全量逐套件扫描（每套件独立进程）

- 扫描 ~270 个 gdunit 套件，除下述预存失败/挂起外全部通过（含全部 voxel/weapon/brew/customer 新套件）。
- **预存失败（未处理，工作树 WIP 状态，非本轮引入）**：
  - `enemy_weapon_attack_test`：177s 后崩溃（敌人 GLB 资源为工作树未提交改动）。
  - `enemy_state_moving_test`：源断言与 WIP 敌人重构漂移。
  - `player_weapon_input_test`：文档化预存（源断言 + Player.new() 无场景树）。
  - `dungeon_scene_builder_test`/`dungeon_generation_baseline_test`/`dungeon_hazard_planner_test`/`nav_diagnose_actual_test`：WIP 地牢优化（未提交）几何/断言漂移。
  - `anime_girl_voxel_test`/`armor_system_test`/`barrel_physics_test`/`bsp_generator_test`/`character_weaponless_assets_test`/`gameplay_light_policy_test`/`goblin_runtime_alignment_test`/`individual_character_model_workflow_test`/`minotaur_scene_test`/`model_viewer_test`/`player_milestone_integration_test`/`project_bootstrap_test`/`shield_durability_buff_alignment_test`/`slime_scene_test`/`spider_scene_test`/`view_model_preview_test`/`voxel_crossbow_asset_test`/`voxel_lighting_adapter_toggle_test`：模型资源/渲染类预存失败（工作树 GLB 改动）。
  - 101（泄漏门禁）：`command_router_test`、`interaction_authority_test`、`intro_scene_screenshot_test`、`terrain_texture_test`（500 泄漏）、`weapon_visual_verification_test`、`has_method_null_guard_test`（崩溃）——均为渲染/资源类预存问题。

## 5. 遗留（未处理，需用户拍板）

1. **P1-5 地牢/敌人单玩家全局依赖**（`GameState.current_player` 回退）：跨 dungeon_runtime/enemy/extraction_portal 的多文件改造，建议单独一轮。
2. **P1-1 可信服务器存档仓**（账号/持久化存储）：需要产品层设计（存档位置/账号体系），本轮未实现；现状保持「服务器忽略客户端存档 + 房主可信摘要」。
3. **P1-8 全项目解析门禁**：Godot 编辑器扫描在本环境不稳定（`EditorSettings not instantiated yet`），依赖 CI 环境修复。
4. 双进程 ENet 集成测试（mp_dungeon/mp_dedicated_server）未在本环境重跑（需双进程编排）；P0-2 的输入缓冲与专服碰撞改动应在其后回归一次。

## 6. 变更清单

**新增**：`globals/multiplayer/client_identity.gd`、`globals/core/equipment_policy.gd`；测试 `client_identity_test.gd`、`equipment_policy_test.gd`、`input_tick_buffer_test.gd`。

**修改**：`network_protocol.gd`、`connection_authority.gd`、`session_root.gd`、`network_manager.gd`、`multiplayer_session.gd`、`spell_authority.gd`、`spell_world_executor.gd`、`dungeon_scene_builder.gd`、`dungeon_session_controller.gd`、`dedicated_server.gd`、`client_command_driver.gd`、`damage_resolver.gd`、`game_state.gd`、`lighting_controller.gd`、`shaders/liquid.gdshader`、`assets/shaders/dungeon_terrain.gdshader`（注释）；测试 `session_root_test.gd`、`connection_authority_test.gd`、`spell_session_atomicity_test.gd`、`spell_world_executor_test.gd`、`attack_context_factory_test.gd`、`lighting_controller_test.gd`、`multiplayer_scene_bridge_test.gd`、`multiplayer_scene_integration_test.gd`、`customer_serve_flow_test.gd`、`tavern_brewing_coordinator_test.gd`、`mp_dedicated_server_test.gd`、`tavern_manager_node.gd`、`brew_ingredient_slot.gd`（预存缺陷定点修复）。

**未提交**：本轮所有改动均为工作树未提交状态（与仓库既有 WIP 改动并存），未执行 git commit。
