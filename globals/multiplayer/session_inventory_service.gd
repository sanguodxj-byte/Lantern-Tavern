class_name SessionInventoryService
extends RefCounted

## 装备/拾取/丢弃命令编排服务（ADR-003 渐进拆分：SessionRoot 第三刀）。
## 从 SessionRoot 迁出 inventory 命令族：pickup（CMD_INTERACT/CMD_PICKUP 共用）、
## equip（CMD_EQUIP）、drop（CMD_DROP），以及装备策略数据源。
##
## 依赖约定：共享状态容器与保留 API 经 `_r`（SessionRoot 引用）访问——
## _ctx_peer/_seq_tracker/_live_state/_entities/_loot_seq、
## interaction_auth/registry、_reject/remove_entity/set_entity/_weapon_registry。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")
const EquipmentPolicyClass := preload("res://globals/core/equipment_policy.gd")

## SessionRoot 引用（无类型：避免循环 preload 与 Node 静态成员限制）。
var _r = null

## 装备策略数据源（P0-4）：从 WeaponRegistry 解析物品类别/手位/护甲部位。
## 可由测试注入 stub（headless 无 autoload）。
var equipment_data_source_custom: Callable = Callable()

func _init(root: Node) -> void:
	_r = root

# ============================================================================
# 拾取 / 交互
# ============================================================================

