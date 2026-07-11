extends GdUnitTestSuite

const NETWORK_MANAGER := preload("res://globals/core/network_manager.gd")

func test_host_rejects_invalid_port_without_activation() -> void:
	var manager := NETWORK_MANAGER.new()
	var result := manager.host(0)
	assert_int(result).is_equal(ERR_INVALID_PARAMETER)
	assert_bool(manager.is_active).is_false()
	assert_int(manager.last_error).is_equal(ERR_INVALID_PARAMETER)
	manager.free()

func test_join_rejects_empty_address_without_activation() -> void:
	var manager := NETWORK_MANAGER.new()
	var result := manager.join("   ", 54321)
	assert_int(result).is_equal(ERR_INVALID_PARAMETER)
	assert_bool(manager.is_active).is_false()
	assert_int(manager.last_error).is_equal(ERR_INVALID_PARAMETER)
	manager.free()

func test_connected_peers_are_sorted_and_host_is_registered() -> void:
	var manager := NETWORK_MANAGER.new()
	manager._register_peer(7)
	manager._register_peer(2)
	manager._register_peer(1)
	assert_array(manager.connected_peers()).is_equal([1, 2, 7])
	assert_int(manager.peer_count()).is_equal(3)
	manager.free()

func test_disconnect_clears_session_metadata_and_contexts() -> void:
	var manager := NETWORK_MANAGER.new()
	manager._register_peer(1)
	manager.session_address = "127.0.0.1"
	manager.session_port = 54321
	manager.is_active = true
	manager.is_host = true
	manager.local_peer_id = 1
	manager.disconnect_session()
	assert_bool(manager.is_active).is_false()
	assert_bool(manager.is_host).is_false()
	assert_int(manager.local_peer_id).is_equal(0)
	assert_str(manager.session_address).is_empty()
	assert_int(manager.session_port).is_equal(0)
	assert_int(manager.peer_count()).is_equal(0)
	manager.free()
