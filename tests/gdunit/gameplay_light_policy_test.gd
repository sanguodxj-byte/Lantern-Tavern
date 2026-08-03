extends GdUnitTestSuite

const ENEMY_SCENES := [
	"res://scenes/characters/enemies/goblin.tscn",
	"res://scenes/characters/enemies/orc_raider.tscn",
	"res://scenes/characters/enemies/skeleton.tscn",
	"res://scenes/characters/enemies/troll.tscn",
	"res://scenes/characters/enemies/rock_golem.tscn",
	"res://scenes/characters/enemies/dragon.tscn",
]
const UNLIT_GAMEPLAY_SCENES := [
	"res://scenes/equipment/pickable_item.tscn",
	"res://scenes/equipment/pickable_axe.tscn",
	"res://scenes/equipment/pickable_sword.tscn",
	"res://scenes/equipment/pickable_buckler.tscn",
	"res://scenes/door/door.tscn",
]


func _collect_scene_state_lights(
		state: SceneState,
		origin: String,
		visited: Dictionary,
		result: Array[String]
) -> void:
	if state == null or visited.has(state.get_instance_id()):
		return
	visited[state.get_instance_id()] = true
	for node_index in state.get_node_count():
		var node_type := String(state.get_node_type(node_index))
		var node_path := String(state.get_node_path(node_index))
		if node_type.ends_with("Light3D"):
			result.append("%s:%s (%s)" % [origin, node_path, node_type])
		var child_scene := state.get_node_instance(node_index) as PackedScene
		if child_scene != null:
			_collect_scene_state_lights(
				child_scene.get_state(),
				child_scene.resource_path,
				visited,
				result
			)
	var base_state := state.get_base_scene_state()
	if base_state != null:
		_collect_scene_state_lights(base_state, origin + "<base>", visited, result)


func _assert_scene_has_no_lights(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	assert_object(packed).is_not_null() \
		.override_failure_message("Failed to load gameplay scene: %s" % scene_path)
	if packed == null:
		return
	var light_paths: Array[String] = []
	_collect_scene_state_lights(packed.get_state(), scene_path, {}, light_paths)
	assert_array(light_paths).is_empty() \
		.override_failure_message("Disallowed light nodes in %s: %s" % [scene_path, light_paths])


func test_enemy_scenes_do_not_contain_lights() -> void:
	for scene_path in ENEMY_SCENES:
		_assert_scene_has_no_lights(scene_path)


func test_unlit_gameplay_scenes_do_not_contain_lights() -> void:
	for scene_path in UNLIT_GAMEPLAY_SCENES:
		_assert_scene_has_no_lights(scene_path)


func test_enemy_runtime_scripts_do_not_manage_presence_lights() -> void:
	for script_path in [
		"res://scenes/characters/enemies/enemy.gd",
		"res://scenes/characters/enemies/state/enemy_state_dying.gd",
	]:
		var source := FileAccess.get_file_as_string(script_path)
		assert_bool(source.contains("presence_light")).is_false() \
			.override_failure_message("Enemy runtime script still manages a presence light: %s" % script_path)
		# 禁止任何游戏内光源创建（Omni/Spot）；仅允许 imposter 贴图捕获视口内的
		# 临时渲染 DirectionalLight3D（_build_imposter_texture 路径，离屏一次性渲染）。
		assert_bool(not source.contains("OmniLight3D.new(")).is_true() \
			.override_failure_message("Enemy runtime script creates a gameplay Omni light: %s" % script_path)
		assert_bool(not source.contains("SpotLight3D.new(")).is_true() \
			.override_failure_message("Enemy runtime script creates a gameplay Spot light: %s" % script_path)
		assert_int(source.count("DirectionalLight3D.new(")) \
			.override_failure_message("Enemy runtime script creates gameplay lights: %s" % script_path) \
			.is_less_equal(1)
		if source.contains("DirectionalLight3D.new("):
			# 唯一允许的光源必须位于 imposter 贴图捕获路径（离屏渲染，不影响玩法光照）。
			assert_bool(source.contains("_build_imposter_texture")) \
				.override_failure_message("Enemy 光源必须限于 imposter 捕获视口: %s" % script_path).is_true()


func test_pickable_runtime_has_no_presence_light_contract() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/equipment/pickable_item.gd")
	assert_bool(source.contains("presence_light")).is_false() \
		.override_failure_message("Ordinary pickables still depend on a PresenceLight node")
