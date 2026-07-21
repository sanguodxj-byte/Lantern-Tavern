extends GdUnitTestSuite

# WorldState（docs/25 §3.2/§9/§13.2）：revision 自增、空间切换、地牢 run 元数据、快照。

const WS := preload("res://globals/multiplayer/world_state.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

var _ws

func before() -> void:
	_ws = auto_free(WS.new())

func test_initial_revision_zero() -> void:
	assert_int(_ws.world_revision).is_equal(0)

func test_bump_revision_increments() -> void:
	var r1 = _ws.bump_revision()
	var r2 = _ws.bump_revision()
	assert_int(r1).is_equal(1)
	assert_int(r2).is_equal(2)

func test_transition_space_returns_new_revision() -> void:
	var r = _ws.transition_space("dungeon")
	assert_str(_ws.current_space).is_equal("dungeon")
	assert_int(r).is_equal(_ws.world_revision)

func test_apply_dungeon_run() -> void:
	_ws.apply_dungeon_run({"run_id": "abc", "run_seed": 18273645, "generation_config_version": 4, "layout_schema_version": 2, "zone_id": "crypt", "difficulty": 2})
	assert_str(_ws.run_id).is_equal("abc")
	assert_int(_ws.run_seed).is_equal(18273645)
	assert_int(_ws.generation_config_version).is_equal(4)
	assert_int(_ws.layout_schema_version).is_equal(2)
	assert_str(_ws.zone_id).is_equal("crypt")
	assert_int(_ws.difficulty).is_equal(2)

func test_session_snapshot_roundtrip() -> void:
	_ws.transition_space("dungeon")
	_ws.apply_dungeon_run({"run_seed": 999, "zone_id": "crypt", "generation_config_version": 4})
	var snap = _ws.build_session_snapshot()
	assert_int(snap["protocol_version"]).is_equal(NP.PROTOCOL_VERSION)
	assert_str(snap["current_space"]).is_equal("dungeon")
	assert_int(snap["run_seed"]).is_equal(999)
	var ws2 = auto_free(WS.new())
	ws2.apply_session_snapshot(snap)
	assert_int(ws2.world_revision).is_equal(_ws.world_revision)
	assert_str(ws2.current_space).is_equal("dungeon")
	assert_int(ws2.run_seed).is_equal(999)
