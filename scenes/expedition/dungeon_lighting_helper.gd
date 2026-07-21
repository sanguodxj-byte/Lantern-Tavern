class_name DungeonLightingHelper
## 地牢光照分类与配置辅助（从 procedural_dungeon.gd 提取）。
## 纯静态工具类，不依赖运行时状态，所有方法均为 static。

## 递归收集节点树中所有非方向光的 Light3D。
static func collect_local_lights(node: Node, result: Array[Light3D]) -> void:
	if node is Light3D and not (node is DirectionalLight3D):
		result.append(node as Light3D)
	for child in node.get_children():
		collect_local_lights(child, result)

## 判断灯光是否为玩家视野灯。
static func is_player_vision_light(light: Light3D, vision_light_name: String) -> bool:
	return light.name == vision_light_name

## 配置玩家视野灯参数。
static func configure_player_vision_light(light: Light3D, base_energy: float, base_range: float) -> void:
	var omni := light as OmniLight3D
	if omni == null:
		return
	omni.visible = true
	omni.light_energy = base_energy
	omni.omni_range = base_range
	omni.omni_attenuation = 0.45
	omni.shadow_enabled = false
	omni.distance_fade_enabled = false

## 判断灯光是否为提示灯（附着在拾取物/敌人/陷阱上的灯）。
## root_node: 地牢根节点，用于终止父链遍历。
static func is_hint_light(light: Light3D, root_node: Node) -> bool:
	if light.name == "PresenceLight":
		return true
	var parent := light.get_parent()
	while parent != null and parent != root_node:
		if parent is PickableItem or parent is Enemy or parent is SpikesTrap or parent is AcidTrap or is_generated_trap_node(parent):
			return true
		parent = parent.get_parent()
	return false

## 判断节点是否为生成的陷阱节点。
static func is_generated_trap_node(node: Node) -> bool:
	if node == null:
		return false
	if node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "hazard":
		return true
	return String(node.name) == "FlameVentTrap"
