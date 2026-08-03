# ADR-003: God Object 拆分策略（DungeonSceneBuilder / Player / TavernEquipmentPanel / SessionRoot）

- 状态：**Accepted（决策已定，实施按变更频率驱动）**
- 关联：架构审查 P1-5/P1-6/P1-7、基线阶段 C

## 背景

`DungeonSceneBuilder` 2417 行、`TavernEquipmentPanel` 1926 行、`Player` 1322 行、`SessionRoot` 1200+ 行。大脚本是变更风险中心。

## 决策

1. **按变更频率驱动拆分，不机械执行**：只有当文件出现以下信号之一才拆——
   - 单次功能变更需理解 >200 行无关代码；
   - 两个以上团队/代理并行修改同一文件冲突；
   - 测试需要构造文件内部状态（说明内聚边界错位）。
2. **已完成的拆分**（不重复）：
   - `Player` → `PlayerCombatRuntime` / `PlayerSpellCaster` / `ClientCommandDriver` / `CombatBuffComponent` 等（历史完成）；
   - `TavernEquipmentPanel` → `InventoryTransferService` + `equipment_panel_inventory.gd`（P0-6/P1-6 完成）；
   - `SessionRoot` → 子权威系统（MovementAuthority/CombatAuthority/InteractionAuthority/LootAuthority/SaveAuthority/DungeonAuthority/EntitySyncAuthority/ConnectionAuthority/SpellAuthority）+ 策略层（AttackContextFactory/AttackCadencePolicy/EquipmentPolicy/SpellAccessPolicy）+ ServerSaveRepository（ADR-001）。
3. **后续优先级**：
   - 高：`DungeonSceneBuilder` 四个 assembler（terrain/traversal/encounter/decoration）+ pipeline——与地牢 WIP 重构（工作树预存）同步进行；
   - 中：`Player` 输入路由拆分——仅在新增输入机制时执行；
   - 低：`TavernEquipmentPanel` 剩余 presenter 拆分——仅在 UI 功能扩展时执行。
4. **观察名单（2026-08-03 架构检查补充，>1000 行）**：`chest_loot_panel.gd`（1154）、`isaac_room_dungeon_generator.gd`（1099）、`voxel_prop.gd`（1073）、`view_model.gd`（1011）、`ui_runtime_capture_driver.gd`（998）——按第 1 条信号评估，不机械拆分。
5. **拆分守则**：保持手工酒馆场景规则不受影响（AGENTS.md 酒馆禁令）；拆分必须逐文件提交、每步跑相关测试。

## 后果

- 拆分与功能开发同步（不单独占迭代）；任何时刻不出现"为拆而拆"的纯重构 PR。
- 新代码禁止追加到上述大文件（>300 行阈值后必须新建文件）。
