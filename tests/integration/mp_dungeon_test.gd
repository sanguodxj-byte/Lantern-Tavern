extends Node3D
## 双进程集成测试（真实地牢 + 真实 Player + 服务器权威移动同步垂直切片）。
## Host 与 Client 加载同一场景，靠 ITEST_ROLE 区分。
##
## 验证范围（用户定义的最关键垂直切片第一步）：
##   1. Host 启动 → Client Join → Client Spawn（含重连 token）
##   2. 双方用同一服务器 seed 确定性重建【真实】地牢（layout 指纹一致）
##   3. 双方各生成【真实 Player】（完整控制器）
##   4. Client 输入 → CMD_INPUT → MovementAuthority 服务器积分权威位置
##   5. 服务器下发 player_snapshot → 客户端本地 Player 被服务器驱动移动
##   6. 远端 avatar（桥接层 RPC）也收到快照并移动（Host 看 Client / Client 看 Host）
##
## 不依赖纯逻辑 headless 测试；本测试驱动真实场景节点 + 真实 RPC + 真实移动权威。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const NetworkManagerClass := preload("res://globals/core/network_manager.gd")
const DungeonSessionController := preload("res://scenes/multiplayer/dungeon_session_controller.gd")

const CANDIDATE_PORTS := [28999, 29001, 29234, 29567, 14567]
const ROLE_HOST := "host"
const ROLE_CLIENT := "client"
const ROLE_CLIENT2 := "client2"
const MOVE_THRESHOLD := 0.5

var _role: String = ""
var _itdir: String = ""
var _bridge: Node = null
var _controller: Node = null
var _local_player: Node = null
var _driver: Node = null
var _seed: int = 0
var _host_peer: int = 1
## 客户端战斗阶段开关：置真后每帧向敌人 1001 发起攻击（驱动内部有冷却）。
var _do_attack: bool = false
## 客户端掉落拾取阶段开关：置真后冻结移动（停在击杀点附近），扫描并拾取身边掉落物。
var _do_loot: bool = false
const TARGET_ENEMY := 1001
const OTHER_ENEMY := 1002

func _ready() -> void:
	_role = OS.get_environment("ITEST_ROLE")
	_itdir = OS.get_environment("ITEST_DIR")
	if _itdir == "":
		_itdir = "D:/123/Lantern Tavern/.tmp_itest_dungeon"
	_bridge = get_node_or_null("MultiplayerSceneBridge")
	if _bridge == null:
		var b: Node = preload("res://globals/multiplayer/multiplayer_scene_bridge.tscn").instantiate()
		b.name = "MultiplayerSceneBridge"
		add_child(b)
		_bridge = b
	if _role == ROLE_HOST:
		_run_host()
	elif _role == ROLE_CLIENT2:
		_run_client2()
	else:
		_run_client()

# ---------------------------------------------------------------------------
# 每帧推进：房主调用 NetworkManager.tick 推进服务器时钟 + 断线清理。
# 同时把自动化输入（override_move）注入本地 driver，驱动服务器积分移动。
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _role == ROLE_HOST:
		var nm: Node = get_node_or_null("/root/NetworkManager")
		if nm != null and nm.is_host:
			nm.tick(delta)
	_inject_input()

func _inject_input() -> void:
	if _driver != null and is_instance_valid(_driver) and _local_player != null:
		if _do_loot:
			_driver.override_move = Vector2.ZERO  # 冻结移动，停在击杀点附近以拾取身边掉落
			return
		# 战斗阶段：朝目标敌人移动并在攻击距离内停步挥砍（避免穿模冲过敌人导致射程校验失败）；
		# 之后持续攻击（驱动内部冷却限流）。真实玩家亦会停在敌前攻击而非一路穿过。
		if _do_attack and _role == ROLE_CLIENT:
			var t: Node3D = _bridge.get_entity_node(TARGET_ENEMY) if _bridge != null else null
			if t != null:
				var to: Vector3 = t.target_position - _local_player.global_position
				var flat: Vector3 = Vector3(to.x, 0.0, to.z)
				var dist: float = flat.length()
				if dist > 1.5:
					_driver.override_move = Vector2(flat.x, flat.z).normalized()
				else:
					_driver.override_move = Vector2.ZERO  # 进入攻击距离：停步挥砍
			else:
				_driver.override_move = Vector2(1.0, 0.0)  # 敌人尚未出现，先向 +X 接近
			if _driver.has_method("send_attack"):
				_driver.send_attack(TARGET_ENEMY)
			return
		_driver.override_move = Vector2(1.0, 0.0)  # 持续向 +X 移动（断言 2+3 用）

