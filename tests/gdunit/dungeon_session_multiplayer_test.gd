extends GdUnitTestSuite
## 联机垂直切片（单进程 headless）：把【真实地牢入口】dungeon_session_controller 与
## 【网络层】NetworkManager 串起来，证明“游戏世界 → 联机复制”这条 seam 真实可用：
##   ① host 用 seed 生成真实地牢并 spawn_server_entities → 敌人注册进权威 SessionRoot 且广播 entity_spawned
##   ② 不同 seed → 不同 layout（seed 接线 #17）
##   ③ 生成的实体出现在 build_session_snapshot 中（重连/晚到客户端据此追平，闭环 Phase10 桥接收敛）
## 仅依赖 autoload NetworkManager（headless 下 multiplayer peer 为 null，事件走 event_dispatched 不被 RPC 卡住）。

const DSC := preload("res://scenes/multiplayer/dungeon_session_controller.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

var _captured: Array = []

func _capture(e: Dictionary) -> void:
	_captured.append(e)

func before() -> void:
	# 每用例重置 autoload 的权威会话，避免跨用例实体污染。
	if NetworkManager.session != null and is_instance_valid(NetworkManager.session):
		NetworkManager.session.free()
	NetworkManager.session = null
	NetworkManager._ensure_session()
	NetworkManager.session.init_server()
	NetworkManager.is_host = true
	_captured.clear()
	if not NetworkManager.event_dispatched.is_connected(_capture):
		NetworkManager.event_dispatched.connect(_capture)

func after() -> void:
	if NetworkManager.event_dispatched.is_connected(_capture):
		NetworkManager.event_dispatched.disconnect(_capture)

## host 生成真实地牢 + 服务器权威生成本地实体 → 注册进 SessionRoot 并广播 entity_spawned。
func test_host_builds_dungeon_and_spawns_networked_entities() -> void:
	var ctrl := DSC.new()
	NetworkManager.add_child(ctrl)
	ctrl.build_authority_only(12345)
	var ids: Array = ctrl.spawn_server_entities()
	assert_int(ids.size()).is_equal(2)  # 1001 Rat / 1002 Skeleton
	# 实体进入权威 SessionRoot（而非仅本地场景）。
	assert_bool(NetworkManager.session.get_entity(1001).is_empty()).is_false()
	assert_bool(NetworkManager.session.get_entity(1002).is_empty()).is_false()
	# 广播了 entity_spawned 事件（两端桥接层据此生成可见节点）。
	var spawned := 0
	for e in _captured:
		if e.get("event", "") == NP.EVT_ENTITY_SPAWNED:
			spawned += 1
	assert_int(spawned).is_equal(2)
	ctrl.free()

## 不同 seed → 不同 layout 指纹（地牢 seed 真实接线 #17）。
func test_different_seeds_produce_different_layouts() -> void:
	var a := DSC.new()
	NetworkManager.add_child(a)
	a.build_authority_only(111)
	var fa := a.layout_fingerprint()
	a.free()
	var b := DSC.new()
	NetworkManager.add_child(b)
	b.build_authority_only(222)
	var fb := b.layout_fingerprint()
	b.free()
	assert_str(fa).is_not_equal(fb)
	assert_str(fa).is_not_equal("none")

## 生成的实体出现在 build_session_snapshot 中（重连/晚到客户端据此追平 → 桥接层收敛 despawn 陈旧）。
func test_session_snapshot_includes_spawned_entities() -> void:
	var ctrl := DSC.new()
	NetworkManager.add_child(ctrl)
	ctrl.build_authority_only(999)
	ctrl.spawn_server_entities()
	var snap: Dictionary = NetworkManager.session.build_session_snapshot()
	assert_bool(snap.has("entities")).is_true()
	assert_bool(snap["entities"].has(1001)).is_true()
	assert_bool(snap["entities"].has(1002)).is_true()
	ctrl.free()
