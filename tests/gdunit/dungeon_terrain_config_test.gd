extends GdUnitTestSuite
## DungeonTerrainConfig 测试。
## 验证地形纹理图集配置和 ShaderMaterial 构建。

const TERRAIN_CFG := preload("res://scenes/expedition/dungeon_terrain_config.gd")

func test_tile_layout_has_required_keys() -> void:
	var required := ["WALL", "FLOOR", "CEILING", "LINTEL", "PILLAR", "DOOR", "BOSS_DOOR", "PORTAL"]
	for key in required:
		assert_bool(TERRAIN_CFG.TILE_LAYOUT.has(key)) \
			.override_failure_message("TILE_LAYOUT 缺少键: %s" % key).is_true()

func test_tile_spans_matches_tile_layout_keys() -> void:
	for key in TERRAIN_CFG.TILE_LAYOUT.keys():
		assert_bool(TERRAIN_CFG.TILE_SPANS.has(key)) \
			.override_failure_message("TILE_SPANS 缺少 TILE_LAYOUT 的键: %s" % key).is_true()

func test_tile_atlas_grid_is_8x4() -> void:
	assert_bool(TERRAIN_CFG.TILE_ATLAS_GRID == Vector2(8, 4)).is_true()

func test_make_terrain_mat_returns_shader_material() -> void:
	var mat := TERRAIN_CFG.make_terrain_mat("WALL", Vector2(1, 1))
	assert_object(mat).is_not_null()
	assert_object(mat).is_instanceof(ShaderMaterial)

func test_make_terrain_mat_sets_shader() -> void:
	var mat := TERRAIN_CFG.make_terrain_mat("FLOOR", Vector2(2, 2)) as ShaderMaterial
	assert_object(mat.shader).is_not_null()

# ── 黑地形回归防护（根因：make_terrain_mat 曾误设 base_texture/" atlas_offset"/"atlas_size"。
# shader dungeon_terrain.gdshader 的真实 uniform 是 atlas / tile_col_row / tile_span / atlas_grid /
# tile_repeat；若 sampler 未绑定则地形全采样成黑色，墙/地/天花板一片黑。）─────────────
func test_make_terrain_mat_binds_atlas_texture() -> void:
	var mat := TERRAIN_CFG.make_terrain_mat("WALL", Vector2(1, 1)) as ShaderMaterial
	var tex = mat.get_shader_parameter("atlas")
	assert_object(tex) \
		.override_failure_message("atlas sampler 必须绑定纹理，否则地形全黑").is_not_null()
	assert_object(tex).is_equal(TERRAIN_CFG.DUNGEON_TEX)

func test_make_terrain_mat_uses_correct_shader_uniform_names() -> void:
	# 旧错 uniform 名不能再出现（它们不在 shader 里，会静默失效）
	var mat := TERRAIN_CFG.make_terrain_mat("WALL", Vector2(1, 1)) as ShaderMaterial
	assert_object(mat.get_shader_parameter("base_texture")) \
		.override_failure_message("不得使用 base_texture，纹理 sampler 名为 atlas").is_null()
	assert_object(mat.get_shader_parameter(" atlas_offset")) \
		.override_failure_message("不得使用 ' atlas_offset'（带前导空格且 shader 无此 uniform）").is_null()
	assert_object(mat.get_shader_parameter("atlas_size")) \
		.override_failure_message("不得使用 atlas_size（shader 无此 uniform）").is_null()

func test_make_terrain_mat_passes_raw_cell_values() -> void:
	# tile_col_row / tile_span 必须是原始格值（shader 内部才除 atlas_grid），不可预除。
	var wall := TERRAIN_CFG.make_terrain_mat("WALL", Vector2(1, 3)) as ShaderMaterial
	assert_object(wall.get_shader_parameter("tile_col_row")).is_equal(Vector2(0, 0))
	assert_object(wall.get_shader_parameter("tile_span")).is_equal(Vector2(1, 1))
	assert_object(wall.get_shader_parameter("atlas_grid")).is_equal(Vector2(8, 4))
	assert_object(wall.get_shader_parameter("tile_repeat")).is_equal(Vector2(1, 3))
	var floor_mat := TERRAIN_CFG.make_terrain_mat("FLOOR", Vector2(3, 3)) as ShaderMaterial
	assert_object(floor_mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(1, 0))
	var door := TERRAIN_CFG.make_terrain_mat("DOOR", Vector2(1, 2)) as ShaderMaterial
	assert_object(door.get_shader_parameter("tile_col_row")).is_equal(Vector2(7, 1))
	assert_object(door.get_shader_parameter("tile_span")).is_equal(Vector2(1, 2))

func test_make_terrain_mat_unknown_tile_uses_default() -> void:
	# 未知 tile_name 不应崩溃，使用默认 Vector2(0,0)
	var mat := TERRAIN_CFG.make_terrain_mat("NONEXISTENT", Vector2(1, 1))
	assert_object(mat).is_not_null()

func test_ceiling_constants_exist() -> void:
	assert_float(TERRAIN_CFG.CEILING_THICKNESS).is_equal(0.1)
	assert_float(TERRAIN_CFG.CEILING_TRANSITION_GAP).is_equal(0.015)
