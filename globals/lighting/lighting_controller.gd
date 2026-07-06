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
#      注意：地牢里的火把仍保持 omni_range>=10 / energy>=3.2（light_fade_distance_test
#      强制的远距离可见性约束），本档案只在酒馆运行时生效，不会破坏该测试。
#   3. 设备画质分级（quality tiers）——低端机更紧的范围、关闭闪烁以省成本。

enum Quality { HIGH, MEDIUM, LOW }

## 酒馆里火把被收束后的照射半径（米）。比原始 11m 小得多，形成明暗层次。
const TAVERN_TORCH_RANGE := {
	Quality.HIGH: 5.0,
	Quality.MEDIUM: 4.0,
	Quality.LOW: 3.0,
}
## 酒馆里火把的亮度。原始为 3.4（地牢需要），酒馆收束避免过曝。
const TAVERN_TORCH_ENERGY := 2.2
## 不同画质下火光闪烁幅度（0 = 不闪烁）。
const FLICKER_AMPLITUDE := {
	Quality.HIGH: 0.12,
	Quality.MEDIUM: 0.09,
	Quality.LOW: 0.0,
}

var _quality_tier := Quality.HIGH
var _time := 0.0


func _ready() -> void:
	_quality_tier = detect_quality_tier()


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


## 对酒馆场景应用光照档案：找到所有 OmniLight3D，标记火光闪烁组，
## 并把火把（meta light_role=="torch"）的范围/亮度收束为酒馆值。
## root: 酒馆根节点（TavernInterior）。玩家自带视觉光会被跳过。
func apply_tavern_profile(root: Node) -> void:
	if root == null:
		return
	for light in _collect_omni_lights(root):
		if light.name == Player.PLAYER_VISION_LIGHT_NAME:
			continue
		if not light.has_meta("flicker_base_energy"):
			light.set_meta("flicker_base_energy", light.light_energy)
		if not light.has_meta("flicker_phase"):
			light.set_meta("flicker_phase", randf() * TAU)
		if light.get_meta("light_role", "") == "torch":
			light.omni_range = TAVERN_TORCH_RANGE[_quality_tier]
			light.light_energy = TAVERN_TORCH_ENERGY
			light.set_meta("flicker_base_energy", light.light_energy)
		light.add_to_group("flicker_light")


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
	for light in get_tree().get_nodes_in_group("flicker_light"):
		if not (light is OmniLight3D) or not is_instance_valid(light):
			continue
		var base: float = light.get_meta("flicker_base_energy", light.light_energy)
		var phase: float = light.get_meta("flicker_phase", 0.0)
		light.light_energy = base * compute_flicker(phase, _time, amp)


func _collect_omni_lights(root: Node) -> Array[OmniLight3D]:
	var result: Array[OmniLight3D] = []
	_collect_omni_lights_recursive(root, result)
	return result


func _collect_omni_lights_recursive(node: Node, result: Array[OmniLight3D]) -> void:
	if node is OmniLight3D:
		result.append(node as OmniLight3D)
	for child in node.get_children():
		_collect_omni_lights_recursive(child, result)
