extends Node

# 场景光照优化控制器（autoload，全局名 LightingController）。
# 注意：不声明 class_name，避免与同名 autoload 单例冲突（Godot 会报
# “Class 'LightingController' hides an autoload singleton” 并导致脚本无法加载）。
# 参考项目中已有的地牢动态光管理思路（procedural_dungeon.gd 按区块流式加载、
# 按距离预算激活局部光），把同一套「按场景/按设备分级管理动态光」的做法带到酒馆场景。
#
# 职责：
#   1. 火光闪烁（fire flicker）——让动态生成的火把/壁炉/蜡烛光有生命力。
#      参考常见 Godot 火光插件：用多层正弦叠加出有机的明灭，幅度小、确定性可测。
#   2. 酒馆专属光照档案（tavern profile）——酒馆是封闭小空间，火把原始 11m 照射范围
#      会让整个房间被均匀照亮、失去层次。此档案在酒馆里把火把范围收束成温暖的“光池”，
#      同时降低低端兼容性后端（gl_compatibility）下大量大范围动态光的重复绘制开销。
#      地牢火把采用更小的局部光池，基础可见性由地牢环境光和玩家短距补光承担；
#      本档案只在酒馆运行时生效。
#   3. 设备画质分级（quality tiers）——低端机更紧的范围、关闭闪烁以省成本。

enum Quality { HIGH, MEDIUM, LOW }

## 酒馆火把只负责局部暖色光池；基础可见性由中性环境光承担。
const TAVERN_TORCH_RANGE := {
	Quality.HIGH: 4.75,
	Quality.MEDIUM: 4.0,
	Quality.LOW: 3.5,
}
const TAVERN_TORCH_ENERGY := 1.55
const TAVERN_TORCH_COLOR := Color(1.0, 0.88, 0.75, 1.0)
const TAVERN_ACCENT_LIGHT_MAX_RANGE := 4.0
const TAVERN_ACCENT_LIGHT_NEUTRALIZATION := 0.4
## 不同画质下火光闪烁幅度（0 = 不闪烁）。
const FLICKER_AMPLITUDE := {
	Quality.HIGH: 0.12,
	Quality.MEDIUM: 0.09,
	Quality.LOW: 0.0,
}

var _quality_tier := Quality.HIGH
var _time := 0.0

## 最近一次 apply_tavern_profile 应用的根节点（P1-2：变档时重应用已有光源范围/能量）。
var _applied_profile_root: Node = null

## 缓存的闪烁光源列表——避免每帧 get_nodes_in_group 全组扫描
var _cached_flicker_lights: Array[OmniLight3D] = []
## 缓存失效标志——apply_tavern_profile 或光源增删时置位
var _flicker_cache_dirty := true


func _ready() -> void:
	_quality_tier = detect_quality_tier()
	# P1-4：订阅 PerformanceBudget 动态质量分档——GPU 压力上升时灯光范围/闪烁幅度跟随
	# 降档（此前只有 3D 分辨率消费者，灯光/阴影/粒子等视觉成本不跟随）。
	var budget: Node = get_node_or_null("/root/PerformanceBudget")
	if budget != null and budget.has_signal("quality_tier_changed"):
		budget.quality_tier_changed.connect(_on_budget_tier_changed)


## 性能预算分档 → 光照质量档映射（P1-4）。
## FULL/BALANCED → HIGH/MEDIUM（动态光成本低时全开）；PERFORMANCE/EMERGENCY → LOW。
static func quality_tier_to_lighting(tier: int) -> Quality:
	if tier >= 2:  # PerformanceBudget.QualityTier.PERFORMANCE / EMERGENCY
		return Quality.LOW
	if tier >= 1:  # BALANCED
		return Quality.MEDIUM
	return Quality.HIGH


func _on_budget_tier_changed(tier: int, _render_scale: float) -> void:
	_quality_tier = quality_tier_to_lighting(tier)
	# P1-2：变档后重应用已应用光源——已有火把的 omni_range/energy 立即跟随新档位，
	# 否则运行中降档只改档位变量、场景光源仍是旧范围。
	if _applied_profile_root != null and is_instance_valid(_applied_profile_root):
		apply_tavern_profile(_applied_profile_root)


## 依据渲染后端推断画质分级。仅 gl_compatibility（兼容性后端）动态光成本高，降到 MEDIUM；
## 其余（forward_plus / forward_mobile）动态光成本低，均为 HIGH。
func detect_quality_tier() -> Quality:
	var method: String = ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus")
	if method == "gl_compatibility":
		return Quality.MEDIUM
	return Quality.HIGH


