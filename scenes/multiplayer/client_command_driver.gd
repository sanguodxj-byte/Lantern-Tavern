extends Node
## 客户端命令驱动（联机表现层）：把真实 Player 的输入/意图转换为联机命令上送服务器。
##
## 职责（docs/25 §19 客户端入口）：
##   * 每个物理帧采集本地 Player 的 input_dir / 朝向，封装 CMD_INPUT 上送；
##   * 接收服务器下发的【本机玩家】player_snapshot，应用到真实 Player 节点（服务器权威位置）；
##   * 暴露 send_attack / send_interact / send_skill 供战斗/交互触发。
##
## 仅在地牢联机模式挂到本地 Player 上；单机模式不创建本节点（Player.multiplayer_driver == null）。
## 房主（listen-server）自身也是玩家：上送走 submit_command 的本地权威路径，不经 RPC 回路。
##
## 不声明 class_name：避免 headless 类注册 / .uid 同步问题；经 preload 引用。

const NP := preload("res://globals/multiplayer/network_protocol.gd")

## 真实 Player 控制器（本地玩家，全功能；远端玩家用 avatar）。
var player: Node = null

## 严格递增序列号（输入/攻击/交互/技能共用，抵抗重放/乱序）。
var _sequence: int = 0
## 本机玩家最新权威快照目标（由事件写入，apply 到 Player）。
var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0

## 攻击冷却（秒）：避免每帧狂发 CMD_ATTACK 刷序列号。
var attack_cooldown: float = 0.5
var _attack_timer: float = 0.0

## 自动化/测试/Bot 输入覆盖：非零时直接作为上送 move 向量（绕过 player.input_dir 的实时采集）。
## 正常游玩时保持 ZERO，由 player.input_dir 驱动。
var override_move: Vector2 = Vector2.ZERO

## 格挡状态（Phase 1）：每帧随 CMD_INPUT 上送，服务器移动权威读取。send_block 仅更新此标志。
var block_active: bool = false

## 客户端心跳间隔（秒）：远低于服务器 HEARTBEAT_TIMEOUT(15s)，保证超时前至少有 2~3 次 ping。
## 由 _physics_process 累加 delta 触发 NetworkManager.send_heartbeat()（Phase 7 闭环：客户端定期 ping）。
const HEARTBEAT_INTERVAL := 5.0
var _heartbeat_accum: float = 0.0

## 远端客户端从服务器广播学到的「当前服务器 world_revision」。房主(is_host)直接读实时 WorldState，不走此缓存。
## 服务器每次结构性世界变更都会广播 EVT_WORLD_REVISION_CHANGED；客户端据此更新，否则会用旧 revision 上送→被拒绝（闭环）。
var _known_server_rev: int = 0

func _ready() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm != null:
		if nm.has_signal("event_received"):
			nm.event_received.connect(_on_event)
		if nm.has_signal("event_dispatched"):
			nm.event_dispatched.connect(_on_event)
	# 配置本地玩家联机身份：房主=NETWORK_SERVER（本地即权威），远端客户端=NETWORK_CLIENT（只上送意图）。
	if player != null and player.has_method("configure_network_input"):
		var mode = player.InputMode.NETWORK_CLIENT
		if nm != null and nm.is_host:
			mode = player.InputMode.NETWORK_SERVER
		player.configure_network_input(self, mode)

