# 地图生成模拟报告（2026-07-17）

> 目标：跑一遍真实地图生成管线，确认产出的场景（scenes）正确、无缺失。

## 方法

headless 驱动真实生产链（不依赖 autoload / 运行时 HUD）：

```
DungeonGenerator.generate(config)         # isaac 算法，42×42 网格
  → layout.validate()                     # 布局合法性
  → DungeonConnectivityValidator.validate # 出生点/boss 可达性
  → DungeonHazardPlanner.plan              # 危险锚点规划
  → DungeonSpawnPlanner.plan_*             # 敌人/掉落/宝箱规划
  → DungeonSceneBuilder.build(layout, lvl)# 把 layout 实例化为 Godot 节点（分阶段 root）
```

遍历 8 个种子（20260717 / 1234 / 99173 / 555 / 7777 / 24680 / 13579 / 80808），每个种子统计生成场景节点并做硬断言。

## 结果（修复前）

| 场景类型 | 每种子数量（均值） | 状态 |
|---|---|---|
| 地形 floor / wall / ceiling | 1764 / 2–3 组 / 83–98 节点 | ✅ 正确 |
| 门面板 Door / BossDoor | 100–144 | ✅ 正确 |
| 宝箱 chest（含 boss_chest） | 8–13 | ✅ 正确 |
| 下楼传送门 DownstairsPortal | 6 | ✅ 正确 |
| 火把 torch | 4–49 | ✅ 正确 |
| 玩家出生点 / boss 房 | 全部命中 | ✅ 正确 |
| 撤离传送门 ExtractionPortal | 8 种子中 2 个（0.2 概率 role） | ✅ 符合预期 |
| **危险地形 spikes/acid/flame_vent** | **0（全部种子）** | ❌ **缺陷** |

`any_hard_fail=false`（核心场景都在），但 hazards 恒为 0 —— 这是真实缺陷，不是 RNG。

## 发现并修复的 Bug：`DungeonHazardPlanner` 守卫短路

**根因**：`dungeon_hazard_planner.gd` 的早退守卫

```gdscript
if layout.is_empty() or not layout.is_floor_at(0, 0):
    return
```

`is_floor_at(0,0)` 检查网格左上角 (0,0)。对真实地牢网格，(0,0) 几乎总是墙体/空洞角点 → `false` → planner 对每个真实地牢**提前 return**，永远不规划任何 hazard 锚点。结果：**spikes / acid / flame_vent 陷阱在所有地牢中永不生成**（仿真诊断 `is_floor_at(0,0)=false` 对全部 8 种子恒成立）。

`is_empty()` 已正确覆盖「未生成/生成失败」判空，该角点检查是错误有效性代理。

**修复**：去掉 `not layout.is_floor_at(0, 0)` 子句，仅保留 `if layout.is_empty(): return`，并补注释说明原因。

**回归测试**：原有 `test_integration_isaac_layout_planner_runs` 仅断言 `validate_plan` 为 valid —— 锚点为 0 时空列表 trivially 通过，故此 bug 漏过 CI。新增 `test_plan_real_isaac_layout_produces_hazard_anchors`：对 8 个真实种子断言 `hazard_anchors.size() > 0` 且 `validate_plan` 仍 valid。

## 结果（修复后）

| 场景类型 | 每种子数量 | 状态 |
|---|---|---|
| 危险地形 spikes/acid/flame_vent | **38–44（全种子）** | ✅ 修复 |
| kick_lane（踢击路线） | 38–44（与锚点 1:1 对应） | ✅ 正确 |
| 其余场景 | 同修复前（均正确） | ✅ |

8 种子累计：hazards=330、chests=86、downstairs=48、doors=1040、torch=223、extraction=2。`any_hard_fail=false`。

**gdUnit 测试**：`dungeon_hazard_planner_test.gd` 全 10 例通过（0 errors / 0 failures），含新增回归测试。

## 结论

地图生成管线产出的场景完整正确：地形 / 门 / 宝箱 / 下楼门 / 火把 / 出生点 / boss 房 / 撤离门（概率）均正常；危险陷阱此前因 planner 守卫 bug 全部缺失，现已修复并锁定回归测试。地牢场景生成无残留问题。

## 附：headless 启动期的无关告警

加载整个工程时，部分脚本报 `Compile Error: Identifier not found: GameState / GameEvents / WeaponRegistry / PhysicsSetup`。这些是引用 autoload 全局名的脚本在 headless 类-DB 构建期的解析告警，不在地牢生成路径上，且地牢仿真与 gdUnit 测试均正常运行 —— 属 headless 解析上下文特性，非本任务范围内的运行缺陷（如需可另查）。
