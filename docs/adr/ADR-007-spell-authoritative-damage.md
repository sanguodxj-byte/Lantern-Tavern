# ADR-007: 法术权威基准伤害（projectile / ray）

- 状态：**Accepted（已实施，2026-08-03；数值经用户拍板确认）**
- 关联：架构审查 P0-1-B（projectile 命中结算纳入会话权威链）

## 决策（用户拍板：2026-08-03）

**保持 `damage = 10`，先闭环。** 法术数值整体校准（heal 28 / absorb 30 / projectile 10 等内联常量）统一由 `docs/战斗数值体系.md` 法术卡规则接管，届时一次性对齐并补契约测试——本轮不再单独调整。

## 背景

effect_plan 的 heal（28）/absorb（30）/distance（5）均为内联设计常量，唯独 projectile/ray 没有基准伤害——单机走武器化 `resolve_projectile_attack`，联机权威路径无来源。

## 决策

1. `SpellRuntime._effect_plan` 的 `projectile/ray` 分支新增权威基准伤害 `base["damage"] = 10`（与 heal 28 同级的内联常量模式）。
2. `SpellAuthority` projectile 分支把 `damage` 与 `caster_peer` 及**会话实体仓 outbox 端口**注入投射物 `skill_data`；投射物命中带 `entity_id` 的权威实体时经端口写回 `SessionRoot._entities`（单次调用，事件进 outbox 统一排空），不再依赖可见节点 `try_receive_hit` 本地结算。
3. 单机法术投射物路径不受影响（skill_data 无端口时走原 `resolve_projectile_attack`）。

## 后果

- 联机法术投射物对权威敌人有可信命中/扣血/死亡/掉落闭环；服务缺失或 spawn 失败不 commit（第三轮已关）。
- 数值 10 为确定性基准并已拍板：法术数值统一校准由 `docs/战斗数值体系.md` 法术卡规则驱动（ADR-007 更新触发条件），不单独占迭代。

## 关联

- ADR-002（正式 Enemy 接入后，投射物命中可直接走 Enemy 实体仓，本端口机制保留为统一伤害出口）。
