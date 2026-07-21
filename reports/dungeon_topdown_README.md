# 地牢 2D 俯视图渲染 — 图例与说明

本目录下的 PNG 是**程序化俯视图**，由 headless 驱动**真实地牢生成链**产出（不含运行时 HUD/光照），用于人工检查生成布局与场景分布是否正确：

```
DungeonGenerator.generate(isaac)
  → DungeonConnectivityValidator.validate
  → DungeonHazardPlanner.plan
  → DungeonSpawnPlanner.{plan_enemy_spawns, plan_item_spawns, plan_chest_spawns}
  → 把 DungeonLayout 逐格画成 RGBA 位图
```

每格放大 8 像素（42×42 网格 → 336×336 图）。颜色含义如下。

## 地形底色（grid TileType）

| 颜色 | 含义 | 枚举值 |
|---|---|---|
| 近黑 | 虚无 EMPTY（墙外/未生成） | 0 |
| 米色 | 地板 FLOOR（可走） | 1 |
| 深灰 | 墙 WALL（不可走） | 2 |
| 浅金 | LOOT 宝箱位（可走） | 3 |
| 浅绿 | RESOURCE 资源格（可走） | 4 |
| 灰棕 | PILLAR 石柱（可走） | 5 |

## 房间边框（room_roles 矩形描边）

| 颜色 | 房间角色 |
|---|---|
| 绿 | start（玩家出生房） |
| 红 | boss（BOSS 房） |
| 青 | extraction（撤离房，0.2 概率） |
| 蓝 | stairs（下楼） |
| 黄 | reward（奖励房，通常在 boss 房内） |

## 标记点（在格中心）

| 颜色 | 含义 |
|---|---|
| 棕（大） | Boss 门；棕（小）普通门 |
| 橙 | spikes 尖刺陷阱 |
| 黄绿 | acid 酸液陷阱 |
| 红橙 | flame_vent 喷火陷阱 |
| 黄（小） | 宝箱 chest |
| 紫（小） | 敌人 spawn |
| 绿（大） | 玩家出生点 player_spawn |
| 红（大） | BOSS 点 boss_cell |
| 蓝（大） | 下楼梯 stairs_cell |
| 青（大） | 撤离点 extraction_cell |
| 黄（中） | 奖励点 reward_cell |

## 各图统计（4 种子）

| 种子 | 房间 | 危险 | 宝箱 | 物品 | 敌人 | start | boss | stairs | extraction | reward |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 16 | 41 | 7 | 14 | 29 | ✓ | ✓ | ✓ | ✗ | ✓ |
| 7 | 18 | 41 | 8 | 16 | 33 | ✓ | ✓ | ✓ | ✗ | ✓ |
| 42 | 18 | 43 | 9 | 16 | 33 | ✓ | ✓ | ✓ | ✗ | ✓ |
| 1337 | 18 | 44 | 9 | 16 | 33 | ✓ | ✓ | ✓ | ✓ | ✓ |

- 危险陷阱 41–44/地牢，印证 `DungeonHazardPlanner` 早退 bug 修复后恢复正常生成。
- extraction 按 0.2 概率仅在 seed 1337 命中，符合设计。
- 所有地牢均含 start/boss/stairs/reward 关键房间与关键点，连通性校验通过。
