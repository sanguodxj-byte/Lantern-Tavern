extends GdUnitTestSuite

# E1/E4（1327 审查）禁止模式守卫：联机/光照/性能等文件不得再有裸 /root 字符串路径查找，
# 统一走 Service 访问器（消除「三种依赖约定」——裸全局 / Service / 绝对 root 路径）。

## 已知豁免：Service 有意不暴露的 autoload（进程生命周期/纯数据/UI 直连型），
## 或由调用方直接使用全局标识符访问。新增豁免需注释理由。
const SERVICE_EXEMPT := {
	"AudioManager": "音效/音频驱动直连型",
	"LocalizationManager": "本地化全局直连",
	"BrewingData": "纯数据注册表，脚本静态访问",
	"DungeonSpawner": "场景驱动型 autoload",
	"ItemSpawner": "场景驱动型 autoload",
	"AffixSystem": "装备词缀服务（脚本静态访问）",
	"ProjectileService": "投射物对象池",
	"LightingController": "渲染/光照控制器",
	"ArmorProficiency": "护甲熟练度（Service 覆盖待补）",
	"PerformanceBudget": "性能档位控制器（场景直连）",
}

func test_service_accessor_contract_migrated_files() -> void:
	# 每个生产文件：源码中不得残留被迁移的裸 /root 路径。
	var files := {
		"res://globals/multiplayer/multiplayer_scene_bridge.gd": [
			'get_node_or_null("/root/GameState")',
			'get_node_or_null("/root/AttrPanel")',
			'get_node_or_null("/root/SaveManager")',
			'get_node_or_null("/root/MultiplayerSession")',
			'get_node_or_null("/root/NetworkManager")',
		],
		"res://globals/core/network_manager.gd": [
			'get_node_or_null("/root/GameState")',
		],
		"res://globals/lighting/lighting_controller.gd": [
			'get_node_or_null("/root/PerformanceBudget")',
		],
		"res://globals/perf/perf_monitor.gd": [
			'get_node_or_null("/root/PerformanceBudget")',
		],
	}
	for path in files.keys():
		var source := (load(path) as GDScript).source_code
		for forbidden in files[path]:
			assert_bool(source.contains(forbidden)).override_failure_message(
				"%s 仍含裸路径 %s（E1：应经 Service 访问器）" % [path, forbidden]
			).is_false()


func test_service_covers_all_registered_autoloads() -> void:
	# 1122 审查 P1-1：不再维护手写抽样列表与会漂移的数量注释——
	# 自动从 project.godot [autoload] 段解析全部登记项，验证 Service 提供访问器。
	var source := (load("res://globals/core/service.gd") as GDScript).source_code
	var missing: Array = []
	var registered: Array = _registered_autoload_names()
	for autoload_name in registered:
		var name := String(autoload_name)
		if SERVICE_EXEMPT.has(name):
			continue
		var accessor := _to_snake(name)
		if not source.contains("func %s(" % accessor):
			missing.append("%s (期望访问器 %s)" % [name, accessor])
	assert_array(missing).is_empty() \
		.override_failure_message("Service 缺失以下 autoload 访问器（共登记 %d 个）：\n%s" % [registered.size(), "\n".join(missing)])

## 从 project.godot [autoload] 段自动解析全部登记名（消除手写抽样漂移）。
func _registered_autoload_names() -> Array:
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	var names: Array = []
	var in_autoload := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if not in_autoload:
			in_autoload = line == "[autoload]"
			continue
		if line.begins_with("["):
			break
		if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq > 0:
			names.append(line.substr(0, eq))
	return names

## CamelCase → snake_case（Service 访问器命名约定：GameState → game_state）。
func _to_snake(camel: String) -> String:
	var out := ""
	for i in camel.length():
		var c := camel[i]
		if c == c.to_upper() and out != "" and not (out[-1] == "_"):
			out += "_"
		out += c.to_lower()
	return out