func set_quality_tier(t: Quality) -> void:
	_quality_tier = t


func get_quality_tier() -> Quality:
	return _quality_tier


## 对酒馆场景应用光照档案：统一关闭所有场景光源的镜面贡献，
## 标记 OmniLight3D 火光闪烁组，并把火把（meta light_role=="torch"）的范围/亮度收束为酒馆值。
## root: 酒馆根节点（TavernInterior）。玩家自带视觉光会被跳过。
## 幂等：已入 flicker_light 组的光源不再重复入组（P1-2 变档重应用安全）。
func apply_tavern_profile(root: Node) -> void:
	if root == null:
		return
	_applied_profile_root = root
	for light in _collect_scene_lights(root):
		# 酒馆环境材质采用非金属体素规范；光源也设为无镜面，
		# 防止遗漏 StandardMaterial3D 或第三方材质时重新出现白色倒影。
		light.light_specular = 0.0
		if light.name == Player.PLAYER_VISION_LIGHT_NAME:
			light.visible = false
			light.light_energy = 0.0
			continue
		if not light is OmniLight3D:
			continue
		var omni := light as OmniLight3D
		omni.light_color = omni.light_color.lerp(
			Color.WHITE, TAVERN_ACCENT_LIGHT_NEUTRALIZATION)
		omni.omni_range = minf(omni.omni_range, TAVERN_ACCENT_LIGHT_MAX_RANGE)
		if not light.has_meta("flicker_base_energy"):
			light.set_meta("flicker_base_energy", light.light_energy)
		if not light.has_meta("flicker_phase"):
			light.set_meta("flicker_phase", randf() * TAU)
		if light.get_meta("light_role", "") == "torch":
			# P1-2：范围/能量按【当前档位】应用——变档重应用会更新已有光源。
			omni.omni_range = TAVERN_TORCH_RANGE[_quality_tier]
			omni.light_energy = TAVERN_TORCH_ENERGY
			omni.light_color = TAVERN_TORCH_COLOR
			light.set_meta("flicker_base_energy", light.light_energy)
		if not light.is_in_group("flicker_light"):
			light.add_to_group("flicker_light")
	# 新光源已入组，标记缓存为脏以便下次 _process 刷新
	_flicker_cache_dirty = true


## 确定性火光闪烁系数：输入相同 (phase, time, amplitude) 必得相同结果，便于单测。
## 返回 [1-amplitude, 1+amplitude] 区间内的乘数。
func compute_flicker(phase: float, time: float, amplitude: float) -> float:
	var a := sin(time * 9.0 + phase) * 0.5 + 0.5
	var b := sin(time * 17.7 + phase * 1.7) * 0.5 + 0.5
	var n := a * 0.6 + b * 0.4
	return 1.0 + (n - 0.5) * 2.0 * amplitude


func _process(delta: float) -> void:
	_time += delta
	var amp: float = FLICKER_AMPLITUDE.get(_quality_tier, 0.0)
	if amp <= 0.0:
		return
	# 仅在缓存脏时刷新光源列表，避免每帧扫描全组
	if _flicker_cache_dirty:
		_refresh_flicker_cache()
	for light in _cached_flicker_lights:
		if not is_instance_valid(light):
			continue
		var base: float = light.get_meta("flicker_base_energy", light.light_energy)
		var phase: float = light.get_meta("flicker_phase", 0.0)
		light.light_energy = base * compute_flicker(phase, _time, amp)

## 刷新闪烁光源缓存：从 flicker_light 组中收集所有有效 OmniLight3D
func _refresh_flicker_cache() -> void:
	_cached_flicker_lights.clear()
	for node in get_tree().get_nodes_in_group("flicker_light"):
		if node is OmniLight3D and is_instance_valid(node):
			_cached_flicker_lights.append(node as OmniLight3D)
	_flicker_cache_dirty = false

## 标记缓存为脏——外部调用（如光源增删）时使用
func invalidate_flicker_cache() -> void:
	_flicker_cache_dirty = true


func _collect_scene_lights(root: Node) -> Array[Light3D]:
	var result: Array[Light3D] = []
	_collect_scene_lights_recursive(root, result)
	return result


func _collect_scene_lights_recursive(node: Node, result: Array[Light3D]) -> void:
	if node is Light3D:
		result.append(node as Light3D)
	for child in node.get_children():
		_collect_scene_lights_recursive(child, result)
