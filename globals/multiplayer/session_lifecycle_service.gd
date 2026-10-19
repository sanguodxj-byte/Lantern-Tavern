class_name SessionLifecycleService
extends RefCounted

## 会话生命周期编排服务（ADR-003 渐进拆分：SessionRoot 第五刀）。
## 从 SessionRoot 迁出玩家生命周期命令族：spawn（含权威存档恢复）、
## register/unregister/bind、断线 GRACE/重连迁移（CMD_RESUME）、心跳、主动离开。
##
## 依赖约定：共享状态容器、信号与保留 API 经 `_r`（SessionRoot 引用）访问——
## _live_state/_ctx_peer/_seq_tracker/_peer_state_nodes/_inventory_baseline/
## _attack_cd_until/_stagger、registry/connection_auth/interaction_auth/
## server_save_repo/expedition_service、player_registered/player_spawned/
## player_unregistered/session_event、_reject/_bump_world/build_session_snapshot/
## current_time/player_spawn_pos/_peer_state_root。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")
const AttrPanelClass := preload("res://globals/combat/attr_panel.gd")
const SkillRuntimeClass := preload("res://globals/combat/skill_runtime.gd")
const ExpeditionInventoryClass := preload("res://globals/core/state/expedition_inventory.gd")
const EquipmentLoadoutClass := preload("res://globals/core/state/equipment_loadout.gd")

var _r = null

func _init(root: Node) -> void:
	_r = root

# ============================================================================
# 生成 / 注册
# ============================================================================

## 注册一个玩家（服务器生成后调用）。
func register_player(peer_id: int, ctx: PlayerContextClass, player = null, position: Vector3 = Vector3.ZERO) -> void:
	_r.registry.register_peer(peer_id, ctx, player)
	_r.live_state()[peer_id] = {"peer_id": peer_id, "is_alive": true, "position": position,
		"facing": Vector3(0, 0, -1), "look_yaw": 0.0}
	_r.ctx_peer()[ctx.get_instance_id()] = peer_id
	_r.registry.set_spawned(peer_id, true)
	_r.player_registered.emit(peer_id)

## 服务器处理一次玩家生成请求（替代 network_manager 的 no-op）。
## 为 peer 创建独立的 PlayerContext（聚合独立属性/技能/背包/装备状态）。
## 联机范围仅限地牢（出征）：玩家进入地牢时只继承各自单人存档状态。
## B2（0644 审查 / 决策 G1-A）：权威存档来源 = 服务器可信存档仓（server_save_repo 按 guid
## 加载）。仓有记录 → 以仓内状态恢复（绝不信任客户端字典）；仓无记录 → 回退 save_state
## （仅房主）→ 仍空则默认上下文（新玩家无存档，决策 A 接受）。
## P0-1：在创建任何玩家子对象/库存基线【前】做在线 GUID 唯一性预检——
## 重复在线身份直接拒绝（返回 null），避免先建状态再覆盖身份索引导致的重连/结算串账。
func handle_spawn_request(peer_id: int, save_state: Dictionary = {}, player_guid: String = "") -> PlayerContextClass:
	if not _r.is_server:
		return null
	if _r.registry.has_peer(peer_id):
		return _r.registry.get_context(peer_id)
	var guid: String = player_guid if player_guid != "" else ("peer_%d" % peer_id)
	# P0-1 预检：该 GUID 已被其他 ONLINE peer 占用 → 拒绝（不创建任何状态）。
	if _r.connection_auth.has_online_guid(guid):
		return null
	var attrs := AttrPanelClass.new()
	attrs.init_defaults()
	var sk := SkillRuntimeClass.new()
	sk.init_defaults()
	attrs.name = "AttrPanel_%d" % peer_id
	sk.name = "SkillRuntime_%d" % peer_id
	_r.peer_state_root().add_child(attrs)
	_r.peer_state_root().add_child(sk)
	_r.peer_state_nodes()[peer_id] = [attrs, sk]
	var inv := ExpeditionInventoryClass.new()
	var lo := EquipmentLoadoutClass.new()
	var ctx: PlayerContextClass = PlayerContextClass.for_peer(attrs, sk, inv, lo, null, guid)
	# P1-1：服务器可信存档仓优先——该身份在服务器已有权威存档时，以仓内状态恢复
	# （材料/装备/法术装配），绝不信任客户端字典；无仓/无存档才用调用方摘要或默认状态。
	var applied_save: Dictionary = {}
	if _r.server_save_repo != null:
		applied_save = _r.server_save_repo.load_save(guid)
	if applied_save.is_empty():
		applied_save = save_state
	if not applied_save.is_empty():
		_r.expedition_service.apply_save_state(ctx, inv, lo, applied_save)
	# 记录进地牢时的背包基线（用于结算时只回写净获得）。
	_r.inventory_baseline()[peer_id] = inv.to_dict()
	register_player(peer_id, ctx, null, _r.player_spawn_pos)
	# P0-1：结构化注册结果；预检后理论上必成功，失败则回滚（不留下半创建状态）。
	var reg: Dictionary = _r.connection_auth.register_online(peer_id, guid, 0.0)
	if not bool(reg.get("ok", false)):
		unregister_player(peer_id)
		return null
	_r.player_spawned.emit(peer_id)
	# 玩家加入是结构性世界变更→推进 world_revision 并广播（闭环）。
	_r.bump_world()
	return ctx

