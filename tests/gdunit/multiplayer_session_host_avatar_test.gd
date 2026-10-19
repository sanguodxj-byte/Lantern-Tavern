extends GdUnitTestSuite

# B3（0644 审查）：晚到客户端的房主 avatar 出生位置必须取服务器权威 live_state，
# 而不是硬编码 rpc(1, Vector3.ZERO)。

const MultiplayerSession := preload("res://globals/multiplayer/multiplayer_session.gd")

class MockSession:
	extends Node
	var _live_state: Dictionary = {}


func test_host_avatar_position_from_authoritative_live_state() -> void:
	var session: MockSession = auto_free(MockSession.new())
	session._live_state = {1: {"position": Vector3(10.0, 0.0, 20.0)}}
	var pos := MultiplayerSession._host_avatar_position(session)
	assert_float(pos.x).is_equal(10.0)
	assert_float(pos.z).is_equal(20.0)


func test_host_avatar_position_falls_back_to_origin_when_no_session() -> void:
	var pos := MultiplayerSession._host_avatar_position(null)
	assert_float(pos.x).is_equal(0.0)
	assert_float(pos.z).is_equal(0.0)


func test_host_avatar_position_falls_back_when_peer_missing() -> void:
	var session: MockSession = auto_free(MockSession.new())
	session._live_state = {}  # 无房主状态
	var pos := MultiplayerSession._host_avatar_position(session)
	assert_float(pos.x).is_equal(0.0)


func test_host_avatar_position_falls_back_when_position_missing() -> void:
	var session: MockSession = auto_free(MockSession.new())
	session._live_state = {1: {"alive": true}}
	var pos := MultiplayerSession._host_avatar_position(session)
	assert_float(pos.x).is_equal(0.0)


func test_no_hardcoded_origin_magic_in_spawn_path() -> void:
	# 禁止模式守卫：生产代码不得再出现硬编码 rpc(1, Vector3.ZERO)。
	var source := (load("res://globals/multiplayer/multiplayer_session.gd") as GDScript).source_code
	assert_bool(source.contains("rpc_spawn_avatar.rpc(1, Vector3.ZERO)")).is_false()
