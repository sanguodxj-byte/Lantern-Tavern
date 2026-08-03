# Lantern Tavern 架构审查（2026-08-03 20:40 · 独立复核轮）

**性质**：在 9 项 ADR 定案与 5 轮整改之后的独立只读架构检查（含对第四轮引入代码的回归审计）。
**结论**：**B-** —— 发布阻断已清零、权威闭环完整、门禁严格；剩余为工程债（大文件/源码字符串测试/预存 WIP）与阶段 B 边界，无新发布阻断。

---

## 1. 已关闭确认（快速复核，均有效）

- 联机权威链：身份唯一、固定 tick 输入、ServerCharacterMotor 碰撞、AttackContext 唯一装配、统一冷却、装备策略（含护甲固有部位）、法术事务（prepare→execute→verify→commit→publish）、事件 outbox、projectile 端口写回、服务器存档仓、击杀经验/升级权威——全部闭环。
- 平台：mobile renderer + 三预设 CI 门禁；质量分档：分辨率 + 动态光重应用 + 环境预算协调。
- 门禁：审查相关套件 0 orphan/退出 0；`-FailOnOrphan` 严格开关。
- 生产代码零 `GameState.current_player` 裸读（仅注释）。

## 2. 本轮新发现并修复（2 个真实缺陷）

### 2.1 VisualQualityCoordinator 无条件覆盖场景环境（第四轮引入回归）→ 已修复

- **问题**：`apply_to_scene` 把 `ENV_PROFILES` 的 fog/ambient 绝对值直接写入所有 WorldEnvironment——变档（含启动时 FULL 应用）会把地牢 zone 1-5 的雾（0.008~0.012）强制改为 0.006、覆盖酒馆雾配置；恢复档位还会把原本关闭的阴影强制开启。
- **修复**：预算语义改为「只降不升 + 原始值还原」——首次接触登记原始值；低档（PERFORMANCE/EMERGENCY）取 `min(原始, 预算)`、关雾、关阴影；高档还原原始；阴影仅在「原始开启且高档」时保持。协调器改为有状态实例（PerformanceBudget 持有），新增 4 项回归测试（含「恢复不得覆盖场景雾」「不得强制开启原本关闭的阴影」）。

### 2.2 ServerSaveRepository 非原子写 → 已修复

- **问题**：`save_save` 直接写目标文件——listen-server 与 dedicated server 同机共享 `user://` 时，读方可能读到半写 JSON（解析失败 → 返回 {} → 权威状态丢失）。
- **修复**：写 `<guid>.json.tmp` 后 rename（原子替换）；`load_save` 在替换窗口期回退读 `.tmp` 完整内容。测试补充后 7/7 通过。

## 3. 观察项（非阻断，记录）

1. `NetworkManager._ensure_session` 在客户端侧也注入 `GameState.player_resolver`（客户端无会话 registry，解析恒回退 current_player）——无功能影响，属注入面过宽；建议仅 `is_host` 时注入（挂 ADR-005）。
2. 法术投射物命中走 `_apply_weapon_wear()`（既有路径一致性）——法术命中会磨损玩家武器，与单机法术投射物行为一致；是否属设计意图待策划确认（挂 ADR-007 数值校准）。
3. 存档仓写回包含 attributes/skills 全量快照——文件随玩家成长增长，量级可接受（单玩家 KB 级）；云存档出现时按 ADR-009 迁移。
4. 源码字符串断言存量：243/457 测试文件仍含 `source_code`/`get_file_as_string`（基线 244，几乎未降）——被点名套件已行为化，但全仓存量面未动。**建议**：ADR-008 补充「新测试禁止源码字符串断言证明行为；存量转换随功能改动渐进」的硬规则。

## 4. 大文件现状与拆分名单补充

| 文件 | 行数 | 状态 |
|---|---|---|
| dungeon_scene_builder.gd | 2303 | ADR-003 高优先级（随地牢 WIP） |
| tavern_equipment_panel.gd | 1772 | ADR-003 低优先级 |
| session_root.gd | 1185 | ADR-003 已列（子权威+策略层已完成大部分） |
| player.gd | 1183 | ADR-003 中优先级 |
| **chest_loot_panel.gd** | 1154 | **本轮补充：纳入 ADR-003 观察名单** |
| **isaac_room_dungeon_generator.gd** | 1099 | **本轮补充：纳入 ADR-003 观察名单** |
| **voxel_prop.gd** | 1073 | **本轮补充：纳入 ADR-003 观察名单** |
| enemy.gd | 1037 | 随敌人 WIP 收口（ADR-002） |
| **view_model.gd** | 1011 | **本轮补充：纳入 ADR-003 观察名单** |
| **ui_runtime_capture_driver.gd** | 998 | 工具脚本，观察 |

> 已更新 ADR-003 观察名单（见下）。

## 5. ADR 状态核对（9/9 定案）

- 已实施 5：001 存档仓、004 视觉协调（本轮语义修正）、006 提交策略、007 法术伤害（用户拍板保持 10）、008 CI 门禁
- 边界已定 3：002 阶段 B（用户拍板随 WIP）、003 God Object 拆分、005 Autoload 收敛
- 产品已拍板 1：009 维持现状（本机 guid + 服务器仓）

## 6. 遗留终态（无新项，均为既定边界）

1. 阶段 B：正式 Enemy 接入实体仓（随敌人 WIP 收口，ADR-002）
2. 阶段 C：God Object 拆分 + 观察名单扩展（ADR-003 更新）
3. Autoload 收敛 / SaveManager 聚合器（ADR-005）
4. 预存 WIP 套件 ~30 个（随各自功能提交，ADR-006）
5. 平台实际导出/真机验收（ADR-009，发布排期）
6. 法术数值整体校准（ADR-007 触发条件：战斗数值文档接管）

---

## 7. 本轮变更

- `globals/perf/visual_quality_coordinator.gd`：预算语义重写（只降不升 + 原始值还原，实例化）。
- `globals/perf/performance_budget_controller.gd`：持有协调器实例。
- `globals/multiplayer/server_save_repository.gd`：原子写（.tmp + rename）+ 窗口期回退读。
- `tests/gdunit/visual_quality_coordinator_test.gd`：重写 7 项（新增「不覆盖场景配置」「不强制开阴影」回归）。
- `docs/adr/ADR-003`：拆分观察名单补充 4 个 >1000 行文件。
- 验证：coordinator 7/7、save repo 7/7、performance budget 4/4、lighting 15/15、session_root 71+、spell 系列全绿（0 orphan、退出 0）。