## 拾取/交互命令（CMD_INTERACT / CMD_PICKUP 共用路由）：
## InteractionAuthority 解析 → 成功时从权威实体仓移除掉落实体并附带 despawn 事件。
func handle_interaction(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	var live: Dictionary = _r.live_state().get(peer_id, {})
	var res: Dictionary = _r.interaction_auth.resolve_interaction(command, ctx, live, _r.entities())
	if bool(res.get("success", false)):
		# 拾取成功：从权威注册表移除掉落实体，并附带 entity_despawned 事件，
		# 使两端表现层移除可见掉落物（玩家拾取后掉落物应从世界消失）。
		var tid: int = int(res.get("target_entity_id", 0))
		if tid != 0 and _r.entities().has(tid):
			var dres: Dictionary = _r.remove_entity(tid)
			if bool(dres.get("success", false)) and dres.has("event") and not dres["event"].is_empty():
				var extra: Array = res.get("extra_events", [])
				if extra == null:
					extra = []
				extra.append(dres["event"])
				res["extra_events"] = extra
	return res

# ============================================================================
# 装备
# ============================================================================

## 客户端请求装备物品（CMD_EQUIP）：服务器校验物品确在该玩家背包内（权威），
## 再经唯一装备策略 EquipmentPolicy 解析类别/槽位兼容/占槽关系后写入 loadout 槽位。
## 材料/符文/未知物品一律拒绝——绝不污染权威 loadout。
func handle_equip(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	if not _r.seq_tracker().accept(peer_id, int(command.get("sequence", 0))):
		return _r.reject(NP.ERR_INVALID_SEQUENCE)
	var item_id: String = String(command.get("item_id", ""))
	# 新协议：slot_kind + slot_index/slot_name；旧协议 slot（int/string）兼容解析。
	var slot_kind: String = String(command.get("slot_kind", ""))
	var slot_index: int = int(command.get("slot_index", -1))
	var slot_name: String = String(command.get("slot_name", ""))
	var legacy_slot = command.get("slot", null)
	if legacy_slot is int:
		slot_kind = "weapon"
		slot_index = int(legacy_slot)
	elif legacy_slot is String:
		slot_kind = "armor"
		slot_name = String(legacy_slot)
	if item_id.is_empty():
		return _r.reject(NP.ERR_INVALID_TARGET)
	# 物品必须在该玩家背包内（权威），否则视为非法请求。
	var inv = ctx.inventory
	var owned: bool = (inv.materials.has(item_id) or inv.runes.has(item_id) or inv.equipment.has(item_id))
	if not owned:
		return _r.reject(NP.ERR_INVALID_TARGET)
	var lo = ctx.loadout
	# P0-4：唯一装备策略（类别/槽位兼容/双手↔盾互斥/唯一性），拒绝任何非装备污染槽位。
	var res: Dictionary = EquipmentPolicyClass.resolve(item_id, slot_kind, slot_index, slot_name,
		lo, equipment_data_source())
	if not bool(res.get("ok", false)):
		return _r.reject(NP.ERR_INVALID_TARGET)
	var ok: bool = false
	if String(res["slot_kind"]) == EquipmentPolicyClass.SLOT_KIND_WEAPON:
		ok = lo.set_weapon_slot(int(res["slot_index"]), item_id)
	else:
		ok = lo.set_armor_slot(String(res["slot_name"]), item_id)
	if not ok:
		return _r.reject(NP.ERR_INVALID_TARGET)
	var evt := {
		"event": NP.EVT_EQUIPMENT_CHANGED,
		"peer_id": peer_id,
		"item_id": item_id,
		"slot_kind": res["slot_kind"],
		"slot_index": res["slot_index"],
		"slot_name": res["slot_name"],
	}
	return {"success": true, "event": evt, "error_code": ""}

## 装备策略数据源（P0-4）：从 WeaponRegistry 解析物品类别/手位/护甲部位。
## 可由测试注入 stub（headless 无 autoload）。
func equipment_data_source() -> Callable:
	if equipment_data_source_custom.is_valid():
		return equipment_data_source_custom
	var reg: Object = _r.weapon_registry()
	if reg == null or not reg.has_method("get_weapon_data"):
		return EquipmentPolicyClass.DEFAULT_DATA_SOURCE
	return func(item_id: String) -> Dictionary:
		var wd = reg.get_weapon_data(item_id)
		if wd == null:
			return {}
		return {"category": String(wd.equipment_category), "hands": String(wd.hands),
			"armor_slot": String(wd.armor_slot)}

# ============================================================================
# 丢弃
# ============================================================================

## 客户端请求丢弃物品（CMD_DROP）：服务器权威夹紧丢弃数量到【玩家实际持有量】
## （绝不信任客户端自报的 drop_amount/绝对数量），从背包移除后于玩家服务器权威
## 坐标生成可拾取的掉落实体。
func handle_drop(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	if not _r.seq_tracker().accept(peer_id, int(command.get("sequence", 0))):
		return _r.reject(NP.ERR_INVALID_SEQUENCE)
	var item_id: String = String(command.get("item_id", ""))
	var cat: String = String(command.get("category", "material"))  # material / rune / equipment
	var inv = ctx.inventory
	var held: int = 0
	match cat:
		"material": held = int(inv.materials.get(item_id, 0))
		"rune": held = int(inv.runes.get(item_id, 0))
		"equipment": held = int(inv.equipment.get(item_id, 0))
		_: return _r.reject(NP.ERR_INVALID_TARGET)
	if held <= 0:
		return _r.reject(NP.ERR_INVALID_TARGET)
	# 夹紧：丢弃量 ∈ [1, 实际持有]，拒绝任何超过持有的请求（防无限复制）。
	var requested: int = int(command.get("amount", 1))
	var amount: int = mini(maxi(requested, 1), held)
	match cat:
		"material": inv.remove_material(item_id, amount)
		"rune": inv.remove_rune(item_id, amount)
		"equipment": inv.remove_equipment(item_id, amount)
	var pos: Vector3 = _r.live_state().get(peer_id, {}).get("position", Vector3.ZERO)
	var lid: int = _r.next_loot_seq()
	var data: Dictionary = {
		"kind": "loot", "label": item_id, "position": pos,
		"item_id": item_id, "item_kind": cat, "amount": amount,
		"current_life": 0, "max_life": 0, "consumed": false,
	}
	var res: Dictionary = _r.set_entity(lid, data)
	var extra: Array = []
	if res.has("event") and not res["event"].is_empty():
		extra.append(res["event"])
	var evt := {
		"event": NP.EVT_INVENTORY_CHANGED,
		"peer_id": peer_id,
		"item_id": item_id, "category": cat, "amount": -amount,
	}
	return {"success": true, "event": evt, "error_code": "", "extra_events": extra}
