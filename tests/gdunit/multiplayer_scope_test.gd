extends GdUnitTestSuite

const PROTOCOL_PATH := "res://globals/multiplayer/network_protocol.gd"
const SESSION_PATH := "res://globals/multiplayer/session_root.gd"
const NETWORK_MANAGER_PATH := "res://globals/core/network_manager.gd"
const DOC_PATH := "res://docs/25-联机总体方案.md"

func test_multiplayer_protocol_contains_only_dungeon_scope_commands() -> void:
	var source := FileAccess.get_file_as_string(PROTOCOL_PATH)
	assert_bool(source.contains("CMD_INPUT")).is_true()
	assert_bool(source.contains("CMD_ATTACK")).is_true()
	assert_bool(source.contains("CMD_EXTRACT")).is_true()
	assert_bool(source.contains("CMD_BREW")).is_false()
	assert_bool(source.contains("CMD_UPGRADE")).is_false()
	assert_bool(source.contains("TAVERN_STATE_CHANGED")).is_false()

func test_session_root_does_not_wire_tavern_authority() -> void:
	var source := FileAccess.get_file_as_string(SESSION_PATH)
	assert_bool(source.contains("TavernAuthority")).is_false()
	assert_bool(source.contains("tavern_auth")).is_false()
	assert_bool(source.contains("CMD_BREW")).is_false()

func test_network_manager_scope_is_dungeon_only() -> void:
	var source := FileAccess.get_file_as_string(NETWORK_MANAGER_PATH)
	assert_bool(source.contains("tavern")).is_false()
	assert_bool(source.contains("brewing")).is_false()

func test_scope_document_explicitly_excludes_tavern() -> void:
	var source := FileAccess.get_file_as_string(DOC_PATH)
	assert_bool(source.contains("多人范围硬约束")).is_true()
	assert_bool(source.contains("酒馆场景、酿造、发酵、升级")).is_true()