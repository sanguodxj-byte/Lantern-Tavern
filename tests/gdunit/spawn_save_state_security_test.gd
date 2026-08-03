extends GdUnitTestSuite

func test_remote_spawn_ignores_client_save_state() -> void:
	var source := (load("res://globals/core/network_manager.gd") as GDScript).source_code
	var section := source.substr(source.find("func rpc_client_spawn"), 900)
	assert_bool(section.contains("_untrusted_save_state")).is_true()
	assert_bool(section.contains("_server_handle_spawn(peer_id, {}, player_guid)")).is_true()
	assert_bool(not section.contains("_server_handle_spawn(peer_id, save_state")).is_true()

func test_client_send_spawn_transmits_no_inventory_payload() -> void:
	var source := (load("res://globals/core/network_manager.gd") as GDScript).source_code
	var section := source.substr(source.find("func send_spawn"), 500)
	assert_bool(section.contains("rpc_client_spawn.rpc_id(HOST_PEER_ID, local_peer_id, {}, player_guid)")).is_true()

func test_host_local_spawn_may_still_supply_trusted_state() -> void:
	var source := (load("res://globals/core/network_manager.gd") as GDScript).source_code
	var section := source.substr(source.find("func spawn_self"), 650)
	assert_bool(section.contains("_server_handle_spawn(local_peer_id, save_state, player_guid)")).is_true()
