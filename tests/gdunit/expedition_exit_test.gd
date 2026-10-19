extends GdUnitTestSuite
## 联机撤离出口测试（0304 审查 P0-2）。
## 验证 dungeon_session_controller 的撤离提交走注入/本地驱动（CMD_EXTRACT），
## 结算完成事件幂等发出一次——不本地直算 GameState/TavernManager。
## 服务器侧幂等结算事务已由 session_root_test 覆盖。

const CONTROLLER := "res://scenes/multiplayer/dungeon_session_controller.gd"

var _exit_emissions: int = 0

func _on_exit_emitted(_settlement) -> void:
	_exit_emissions += 1

class StubDriver:
	extends Node
	var called := false
	func send_extract() -> void:
		called = true

func test_request_extraction_submits_via_injected_driver() -> void:
	var ctl: Node = load(CONTROLLER).new()
	add_child(ctl)
	var stub := StubDriver.new()
	add_child(stub)
	ctl.extraction_driver = stub
	assert_bool(ctl.request_extraction()).is_true()
	assert_bool(stub.called).is_true()
	ctl.free()

func test_request_extraction_returns_false_without_driver() -> void:
	var ctl: Node = load(CONTROLLER).new()
	add_child(ctl)
	# 无注入驱动、无本地 Player → 无法提交
	assert_bool(ctl.request_extraction()).is_false()
	ctl.free()

func test_request_extraction_resolves_local_player_driver() -> void:
	var ctl: Node = load(CONTROLLER).new()
	add_child(ctl)
	var player := Node.new()
	player.name = "LocalPlayer"
	add_child(player)
	var stub := StubDriver.new()
	stub.name = "ClientCommandDriver"
	player.add_child(stub)
	ctl.local_player = player
	assert_bool(ctl.request_extraction()).is_true()
	assert_bool(stub.called).is_true()
	ctl.free()

func test_extraction_completed_emitted_once() -> void:
	var ctl: Node = load(CONTROLLER).new()
	add_child(ctl)
	_exit_emissions = 0
	ctl.extraction_completed.connect(_on_exit_emitted)
	var settlement := {"materials": {"goblin_tooth": 2}}
	ctl.notify_extraction_applied(settlement)
	ctl.notify_extraction_applied(settlement)  # 重放：不得重复发出
	assert_int(_exit_emissions).is_equal(1)
	assert_bool(ctl.is_extraction_applied()).is_true()
	ctl.free()

## P0-2（0643 审查）：生产撤离装配测试——从【真实 portal 信号】一路断言到
## CMD_EXTRACT 提交（wire_extraction_portal → request_extraction → driver.send_extract）。
## 禁止只测 controller stub：controller 是真实脚本实例，portal 是真实 prefab 节点，
## 仅网络驱动层注入 stub（expedition_exit_test 既有约定）。
func test_portal_signal_reaches_cmd_extract_via_real_assembly() -> void:
	var ctl: Node = load(CONTROLLER).new()
	add_child(ctl)
	# 注入计数驱动：记录 send_extract（= CMD_EXTRACT 提交）调用次数。
	var stub := CountingDriver.new()
	add_child(stub)
	ctl.extraction_driver = stub
	# 构建真实 dungeon_root + 真实 ExtractionPortal prefab（与 builder 产物同构）。
	var root := Node3D.new()
	root.name = "RealDungeon_1"
	add_child(root)
	ctl.dungeon_root = root
	var portal: Node = load("res://scenes/expedition/extraction_portal.tscn").instantiate()
	root.add_child(portal)
	portal.set_meta("topdown_kind", "extraction")
	# 生产装配：wire 后 portal 信号必须到达权威撤离链。
	assert_bool(ctl.wire_extraction_portal()).is_true()
	assert_bool(portal.extraction_requested.is_connected(ctl._on_portal_extraction_requested)).is_true()
	var player := Node.new()
	root.add_child(player)
	portal.extraction_requested.emit(player)
	assert_int(stub.called_count).is_equal(1)
	# 幂等：重复触发只提交一次（已应用后拦截；wire 本身防重入）。
	portal.extraction_requested.emit(player)
	assert_int(stub.called_count).is_equal(1)
	# 结算应用后 portal 信号不再提交（_extraction_applied 拦截）。
	ctl.notify_extraction_applied({})
	portal.extraction_requested.emit(player)
	assert_int(stub.called_count).is_equal(1)
	ctl.free()

class CountingDriver:
	extends Node
	var called_count := 0
	func send_extract() -> void:
		called_count += 1