# ---------------------------------------------------------------------------
# Host
# ---------------------------------------------------------------------------
func _run_host() -> void:
	var bound := false
	for p in CANDIDATE_PORTS:
		var err := NetworkManager.host(p)
		if err == OK:
			_write("server_port.txt", str(p))
			bound = true
			break
		else:
			_write("host_fail_%d.txt" % p, "host err %d" % err)
	if not bound:
		_write("host_fail.txt", "all candidate ports failed")
		return
	_write("server_ready.txt", "ready")
	# 房主自身也是玩家：建立本地 PlayerContext（peer 1）。
	NetworkManager.spawn_self({}, "host_guid_001")
	# 开启出征：服务器选 seed 并广播 dungeon_layout（此时客户端尚未连接，会漏收，
	# 故在 _on_host_peer_authorized 中对新连接的客户端重播 layout）。
	var layout_evt: Dictionary = NetworkManager.start_expedition()
	_seed = int(layout_evt.get("seed", 0))
	# 房主用该 seed 构建真实本地地牢 + 真实 Player。
	_controller = DungeonSessionController.new()
	_controller.name = "DungeonSession"
	add_child(_controller)
	_local_player = _controller.build_and_enter(_seed)
	_driver = _local_player.get_node_or_null("ClientCommandDriver")
	# 服务器权威放置敌人实体（经桥接层复制到两端）。
	var ent_ids: Array = _controller.spawn_server_entities()
	_write("host_entities.txt", str(ent_ids.size()))
	_write("host_seed.txt", "%d|%s" % [_seed, _controller.layout_fingerprint()])
	_write("server_ok.txt", "OK seed=%d entities=%d" % [_seed, ent_ids.size()])
	# 监听客户端接入：重播 dungeon_layout，确保晚到的客户端拿到 seed。
	NetworkManager.peer_authorized.connect(_on_host_peer_authorized)

func _on_host_peer_authorized(peer_id: int, _ctx) -> void:
	print("[HOST] peer_authorized peer=", peer_id, " local=", NetworkManager.local_peer_id)
	# 对每个接入的客户端重播当前 dungeon_layout（含权威 seed），客户端据此重建地牢。
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm != null and nm.session != null and nm.session.dungeon_auth != null:
		nm._dispatch_event(nm.session.dungeon_auth.make_layout_event(), 0)
	# 向新客户端重播全部权威实体（敌人），使其在本地生成可见节点。
	if nm != null and nm.has_method("rebroadcast_entities"):
		nm.rebroadcast_entities()
	# 给新客户端一个【服务器自身(peer 1)】的远端 avatar，使其能看到房主移动
	# （bridge 自身不会对本地 peer 1 广播，须显式下发，见 avatar 集成测试同款做法）。
	if _bridge != null and _bridge.has_method("rpc_spawn_avatar"):
		_bridge.rpc_spawn_avatar.rpc(1, Vector3.ZERO)
	# 向新客户端【定向、可靠】下发完整会话快照（实体全集 + 全部玩家 avatar + 地牢），
	# 替代仅靠广播重播的竞态路径：晚到/重连客户端据此可靠追平真实场景（实体/avatar 不漏收）。
	if nm != null and nm.session != null and nm.has_method("rpc_server_event"):
		var snap_evt := {"event": NP.EVT_SESSION_SNAPSHOT, "peer_id": peer_id, "snapshot": nm.session.build_session_snapshot()}
		print("[HOST] sending SESSION_SNAPSHOT to peer=", peer_id, " players=", (snap_evt["snapshot"].get("players", []) if snap_evt.has("snapshot") else "none"))
		nm.rpc_server_event.rpc_id(peer_id, snap_evt)

# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------
func _run_client() -> void:
	var connected := false
	for p in CANDIDATE_PORTS:
		NetworkManager.join("127.0.0.1", p)
		for i in range(300):
			await get_tree().process_frame
			if NetworkManager.local_peer_id != 0:
				connected = true
				break
		if connected:
			_write("client_port.txt", str(p))
			break
		NetworkManager.disconnect_session()
		await get_tree().process_frame
	if not connected:
		_write("client_ok.txt", "FAIL connect (no server on candidate ports)")
		return
	# 监听服务器事件（含 dungeon_layout），拿到 seed 后重建真实地牢。
	NetworkManager.event_received.connect(_on_client_event)
	NetworkManager.send_spawn({}, "client_guid_001")
	# 等待：重连 token（spawn 成功）+ 收到 dungeon_layout 并构建完地牢 + 出现 Host 的远端 avatar。
	var ready := false
	for i in range(900):
		await get_tree().process_frame
		if NetworkManager.reconnect_token != "" and _local_player != null and _bridge.get_avatar(_host_peer) != null:
			ready = true
			break
	if not ready:
		_write("client_ok.txt", "FAIL setup (token=%s player=%s av=%s)" % [
			NetworkManager.reconnect_token, _local_player != null, _bridge.get_avatar(_host_peer) != null])
		return
	_write("client_ready.txt", "OK")
	# 断言 1：地牢 seed + layout 指纹与房主一致（同图重建）。
	var host_line: String = _read("host_seed.txt")
	var client_line: String = "%d|%s" % [_seed, _controller.layout_fingerprint()]
	var seed_match: bool = host_line.get_slice("|", 0) == str(_seed)
	var fp_match: bool = (_host_fingerprint() == _controller.layout_fingerprint()) and host_line != "" and _controller.layout_fingerprint() != "none"
	_write("client_dungeon.txt", "seed_match=%s fp_match=%s host=%s client=%s" % [seed_match, fp_match, host_line, client_line])
	# 断言 4：服务器权威敌人实体经桥接层复制到客户端场景（entity_spawned → 可见节点）。
	var ent_ok := false
	for i in range(600):
		await get_tree().process_frame
		if _bridge.get_entity_node(1001) != null and _bridge.get_entity_node(1002) != null:
			ent_ok = true
			break
	var ent_count: int = _bridge.entity_count() if _bridge.has_method("entity_count") else 0
	# 校验复制来的敌人位置/HP 与服务器权威一致（抽查 1001）。
	var ent_detail := "none"
	var e1: Node3D = _bridge.get_entity_node(1001)
	if e1 != null:
		ent_detail = "kind=%s hp=%d/%d pos=%s" % [e1.kind, e1.hp, e1.max_hp, str(e1.target_position)]
	_write("client_entities.txt", "ent_ok=%s count=%d detail=%s" % [ent_ok, ent_count, ent_detail])
	# 断言 2+3：客户端本地 Player 被服务器驱动移动 + Host 远端 avatar 同步移动。
	# 注意：玩家权威出生点已落在地牢坐标系（非原点），故以「相对出生点的位移」判定移动，
	# 而非绝对坐标 > 阈值（dungeon spawn x 可能为负，绝对阈值会恒假）。
	var local_moved := false
	var remote_moved := false
	var start_lx: float = _local_player.global_position.x if _local_player != null else 0.0
	var av0: Node3D = _bridge.get_avatar(_host_peer)
	var start_ax: float = av0.global_position.x if av0 != null else 0.0
	for i in range(600):
		await get_tree().process_frame
		var lx: float = _local_player.global_position.x if _local_player != null else 0.0
		var av: Node3D = _bridge.get_avatar(_host_peer)
		var ax: float = av.global_position.x if av != null else 0.0
		if lx - start_lx > MOVE_THRESHOLD:
			local_moved = true
		if ax - start_ax > MOVE_THRESHOLD:
			remote_moved = true
		if local_moved and remote_moved:
			break
	var lx: float = _local_player.global_position.x if _local_player != null else 0.0
	var av: Node3D = _bridge.get_avatar(_host_peer)
	var ax: float = av.global_position.x if av != null else 0.0
	# 断言 5：真实攻击命中——客户端攻击敌人 1001 → 服务器权威扣血 → entity_snapshot HP 下降 →
	#          死亡 → entity_despawned 两端移除；敌人 1002 未被攻击应仍存活。
	var combat_ok := false
	var start_hp: int = 0
	var t0: Node3D = _bridge.get_entity_node(TARGET_ENEMY)
	if t0 != null:
		start_hp = t0.hp
	_do_attack = true  # 开始攻击（_process 每帧调用 send_attack，驱动内部冷却限流）
	var hp_dropped := false
	for i in range(900):
		await get_tree().process_frame
		var t: Node3D = _bridge.get_entity_node(TARGET_ENEMY)
		if t != null and t.hp < start_hp:
			hp_dropped = true
		if _bridge.get_entity_node(TARGET_ENEMY) == null:  # 已死亡移除
			combat_ok = true
			break
	_do_attack = false
	var other_alive: bool = _bridge.get_entity_node(OTHER_ENEMY) != null
	# 死亡即算命中链闭环；hp_dropped 记录中途扣血过程（可能因两击致死太快未采样到中间值，故不作硬性条件）。
	var combat_pass: bool = combat_ok and other_alive
	_write("client_combat.txt", "combat_ok=%s start_hp=%d hp_dropped=%s other_alive=%s" % [combat_ok, start_hp, hp_dropped, other_alive])
	# 断言 6（Phase ⑤）：掉落实体复制 + 拾取。
	# 战斗结束后冻结本地移动（玩家停在击杀点附近，掉落就在身边），扫描 kind=loot 实体，
	# 经 send_interact 拾取 → 服务器权威移除掉落实体 → entity_despawned 两端移除可见节点。
	_do_loot = true
	for _i in range(20):
		await get_tree().process_frame
	var loot_id := 0
	for eid in _bridge._entities.keys():
		var node = _bridge._entities[eid]
		if node != null and node.kind == "loot":
			loot_id = int(eid)
			break
	var loot_appeared := loot_id != 0
	var loot_picked := false
	if loot_appeared and _driver.has_method("send_interact"):
		_driver.send_interact(loot_id)
		for _i in range(180):
			await get_tree().process_frame
			if _bridge.get_entity_node(loot_id) == null:
				loot_picked = true
				break
	_do_loot = false
	var loot_ok := loot_appeared and loot_picked
	_write("client_loot.txt", "loot_ok=%s appeared=%s picked=%s id=%d" % [loot_ok, loot_appeared, loot_picked, loot_id])
	# 断言 7（Phase ⑧）：出征结算写回单人存档。
	# 客户端 send_extract → 服务器权威结算（本次净获得） → EVT_EXTRACTION_RESULT
	# → 桥接层把净获得合并进本地 GameState.expedition_inventory（玩家各自的单人存档）并持久化。
	# 掉落物为 goblin_tooth（Rat 掉落表），结算后本机 GameState 应含该材料。
	var extract_ok := false
	if _driver.has_method("send_extract"):
		_driver.send_extract()
		var gs: Node = get_node_or_null("/root/GameState")
		for _i in range(240):
			await get_tree().process_frame
			if gs != null and gs.get_carried_materials_dict().has("goblin_tooth"):
				extract_ok = true
				break
	_write("client_extract.txt", "extract_ok=%s" % [extract_ok])
	if local_moved and remote_moved and seed_match and fp_match and ent_ok and combat_pass and loot_ok and extract_ok:
		_write("client_move_ok.txt", "OK local_x=%.3f remote_x=%.3f" % [lx, ax])
		_write("client_ok.txt", "OK local_x=%.3f remote_x=%.3f seed_match=%s fp_match=%s entities=%d combat=%s loot=%s extract=%s" % [lx, ax, seed_match, fp_match, ent_count, combat_pass, loot_ok, extract_ok])
	else:
		_write("client_move_fail.txt", "local_x=%.3f remote_x=%.3f seed_match=%s fp_match=%s ent_ok=%s combat=%s loot=%s extract=%s" % [lx, ax, seed_match, fp_match, ent_ok, combat_pass, loot_ok, extract_ok])
		_write("client_ok.txt", "FAIL local_x=%.3f remote_x=%.3f seed_match=%s fp_match=%s ent_ok=%s combat=%s loot=%s extract=%s" % [lx, ax, seed_match, fp_match, ent_ok, combat_pass, loot_ok, extract_ok])

