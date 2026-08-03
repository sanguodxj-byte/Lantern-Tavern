extends GdUnitTestSuite

func test_dungeon_environment_uses_cool_midtones_and_highlight_headroom() -> void:
	var dungeon := ProceduralDungeon.new()
	var config := dungeon._get_zone_ambient_config(0)
	var ambient_color: Color = config.ambient_color

	assert_float(float(config.light_energy)).is_equal_approx(0.26, 0.001)
	assert_float(float(config.ambient_energy)).is_equal_approx(0.40, 0.001)
	assert_float(ambient_color.r).is_equal_approx(0.14, 0.001)
	assert_float(ambient_color.g).is_equal_approx(0.16, 0.001)
	assert_float(ambient_color.b).is_equal_approx(0.20, 0.001)
	assert_float(ambient_color.b) \
		.override_failure_message("地牢暗部应略偏冷，以抵消暖色火把污染") \
		.is_greater(ambient_color.r)
	assert_float(float(config.fog_density)).is_equal_approx(0.006, 0.001)

	dungeon.dungeon_zone = 0
	dungeon._setup_zone_ambient()
	var world_env := _find_world_environment(dungeon)
	assert_object(world_env).is_not_null()
	assert_float(world_env.environment.tonemap_exposure) \
		.override_failure_message("地牢曝光需保留火焰和浅色道具的高光余量") \
		.is_equal_approx(0.96, 0.001)
	assert_int(world_env.environment.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_COLOR)

	dungeon.free()


func test_all_zones_ambient_darkened_below_old_floor() -> void:
	# 地牢整体环境光调暗回归：所有区域 ambient_energy 必须低于旧值 0.62 的上限，
	# 且主区域（zone 0）相比旧值明显下调（≥30%）。
	var dungeon := ProceduralDungeon.new()
	var zone0_old := 0.62
	for zone in range(0, 6):
		var config := dungeon._get_zone_ambient_config(zone)
		assert_float(float(config.ambient_energy)) \
			.override_failure_message("zone %d 环境光未整体调暗" % zone) \
			.is_less(zone0_old)
	assert_float(float(dungeon._get_zone_ambient_config(0).ambient_energy)) \
		.override_failure_message("zone 0 环境光应较旧值下调至少 30%") \
		.is_less_equal(0.62 * 0.70)
	dungeon.free()

func test_dungeon_terrain_shader_keeps_unlit_walls_readable_without_emission() -> void:
	var shader_source := FileAccess.get_file_as_string("res://assets/shaders/dungeon_terrain.gdshader")
	assert_bool(shader_source.contains("DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, vec3(voxel_base_fill))")) \
		.override_failure_message("地形 shader 必须用非自发光的最低漫反射填充保持墙面可读").is_true()
	assert_bool(shader_source.contains("EMISSION = col.rgb * emission_tint.rgb * emission_strength")) \
		.override_failure_message("地形基础可读性不能改成普通材质自发光").is_true()
	var builder := DungeonSceneBuilder.new()
	var wall_material := builder._make_terrain_mat("WALL", Vector2.ONE)
	assert_float(float(wall_material.get_shader_parameter("voxel_base_fill"))) \
		.override_failure_message("普通墙体最低填充应轻微提高以保留石砖层次").is_equal_approx(0.24, 0.001)

func _find_world_environment(root: Node) -> WorldEnvironment:
	for child in root.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
	return null
