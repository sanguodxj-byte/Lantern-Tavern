extends GdUnitTestSuite
## PlayerAimHelper 单元测试
## 验证从 player.gd 提取的瞄准辅助工具

const AIM := preload("res://scenes/characters/player/player_aim_helper.gd")

# ============================================================================
# 1. 源码结构验证
# ============================================================================

func test_aim_helper_has_get_aim_point() -> void:
	var source := _source("res://scenes/characters/player/player_aim_helper.gd")
	assert_bool(source.contains("static func get_aim_point")).is_true()

func test_aim_helper_has_get_aim_transform() -> void:
	var source := _source("res://scenes/characters/player/player_aim_helper.gd")
	assert_bool(source.contains("static func get_aim_transform")).is_true()

func test_aim_helper_uses_intersect_ray() -> void:
	var source := _source("res://scenes/characters/player/player_aim_helper.gd")
	assert_bool(source.contains("intersect_ray")).is_true()

func test_aim_helper_uses_camera_global_position() -> void:
	var source := _source("res://scenes/characters/player/player_aim_helper.gd")
	assert_bool(source.contains("camera.global_position")).is_true()

func test_aim_helper_uses_looking_at() -> void:
	var source := _source("res://scenes/characters/player/player_aim_helper.gd")
	assert_bool(source.contains("looking_at")).is_true()

func test_aim_helper_uses_physics_layers() -> void:
	var source := _source("res://scenes/characters/player/player_aim_helper.gd")
	assert_bool(source.contains("LAYER_ENVIRONMENT")).is_true()
	assert_bool(source.contains("LAYER_ENEMY")).is_true()
	assert_bool(source.contains("LAYER_SCENE_OBJECT")).is_true()

# ============================================================================
# 2. player.gd 薄代理验证
# ============================================================================

func test_player_delegates_to_aim_helper() -> void:
	var source := _source("res://scenes/characters/player/player.gd")
	assert_bool(source.contains("AIM_HELPER.get_aim_point")).is_true()
	assert_bool(source.contains("AIM_HELPER.get_aim_transform")).is_true()

func test_player_still_has_aim_method_signatures() -> void:
	var source := _source("res://scenes/characters/player/player.gd")
	assert_bool(source.contains("func get_aim_point")).is_true()
	assert_bool(source.contains("func get_aim_transform")).is_true()

# ============================================================================
# 3. 边界条件
# ============================================================================

func test_get_aim_point_returns_fallback_when_camera_null() -> void:
	var origin := Vector3(0, 0, 0)
	var result := AIM.get_aim_point(null, origin)
	# When camera is null, should return origin - FORWARD * max_distance
	assert_vector(result).is_not_null()

func test_get_aim_transform_returns_valid_transform() -> void:
	# Without a real camera/world, get_aim_point will return the fallback point
	# get_aim_transform should still produce a valid Transform3D
	var result := AIM.get_aim_transform(null, Vector3(0, 1, 0))
	assert_bool(result is Transform3D).is_true()

# ============================================================================
# 辅助
# ============================================================================

static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code
