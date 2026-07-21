extends GdUnitTestSuite

const DUNGEON_SCENE_PATH := "res://scenes/expedition/procedural_dungeon.tscn"
const DUNGEON_SCRIPT_PATH := "res://scenes/expedition/procedural_dungeon.gd"
const NETWORK_MANAGER_PATH := "res://globals/core/network_manager.gd"
const SERVICE_PATH := "res://globals/core/service.gd"

func test_dungeon_scene_mounts_multiplayer_scene_bridge() -> void:
	var scene_text := FileAccess.get_file_as_string(DUNGEON_SCENE_PATH)
	assert_bool(scene_text.contains("multiplayer_scene_bridge.tscn")).is_true()
	assert_bool(scene_text.contains("MultiplayerSceneBridge")).is_true()

func test_dungeon_process_advances_network_session_clock() -> void:
	var script_text := FileAccess.get_file_as_string(DUNGEON_SCRIPT_PATH)
	assert_bool(script_text.contains("Service.network_manager()")).is_true()
	assert_bool(script_text.contains("network_manager.tick(delta)")).is_true()

func test_client_commands_wait_for_handshake_peer_id() -> void:
	var script_text := FileAccess.get_file_as_string(NETWORK_MANAGER_PATH)
	assert_bool(script_text.contains("func send_spawn(save_state: Dictionary, player_guid: String) -> void:")).is_true()
	assert_bool(script_text.contains("local_peer_id <= 0")).is_true()
	assert_bool(script_text.contains("local_peer_id <= 0 or reconnect_token == \"\"")).is_true()

func test_service_exposes_network_manager_accessor() -> void:
	var service_text := FileAccess.get_file_as_string(SERVICE_PATH)
	assert_bool(service_text.contains("static func network_manager() -> Node:")).is_true()