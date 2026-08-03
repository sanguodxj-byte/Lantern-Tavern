class_name VisualQualityCoordinator
extends RefCounted

## VisualQualityCoordinator（架构审查 P1-2/基线 P1-8）—— 性能档位 → 视觉成本预算的统一映射。
##
## 此前动态质量分档只有两个消费者：Viewport FSR scale（PerformanceBudget 自身）与
## LightingController 的光源档（火把范围/能量）。阴影、环境雾、环境光等场景级成本
## 不跟随 GPU 压力。本协调器把档位映射为「环境 + 主光阴影」预算。
##
## 预算语义（2026-08-03 架构检查修正）：**只降不升 + 原始值还原**——
##   * 低档（PERFORMANCE/EMERGENCY）：fog 关闭、fog_density/ambient_light_energy 取
##     min(原始值, 预算值)——绝不上调场景已调好的值；
##   * 高档（FULL/BALANCED）：**还原**首次记录的场景原始值——绝不覆盖地牢 zone 配置
##     （zone 1-5 雾 0.008~0.012）或酒馆雾，也绝不强制开启原本关闭的阴影。
## 实例持有原始值快照；由 PerformanceBudget 持有并在每次变档时调用。

## PerformanceBudget.QualityTier: FULL=0 / BALANCED=1 / PERFORMANCE=2 / EMERGENCY=3
const ENV_PROFILES := {
	0: {"fog_enabled": true, "fog_density": 0.006, "ambient_energy": 0.6, "shadows": true},
	1: {"fog_enabled": true, "fog_density": 0.004, "ambient_energy": 0.5, "shadows": true},
	2: {"fog_enabled": false, "fog_density": 0.0, "ambient_energy": 0.4, "shadows": false},
	3: {"fog_enabled": false, "fog_density": 0.0, "ambient_energy": 0.3, "shadows": false},
}

## 实例 id -> {fog_enabled, fog_density, ambient_light_energy}（首次记录的场景原始值）。
var _original_env: Dictionary = {}
## 光实例 id -> bool（原始 shadow_enabled）。
var _original_shadow: Dictionary = {}

## 取档位预算（未知档位回退 FULL，避免 null 崩溃）。
static func profile_for(tier: int) -> Dictionary:
	return ENV_PROFILES.get(tier, ENV_PROFILES[0])

## 是否降档（PERFORMANCE 及以下才应用预算；FULL/BALANCED 还原原始）。
static func is_budget_tier(tier: int) -> bool:
	return tier >= 2

## 对单个 Environment 应用档位预算（min 语义 + 原始值还原）。
## env 首次出现时登记原始值。
func apply_environment(env: Environment, tier: int) -> bool:
	if env == null:
		return false
	var env_id := env.get_instance_id()
	if not _original_env.has(env_id):
		_original_env[env_id] = {
			"fog_enabled": env.fog_enabled,
			"fog_density": env.fog_density,
			"ambient_light_energy": env.ambient_light_energy,
		}
	var orig: Dictionary = _original_env[env_id]
	var p := profile_for(tier)
	if is_budget_tier(tier):
		if "fog_enabled" in env:
			env.fog_enabled = bool(p["fog_enabled"])
		if "fog_density" in env:
			env.fog_density = minf(float(orig["fog_density"]), float(p["fog_density"]))
		if "ambient_light_energy" in env:
			env.ambient_light_energy = minf(float(orig["ambient_light_energy"]), float(p["ambient_energy"]))
	else:
		if "fog_enabled" in env:
			env.fog_enabled = bool(orig["fog_enabled"])
		if "fog_density" in env:
			env.fog_density = float(orig["fog_density"])
		if "ambient_light_energy" in env:
			env.ambient_light_energy = float(orig["ambient_light_energy"])
	return true

## 对场景根应用档位预算：遍历 WorldEnvironment 与 DirectionalLight3D。
## 返回被应用的 WorldEnvironment 数量（测试断言用）。
func apply_to_scene(root: Node, tier: int) -> int:
	if root == null:
		return 0
	var applied := 0
	for env_node in root.find_children("*", "WorldEnvironment", true, false):
		var env := (env_node as WorldEnvironment).environment
		if apply_environment(env, tier):
			applied += 1
	for light in root.find_children("*", "DirectionalLight3D", true, false):
		var light_id := light.get_instance_id()
		if not _original_shadow.has(light_id):
			_original_shadow[light_id] = bool(light.shadow_enabled)
		# 只降不升：阴影仅在【原始开启】且【高档位】时保持；降档关闭。
		light.shadow_enabled = (not is_budget_tier(tier)) and bool(_original_shadow[light_id])
	return applied