func _physics_process(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	# 客户端心跳调度（Phase 7）：独立于玩家节点状态，定期向服务器 ping 以刷新断线判定 last_seen。
	_maybe_send_heartbeat(delta)
	if player == null or not is_instance_valid(player):
		return
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	if not nm.is_client() and not nm.is_host:
		return
	_send_input_frame(nm)
	# 应用本机玩家权威快照到真实 Player（服务器驱动位置/朝向）
	if _target_position != Vector3.ZERO or _target_yaw != 0.0:
		if player.has_method("apply_remote_snapshot"):
			player.apply_remote_snapshot(_target_position, _target_yaw)

## 客户端心跳调度（Phase 7）：每累计 HEARTBEAT_INTERVAL 秒调用一次 NetworkManager.send_heartbeat()。
## 房主(is_host)自身即服务器，无需向自己 ping；仅远端客户端(is_client)触发。
## nm_override 用于测试注入；生产路径传 null，经 get_node_or_null 取真实 NetworkManager。
## 单帧超大 delta（如卡顿/断点恢复）只触发 1 次（不求整补发），避免瞬间风暴。
## 参数类型用 Object（而非 Node）：既接受真实的 NetworkManager(Node)，也接受测试 mock(RefCounted)。
func _maybe_send_heartbeat(delta: float, nm_override: Object = null) -> void:
	_heartbeat_accum += delta
	if _heartbeat_accum < HEARTBEAT_INTERVAL:
		return
	_heartbeat_accum = 0.0
	var nm: Object = nm_override if nm_override != null else get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active or not nm.is_client():
		return
	nm.send_heartbeat()

## 采集输入帧并上送（CMD_INPUT）。服务器从该输入积分权威位置，绝不信任客户端坐标。
func _send_input_frame(nm: Node) -> void:
	var move := override_move
	if move.is_zero_approx() and "input_dir" in player:
		move = player.input_dir
	var yaw: float = 0.0
	if "rotation" in player:
		yaw = player.rotation.y
	_sequence += 1
	var cmd := {
		"type": NP.CMD_INPUT,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		# input_dir 的 y 轴与世界 z 轴符号相反（与 player.process_movement 一致）
		"move": [move.x, -move.y],
		"sprint": Input.is_action_pressed("run"),
		"look_yaw": yaw,
		"look_pitch": 0.0,
		"block": block_active,
	}
	nm.submit_command(cmd)

## 发起一次攻击（CMD_ATTACK）。target_hint = 服务器实体 id（敌人/可破坏物）。
## 架构审查 P0-2：客户端只提交意图（手位/蓄力/目标提示），不再提交 attack_type——
## 攻击类型/射程/冷却/伤害全部由服务器从权威 loadout 派生（AttackContextFactory）。
func send_attack(target_hint: int, hand: String = "primary", charge_ratio: float = 1.0) -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	_sequence += 1

	nm.submit_command({
		"type": NP.CMD_ATTACK,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"hand": hand,
		"charge_ratio": clampf(charge_ratio, 0.0, 1.0),
		"target_hint": target_hint,
	})

## 发起一次交互/拾取（CMD_INTERACT / CMD_PICKUP）。target = 实体 id（服务器权威识别）。
## 注意：交互权威读取 target_entity_id（与战斗权威读取 target_hint 不同），此处两者都带齐以兼容。
func send_interact(target: int = 0) -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_INTERACT,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"target_entity_id": target,
		"target_hint": target,
	})

## 发起一次技能（CMD_SKILL）。技能 id 由服务器校验归属；攻击类型由服务器权威派生。
func send_skill(skill_id: String) -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_SKILL,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"skill_id": skill_id,
	})

## 发起法术施放。客户端只提交槽位/方向提示；服务端必须重解析固定配方与数值。
func send_cast_spell(slot_index: int, origin: Vector3, direction: Vector3, target_hint: Variant = null) -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_CAST_SPELL,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"slot_index": clampi(slot_index, 0, 4),
		"origin": [origin.x, origin.y, origin.z],
		"direction": [direction.x, direction.y, direction.z],
		"target_hint": target_hint,
	})

## 发起一次出征结算（CMD_EXTRACT）：服务器计算本次净获得并回传 EVT_EXTRACTION_RESULT，
## 由桥接层写回本机玩家各自的单人存档（GameState.expedition_inventory）。
func send_extract() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_EXTRACT,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
	})

## 发起一次格挡状态变更（CMD_INPUT.block 字段随每帧上送；此处仅更新本地标志）。
## 协议当前无独立 CMD_BLOCK：服务器移动权威从 CMD_INPUT.block 读取持盾/格挡状态。
func send_block(active: bool) -> void:
	block_active = active

## 发起一次升级选择意图（CMD_LEVEL_UP_CHOICE，P1-4 权威闭环）。
## 客户端只提交选择；服务器校验 pending 次数/候选后应用，绝不直接修改权威属性。
func send_level_up_choice(kind: String, attr_key: String = "", rune_id: String = "") -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_LEVEL_UP_CHOICE,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"kind": kind,
		"attr_key": attr_key,
		"rune_id": rune_id,
	})

## 请求本次升级的符文候选（CMD_LEVEL_UP_RUNE_CANDIDATES）：服务器按 player_guid
## 确定性掷出并经 EVT_PROGRESSION_RUNE_CANDIDATES 下发。
func request_level_up_rune_candidates() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_LEVEL_UP_RUNE_CANDIDATES,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
	})

## 发起一次拾取（CMD_PICKUP）。entity_id 为服务器实体 id；0 表示由服务器按玩家位置/朝向推断。
func send_pickup(entity_id: int) -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_PICKUP,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"target_entity_id": entity_id,
	})

## 发起一次投掷（CMD_DROP + throw=true）。协议无独立 CMD_THROW：复用 CMD_DROP 的投掷语义，
## 服务器在 Phase 2 依据 throw 标志区分「丢弃」与「投掷」。item_id 为空时投出当前主手武器。
func send_throw(item_id: String = "") -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_DROP,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"item_id": item_id,
		"throw": true,
	})

## 装备切换（CMD_EQUIP，P0-4 协议统一）。
## item_id 为目标物品；slot_kind="weapon"/"armor" + slot_index(int)/slot_name(String) 明确表达槽位；
## slot_kind 为空时由服务器按物品类别自动判定（武器→武器槽 / 护甲→护甲槽）。
func send_equip(item_id: String, slot_kind: String = "", slot_index: int = -1, slot_name: String = "") -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_EQUIP,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"item_id": item_id,
		"slot_kind": slot_kind,
		"slot_index": slot_index,
		"slot_name": slot_name,
	})