func _on_client_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	# dungeon_layout 事件使用 "type" 键（make_layout_event），其他事件用 "event" 键，二者都认。
	var kind: String = event.get("event", event.get("type", ""))
	if kind != NP.EVT_DUNGEON_LAYOUT:
		return
	if _local_player != null:
		return  # 已构建，忽略重复 layout
	_seed = int(event.get("seed", 0))
	_controller = DungeonSessionController.new()
	_controller.name = "DungeonSession"
	add_child(_controller)
	_local_player = _controller.build_and_enter(_seed)
	_driver = _local_player.get_node_or_null("ClientCommandDriver")

# ---------------------------------------------------------------------------
# Client2（晚到 / 重连恢复验证，Phase ⑨）
# ---------------------------------------------------------------------------
## 晚到客户端：在 Host + Client1 已建图、实体已生成、两端 avatar 已存在之后才接入。
## 验证“真实场景恢复”——仅凭服务器权威广播，本地重建出与既有会话一致的地牢 + 实体 + 全部玩家 avatar。
func _run_client2() -> void:
	var connected := false
	for p in CANDIDATE_PORTS:
		NetworkManager.join("127.0.0.1", p)
		for i in range(300):
			await get_tree().process_frame
			if NetworkManager.local_peer_id != 0:
				connected = true
				break
		if connected:
			_write("client2_port.txt", str(p))
			break
		NetworkManager.disconnect_session()
		await get_tree().process_frame
	if not connected:
		_write("client2_recovery.txt", "FAIL connect (no server on candidate ports)")
		return
	NetworkManager.event_received.connect(_on_client2_event)
	NetworkManager.send_spawn({}, "client2_guid_001")
	# 晚到恢复：重连 token（spawn 成功）+ 地牢重建 + 既有两端 avatar（房主 peer1 + 先到客户端）。
	# 注意：client1 的 peer id 是 ENet 动态分配的（非固定 2），故“既有玩家 avatar”须动态查找
	# （任何既非房主 peer1、也非自身 local_peer_id 的远端 avatar 即视为先到客户端）。
	var local_pid: int = NetworkManager.local_peer_id
	var recovered := false
	for i in range(900):
		await get_tree().process_frame
		var host_av = _bridge.get_avatar(1) if _bridge != null else null
		var peer1_av = _find_remote_avatar(local_pid) if _bridge != null else null
		if NetworkManager.reconnect_token != "" and _local_player != null and host_av != null and peer1_av != null:
			recovered = true
			break
	var host_av = _bridge.get_avatar(1) if _bridge != null else null
	var peer1_av = _find_remote_avatar(local_pid) if _bridge != null else null
	var ent_cnt: int = _bridge.entity_count() if (_bridge != null and _bridge.has_method("entity_count")) else 0
	var host_line: String = _read("host_seed.txt")
	var fp_match: bool = (host_line != "" and _controller != null and _controller.layout_fingerprint() != "none"
		and _host_fingerprint() == _controller.layout_fingerprint())
	print("[CLIENT2-REC] host_line='", host_line, "' local_fp='", (_controller.layout_fingerprint() if _controller != null else "null"), "' host_fp='", _host_fingerprint(), "' fp_match=", fp_match, " peers=", (_bridge.get_avatar_peers() if _bridge != null else []))
	var both_av: bool = host_av != null and peer1_av != null
	# 额外证明既有玩家在动：等若干帧，抽查 peer2 avatar 是否产生位移（服务器快照已路由到晚到客户端）。
	var moved := false
	var x0: float = peer1_av.global_position.x if peer1_av != null else 0.0
	for i in range(300):
		await get_tree().process_frame
		if peer1_av != null and abs(peer1_av.global_position.x - x0) > MOVE_THRESHOLD:
			moved = true
			break
	var ok := recovered and both_av and ent_cnt >= 1 and fp_match
	_write("client2_recovery.txt", "ok=%s recovered=%s both_avatars=%s host_av=%s peer1_av=%s entities=%d fp_match=%s peer_moved=%s" % [
		ok, recovered, both_av, host_av != null, peer1_av != null, ent_cnt, fp_match, moved])

