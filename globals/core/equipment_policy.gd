class_name EquipmentPolicy
extends RefCounted

## EquipmentPolicy —— 装备命令的唯一策略真相（架构审查 P0-4）。
##
## 背景：服务器曾只要「物品在背包任一字典」就写入 loadout 槽位——材料/符文可被装进
## 武器槽污染权威 loadout（影响攻击上下文/施法资格/存档/结算）；客户端与服务器槽位
## 协议也不一致（客户端 slot 固定 String，服务器武器槽要求 int）。
##
## 本策略从权威注册表解析物品类别、槽位兼容与占槽关系（双手/盾互斥、唯一性），
## 并把协议统一为明确 slot_kind("weapon"/"armor") + slot_index(int)/slot_name(String)。
## 纯逻辑、无场景树依赖；物品元数据经 data_source Callable 注入（WeaponRegistry 或测试 stub）。

const SLOT_KIND_WEAPON := "weapon"
const SLOT_KIND_ARMOR := "armor"

## 数据源契约：func(item_id:String) -> {category:String, hands:String, armor_slot:String}。
## 未知物品返回空字典（调用方应视为「非装备」拒绝）。
const DEFAULT_DATA_SOURCE := Callable()

## 解析物品类别元数据。data_source 为空时返回 {}（headless 无注册表 → 未知）。
static func item_meta(item_id: String, data_source: Callable) -> Dictionary:
	if data_source.is_valid():
		var meta = data_source.call(item_id)
		if meta is Dictionary and not (meta as Dictionary).is_empty():
			return meta
	return {}

## 是否为可装备类别（weapons / shields / armor_*；材料与符文不是装备）。
static func is_equippable(meta: Dictionary) -> bool:
	var category := String(meta.get("category", ""))
	return category == "weapons" or category == "shields" or category.begins_with("armor")

## 解析装备目标槽位（唯一策略真相）：
##   slot_kind 为空时按物品类别自动判定；slot_index/slot_name 由调用方从协议解析
##   （自动槽位时传 -1/""）。
## loadout: EquipmentLoadout（占槽关系校验用：双手/盾互斥、唯一性）。
## 返回 {ok:bool, error_code:String, slot_kind:String, slot_index:int, slot_name:String,
##        category:String, hands:String}。
static func resolve(item_id: String, slot_kind: String, slot_index: int, slot_name: String,
		loadout: Object, data_source: Callable) -> Dictionary:
	var meta := item_meta(item_id, data_source)
	var category := String(meta.get("category", ""))
	var hands := String(meta.get("hands", ""))
	if not is_equippable(meta):
		# 材料/符文/未知物品一律拒绝——绝不进入 loadout 槽位。
		return _fail(item_id, category, hands)
	var kind: String = slot_kind
	if kind.is_empty():
		kind = SLOT_KIND_WEAPON if (category == "weapons" or category == "shields") else SLOT_KIND_ARMOR
	if kind == SLOT_KIND_WEAPON:
		if category.begins_with("armor"):
			return _fail(item_id, category, hands)
		return _resolve_weapon(item_id, category, hands, slot_index, loadout, data_source)
	if kind == SLOT_KIND_ARMOR:
		if not category.begins_with("armor"):
			return _fail(item_id, category, hands)
		var target_name := slot_name
		if target_name.is_empty():
			target_name = String(meta.get("armor_slot", "body"))
		# P0-2：护甲固有部位校验——单部位护甲必须等于 meta.armor_slot；
		# 未来多部位装备须显式声明 armor_slots 数组（未声明则只允许固有部位）。
		var intrinsic := String(meta.get("armor_slot", ""))
		var allowed: Array = meta.get("armor_slots", [])
		var allowed_match: bool = allowed is Array and allowed.size() > 0 and target_name in allowed
		if not allowed_match and target_name != intrinsic:
			return _fail(item_id, category, hands)
		if not target_name in EquipmentLoadout.VALID_ARMOR_SLOTS:
			return _fail(item_id, category, hands)
		return {"ok": true, "error_code": "", "slot_kind": SLOT_KIND_ARMOR,
			"slot_index": -1, "slot_name": target_name, "category": category, "hands": hands}
	return _fail(item_id, category, hands)

## 武器槽占槽规则（唯一策略真相）：
##   * 双手武器 ↔ 盾 互斥（同 loadout 不得共存）；
##   * 双手武器最多一把；
##   * 盾最多一面。
## 现有槽内容经同一 data_source 解析类别（不靠 id 字符串猜测）。
static func _resolve_weapon(item_id: String, category: String, hands: String, slot_index: int,
		loadout: Object, data_source: Callable) -> Dictionary:
	var count: int = int(loadout.WEAPON_SLOT_COUNT) if "WEAPON_SLOT_COUNT" in loadout else 4
	if slot_index < 0 or slot_index >= count:
		return _fail(item_id, category, hands)
	var is_two_hand: bool = hands == "two_hand"
	var is_shield: bool = category == "shields"
	for i in range(count):
		if i == slot_index:
			continue
		var existing := String(loadout.get_weapon_slot(i)) if loadout.has_method("get_weapon_slot") else ""
		if existing.is_empty():
			continue
		var em := item_meta(existing, data_source)
		var existing_category := String(em.get("category", ""))
		var existing_hands := String(em.get("hands", ""))
		if is_two_hand and existing_category == "shields":
			return _fail(item_id, category, hands)  # 双手 ↔ 盾 互斥（正向）
		if is_shield and existing_hands == "two_hand":
			return _fail(item_id, category, hands)  # 双手 ↔ 盾 互斥（反向）
		if is_shield and existing_category == "shields":
			return _fail(item_id, category, hands)  # 最多一面盾
		if is_two_hand and existing_category == "weapons" and existing_hands == "two_hand":
			return _fail(item_id, category, hands)  # 双手武器唯一
	return {"ok": true, "error_code": "", "slot_kind": SLOT_KIND_WEAPON,
		"slot_index": slot_index, "slot_name": "", "category": category, "hands": hands}

static func _fail(item_id: String, category: String, hands: String) -> Dictionary:
	return {"ok": false, "error_code": "INVALID_TARGET", "slot_kind": "",
		"slot_index": -1, "slot_name": "", "category": category, "hands": hands}
