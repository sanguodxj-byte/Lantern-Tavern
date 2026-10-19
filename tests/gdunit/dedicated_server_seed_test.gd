extends GdUnitTestSuite
## Dedicated Server 出征行为测试（0304 审查 P0-1）。
## 验证专用服务器正确解包 start_expedition 包裹返回值，服务器权威 seed 与
## dungeon_auth 广播 seed 一致（此前误取包裹层 seed 恒得 0，导致碰撞世界/实体
## 与客户端布局分裂）。

func test_start_expedition_unwraps_seed_matching_dungeon_auth() -> void:
	var nm: Node = Engine.get_main_loop().root.get_node("NetworkManager")
	# 清理可能残留的会话（保证干净服务器态）
	if nm.session != null and is_instance_valid(nm.session):
		nm.session.free()
	nm.session = null
	nm._ensure_session()
	nm.session.init_server()
	# P0-2（2228 审查修复）：隔离存档目录——固定 guid ds_test_guid 的残留存档
	# 会跨运行污染 spawn 恢复（同 reconnect_recovery_test 约定）。
	nm.session.server_save_repo.set_save_dir("user://dedsrv_seed_%d" % Time.get_ticks_usec())
	nm.is_host = true
	nm.local_peer_id = 1
	# 首个玩家 spawn（专用服务器触发出征的条件）
	var ctx = nm.session.handle_spawn_request(1, {}, "ds_test_guid")
	assert_object(ctx).is_not_null()
	# 构造 DedicatedServer 实例（不调 _ready——避免真实 ENet host）
	var ds: Node = load("res://scenes/multiplayer/dedicated_server.gd").new()
	add_child(ds)
	ds._start_expedition()
	# 断言：seed 正确解包（非 0 且与 dungeon_auth 权威 seed 一致）
	assert_int(ds._seed).is_greater(0) \
		.override_failure_message("P0-1：专用服务器必须解包 result.event.seed，不得恒为 0")
	assert_int(ds._seed).is_equal(nm.session.dungeon_auth.seed) \
		.override_failure_message("P0-1：controller seed 必须与 dungeon_auth 广播 seed 一致")
	assert_object(ds._controller).is_not_null()
	assert_bool(ds._expedition_started).is_true()
	# 清理：释放 controller、ds、会话，避免污染后续套件
	if ds._controller != null and is_instance_valid(ds._controller):
		ds._controller.free()
	ds.free()
	if nm.session != null and is_instance_valid(nm.session):
		nm.session.free()
	nm.session = null
