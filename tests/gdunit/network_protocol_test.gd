extends GdUnitTestSuite

# NetworkProtocol（docs/25 §12/§19）：版本常量、命令/事件合法性、协议头构造。

const NP := preload("res://globals/multiplayer/network_protocol.gd")

func test_version_constants() -> void:
	assert_int(NP.PROTOCOL_VERSION).is_equal(1)
	assert_int(NP.SAVE_VERSION).is_equal(1)
	assert_int(NP.DUNGEON_LAYOUT_VERSION).is_equal(1)
	assert_int(NP.WEAPON_DATA_VERSION).is_equal(1)

func test_is_valid_command() -> void:
	assert_bool(NP.is_valid_command(NP.CMD_ATTACK)).is_true()
	assert_bool(NP.is_valid_command("not_a_command")).is_false()

func test_is_valid_event() -> void:
	assert_bool(NP.is_valid_event(NP.EVT_COMBAT_RESOLVED)).is_true()
	assert_bool(NP.is_valid_event("not_an_event")).is_false()

func test_make_header() -> void:
	var h = NP.make_header(NP.PROTOCOL_VERSION, 12, 1200, 450)
	assert_int(h["protocol_version"]).is_equal(1)
	assert_int(h["world_revision"]).is_equal(12)
	assert_int(h["client_tick"]).is_equal(1200)
	assert_int(h["sequence"]).is_equal(450)
