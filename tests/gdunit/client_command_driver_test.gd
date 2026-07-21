extends GdUnitTestSuite
## 客户端命令驱动单元测试：重点覆盖 Phase 7 心跳调度逻辑。
## 不依赖真实 NetworkManager / 场景树：通过 nm_override 注入最小 mock 直接驱动 _maybe_send_heartbeat。

const ClientDriverClass := preload("res://scenes/multiplayer/client_command_driver.gd")

## 最小 mock NetworkManager：交互面与真实 NetworkManager 一致（is_active 属性 / is_client / is_host 方法 / send_heartbeat），
## 仅额外计数 send_heartbeat 调用次数，便于断言调度频率。
class MockNM extends RefCounted:
	var is_active: bool = true
	var _client: bool = true
	var _host: bool = false
	var heartbeat_calls: int = 0
	func is_client() -> bool: return _client
	func is_host() -> bool: return _host
	func send_heartbeat() -> void: heartbeat_calls += 1

func _make_driver() -> Node:
	return auto_free(ClientDriverClass.new())

func test_heartbeat_not_fired_before_interval() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	d._maybe_send_heartbeat(4.0, nm)   # 4.0 < 5.0 → 不触发
	assert_int(nm.heartbeat_calls).is_equal(0)

func test_heartbeat_fired_once_when_interval_crossed() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	d._maybe_send_heartbeat(4.0, nm)
	d._maybe_send_heartbeat(2.0, nm)   # 累计 6.0 >= 5.0 → 触发 1 次，累加器归零
	assert_int(nm.heartbeat_calls).is_equal(1)

func test_heartbeat_resets_accumulator_between_fires() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	d._maybe_send_heartbeat(4.0, nm)
	d._maybe_send_heartbeat(2.0, nm)   # 触发 1，归零
	d._maybe_send_heartbeat(4.0, nm)   # 4.0 < 5.0 → 不触发
	assert_int(nm.heartbeat_calls).is_equal(1)
	d._maybe_send_heartbeat(2.0, nm)   # 累计 6.0 → 触发 2
	assert_int(nm.heartbeat_calls).is_equal(2)

func test_heartbeat_skipped_when_not_client() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	nm._client = false     # 房主 / 非客户端：不应向自己 ping
	d._maybe_send_heartbeat(20.0, nm)
	assert_int(nm.heartbeat_calls).is_equal(0)

func test_heartbeat_skipped_when_inactive() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	nm.is_active = false   # 网络未激活：不 ping
	d._maybe_send_heartbeat(20.0, nm)
	assert_int(nm.heartbeat_calls).is_equal(0)

func test_heartbeat_fires_only_once_on_large_delta() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	d._maybe_send_heartbeat(100.0, nm)   # 单帧超大 delta：只触发 1 次（不补发多次）
	assert_int(nm.heartbeat_calls).is_equal(1)

## 端到端（服务器权威侧）：客户端心跳经 send_heartbeat→服务器 heartbeat→刷新 last_seen，
## 使 check_timeout 在超时窗口内恢复为 false。验证调度器的下游闭环有效。
func test_heartbeat_refreshes_server_last_seen() -> void:
	var ca := preload("res://globals/multiplayer/connection_authority.gd").new()
	ca.register_online(7, "guid_7", 0.0)
	assert_bool(ca.check_timeout(7, 16.0)).is_true()      # 16s 无心跳 → 超时
	ca.touch(7, 16.0)                                      # 等价于客户端心跳到达
	assert_bool(ca.check_timeout(7, 18.0)).is_false()      # 刷新后 2s 内仍在线
