extends GdUnitTestSuite

## enemy._resolve_target_player（P1-5）—— 敌人目标玩家唯一解析优先级：
## 已登记交战玩家 player → 会话注册表（player_peer_id 锚定）→ 生成器候选 player_ref → 单机全局。
## 替代旧的多处裸读 GameState.current_player（联机下可能默认落到房主/单机玩家）。

const EnemyScript := preload("res://scenes/characters/enemies/enemy.gd")

func test_prefers_registered_player() -> void:
	var e = EnemyScript.new()
	var engaged := Player.new()
	var other := Player.new()
	e.player = engaged
	assert_object(e._resolve_target_player()).is_equal(engaged)
	assert_object(e._resolve_target_player()).is_not_equal(other)
	e.free()
	engaged.free()
	other.free()

func test_falls_back_to_player_ref_meta() -> void:
	var e = EnemyScript.new()
	var ref := Player.new()
	e.set_meta("player_ref", ref)
	assert_object(e._resolve_target_player()).is_equal(ref)
	e.free()
	ref.free()

func test_uses_peer_resolver_when_peer_meta_set() -> void:
	# 联机 per-peer 路径：player_peer_id 命中会话注册表 → 返回该 peer 玩家节点。
	var e = EnemyScript.new()
	var gs: Node = get_node_or_null("/root/GameState")
	var peer := Player.new()
	var previous: Callable = gs.player_resolver
	gs.player_resolver = func(pid: int) -> Node:
		return peer if pid == 42 else null
	e.set_meta("player_peer_id", 42)
	assert_object(e._resolve_target_player()).is_equal(peer)
	# 未知 peer → 回退 player_ref / 全局。
	var e2 = EnemyScript.new()
	e2.set_meta("player_peer_id", 99)
	assert_object(e2._resolve_target_player()).is_null()
	gs.player_resolver = previous
	e.free()
	e2.free()
	peer.free()

func test_null_safe_without_any_source() -> void:
	var e = EnemyScript.new()
	assert_object(e._resolve_target_player()).is_null()
	e.free()

func test_does_not_crash_without_scene_tree() -> void:
	# 回归：helper 不依赖 _ready/@onready（headless 无场景树可安全调用）。
	var e = EnemyScript.new()
	var resolved: Node = e._resolve_target_player()
	assert_object(resolved).is_null()
	e.free()
