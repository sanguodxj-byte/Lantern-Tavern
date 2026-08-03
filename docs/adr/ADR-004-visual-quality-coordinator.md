# ADR-004: 视觉质量统一协调（VisualQualityCoordinator）

- 状态：**Accepted（已实施，2026-08-03）**
- 关联：架构审查 P1-2、基线 P1-8

## 背景

动态质量分档长期只有两个消费者：Viewport FSR scale 与 LightingController 光源档。降档时阴影、环境雾、环境光不跟随；现有光源范围此前也不重应用（第三轮已修）。

## 决策

1. **分工**：
   - `PerformanceBudget`：帧时间采样、分档决策、Viewport FSR scale（分辨率）；
   - `LightingController`：动态光源（火把/闪烁）档位 + 变档重应用（订阅 `quality_tier_changed`）；
   - `VisualQualityCoordinator`（新，纯静态工具）：环境级预算——`Environment` 的 fog 开关/密度、`ambient_light_energy`，以及 `DirectionalLight3D.shadow_enabled`（PERFORMANCE 以下关阴影）。
2. `PerformanceBudget._apply_quality_tier` 每次变档调用 `VisualQualityCoordinator.apply_to_scene(current_scene, tier)`。
3. 档位预算表 `ENV_PROFILES`（FULL/BALANCED/PERFORMANCE/EMERGENCY）为唯一映射真相，未知档位回退 FULL。

## 决策边界（本轮不做）

- 粒子/法术 FX/LOD 距离预算未接入：粒子属于单机表现层（spell FX 已有独立节流），LOD 随模型资产工作流配置。若后续出现移动端 GPU 压力证据，在 `ENV_PROFILES` 扩展字段并接入对应消费者，**不再新建第二个协调器**。

## 后果

- 变档一次性应用：分辨率 + 动态光 + 环境雾/光 + 主光阴影。
- 新增视觉成本消费者一律注册到本协调器（或 LightingController），禁止旁路。