## 丢弃（CMD_DROP + throw=false）。
func send_drop(item_id: String, amount: int = 1) -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_active:
		return
	_sequence += 1
	nm.submit_command({
		"type": NP.CMD_DROP,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": _server_world_revision(nm),
		"sequence": _sequence,
		"item_id": item_id,
		"amount": amount,
		"throw": false,
	})

## P0（2331 审查）：把服务器权威战斗状态应用到本机 Player 组件（只读镜像）。
## health → 生命；mana → 法力；shield → damage_absorb buff（HUD 护盾条读取）；
## buffs → spell_power buff（法术倍率表现）。
func _apply_combat_state(current_life: int, max_life: int, shield: int, buffs: Dictionary, mana: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	if "health" in player and player.health != null:
		var h = player.health
		if h.has_method("set_max_life"):
			h.set_max_life(max_life)
		if h.has_method("set_current_life"):
			h.set_current_life(current_life)
		elif "current_life" in h:
			h.current_life = current_life
	if "mana" in player and player.mana != null and "current_mana" in player.mana:
		player.mana.current_mana = mana
	if "buffs" in player and player.buffs != null and player.buffs.has_method("add"):
		# shield → damage_absorb 表现（吸收百分比由 HUD 显示）。
		var existing_absorb := false
		for buff_id in buffs.keys():
			if buff_id == "spell_power" and player.buffs.has_method("add"):
				player.buffs.add("spell_power", 6.0, {"percent": 20.0})
			if buff_id == "shield":
				existing_absorb = true
		if shield > 0:
			var pct := clampf(float(shield) / float(maxi(max_life, 1)) * 100.0, 0.0, 100.0)
			player.buffs.add("damage_absorb", 5.0, {"percent": pct})
		elif existing_absorb and player.buffs.has_method("remove"):
			player.buffs.remove("damage_absorb")

func _server_world_revision(nm: Node) -> int:
	if nm != null and nm.is_host:
		# 房主共享权威 WorldState，直接读实时值（始终最新，无需事件缓存）。
		if nm.session != null and nm.session.world != null:
			return int(nm.session.world.world_revision)
		return 0
	# 远端客户端：只能靠服务器广播的 EVT_WORLD_REVISION_CHANGED 更新缓存。
	return _known_server_rev

## 监听服务器事件：只处理本机玩家（peer_id == local_peer_id）的 player_snapshot，
## 以及 EVT_WORLD_REVISION_CHANGED（更新本机已知服务器 revision，保证上送命令通过校验）。
func _on_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var kind: String = event.get("event", "")
	if kind == NP.EVT_WORLD_REVISION_CHANGED:
		_known_server_rev = int(event.get("world_revision", _known_server_rev))
		return
	if kind == NP.EVT_SESSION_SNAPSHOT:
		# 闭环自愈：晚到/重连客户端经会话快照补学当前服务器 revision
		# （可能错过早期 EVT_WORLD_REVISION_CHANGED 广播，否则所有命令被永久拒绝）。
		var snap = event.get("snapshot", {})
		if snap is Dictionary and snap.has("world_revision"):
			_known_server_rev = int(snap["world_revision"])
		# P0（2331 审查）：重连快照落地本机战斗状态（players 数组含 spell_state.combat_state）。
		if snap is Dictionary and snap.has("players"):
			var nm0: Node = get_node_or_null("/root/NetworkManager")
			var me := int(nm0.local_peer_id) if nm0 != null else 0
			for pd in snap["players"]:
				if pd is Dictionary and int(pd.get("peer_id", 0)) == me and pd.has("spell_state"):
					var cs: Dictionary = Dictionary(Dictionary(pd["spell_state"]).get("combat_state", {}))
					if not cs.is_empty():
						_apply_combat_state(int(cs.get("current_life", 100)), int(cs.get("max_life", 100)),
							int(cs.get("shield", 0)), Dictionary(cs.get("buffs", {})),
							int(Dictionary(pd["spell_state"]).get("spell_mana", 100)))
		return
	if kind == NP.EVT_PLAYER_COMBAT_STATE:
		# P0（2331 审查）：权威战斗状态事件——只应用本机玩家，只读镜像（不反向写服务器）。
		var nm: Node = get_node_or_null("/root/NetworkManager")
		if nm == null:
			return
		if int(event.get("peer_id", 0)) != int(nm.local_peer_id):
			return
		_apply_combat_state(int(event.get("current_life", 100)), int(event.get("max_life", 100)),
			int(event.get("shield", 0)), Dictionary(event.get("buffs", {})),
			int(event.get("spell_mana", 100)))
		return
	if kind != NP.EVT_PLAYER_SNAPSHOT:
		return
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null:
		return
	if int(event.get("peer_id", 0)) != int(nm.local_peer_id):
		return
	_target_position = event.get("position", Vector3.ZERO)
	_target_yaw = float(event.get("look_yaw", 0.0))
