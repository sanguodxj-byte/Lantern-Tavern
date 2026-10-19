extends GdUnitTestSuite

## B2（0644 审查 / 决策 G1-A）：spawn 链路上不再携带任何客户端存档字典——
## 远端客户端只上送 player_guid，服务器按 guid 从 ServerSaveRepository 加载权威存档。
## 本套件以源码断言锁定 wire/签名契约（客户端字典在 spawn 路径已彻底移除，无从伪造）。

func test_remote_spawn_has_no_save_state_param() -> void:
	# B2：rpc_client_spawn 移除 _untrusted_save_state 参数，服务器按 guid 从存档仓加载，
	# 不再调用 _server_handle_spawn(peer_id, {}, player_guid) 的空字典占位路径。
	var source := (load("res://globals/core/network_manager.gd") as GDScript).source_code
	var section := source.substr(source.find("func rpc_client_spawn"), 600)
	assert_bool(section.contains("func rpc_client_spawn(peer_id: int, player_guid: String) -> void:")).is_true()
	assert_bool(not section.contains("_untrusted_save_state")).is_true()
	assert_bool(section.contains("_server_handle_spawn(peer_id, player_guid)")).is_true()
	assert_bool(not section.contains("_server_handle_spawn(peer_id, {}, player_guid)")).is_true()

func test_client_send_spawn_transmits_no_inventory_payload() -> void:
	# B2：send_spawn 只上送 guid；RPC wire 上不再有 {} 存档占位。
	var source := (load("res://globals/core/network_manager.gd") as GDScript).source_code
	var section := source.substr(source.find("func send_spawn"), 500)
	assert_bool(section.contains("rpc_client_spawn.rpc_id(HOST_PEER_ID, local_peer_id, player_guid)")).is_true()
	assert_bool(not section.contains("local_peer_id, {}, player_guid")).is_true()

func test_host_local_spawn_may_still_supply_trusted_state() -> void:
	# 房主本地路径仍可提供单人存档摘要（B2：作为仓无记录时的回退，仓内记录永远优先）。
	var source := (load("res://globals/core/network_manager.gd") as GDScript).source_code
	var section := source.substr(source.find("func spawn_self"), 650)
	assert_bool(section.contains("_server_handle_spawn(local_peer_id, player_guid, save_state)")).is_true()
