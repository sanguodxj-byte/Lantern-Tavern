extends GdUnitTestSuite
## Listen/Dedicated 出征装配契约测试（1417 审查 P1-1 落实）。
## 两种宿主（listen-server 完整地牢 / dedicated 权威碰撞-only）共用
## DungeonSessionController 生成管线：相同 seed 必须产出相同 layout fingerprint
## 与玩家出生点——保证服务器碰撞世界/实体与客户端广播布局一致。

const CONTROLLER := "res://scenes/multiplayer/dungeon_session_controller.gd"

func test_authority_and_listen_assembly_share_layout() -> void:
	var ctl: Node = load(CONTROLLER).new()
	add_child(ctl)
	ctl.build_authority_collision_only(12345)
	var auth_fp: String = ctl.layout_fingerprint()
	var auth_spawn: Vector3 = ctl._player_spawn_pos
	assert_str(auth_fp).is_not_equal("none")
	ctl.free()

	var ctl2: Node = load(CONTROLLER).new()
	add_child(ctl2)
	ctl2.build_and_enter(12345)
	var listen_fp: String = ctl2.layout_fingerprint()
	var listen_spawn: Vector3 = ctl2._player_spawn_pos
	# 相同 seed → 相同 fingerprint（跨进程/跨模式确定性）
	assert_str(auth_fp).is_equal(listen_fp) \
		.override_failure_message("P1-1：authority-only 与 listen 装配必须产出同一布局指纹")
	assert_float(auth_spawn.x).is_equal_approx(listen_spawn.x, 0.001)
	assert_float(auth_spawn.z).is_equal_approx(listen_spawn.z, 0.001)
	# 清理：释放本地 Player 与 controller；Player._ready 有 deferred 挂载节点，
	# 等待多帧让 pending 队列清空（防 orphan）。
	if ctl2.local_player != null and is_instance_valid(ctl2.local_player):
		ctl2.local_player.free()
	ctl2.free()
	for i in range(3):
		await await_idle_frame()

func test_assembly_deterministic_across_seeds() -> void:
	# 不同 seed 必须产出不同指纹（防止"恒同布局"假一致）
	var ctl: Node = load(CONTROLLER).new()
	add_child(ctl)
	ctl.build_authority_collision_only(111)
	var fp1: String = ctl.layout_fingerprint()
	ctl.free()
	var ctl2: Node = load(CONTROLLER).new()
	add_child(ctl2)
	ctl2.build_authority_collision_only(222)
	var fp2: String = ctl2.layout_fingerprint()
	ctl2.free()
	assert_bool(fp1 != fp2).is_true() \
		.override_failure_message("P1-1：不同 seed 必须产出不同布局指纹")