## 把真实 Player 实体绑定到 peer 的权威 PlayerContext（架构审查 P0-4）。
## 服务器法术权威执行依赖已绑定的 caster 节点；未绑定时施法在资源 commit 前被拒绝。
## 由表现层（DungeonSessionController 房主本地玩家 / MultiplayerSceneBridge 远端 avatar）
## 在实体创建后调用。返回是否绑定成功。
func bind_player_entity(peer_id: int, player_entity: Node3D) -> bool:
	if player_entity == null or not is_instance_valid(player_entity):
		return false
	var ctx: PlayerContextClass = _r.registry.get_context(peer_id)
	if ctx == null:
		return false
	ctx.player_node = player_entity
	return true

## 注销玩家（断线清理）。
func unregister_player(peer_id: int) -> void:
	var ctx = _r.registry.get_context(peer_id)
	if ctx != null:
		_r.ctx_peer().erase(ctx.get_instance_id())
	_free_peer_state_nodes(peer_id)
	_r.registry.unregister_peer(peer_id)
	_r.live_state().erase(peer_id)
	_r.seq_tracker().reset_peer(peer_id)
	_r.inventory_baseline().erase(peer_id)
	_r.player_unregistered.emit(peer_id)

func _free_peer_state_nodes(peer_id: int) -> void:
	var state_nodes: Array = _r.peer_state_nodes().get(peer_id, [])
	_r.peer_state_nodes().erase(peer_id)
	for node in state_nodes:
		if node is Node and is_instance_valid(node):
			node.free()

# ============================================================================
# 连接生命周期（§13）：断线保留 / 重连 / 心跳超时 / 主动离开
# ============================================================================

## 心跳（客户端定期 ping）：刷新该 peer 的最后活跃时间。
func heartbeat(peer_id: int, now: float = -1.0) -> void:
	if now < 0.0:
		now = _r.current_time
	_r.connection_auth.touch(peer_id, now)

## 服务器检测到 peer 掉线（显式断开 或 心跳超时）：进入 GRACE 保留期。
## 保留 PlayerContext，广播 player_despawned，释放其交互锁，并发放重连 token。
## 返回 {token, was_tracked}。调用方据此把 token 回传客户端供其重连使用。
func handle_peer_disconnected(peer_id: int, now: float = -1.0) -> Dictionary:
	if now < 0.0:
		now = _r.current_time
	var res: Dictionary = _r.connection_auth.on_disconnect(peer_id, now)
	if res["was_tracked"]:
		# 释放该 peer 持有的全部交互锁（§13.1「释放交互锁」）
		_r.interaction_auth.clear_locks_for(peer_id)
		# 广播断线（其他客户端隐藏其实体；保留期后由 tick_connections 真正清理）
		var evt := {"event": NP.EVT_PLAYER_DESPAWNED, "peer_id": peer_id}
		_r.session_event.emit(evt)
		# 玩家离开是结构性世界变更→推进 world_revision 并广播（闭环）。
		_r.bump_world()
	return res

## 客户端主动离开（不再重连）：立即清理 PlayerContext。
func handle_peer_left(peer_id: int) -> void:
	_r.connection_auth.on_leave(peer_id)
	_r.interaction_auth.clear_locks_for(peer_id)
	unregister_player(peer_id)
	var evt := {"event": NP.EVT_PLAYER_DESPAWNED, "peer_id": peer_id}
	_r.session_event.emit(evt)
	# 玩家主动离开是结构性世界变更→推进 world_revision 并广播（闭环）。
	_r.bump_world()

