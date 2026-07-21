extends GdUnitTestSuite
## MultiplayerSceneBridge 专项测试（headless 纯逻辑）：
## 覆盖 Phase 10 优化点 —— 重连/晚到会话快照的【收敛】(despawn 陈旧 + spawn 新增)，
## 以及正常游戏期 entity 事件路由、幂等不受影响。

const Bridge := preload("res://globals/multiplayer/multiplayer_scene_bridge.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

## 构造一个脱离场景树/autoload 的桥接层实例（手动 _ready 初始化）。
func _make_bridge() -> Node:
	var b = Bridge.new()
	var ra = Node3D.new()
	ra.name = "RemoteAvatars"
	b.add_child(ra)
	b._ready()  # 手动初始化（纯逻辑单测无 autoload / 无场景树）
	return b

## 核心回归：重连客户端 _entities 含服务器已不存在的陈旧实体(99)，
## 应用权威会话快照后应被 despawn，且新增实体(3)应被 spawn，无幽灵节点残留。
func test_session_snapshot_converges_despawn_stale() -> void:
	var b = _make_bridge()
	b._spawn_entity_local(1, {"kind": "enemy", "label": "Rat"})
	b._spawn_entity_local(2, {"kind": "chest", "label": "chest"})
	b._spawn_entity_local(99, {"kind": "enemy", "label": "Ghost"})  # 断线期间被击杀
	assert_int(b.entity_count()).is_equal(3)
	var snap = {"entities": {
		1: {"kind": "enemy", "label": "Rat", "current_life": 5},
		2: {"kind": "chest", "label": "chest"},
		3: {"kind": "loot", "label": "iron_ore"},
	}}
	b._apply_session_snapshot(snap)
	assert_int(b.entity_count()).is_equal(3)
	assert_object(b.get_entity_node(99)).is_null()      # 陈旧幽灵已清理
	assert_object(b.get_entity_node(3)).is_not_null()   # 新增实体已生成
	assert_object(b.get_entity_node(1)).is_not_null()
	assert_object(b.get_entity_node(2)).is_not_null()

## 晚到客户端 _entities 为空 → 全量 spawn，不误杀任何本地实体（无 ghost 可清）。
func test_session_snapshot_fresh_late_join_no_despawn() -> void:
	var b = _make_bridge()
	var snap = {"entities": {1: {"kind": "enemy"}, 2: {"kind": "chest"}}}
	b._apply_session_snapshot(snap)
	assert_int(b.entity_count()).is_equal(2)
	assert_object(b.get_entity_node(1)).is_not_null()
	assert_object(b.get_entity_node(2)).is_not_null()

## 正常游戏期：entity_spawned/snapshot/despawned 经 _on_event 走幂等路径，不受收敛改动影响。
func test_entity_event_routing_spawn_update_despawn() -> void:
	var b = _make_bridge()
	b._on_event({"event": NP.EVT_ENTITY_SPAWNED, "entity_id": 7, "data": {"kind": "enemy"}})
	assert_int(b.entity_count()).is_equal(1)
	b._on_event({"event": NP.EVT_ENTITY_SNAPSHOT, "entity_id": 7, "data": {"current_life": 3}})
	b._on_event({"event": NP.EVT_ENTITY_DESPAWNED, "entity_id": 7})
	assert_int(b.entity_count()).is_equal(0)

## 收敛不破坏幂等：重复应用同一快照不产生重复节点、不丢实体。
func test_session_snapshot_idempotent_reapply() -> void:
	var b = _make_bridge()
	var snap = {"entities": {1: {"kind": "enemy"}, 2: {"kind": "chest"}}}
	b._apply_session_snapshot(snap)
	b._apply_session_snapshot(snap)
	assert_int(b.entity_count()).is_equal(2)
