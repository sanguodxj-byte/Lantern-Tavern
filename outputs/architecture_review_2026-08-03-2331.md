# Lantern Tavern 增量架构审查（2026-08-03 23:31）

## 结论

**评级：B-（主干闭环显著改善，但联机玩家受击与客户端战斗状态同步仍是发布阻断）**

本轮基于 23:17 提交 `60be9c7` 及当前工作树进行只读增量复核。上一轮 22:18 报告中的法术自目标状态、召唤寻敌、可靠实体基线、投射物会话生命周期与权威实体碰撞门禁已基本闭合。当前最关键风险已从“法术无法命中/无法结算”转移到“玩家侧战斗权威真值没有接入生产敌人攻击链，也没有实时复制到客户端表现层”。

- **P0：2 项**
- **P1：5 项**
- **P2：3 项**
- 专项测试：**51/51 通过，0 failure，0 orphan，runner exit 0**
- Godot 4.7 editor 扫描：**exit 0**；关闭阶段仍有 2 条 `EditorSettings` Android 设置诊断
- 未执行：真实双进程玩家受击/法术表现、Android 真机、窗口视觉验收、全量测试

---

## P0-1：联机生产敌人不会伤害远端玩家的权威 `PlayerContext`

### 证据

1. `SessionRoot.apply_damage_to_player()` 已建立，但全仓库只有定义，没有生产调用：
   - `globals/multiplayer/session_root.gd:905-921`
2. 联机敌人是 `multiplayer_entity.gd` 的表现代理，仅保存 HP/位置，无 AI、攻击状态机、伤害输出：
   - `scenes/multiplayer/multiplayer_entity.gd:1-21`
3. 真实敌人攻击状态仍只识别本进程 `Player`，直接调用 `player.try_receive_hit_result()`：
   - `scenes/characters/enemies/state/enemy_state_slashing.gd:166-179`
4. 联机入口 `spawn_server_entities()` 只向 SessionRoot 注册字典实体，不生成真实敌人 AI：
   - `scenes/multiplayer/dungeon_session_controller.gd:135-172`

### 影响

当前联机垂直切片里，玩家可以攻击权威敌人，法术也可写回敌人实体仓；但敌人不会经服务器权威链攻击远端玩家。`shield/current_life/buffs` 虽已实现，除单测和自目标法术外，没有敌方伤害生产入口，联机战斗仍是单向的。

### 整改

- 明确一个服务器权威敌人模拟器：真实 Enemy AI 或独立 `ServerEnemyCombatMotor`，不能继续由客户端表现代理承担。
- 敌人命中后只调用 `SessionRoot.apply_damage_to_player(peer_id, damage)`；禁止直接命中客户端 `Player` 作为联机真值。
- 增加双进程门禁：敌人攻击远端 peer → 先扣盾 → 扣生命 → 死亡状态/事件正确下发。

---

## P0-2：玩家生命/魔法盾/buff 没有实时复制到客户端 HUD 与本地角色

### 证据

1. `PlayerContext` 的 `current_life/max_life/shield/buffs` 已进入 `serialize_spell_state()`：
   - `globals/core/player_context.gd:39-49, 102-121`
2. 这些状态只存在重连/会话快照中：
   - `globals/multiplayer/session_root.gd:1352-1366`
3. 网络协议没有玩家战斗状态事件；现有 `EVT_PLAYER_SNAPSHOT` 仅位置/朝向：
   - `globals/multiplayer/network_protocol.gd:41-53`
4. `ClientCommandDriver` 收到 `EVT_SESSION_SNAPSHOT` 只更新 world revision，不应用本机 `spell_state/combat_state`：
   - `scenes/multiplayer/client_command_driver.gd:316-322`
5. `MultiplayerSceneBridge` 的 `EVT_SPELL_RESOLVED` 只同步本机 mana，heal/barrier/buff 没有写回本地 `health`/护盾 HUD：
   - `globals/multiplayer/multiplayer_scene_bridge.gd:159-164`
6. `CombatHUD` 仍读取本地 Player 的 `health`、ManaComponent 和本地 buff/equipment：
   - `scenes/ui/combat_hud.gd:245-255, 336-367`

### 影响

