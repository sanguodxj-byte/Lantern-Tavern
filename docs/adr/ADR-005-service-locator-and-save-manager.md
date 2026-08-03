# ADR-005: 服务定位器收敛与存档聚合器（Autoload / SaveManager）

- 状态：**Proposed（决策已定，实施挂阶段 C/D）**
- 关联：架构审查 P2-1（Autoload 面过宽）、P2-2（SaveManager 聚合器）

## 背景

31 个 Autoload；`Service` 通过根节点字符串返回 `Node`，类型安全有限且隐藏依赖；`SaveManager.serialize_all()/deserialize_all()` 显式拉取全部领域单例，新增领域必须改中央文件。

## 决策

1. **Autoload 分层**（按需迁移，不一次性重构）：
   - 保留进程级基础设施：`GameState`、`GameEvents`、`AudioManager`、`LocalizationManager`、`Settings`、`NetworkManager`、`Service`（兼容层）、`PerformanceBudget`、`LightingController`、`TavernManager`（酒馆领域权威）、`WeaponRegistry`（数据表）。
   - 纯数据/纯策略 → `class_name` 常量经 preload 引用，退出 Autoload：`ExpeditionInventory`、`EquipmentLoadout`、`SpellLoadout`、`AttackCadencePolicy`、`EquipmentPolicy`、`SpellAccessPolicy`、`VisualQualityCoordinator`（已完成）、`ServerSaveRepository`（已完成）。
   - 场景级服务 → 由 Composition Root 显式注入：`ProjectileService`、`DungeonSpawner`、`ItemSpawner` 等——**仅当新增场景需要独立生命周期时迁移**。
2. **SaveManager 聚合器**：新增 `SaveSection` 注册协议（领域模块自注册 `serialize/deserialize`），`SaveManager` 只编排节列表与版本迁移；**在本轮不实施**（存档格式稳定、改动收益低），挂阶段 D 与存档版本迁移一起做。
3. 新增代码禁止新增 Autoload（除非进程级基础设施且经本 ADR 评审）。

## 后果

- 渐进收敛：每次功能改动顺手迁移一个服务定位器调用，不安排独立重构迭代。
- SaveManager 聚合器与账号/云存档决策（ADR-009）联动，避免双重迁移。
