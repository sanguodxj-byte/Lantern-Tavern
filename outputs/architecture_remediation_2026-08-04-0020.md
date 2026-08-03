# Lantern Tavern 架构审查整改报告（2026-08-04 00:20 · 2331 审查闭环）

**基线**：`outputs/architecture_review_2026-08-03-2331.md`（2×P0 / 5×P1 / 3×P2，B-）
**验证**：27/27 相关套件全绿（0 orphan、退出 0）。

---

## 1. P0-1 联机敌人权威伤害远端玩家 —— 闭环 ✅

**根因**：`apply_damage_to_player` 无生产调用者；联机敌人只是字典+表现代理，无服务器攻击模拟。

**修复**（`session_root.gd`）：
- 新增 `tick_enemy_combat(now)` 服务器权威敌人攻击模拟：遍历 `_entities` 存活 enemy，对近战范围（1.8m）内在线玩家按 `ENEMY_ATTACK_INTERVAL`（1.5s）周期性经 `apply_damage_to_player` 造成伤害（`ENEMY_ATTACK_DAMAGE` 8）；
- 每敌人 `next_attack_at`（实体 data 字段）控制攻击节拍；
- 死亡 → `set_player_alive(false)`；
- `NetworkManager.tick` 调用（服务器权威链，客户端不可绕过）。

**测试**（+3）：敌人 tick 扣血+广播状态+冷却节拍；盾先抵扣（8 伤全入盾、命不减）；击杀 → 状态事件 + is_alive false。

## 2. P0-2 玩家战斗状态实时同步客户端 —— 闭环 ✅

**根因**：服务器有权威 current_life/shield/buffs，但无事件发布；客户端 HUD/角色不接收；重连快照未落地。

**修复**：
- 协议新增 `EVT_PLAYER_COMBAT_STATE`（reliable）；
- `SessionRoot.broadcast_player_combat_state(peer_id)`：含 current_life/max_life/shield/buffs/spell_mana + 递增 revision；在 `apply_damage_to_player`（受伤/死亡）与 `_apply_self_effect`（自目标法术）后发布；
- 客户端 `ClientCommandDriver._apply_combat_state`：应用到本机 Player（health 生命、mana 法力、shield→damage_absorb 护盾、buffs→spell_power）——只读镜像，不反向写服务器；
- 重连快照落地：`EVT_SESSION_SNAPSHOT` 的 players 数组 combat_state 应用到本机组件。

**测试**（+1）：自目标 heal 后广播状态事件（revision/life 一致）；另由 P0-1 测试覆盖受伤广播。

## 3. P1-1 SpellAuthority 无端口无组件必须失败 —— 闭环 ✅

- heal/barrier/buff 无 `self_effect_port` 且目标无组件 → `ok=false/reason=self_effect_target_unavailable`（移除「无副作用成功」）；
- 测试：直接 execute 无端口无组件 → 失败 + 正确 reason；SessionRoot 施法路径（端口已注入）保持成功。

## 4. P1-3 场景切换后质量预算重应用 —— 闭环 ✅

- `PerformanceBudget._process` 每帧对比 `current_scene` 引用，变化即以当前 `quality_tier` 重应用环境预算（SceneTree 无 current_scene_changed 信号，改轮询）；
- 新场景环境雾/主光阴影不再因「档位未再变化」保留高档成本。

## 5. 未处理（记录，挂后续）

- **P1-2**：法术数值（heal 28/barrier 30/buff 20%/spell_power 1.2）仍是执行器默认值——需 effect_plan 完整携带业务数值（ADR-007 数值校准触发条件，随战斗数值文档接管）。
- **P1-4**：移动端渲染显式配置与导出验收——需模板机/真机。
- **P1-5**：editor 关闭阶段 Android EditorSettings 诊断——隔离 MCP 插件后复测。
- **P2**：源码字符串测试存量、工作树换行噪音、C# feature 工具链。

## 6. 变更清单

**修改**：`network_protocol.gd`（EVT_PLAYER_COMBAT_STATE）、`session_root.gd`（tick_enemy_combat/broadcast_player_combat_state/combat revision）、`network_manager.gd`（tick 敌人攻击）、`client_command_driver.gd`（_apply_combat_state + 快照落地）、`spell_authority.gd`（无目标失败）、`performance_budget_controller.gd`（场景切换重应用）、`tests/gdunit/spell_session_atomicity_test.gd`（+5）。

**验证**：27/27 套件全绿（0 orphan、退出 0）。