即便服务器 `PlayerContext` 已正确治疗、加盾、加 buff 或受伤，客户端 HUD 和本地角色组件可能保持旧值。当前测试验证的是服务器对象内部状态与序列化往返，不是服务器→客户端→HUD 的生产闭环。

### 整改

- 新增 `EVT_PLAYER_COMBAT_STATE`，或扩展定向可靠玩家状态快照；至少包含 `current_life/max_life/shield/buffs/spell_mana` 和递增 revision。
- 自目标法术、玩家受伤、buff 过期后发布；重连快照也必须落地到本机 Player/HUD。
- 客户端只把事件应用为表现镜像，不允许反向写服务器。
- 增加双进程测试：远端 heal/barrier/buff/受伤后客户端数值与服务器 Context 一致。

---

## P1-1：`SpellAuthority` 在无效果端口/组件时仍把 heal 记为成功

### 证据

- `globals/combat/spell_authority.gd:59-70`：无 `self_effect_port` 且 caster 无 health 时执行 `pass`，仍返回 `ok=true` 与 healed 摘要。
- 对应测试把此行为固化为成功：`tests/gdunit/spell_session_atomicity_test.gd:231-238`。

### 风险

生产 SessionRoot 当前会注入端口，因此主路径暂不触发；但这个 API 合同会掩盖未来漏接线和单机无组件错误，与文件注释“组件缺失应失败”自相矛盾。

### 建议

无端口且无目标组件必须返回 `ok=false/reason=self_effect_target_unavailable`；纯逻辑测试应显式注入 spy port，而不是接受无副作用成功。

---

## P1-2：法术数值仍是分散的实现占位，未形成设计数据单一真相

### 证据

- `SpellAuthority.execute()` 内仍存在 heal 28、barrier 30、buff 20% 等默认值：`globals/combat/spell_authority.gd:59-89`。
- `PlayerContext.spell_power_mult()` 固定返回 1.2：`globals/core/player_context.gd:96-100`。

### 风险

`SpellRecipeData` 虽是配方真相，但实际执行数值仍可能由执行器默认值兜底，后续逐法术平衡时容易出现“卡面/配方/服务端执行”三套数值。

### 建议

所有执行参数必须在权威 spell/effect plan 中完整存在；执行器禁止静默默认业务数值，只允许结构校验和执行。

---

## P1-3：运行时质量协调只在“变档瞬间”扫描当前场景，新加载场景可能错过当前低档预算

### 证据

- `PerformanceBudget._apply_quality_tier()` 只对 `get_tree().current_scene` 调一次协调器：`globals/perf/performance_budget_controller.gd:104-120`。
- `VisualQualityCoordinator` 只遍历调用时已存在的 WorldEnvironment/DirectionalLight3D：`globals/perf/visual_quality_coordinator.gd:68-84`。

### 风险

如果质量已经降为 PERFORMANCE/EMERGENCY 后再切换地牢/酒馆，而帧时间没有触发下一次档位变化，新场景环境雾和主光阴影仍保留高档成本。LightingController 仅对酒馆动态光做独立重应用，不能覆盖场景环境。

### 建议

监听 `SceneTree.current_scene` 变化或提供场景 ready 接口，在每次场景装载后用“当前 quality_tier”重新应用预算；补场景切换回归测试。

---

## P1-4：移动端渲染选择主要依赖项目/平台默认，缺少可审计的显式配置与导出验收

### 证据

- `project.godot` 未见显式 renderer/rendering_method 配置，仅保留 `config/features=("4.7", "C#")`：`project.godot:13-15`。
- Android preset 已存在且只导出 arm64：`export_presets.cfg:113-179`。
- 文档要求桌面 Forward+、Android Mobile，但本轮未做 Android 导出或真机 `RenderingServer.get_rendering_method()` 验证。

### 风险

项目当前可能依靠编辑器/导出平台默认正确工作，但配置漂移不容易在代码审查中发现；尤其项目使用 Mono feature 和 Android 导出时，实际模板/后端是否一致仍未验证。

### 建议

增加启动期诊断与导出 smoke test，记录平台、renderer、rendering_method、驱动；CI 对 Windows/Android preset 做最小导出验证。

---

## P1-5：Godot editor 扫描虽成功，但关闭阶段 Android EditorSettings 诊断持续存在

