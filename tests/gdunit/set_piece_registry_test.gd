extends GdUnitTestSuite

# P1 验证：SetPieceRoom 资源 + SetPieceRegistry 注册表
# 设计依据：docs/set_piece_room_design.md §4.1（数据模型）/ §4.2（注册表）
#
# 运行（需在允许 Godot 写 user:// 的环境，本会话沙箱拦截了 headless 验证）：
#   Godot --headless --path "D:/123/Lantern Tavern" -s res://tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/set_piece_registry_test.gd

## 直接实例化注册表并加载目录（不依赖 autoload 时序，测试更确定）。
func _make_registry() -> Node:
	load("res://data/set_piece_room.gd")   # 确保 class_name 全局注册（供 as 转换）
	var reg: Node = auto_free(load("res://data/set_piece_registry.gd").new())
	reg._load_all()
	return reg

func test_registry_loads_sample_piece() -> void:
	var reg: Node = _make_registry()
	var all: Array = reg.get_all()
	assert_int(all.size()).is_greater(0)
	var sp: SetPieceRoom = reg.get_set_piece("boss_arena_simple")
	assert_object(sp).is_not_null()
	assert_bool(sp.is_valid()).is_true()

func test_registry_ids_unique() -> void:
	var reg: Node = _make_registry()
	var seen: Dictionary = {}
	for p in reg.get_all():
		assert_bool(seen.has(p.id)).is_false() \
			.override_failure_message("重复 id: %s" % p.id)
		seen[p.id] = true

func test_filter_candidates_by_role() -> void:
	var reg: Node = _make_registry()
	var boss_cands: Array = reg.filter_candidates(0, 100, "boss")
	assert_int(boss_cands.size()).is_greater(0)
	for c in boss_cands:
		var piece := c as SetPieceRoom
		assert_str(piece.required_role).is_equal("boss")

func test_filter_candidates_respects_allowed_zones() -> void:
	var reg: Node = _make_registry()
	# 样板 boss_arena_simple 的 allowed_zones 为空（=所有 zone）
	var any_zone: Array = reg.filter_candidates(3, 100, "")
	assert_int(any_zone.size()).is_greater(0)

func test_is_valid_rejects_empty_pattern() -> void:
	var sp := SetPieceRoom.new()
	sp.id = "bad_empty"
	sp.tile_pattern = []
	assert_bool(sp.is_valid()).is_false()

func test_is_valid_rejects_non_rectangular() -> void:
	var sp := SetPieceRoom.new()
	sp.id = "bad_rect"
	sp.tile_pattern = [[2, 2, 2], [2, 1]]   # 行宽不等
	assert_bool(sp.is_valid()).is_false()

func test_is_valid_rejects_open_border() -> void:
	var sp := SetPieceRoom.new()
	sp.id = "bad_border"
	sp.tile_pattern = [
		[2, 2, 1, 2, 2, 2, 2, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 2, 2, 2, 2, 2, 2, 2],
	]
	assert_bool(sp.is_valid()).is_false()

func test_is_valid_rejects_out_of_bounds_anchor() -> void:
	var sp := SetPieceRoom.new()
	sp.id = "bad_anchor"
	sp.tile_pattern = [
		[2, 2, 2, 2, 2, 2, 2, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 2, 2, 2, 2, 2, 2, 2],
	]
	sp.door_anchors = [{"edge": "N", "cell": Vector2i(9, 0), "dir": Vector2i(0, -1)}]  # x=9 越界
	assert_bool(sp.is_valid()).is_false()

func test_is_valid_accepts_valid_pattern() -> void:
	var sp := SetPieceRoom.new()
	sp.id = "ok"
	sp.tile_pattern = [
		[2, 2, 2, 2, 2, 2, 2, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 2, 2, 2, 2, 2, 2, 2],
	]
	sp.door_anchors = [{"edge": "N", "cell": Vector2i(3, 0), "dir": Vector2i(0, -1)}]
	assert_bool(sp.is_valid()).is_true()

func test_macro_footprint_derives_from_pattern() -> void:
	var sp := SetPieceRoom.new()
	sp.tile_pattern = [
		[2, 2, 2, 2, 2, 2, 2, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 1, 1, 1, 1, 1, 1, 2],
		[2, 2, 2, 2, 2, 2, 2, 2],
	]
	var fp: Vector2i = sp.macro_footprint(8)
	assert_int(fp.x).is_equal(1)
	assert_int(fp.y).is_equal(1)
