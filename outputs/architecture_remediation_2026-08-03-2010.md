# Lantern Tavern 遗留项修复与决策记录（2026-08-03 20:10）

**范围**：关闭矩阵（`outputs/architecture_closure_matrix_2026-08-03.md`）§5 遗留项的可落地部分 + 全部决策写入 `docs/adr/`（9 份 ADR）。
**验证**：19/19 相关套件最终批全绿（0 orphan、退出 0）。

---

## 1. 本轮修复的遗留项（3 项）

### 1.1 P1-1 服务器可信存档仓 —— 闭环 ✅

- 新增 `globals/multiplayer/server_save_repository.gd`：按 `player_guid` 持久化权威状态（`user://server_saves/<guid>.json`）；**GUID 白名单消毒防路径穿越**（`[A-Za-z0-9_-]` ≤128，逐字符校验，无正则依赖）。
- `SessionRoot.handle_spawn_request`：服务器仓优先恢复（materials/loadout/spell_state/attributes/skills）；无仓/无存档才用调用方摘要——**远端可信来源成立**。
- `_settle_expedition`：结算成功把当前权威状态写回仓（持久化闭环）。
- `NetworkManager._ensure_session` 注入仓实例。
- 测试：`server_save_repository_test.gd`（6 项：穿越拒绝/消毒/往返/缺失/删除/目录隔离）+ `session_root_test` 新增 2 项（同身份重连恢复不被空 save_state 覆盖；结算写回仓）。

### 1.2 P0-1-B projectile 命中纳入会话权威链 —— 闭环 ✅

- `SpellRuntime._effect_plan` projectile/ray 新增权威基准伤害 `damage=10`（与 heal 28/absorb 30 同级常量模式；数值对齐策划见 ADR-007）。
- `SpellAuthority` 把 `damage/caster_peer` + **outbox 端口**注入投射物 `skill_data`。
- `projectile_entity._on_body_entered` 新增分支：命中带 `entity_id` 的权威实体 → 端口写回 `_entities`（单次调用、事件进 outbox、穿透去重）。
- 测试：`spell_session_atomicity` 新增 2 项（未注册 projectile_id → spawn null → 不 commit；端口写回扣血/死亡/掉落 + outbox 排空）。

### 1.3 P1-2 视觉质量统一协调 —— 闭环 ✅

- 新增 `globals/perf/visual_quality_coordinator.gd`（纯静态工具，无新增 autoload）：档位 → `Environment`（fog 开关/密度、ambient_light_energy）+ `DirectionalLight3D.shadow_enabled`（PERFORMANCE 以下关阴影）；未知档位回退 FULL。
- `PerformanceBudget._apply_quality_tier` 变档时对当前场景根应用。
- 与 LightingController（动态光源）分工明确，互不重叠。
- 测试：`visual_quality_coordinator_test.gd`（5 项：回退/映射/空安全/场景遍历含阴影/遍历空安全）。

## 2. 文档核对（遗留项 4）

- `docs/25-联机总体方案.md`：header「已落地」更新为当前实现现状（SessionRoot 权威编排/碰撞移动/策略层/服务器仓）。
- `README_ARCHITECTURE.md`：头部标注【历史参考】（OBJ/纸娃娃/像素 UI 草案），指向当前权威文档。
- `docs/24`、`docs/16`、法术审计：前轮已完成（关闭矩阵 P2-3 行）。

## 3. 决策记录（docs/adr/，9 份）

| ADR | 主题 | 状态 |
|---|---|---|
| ADR-001 | 服务器可信存档仓（键控/消毒/恢复/写回） | Accepted（已实施） |
| ADR-002 | 正式 Enemy 接入阶段 B 边界（字典代理过渡承诺） | Accepted（推迟实施） |
| ADR-003 | God Object 拆分策略（变更频率驱动 + 已拆分清单 + 优先级） | Accepted（挂阶段 C） |
| ADR-004 | 视觉质量协调分工（分辨率/动态光/环境预算；不再新建第二协调器） | Accepted（已实施） |
| ADR-005 | 服务定位器收敛 + SaveManager 聚合器（分层/渐进/禁新增 autoload） | Proposed（挂阶段 C/D） |
| ADR-006 | 工作树提交策略（主题拆分、禁 git add -A、WIP 归属、证据入库） | Accepted（立即生效） |
| ADR-007 | 法术权威基准伤害（projectile/ray=10；数值待策划对齐） | Accepted（已实施） |
| ADR-008 | CI 门禁策略（orphan 分档 + -FailOnOrphan、解析门禁、报告隔离） | Accepted（已实施） |
| ADR-009 | 账号/云存档/平台验收范围（产品层待决 + 技术约束） | Proposed（等产品） |

## 4. 遗留项终态

| 遗留项 | 状态 |
|---|---|
| 阶段 B：正式 Enemy 接入实体仓 + 重连恢复测试 | ADR-002（随敌人 WIP 收口） |
| 账号体系/云存档 | ADR-009（产品决策） |
| 阶段 C：God Object 拆分 / 粒子/FX/LOD 全量预算 | ADR-003/ADR-004（变更频率驱动） |
| Autoload 收敛 / SaveManager 聚合器 | ADR-005（挂阶段 C/D） |
| 平台导出/真机验收 | ADR-009（发布排期） |
| 预存 WIP 套件（~30） | ADR-006（随各自功能提交） |

## 5. 变更清单（本轮）

**新增**：`globals/multiplayer/server_save_repository.gd`、`globals/perf/visual_quality_coordinator.gd`；测试 `server_save_repository_test.gd`、`visual_quality_coordinator_test.gd`；`docs/adr/`（9 份 ADR）。

**修改**：`session_root.gd`（仓注入/恢复/写回）、`network_manager.gd`（仓注入）、`spell_runtime.gd`（基准伤害）、`spell_authority.gd`（端口注入 skill_data）、`spell_world_executor.gd`（make_outbox_port）、`projectile_entity.gd`（命中端口分支）、`performance_budget_controller.gd`（协调器接入）、`docs/25`、`README_ARCHITECTURE.md`、`tests/gdunit/session_root_test.gd`、`spell_session_atomicity_test.gd`。

**验证**：19/19 套件全绿（含新增 2 套件 11 用例）。本轮改动未提交（与既有 WIP 并存，按 ADR-006 策略逐主题提交）。
