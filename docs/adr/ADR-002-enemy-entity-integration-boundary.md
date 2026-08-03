# ADR-002: 正式 Enemy 实体接入会话实体仓（阶段 B 边界）

- 状态：**Accepted（决策已定，实施随敌人 WIP 重构收口；用户拍板 2026-08-03）**
- 关联：架构审查 P1-2（单机/联机两套实体）、验收清单「正式 Enemy AI/碰撞/死亡/掉落真实双进程」

## 用户决策（2026-08-03）

**随敌人 WIP 重构收口**——工作树已有大量未提交敌人重构（enemy.gd 316 行改动、状态机/索敌/光照断言漂移），阶段 B 与其合并推进，避免并行修改同一文件集；不单独占迭代。

## 背景

联机服务器实体是 `_entities` 字典，客户端显示为 Label/HP 文本代理；真实单机敌人（Enemy 场景/状态机/导航/武器）未接入会话实体仓。当前双进程"战斗通过"证明的是字典代理链。

## 决策

1. **阶段 B 边界**（本轮不实施）：正式 Enemy 生命周期（生成/移动/受击/死亡/掉落/经验）全部注册到 `SessionRoot._entities` 权威表，客户端用同一正式模型的非权威 proxy。
2. **过渡承诺**：字典代理链继续作为传输/复制正确性的验证面；任何新增联机玩法不得绕过实体仓直改可见节点。
3. **已在第三/四轮完成的铺垫**：`damage_entity_port`（法术世界伤害写回实体仓）、projectile 命中端口写回（ADR-007）、事件 outbox、ProgressionAuthority 击杀经验/升级权威（per-peer attributes）。
4. 正式 Enemy 接入随敌人 WIP 重构（工作树预存）一起收口，避免并行修改同一文件集。

## 后果

- 阶段 B 完成前，联机击杀/掉落以实体仓为准、AI 表现以字典代理为准（已知限制）。
- 完成后移除 `dungeon_session_controller.spawn_server_entities` 的硬编码 Rat/Skeleton 生产路径。

## 更新（2026-08-03 21:30 · 2124 审查后）

**实体碰撞接缝已先行关闭**：服务器权威实体物理节点映射（AuthoritativeEntityBody——
可受击 enemy 装配 StaticBody3D + CapsuleShape + entity_id meta，ray/projectile 经祖先
查找命中并写回实体仓）已实施；阶段 B 剩余范围收窄为「正式 Enemy 场景/状态机/AI 接入
实体仓与表现代理统一」，仍随敌人 WIP 收口。