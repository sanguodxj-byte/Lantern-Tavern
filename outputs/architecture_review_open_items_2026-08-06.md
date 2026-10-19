# 架构审查开放项汇总（2026-08-06）

> 生成时间：2026-08-06 18:40（GMT+8），更新 20:10
> 处理范围：`reports/` 与 `outputs/` 全部架构审查报告（2026-08-02 ~ 2026-08-06 共 70+ 份）
> 处理方式：已全部关闭/被后续轮次覆盖的报告已删除；本表汇总仍开放的治理项。

## 一、已关闭总量（删除的报告）

- **08-02 系列**：攻击冷却统一、库存转移、Mobile renderer、export presets、per-player 迁移、NetworkManager 边界、README 降级等——全部修复。
- **08-03 系列**：spawn save_state 安全、法术联机入口、AttackContext 权威化、结算事务、存档仓等——全部修复。
- **08-04 系列**：战斗/法术/存档/酒馆后续问题——全部修复。
- **08-05 已验收**：`0913`、`1122`、`2251`——全部关闭。
- **08-06 已验收**：`0304`、`1727`——全部关闭。
- 中间快照（`2028/2149/0002/from_scratch_08-05/0200~1528` 等）：被最终版覆盖，已删除。

**当前测试门禁：19 套件 256/256 通过、0 错误、0 失败、0 orphan（2026-08-06 20:10 回归）。**

## 二、保留报告（有开放项）

### 1. `reports/architecture_review_2026-08-02.md`（主报告）

| 开放项 | 状态 |
| --- | --- |
| P1-2 autoload 全局服务总线 | ✅ 纯数据表移出（SkillData/ActionSkills，33→31，2026-08-06）；服务型实例依赖项（SkillIcons/LootTable/AffixSystem）待迁移 |
| P1-4 架构测试扩展 | ✅ 方向性依赖规则 R1/R2/R3 + 窄端口 R4 已落地 |
| P2-1 移动端 shader FBM 分档 | 开放（需视觉验收通道） |

### 2. `reports/architecture_review_2026-08-02_hourly.md` 等 6 份复审

| 开放项 | 状态 |
| --- | --- |
| autoload 治理 | ✅ 纯数据表移出（33→31）；实例依赖项待迁移 |
| orphan 严格门禁 | ✅ 默认 RED + `-AllowOrphan` |
| 法术行为/协议测试 | ✅ 已补 |

### 3. `outputs/architecture_review_fresh_2026-08-05-1417.md`

| 开放项 | 状态 |
| --- | --- |
| P1-1 Listen/Dedicated 出征生命周期统一 | ✅ 装配契约测试落地（两种宿主共享生成管线一致性）；ExpeditionLifecycle 状态机仍开放 |
| P1-3 SaveManager 聚合器 | ✅ SaveSection 协议落地（ZoneManager 迁移验证） |
| P2-1 注册表职责过宽 | 开放 |
| P2-5 Web/Mono 平台决策 | 开放 |

### 4. 跨报告共性开放项（合并跟踪）

| 开放项 | 状态 |
| --- | --- |
| 依赖方向门禁 | ✅ R1/R2/R3 + 窄端口 R4 已落地（architecture_dependency_rule_test 8 用例） |
| SaveManager SaveSection | ✅ 已落地（SaveSection 基类 + register_section + ZoneManager 迁移 + stub 协议测试） |
| Session 服务窄端口化 | ✅ 全部 5 服务迁移至端口访问（`_r._` 私有访问清零，R4 门禁） |
| autoload 存量缩减 | ✅ 部分（纯数据表 SkillData/ActionSkills 移出，33→31）；SkillIcons/LootTable/AffixSystem 实例依赖迁移开放 |
| Listen/Dedicated 装配一致性 | ✅ 契约测试落地（`dungeon_host_assembly_contract_test`）；生命周期状态机统一开放 |
| 移动端 shader ALU 分档（FBM octave） | ✅ 预留通道落地（fire_flame/liquid_alchemy 加 `fbm_octaves` uniform，默认 4 行为不变，移动端可降 2）；RenderingProfile 接入仍开放 |
| ExtractionPortal 联机场景接入 | ✅ 生产垂直接线闭环（2026-08-07 0643/0952 审查）：`DungeonSessionController.wire_extraction_portal()` 将真实 portal 的 `extraction_requested` 装配到 `request_extraction()`（CMD_EXTRACT 权威事务），`MultiplayerSession._on_extraction_completed` 负责离场；`DungeonRuntime` 增 `extraction_port` 端口（单机本地结算 / 联机权威链分叉）。生产装配测试：`expedition_exit_test.test_portal_signal_reaches_cmd_extract_via_real_assembly`（真实 portal 信号 → CMD_EXTRACT → 幂等单次提交） |
| Android 真机 / 双进程 ENet 全流程验收 | 开放（`-RunIntegration` 门禁就绪 + PASS/FAIL 退出码已修） |
| 编辑器扫描 stderr 精确白名单 | ✅ 已落地（run_ci.ps1 白名单外 ERROR 直接 RED） |

## 三、2026-08-07 from_scratch 审查（0643/0952）新增项

### ✅ 已关闭（2026-08-07 修复）

