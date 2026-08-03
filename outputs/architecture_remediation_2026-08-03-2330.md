# Lantern Tavern 架构审查整改报告（2026-08-03 23:30 · 2218 审查闭环）

**基线**：`outputs/architecture_review_2026-08-03-2218.md`（2×P0 / 3×P1，C+）
**验证**：28/28 相关套件全绿（0 orphan、退出 0）；权威实体测试 0 Godot ERROR。

---

## 1. P0-1 远端 heal/barrier/buff 进入真实战斗状态 —— 闭环 ✅

**根因**：`spell_effect_state` 只是摘要字典（healed_total/absorb/buff_duration），不参与生命/伤害/结算；未序列化。

**修复**（`player_context.gd` 建立 per-peer 权威战斗状态）：
- `current_life/max_life`：heal 真实提升当前生命（封顶 max_life），`apply_damage` 扣命；
- `shield`：barrier 累加吸收盾，`apply_damage` **先扣盾再扣命**；
- `buffs{id:expiry_ms}`：buff 登记带过期时间的增益，`expire_buffs(now)` 推进过期；
- `spell_power_mult()`：buff 影响权威法术结算（×1.2）；
- **序列化闭环**：`serialize_spell_state` 含 `combat_state`（life/shield/buffs），`deserialize` 恢复——重连/存档不丢；
- `SessionRoot._spell_damage_entity` 应用施法者 `spell_power_mult`（buff 影响法术伤害）；
- `SessionRoot.apply_damage_to_player`（敌方伤害入口，阶段 B 敌人 AI 完成后调用）+ `tick_player_buffs`（NetworkManager.tick 推进过期）。

**测试**（+4）：heal 真实提升生命（先受 40 伤再 heal 恢复）；barrier 盾抵扣 60 伤害（盾 30 全抵 + 命 30）；buff 登记+过期+倍率 1.0/1.2；combat_state 序列化往返（重连恢复 75 命/30 盾/buff）。

## 2. P0-2 召唤物无法发现生产联机敌人 —— 闭环 ✅

**根因**：`SpellSummon._nearest_enemy` 只扫表现层 `"enemies"` 场景组；联机权威敌人不入组。

**修复**（会话权威目标查询）：
- `SpellWorldExecutor.query_targets_port`（SessionRoot 注入 `_query_spell_targets`：查 `_entities` kind=enemy 且存活）；
- `SpellSummon._process` 分流：权威端口存在 → `_nearest_enemy_entity_id` 查实体仓 → `damage_port` 写回；无端口（单机）→ 保留 "enemies" 组节点直伤回退；
- 消除临时 proxy 节点泄漏（寻敌不再创建游离 Node3D）。

**测试**（+2）：`_query_spell_targets` 只返回存活 enemy、范围过滤；召唤物经权威目标端口发现实体并写回扣血。

## 3. P1-1 周期实体基线实际走 unreliable —— 闭环 ✅

- 新增 `NetworkManager._dispatch_event_reliable`（强制可靠 RPC，绕过 `_is_high_frequency_event` 分类）；
- 3s 实体基线改走可靠出口——注释与行为一致。

## 4. P1-2 投射物生命周期跨会话共享 —— 闭环 ✅

- `ProjectileService.spawn()` 接受显式 `parent` 参数（默认回退全局父节点，单机不变）；
- `SpellAuthority` 投射物挂会话世界容器（随会话释放）；
- `SessionRoot` teardown 只回收**仍有效且仍在场景树**（active、未被池复用）的投射物——消除「旧会话引用释放新会话节点」风险。

## 5. P1-3 权威实体测试引擎报错 + 门禁漏洞 —— 闭环 ✅

- 测试夹具修复：bridge 入测试场景树 + 引擎调用生产 `_ready()`（消除 "节点不在活动场景树" ERROR）；移除 DBG 打印；确认 0 ERROR；
- **CI ERROR 门禁**：`run_all_gdunit_batched.ps1` 将运行期 `SCRIPT ERROR / Parse Error / ERROR:` 判为 FAIL——断言全绿但引擎报错不再漏过。

## 6. 验证

- **28/28 套件全绿**（0 orphan、退出 0）：spell 系列 8 套、session_root、player_context_factory、multiplayer_entity_authority（0 ERROR）、multiplayer_scene_bridge、projectile_service、crossbow、weapon_throw、save repo、attack context、equipment、performance/lighting/visual coordinator、movement、input tick、security、connection、game_state、expedition、network_manager。
- 双进程 projectile/summon 行为测试与窗口视觉验收未执行（记录待发布前）。

## 7. 变更清单

**修改**：`player_context.gd`（权威战斗状态+序列化）、`session_root.gd`（_apply_self_effect 节点同步/apply_damage_to_player/tick_player_buffs/_spell_damage_entity 倍率/_query_spell_targets）、`spell_world_executor.gd`（query_targets_port + summon 分流 + 去 proxy 泄漏）、`spell_authority.gd`（投射物挂会话容器）、`projectile_service.gd`（spawn parent 参数）、`network_manager.gd`（_dispatch_event_reliable + tick buffs）、`tools/run_all_gdunit_batched.ps1`（ERROR 门禁）、`tests/gdunit/spell_session_atomicity_test.gd`（+6）、`tests/gdunit/spell_end_to_end_test.gd`（projectile 注册 id 适配）、`tests/gdunit/multiplayer_entity_authority_test.gd`（夹具入树+去 DBG）。