### 证据

扫描 exit 0，但退出阶段输出：

- `EditorSettings not instantiated yet when getting setting "export/android/android_sdk_path"`
- `EditorSettings not instantiated yet when getting setting "export/android/shutdown_adb_on_exit"`

### 风险

不阻断脚本解析，但说明 editor/plugin/export 初始化与销毁顺序存在噪音，会降低 CI 对真实 ERROR 的识别信噪比。

### 建议

隔离 MCP editor 插件后复测；若错误消失，调整插件 shutdown 生命周期。CI 保留“运行期 ERROR 为失败”，同时对白名单退出诊断做精确管理，禁止全局忽略 `ERROR:`。

---

## P2

### P2-1：测试仍大量依赖 `script.source_code.contains/substr`

全仓测试存在大量源码字符串断言，重构、换行或函数挪位会造成假失败/假通过。架构合同优先改为行为测试或暴露只读查询 API；源码扫描仅保留“禁止模式”类约束。

### P2-2：工作树有未整理变更和新增 `.uid`

当前 `git status --short`：

- 修改：`tests/gdunit/enemy_weapon_attack_test.gd`
- 修改：`tests/gdunit/nav_diagnose_actual_test.gd`
- 修改：`tools/dungeon_stress_perf_probe.gd`
- 未跟踪：`overview_2026-08-03-2218.md`
- 未跟踪：`tests/gdunit/multiplayer_entity_authority_test.gd.uid`

其中压力工具显示大规模换行 diff，需先确认是实际逻辑修改还是 CRLF/LF 噪音，避免污染下一次提交。

### P2-3：C# feature 仍由仅编辑器 MCP 插件驱动

`project.godot` 声明 C#，`LanternTavern.csproj` 只编译 `addons/mcp_listener/*.cs`。这不是运行时架构错误，但意味着 Android/桌面发行物承担 Mono 模板复杂度主要是为了编辑器插件。建议评估插件是否可 editor-only 隔离，避免发行目标被工具链绑定。

---

## 已确认关闭的上一轮问题

1. 远端 heal/barrier/buff 已进入 per-peer `PlayerContext` 真实生命/盾/buff，并可序列化。
2. 召唤物已通过 `query_targets_port` 查询 SessionRoot 权威敌人实体仓。
3. ray/projectile/summon 伤害端口已写回实体仓并进入事件 outbox。
4. 周期实体基线已通过显式 reliable 出口发送。
5. 投射物由 SessionRoot 跟踪并在会话 teardown 回收。
6. 服务器表现实体已为 enemy 装配命中专用碰撞体与 `entity_id` meta。
7. EquipmentPolicy 已校验护甲固有部位与多部位声明。
8. 攻击上下文、武器冷却和流派 `damage_mult` 已收口到权威工厂/策略。
9. PerformanceBudget 已有环境/主光消费者，LightingController 已订阅动态分档。

---

## 验证记录

### 通过

组合专项：

- `spell_session_atomicity_test.gd`：24/24
- `multiplayer_entity_authority_test.gd`：4/4
- `spell_world_executor_test.gd`：8/8
- `equipment_policy_test.gd`：15/15
- **总计 51/51，0 errors，0 failures，0 skipped，0 orphans，exit 0**

报告：`reports/report_5655/index.html`

Godot editor 项目扫描：**exit 0**，完成文件扫描、autoload 初始化、插件启停与资源导入。

### 未覆盖

- 双进程敌人攻击远端玩家
- 双进程玩家 combat state 到客户端 HUD
- projectile/summon 的真实场景命中与表现
- Android 导出与真机 renderer/性能
- 窗口模式视觉验收
- 全量 gdUnit4

---

## 建议整改顺序

1. **先补服务器敌人模拟 → `apply_damage_to_player` 生产调用链。**
2. **新增玩家战斗状态可靠事件并落地客户端 Player/HUD。**
3. 用双进程测试锁住“敌人命中、盾吸收、生命同步、死亡/重连”。
4. 收紧 `SpellAuthority` 无目标时的失败合同，移除业务默认数值。
5. 补场景切换后动态质量预算重应用。
6. 最后清理工作树换行噪音、源码字符串测试和 editor 关闭诊断。