## 推进连接时间：清理所有 GRACE 超时的 peer（保留期已过，注销 PlayerContext）。
## 返回被清理的 peer_id 列表。
func tick_connections(now: float = -1.0) -> Array:
	if now < 0.0:
		now = _r.current_time
	var cleaned: Array = []
	for pid in _r.connection_auth.collect_expired_grace(now):
		unregister_player(pid)
		cleaned.append(pid)
	return cleaned

## 客户端重连请求（CMD_RESUME）：按 guid/token 锚定旧条目，把全部服务器权威状态
## 从旧 peer_id 接管（迁移）到新 peer_id，恢复在线、重置序列、下发 session_snapshot
## （§13.2 重连快照）。重连沿用断线保留期内的同一 PlayerContext（inventory/位置/状态连续）。
func handle_resume(command: Dictionary, _ctx: PlayerContextClass) -> Dictionary:
	var new_peer_id: int = int(command.get("peer_id", 0))
	var token: String = String(command.get("token", ""))
	var guid: String = String(command.get("player_guid", ""))
	# 重连身份按 guid/token 锚定（不依赖会变的 peer_id）。
	var vr: Dictionary = _r.connection_auth.validate_reconnect_by_guid(guid, token, _r.current_time)
	if not vr["ok"]:
		return _r.reject(vr["reason"])
	var old_peer_id: int = int(vr["peer_id"])
	# 把旧 peer_id 的全部服务器权威状态迁移到新 peer_id（重连接管，不丢 inventory/位置/状态）。
	_r.connection_auth.migrate_peer(old_peer_id, new_peer_id)
	migrate_peer_state(old_peer_id, new_peer_id)
	# 完成重连：恢复 ONLINE（peer_id 已迁移到 new_peer_id）。
	var res: Dictionary = _r.connection_auth.resume(new_peer_id, token, _r.current_time)
	if not res["ok"]:
		return _r.reject(res["reason"])
	# 重连 = 新连接，重置该 peer 的命令序列（防重放/乱序）
	_r.seq_tracker().reset_peer(new_peer_id)
	# 保证 live_state 仍在线（断线保留期未清除；迁移后键为 new_peer_id）
	if not _r.live_state().has(new_peer_id):
		_r.live_state()[new_peer_id] = {"peer_id": new_peer_id, "is_alive": true, "position": Vector3.ZERO}
	# 下发完整重连快照（先全量，再增量）
	var snap: Dictionary = _r.build_session_snapshot()
	var evt := {"event": NP.EVT_SESSION_SNAPSHOT, "peer_id": new_peer_id, "snapshot": snap}
	_r.session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 把某旧 peer_id 的服务器权威状态整体接管（迁移）到新 peer_id（重连后新连接的新 peer_id）。
## 保留 PlayerContext（含 inventory/属性/技能/装备）、权威位置/朝向/存活、出征背包基线、
## 攻击冷却/硬直状态，并更新 ctx→peer 反向索引与 spawned 标记。旧键随后由调用方各自清除。
func migrate_peer_state(old_id: int, new_id: int) -> void:
	if old_id == new_id:
		return
	if _r.peer_state_nodes().has(old_id):
		_r.peer_state_nodes()[new_id] = _r.peer_state_nodes()[old_id]
		_r.peer_state_nodes().erase(old_id)
	# registry：把旧 ctx 重新登记到新 peer_id（保留 PlayerContext 全部状态，不重建）
	var ctx = _r.registry.get_context(old_id)
	if ctx != null:
		_r.registry.unregister_peer(old_id)
		_r.registry.register_peer(new_id, ctx, null)
		_r.registry.set_spawned(new_id, true)
		_r.ctx_peer()[ctx.get_instance_id()] = new_id
	# live_state：保留权威位置/朝向/存活
	if _r.live_state().has(old_id):
		_r.live_state()[new_id] = _r.live_state()[old_id]
		_r.live_state()[new_id]["peer_id"] = new_id
		_r.live_state().erase(old_id)
	# 出征背包基线 / 攻击冷却 / 硬直 / 交互锁（interaction_auth 以 peer_id 为键，一并迁移）
	if _r.inventory_baseline().has(old_id):
		_r.inventory_baseline()[new_id] = _r.inventory_baseline()[old_id]
		_r.inventory_baseline().erase(old_id)
	if _r.attack_cd_until().has(old_id):
		_r.attack_cd_until()[new_id] = _r.attack_cd_until()[old_id]
		_r.attack_cd_until().erase(old_id)
	if _r.stagger().has(old_id):
		_r.stagger()[new_id] = _r.stagger()[old_id]
		_r.stagger().erase(old_id)
	_r.interaction_auth.migrate_locks(old_id, new_id)