## 返回任意一个“既非房主(1)、也非自身”的远端 avatar（晚到/重连场景下即先到客户端）。
## ENet 动态分配 peer id，不能写死为 2。
func _find_remote_avatar(local_pid: int) -> Node:
	if _bridge == null or not _bridge.has_method("get_avatar_peers"):
		return null
	for pid in _bridge.get_avatar_peers():
		if int(pid) != 1 and int(pid) != local_pid:
			return _bridge.get_avatar(int(pid))
	return null

func _on_client2_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var kind: String = event.get("event", event.get("type", ""))
	print("[CLIENT2] recv event=", kind, " local_peer=", NetworkManager.local_peer_id)
	# 调试：记录 client2 收到的每一个事件及种子，定位晚到/重连恢复时序。
	_write("client2_evt.log", "EVT kind=%s seed=%s" % [kind, event.get("seed", event.get("type", ""))])
	# dungeon_layout 事件使用 "type" 键（make_layout_event），其他事件用 "event" 键，二者都认。
	if kind != NP.EVT_DUNGEON_LAYOUT:
		return
	if _local_player != null:
		return  # 已构建，忽略重复 layout
	_seed = int(event.get("seed", 0))
	print("[CLIENT2] building dungeon from seed=", _seed)
	_controller = DungeonSessionController.new()
	_controller.name = "DungeonSession"
	add_child(_controller)
	_local_player = _controller.build_and_enter(_seed)
	_driver = _local_player.get_node_or_null("ClientCommandDriver")
	print("[CLIENT2] dungeon built local_peer=", NetworkManager.local_peer_id, " fp=", _controller.layout_fingerprint(), " player_ok=", (_local_player != null))
	var _hl := _read("host_seed.txt")
	_write("client2_evt.log", "BUILT seed=%d fp=%s host=%s match=%s" % [_seed, _controller.layout_fingerprint(), _hl, (_hl.get_slice("|", 1) == _controller.layout_fingerprint())])

# ---------------------------------------------------------------------------
func _write(name: String, content: String) -> void:
	var f := FileAccess.open(_itdir + "/" + name, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()

func _read(name: String) -> String:
	var f := FileAccess.open(_itdir + "/" + name, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s

## host_seed.txt 格式为 "seed|width|height|gridhash|spawncell"。
## 提取“第一个 '|' 之后的完整地牢指纹”（get_slice("|",1) 只会返回宽度单字段，故用 split）。
func _host_fingerprint() -> String:
	var hl: String = _read("host_seed.txt")
	if hl == "":
		return ""
	var parts: PackedStringArray = hl.split("|", true, 1)
	return parts[1] if parts.size() > 1 else ""
