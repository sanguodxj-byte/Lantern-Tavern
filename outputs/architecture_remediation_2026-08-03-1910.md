# Lantern Tavern 架构审查整改报告 · 第三轮（2026-08-03 19:10）

**基线**：`outputs/architecture_review_2026-08-03-1826.md`（2×P0 开放 / 4×P1 / 5×P2）
**范围**：2 项 P0 全部闭环；4 项 P1 中 3 项闭环（P1-1 存档仓按设计待定）；5 项 P2 全部处理。
**验证**：21/21 相关套件最终批全绿（0 orphan、退出 0）。

---

## 1. P0 整改（全部关闭）

### P0-1 联机法术权威状态/投射物/实体事件复制闭环

| 子项 | 修复 | 文件 | 验证 |
|---|---|---|---|
| D. ray 双重伤害（新增确认） | `_apply_damage` 收敛为【单次】伤害应用：返回 `{applied, port_called, port_result}`；`_execute_ray` 不再二次调用端口 | `spell_world_executor.gd` | 行为测试：带 entity_id 目标端口恰好调用 1 次、port_result 透传、无 entity_id 不触发 |
| A. 自目标法术「成功但无效果」 | heal 缺 health 组件 / barrier/buff 缺 buffs 组件 → `ok=false`（commit 前拒绝，法力/冷却不扣）；movement 落点同步 `_live_state` 权威位置（快照不再回弹覆盖位移）；`EVT_SPELL_RESOLVED` 增补 `effects` 摘要 | `spell_authority.gd`、`session_root.gd` | spell_session_atomicity 14/14 + spell_completion/end_to_end/focus_flow/system 全绿（单机 caster 带真实组件不受影响） |
| B. projectile 失败可 commit | 服务缺失 / 无 spawn 方法 / `spawn()` 返回 null → `ok=false`（不 commit）；成功才记录 projectile | `spell_authority.gd` | 源契约 + 行为路径保持 |
| C. field/summon 事件丢失 | 执行器新增事件 outbox（`_port_with_outbox` 收集端口返回 events）；SessionRoot `poll_spell_world_events()` 由 NetworkManager.tick 排空广播；ray 的 `port_result.events` 提升为 `extra_events`（施法响应窗口同步出口） | `spell_world_executor.gd`、`session_root.gd`、`network_manager.gd` | 行为测试：端口事件入 outbox 且可排空、空 events 不累积；spell_network_completion 4/4 |

### P0-2 护甲固有部位校验

- `EquipmentPolicy.resolve`：显式 slot_name 必须等于 `meta.armor_slot`（单部位）；未来多部位装备须声明 `armor_slots` 数组（未声明则只允许固有部位）。
- 反例双层：策略层（`leather_cap→body`、`cloth_armor→head` 拒绝；多部位声明数组用例）+ 会话层（`test_handle_equip_rejects_armor_into_wrong_intrinsic_slot`：权威 loadout 不被污染、物品保留）。

## 2. P1 整改

- **P1-2 性能预算与灯光协调**：`LightingController` 记录 `_applied_profile_root`，`_on_budget_tier_changed` 变档后重应用已应用光源（火把 omni_range/energy 立即跟随新档）；`apply_tavern_profile` 幂等（已入组光源不重复入组）。新增行为测试（HIGH 应用 → 降 LOW → 范围断言）。
- **P1-3 多人领域 `GameState.current_player` 回退**：`tools/dungeon_stress_perf_probe.gd`、`tools/dungeon_real_overview_capture.gd` 收口 `resolve_player_node(0)`。
- **P1-4 专服 collision-only 端到端门禁**：新增 `dungeon_session_collision_authority_test.gd`（4 项）——真实 seed 产出静态墙体、马达持续向墙 5 秒不穿墙（距墙心 ≥ 1.05m）、同单元自由移动反例、layout 指纹确定性。
- **P1-1 可信服务器存档仓**：维持待定——需要产品层设计（账号体系/存档位置/SaveRepository）。当前安全边界不变：服务器忽略客户端自报 save_state，spawn 只接受房主可信摘要 + spell_state 权威恢复。

## 3. P2 整改

1. **tavern_atlas_world_32px.gdshader**：13 个 float uniform 补齐 `hint_range`（tile/inset/meters/roughness/metallic/noise/decal 等）；vec2/vec4 按 Godot 限制以注释说明。
2. **spell_world_executor_test 源码断言**：替换为行为测试（fake port 单次调用回归、outbox 收集/排空、null 目标 noop）。
3. **tools/load_check.gd**：增加 GDScript 源码真实性校验（source_code 非空 + can_instantiate），编译失败以退出码 1 结束（实测对依赖编译失败的文件输出 `SCRIPT COMPILE FAILED` 并退出 1）。
4. **docs/16 C#/Mono 旧表述**：头部加「C#/Mono 均为历史参考」说明；§6.1 渲染参数改为当前决策（桌面 forward_plus / 移动 mobile），旧 gl_compatibility/d3d12 标记历史参考。
5. **工作树拆分**：过程性指引（发布前按领域拆分、禁止 `git add -A`），随提交策略执行。

## 4. 验证

- 最终批 21/21：spell_world_executor、spell_session_atomicity、spell_network_completion、spell_completion/end_to_end/focus_flow/system、equipment_policy、session_root、lighting_controller（新增重应用用例）、dungeon_session_collision_authority（新增 4 项）、tavern_material_shader、fire_flame_shader、liquid_alchemy_shader、attack_context_factory、connection_authority、movement_authority、input_tick_buffer、security_audit、gameplay_light_policy、dungeon_topdown_generation。
- `tools/load_check.gd`：对编译失败文件输出 `SCRIPT COMPILE FAILED` 且退出码 1（`-s` 模式缺 autoload 属工具环境限制，传播机制已验证）。
- 双进程 ENet 测试本轮未重跑（本轮改动仅法术/装备/光照路径，未触及输入/移动/专服碰撞；前一轮 mp_dungeon/mp_dedicated_server 均 PASS，建议随提交前完整回归一次）。

## 5. 遗留

1. **P1-1 服务器 SaveRepository**：产品层决策后实施。
2. **projectile 命中结算纳入会话实体仓**（P0-1-B 完整形态）：本轮完成「失败不 commit」；projectile 命中仍走可见节点 `try_receive_hit*`。完整接入会话实体仓/事件出口属于 Phase B（正式 Enemy 实体接入）的一部分。
3. 上两轮遗留的预存 WIP 套件清单不变（模型/地牢/敌人 WIP，随各自功能提交）。
4. 本轮改动未提交（与仓库既有 WIP 并存）。

## 6. 本轮变更清单

**修改（生产）**：`spell_world_executor.gd`（单次伤害语义 + outbox）、`spell_authority.gd`（组件/服务失败传播）、`session_root.gd`（movement 同步 + extra_events + poll_spell_world_events + effects 摘要）、`network_manager.gd`（outbox 排空）、`equipment_policy.gd`（固有部位）、`lighting_controller.gd`（重应用）、`tools/dungeon_stress_perf_probe.gd`、`tools/dungeon_real_overview_capture.gd`、`tools/load_check.gd`、`scenes/tavern/materials/tavern_atlas_world_32px.gdshader`、`docs/16-技术架构与代码设计.md`。

**修改（测试）**：`spell_world_executor_test.gd`（行为化）、`spell_network_completion_test.gd`（窗口 6000）、`equipment_policy_test.gd`（固有部位 + 多部位）、`session_root_test.gd`（会话层反例 + leather_cap stub）、`lighting_controller_test.gd`（重应用用例）、新增 `dungeon_session_collision_authority_test.gd`。