| 开放项 | 关闭方式 |
| --- | --- |
| P0-1 标准 CI 与 Service 契约失配（service_test.gd 引用已移除的 skill_data/action_skills） | `service_test.gd` 删除旧访问器断言，契约单一来源 `service_access_contract_test.gd`（6/6 通过） |
| P1-1 技能 buff 秒数写入绝对毫秒容器（iframes/dodge_frames 立即过期） | `PlayerContext.apply_timed_buff()` 唯一写入口（绝对 expire_ms）；`SkillAuthority` 改经端口写入；`session_root_test` 改行为断言（施放有效/到期清除/续期取晚） |
| P1-4 SpellAuthority 直接 `/root/ProjectileService` | 注入 `projectile_spawn_port`（SessionCombatService 经 Service 定位装配）；无端口整体拒绝，不再猜测全局单例 |
| P2 聚焦测试重复 `session_event` 连接 ERROR | `spell_network_behavior_test._setup_peer` 连接前 `is_connected` 判重 |
| 附带：`spell_world_executor_test` 检查已迁移的 `_handle_cast_spell`（ADR-003 拆分后失效） | 断言目标改 `session_combat_service.gd.handle_cast_spell`（12/12） |
| 附带：`spell_end_to_end_test` projectile 用例未装配 spawn 端口 | 测试注入 stub 端口（4/4） |
| 附带：project.godot 丢失 renderer/rendering_method 键 | 恢复 `forward_plus` + `mobile`（rendering_config_contract_test 3/3） |

### ⚠️ 仍开放（跟踪中）

| 开放项 | 说明 |
| --- | --- |
| P0-2 联机撤离真实 ENet 全流程验收（Listen 移动 verdict 缺失，0952；runner 挂起，2228） | 生产装配已闭环；真实 Listen ENet 移动判定偶发 MISSING，需连续 10 次统计 + verdict 分阶段记录（`tests/integration/mp_dungeon_test.gd`）。2228 报告 runner 挂起 20 分钟无 verdict——2026-08-08 本地实测 Listen 集成可 8 分钟产出 verdict（参数化后），挂起疑为审查环境进程争用；CI workflow 已落地独立 ENet job（.github/workflows/ci.yml） |
| P0-2（2228）重连结算幂等缓存损坏 | ✅ **已修复（2026-08-08）**：根因=reconnect_recovery_test 未隔离存档目录，残留 `user://server_saves/g3.json` 污染 spawn（恢复 30 材料→space_limit 满→拾取 2 失败→结算 0）。修复=测试注入唯一 `set_save_dir`（reconnect_recovery_test 2 处 + dedicated_server_seed_test 1 处）；5/5 + 1/1 通过，连跑 2 轮稳定 |
| P1-1 全量 CI 不可收敛（0014：120s 超时；2228：109 failures/126 orphans；1220：signal 11） | 工作树预存失败（资产/音频/动画/顺序污染，HEAD 基线亦失败）+ 全量耗时超长。分批复用 `tools/run_all_gdunit_batched.ps1` 治理中；ENet 门禁已独立 job 不受影响 |
| P1-2 主动技能/法术权威（1220 P1-3：ActionSkills/SkillData 双数据源隐式优先级） | ✅ 核心效果已兑现（skill_effects_test 10/10）；当前无 ID 冲突（5+48 实测）。剩余：启动时 ID 全局唯一守卫 + 显式 skill_kind（渐进改进） |
| P1-3 真实 ENet 合并必跑 | ✅ workflow 落地（`.github/workflows/ci.yml`，2026-08-07）：独立 `enet-integration` job（Listen + Dedicated），合并必跑；集成脚本参数化（-ProjectPath/-GodotPath），.cmd 启动器环境变量驱动（本地默认值兼容）；本地参数化链路实测通过。合并保护需在 GitHub 侧将 enet-integration 设为 required |
| P1-5 SessionRoot 编排热点（786 行） | 已拆 5 个 session service；按命令族窄端口继续收敛，不机械切文件 |
| 全量测试预存失败（~50，资产/音频/动画/顺序污染类） | HEAD 基线亦失败，非本次修复引入；单跑通过者属测试间污染，需逐一隔离 |
| SpellAuthority movement headless fallback 直改位置（1220 P1-2） | 设计权衡：仅无端口时回退（headless 纯逻辑/测试），生产经 SessionRoot 注入碰撞端口。可加"导出构建禁用 fallback"守卫（渐进） |
| SaveManager 双轨迁移（1220/2228/0014 P1） | ADR-005 渐进：SaveSection 已落地（ZoneManager 迁移），旧聚合路径待逐领域删除 |
| Autoload 33 vs 门禁 31（0014 P1-1） | ⚠️ **已核实为误报**：project.godot 实际 31 个 Autoload（0014 计数方法把非 autoload 行也算入）；门禁 31 与现状一致 |

## 四、后续建议优先级（更新）

1. **Listen ENet 移动判定稳定性**（真实联机验收：verdict 分阶段记录 + 连续 10 次统计）。
2. **autoload 服务型实例迁移**（SkillIcons/LootTable/AffixSystem——按 ADR-005 随功能改动顺带，31→28）。
3. **全量测试顺序污染治理**（单跑绿/全量红的套件加隔离，恢复标准 CI 全绿）。
4. **注册表职责拆分**（EquipmentCatalog）与 **RenderingProfile 接入 shader 降档**（移动端通道已预留）。
5. **Listen/Dedicated 生命周期状态机**（装配一致性已验证，状态机待玩法定稿）。
