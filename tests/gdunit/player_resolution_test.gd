extends GdUnitTestSuite

## GameState.resolve_player_node（P1-5）—— 单玩家全局引用的统一解析入口。
## 地牢压力/撤离/交互/敌人目标一律经此取玩家节点：peer_id=0 → 单机全局 current_player；
## peer_id>0 且联机会话已注入解析器 → 按 peer 解析；解析失败回退全局。

func _gs() -> Node:
	return get_node_or_null("/root/GameState")

func test_default_resolution_returns_current_player() -> void:
	var gs := _gs()
	assert_object(gs).is_not_null()
	# 测试环境无玩家注册 → 安全回退 null（不崩溃、不误伤）。
	assert_object(gs.resolve_player_node(0)).is_null()

func test_peer_resolution_uses_injected_resolver() -> void:
	var gs := _gs()
	var fake := Node3D.new()
	fake.name = "ResolverFake"
	add_child(fake)
	var previous: Callable = gs.player_resolver
	gs.player_resolver = func(pid: int) -> Node:
		return fake if pid == 7 else null
	# 命中 peer → 返回注册表解析节点（联机 per-peer 路径）。
	assert_object(gs.resolve_player_node(7)).is_equal(fake)
	# 未知 peer → 回退全局（null）。
	assert_object(gs.resolve_player_node(8)).is_null()
	gs.player_resolver = previous
	fake.queue_free()

func test_peer_resolution_falls_back_when_resolver_returns_invalid() -> void:
	var gs := _gs()
	var previous: Callable = gs.player_resolver
	gs.player_resolver = func(pid: int) -> Node:
		return null
	# 解析器存在但返回 null → 回退单机全局（current_player 为 null → null）。
	assert_object(gs.resolve_player_node(3)).is_null()
	gs.player_resolver = previous

func test_peer_zero_never_calls_resolver() -> void:
	var gs := _gs()
	var called := {"n": 0}
	var previous: Callable = gs.player_resolver
	gs.player_resolver = func(pid: int) -> Node:
		called["n"] += 1
		return null
	gs.resolve_player_node(0)
	assert_int(called["n"]).is_equal(0)
	gs.player_resolver = previous

func test_peer_resolution_returns_invalid_peer_node_ignored() -> void:
	# 解析器返回已释放/无效节点 → 不采用，回退全局。
	var gs := _gs()
	var stale := Node3D.new()
	var stale_id := stale.get_instance_id()
	stale.free()
	var previous: Callable = gs.player_resolver
	gs.player_resolver = func(pid: int) -> Node:
		return instance_from_id(stale_id) if pid == 5 else null
	assert_object(gs.resolve_player_node(5)).is_null()
	gs.player_resolver = previous
