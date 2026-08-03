class_name Chest
extends StaticBody3D

const DUNGEON_SPAWN_FOOTPRINT := preload("res://scenes/expedition/dungeon_spawn_footprint.gd")

# Loot uses a deterministic square-ring search instead of random offsets. The
# 1.30m spacing clears the conservative item AABB and the normal chest AABB;
# later rings keep searching when a room has more loot or nearby decor.
const LOOT_GRID_SPACING := 1.30
const LOOT_GRID_MAX_RING := 6

## 宝箱当前所在区域（BrewingData.Zone 枚举值）。
## 由 procedural_dungeon 在放置宝箱时注入，决定材料掉落池。
@export var zone: int = 0  # 默认森林

## 掉落倍率。普通箱 1；boss 奖励大箱 3（见 boss_chest.tscn）。
## 影响材料轮数与装备抽取次数；主武器字段仍保留 "weapon" 以兼容旧 UI。
@export var loot_multiplier: int = 1

var is_opened := false

## 交互开启时生成的战利品数据（由 chest_loot_panel 读取）。
## 结构: {
##   "weapon": WeaponData|null,           # 首件装备（兼容旧面板）
##   "weapons": Array[WeaponData],        # 全部装备（倍率>1 时多件）
##   "materials": Array[Dictionary],
##   "runes": Array[Dictionary]
## }
var loot_data: Dictionary = {}

## 宝箱是否已展示战利品面板（面板关闭后销毁宝箱）。
var _loot_panel_open := false

func can_interact() -> bool:
	return not is_opened

func try_receive_hit(_source_player: Node, _damage: int) -> void:
	open_chest()

func try_receive_furniture_impact(_thrown_item: RigidBody3D) -> void:
	open_chest()

func interact(_source_player: Node = null) -> void:
	open_chest(true)

func open_chest(by_interact: bool = false) -> void:
	if is_opened:
		return
	is_opened = true

	# Play chest opening/breaking sound
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if is_inside_tree() else null
	if audio_mgr:
		audio_mgr.play("barrel-destroy", null)

	if by_interact:
		# 交互开启：生成战利品数据，显示 UI 面板，不生成物理掉落物
		_generate_loot_data()
		_loot_panel_open = true
		GameEvents.chest_opened.emit(self)
	else:
		# 攻击破坏：保留原行为，直接生成物理掉落物
		_spawn_loot_physical()
		queue_free()

## 生成战利品数据（存储到 loot_data 供 UI 读取）
func _generate_loot_data() -> void:
	var loot_table: Node = get_tree().root.get_node_or_null("LootTable") if is_inside_tree() else null
	if loot_table == null:
		push_warning("[Chest] LootTable autoload not found, no loot dropped")
		loot_data = {"weapon": null, "weapons": [], "materials": [], "runes": []}
		return
	var mult := maxi(loot_multiplier, 1)
	var weapons: Array = []
	var materials: Array = []
	var runes: Array = []
	for _i in range(mult):
		var drop = loot_table.generate_loot(zone)
		if not drop.weapon.is_empty():
			var weapon_data = drop.weapon.get("weapon_data", null)
			if weapon_data:
				weapons.append(weapon_data)
				var affix_str := ""
				if weapon_data.affixes.size() > 0:
					affix_str = " [%s]" % ", ".join(weapon_data.affixes)
				print("[Chest] Loot equipment: %s (tier %d: %s)%s" % [
					drop.weapon.get("id", "?"),
					drop.weapon.get("tier_index", 0),
					drop.weapon.get("tier_name", "?"),
					affix_str,
				])
		materials.append_array(drop.materials.duplicate())
		runes.append_array(drop.runes.duplicate(true))
	loot_data = {
		"weapon": weapons[0] if not weapons.is_empty() else null,
		"weapons": weapons,
		"materials": materials,
		"runes": runes,
	}

## 战利品面板关闭时调用：如果还有剩余物品则丢弃到地面，然后销毁宝箱
func close_loot_panel() -> void:
	_loot_panel_open = false
	# 将未取走的物品生成为物理掉落物
	if not loot_data.is_empty():
		_spawn_remaining_loot()
	queue_free()

## 将剩余战利品生成为物理掉落物（面板关闭时未取走的物品）
func _spawn_remaining_loot() -> void:
	var pickable_scene = load("res://scenes/equipment/pickable_item.tscn")
	if pickable_scene == null:
		return
	var registry: Array = _loot_spawn_registry()
	var drop_index := 0
	# 剩余装备：优先 weapons 数组，兼容旧 weapon 单字段
	var remaining_weapons: Array = loot_data.get("weapons", [])
	if remaining_weapons.is_empty():
		var single = loot_data.get("weapon", null)
		if single != null:
			remaining_weapons = [single]
	for weapon_data in remaining_weapons:
		if weapon_data == null:
			continue
		var p_item = pickable_scene.instantiate()
		p_item.weapon_data = weapon_data
		if _place_loot_item(p_item, registry, drop_index, "weapon"):
			drop_index += 1
	# 剩余材料
	var remaining_materials: Array = loot_data.get("materials", [])
	for mat_entry in remaining_materials:
		var mat_id: String = mat_entry.get("material_id", "")
		if mat_id == "":
			continue
		var p_item = pickable_scene.instantiate()
		p_item.material_id = mat_id
		if _place_loot_item(p_item, registry, drop_index, "material:%s" % mat_id):
			drop_index += 1
			print("[Chest] Dropped remaining material: %s" % mat_id)
	# 剩余符文
	var remaining_runes: Array = loot_data.get("runes", [])
	for rune_entry in remaining_runes:
		var rune_id: String = rune_entry.get("id", "")
		if rune_id == "":
			continue
		var p_item = pickable_scene.instantiate()
		p_item.rune_id = rune_id
		if _place_loot_item(p_item, registry, drop_index, "rune:%s" % rune_id):
			drop_index += 1
			print("[Chest] Dropped remaining rune: %s" % rune_id)

## Find the shared dungeon registry when this chest belongs to a generated level.
## Non-dungeon chests still get a local registry so their own drops never overlap.
func _loot_spawn_registry() -> Array:
	var node: Node = self
	while node != null:
		var build_result = node.get("build_result")
		if build_result != null:
			var footprints: Variant = build_result.get("spawn_footprints")
			if footprints is Array:
				return footprints
		node = node.get_parent()
	return []

## Place one loot item at the first free deterministic square-ring position.
## The item is registered before it enters the tree, so the next drop sees it.
func _place_loot_item(item: Node3D, registry: Array, ordinal: int, label: String) -> bool:
	if item == null or get_parent() == null:
		if item != null:
			_discard_unparented_item(item)
		return false
	var world_position = _find_loot_position(registry, ordinal)
	if world_position == null:
		push_warning("[Chest] skipped overlapping loot drop: %s" % label)
		_discard_unparented_item(item)
		return false
	if get_parent() is Node3D:
		item.position = (get_parent() as Node3D).to_local(world_position)
	else:
		item.global_position = world_position
	DUNGEON_SPAWN_FOOTPRINT.register(registry, world_position,
		DUNGEON_SPAWN_FOOTPRINT.half_extents_for("item", label), "chest_loot:%s" % label)
	get_parent().add_child(item)
	return true

func _discard_unparented_item(item: Node3D) -> void:
	if item.is_inside_tree():
		item.queue_free()
	else:
		item.free()

## Deterministic square-ring candidates; no random state means replay/debug runs
## produce the same spread and tests can prove the non-overlap contract.
func _find_loot_position(registry: Array, ordinal: int):
	var candidate_index := 0
	var origin := global_position if is_inside_tree() else position
	for ring in range(1, LOOT_GRID_MAX_RING + 1):
		for x in range(-ring, ring + 1):
			for z in range(-ring, ring + 1):
				if maxi(absi(x), absi(z)) != ring:
					continue
				var offset := Vector3(float(x) * LOOT_GRID_SPACING, 0.34,
					float(z) * LOOT_GRID_SPACING)
				var candidate := origin + offset
				if DUNGEON_SPAWN_FOOTPRINT.can_place(registry, candidate,
					DUNGEON_SPAWN_FOOTPRINT.half_extents_for("item", "chest_loot")):
					if candidate_index >= ordinal:
						return candidate
					candidate_index += 1
	return null

## 攻击破坏时直接生成物理掉落物（保留原行为）
func _spawn_loot_physical() -> void:
	var loot_table: Node = get_tree().root.get_node_or_null("LootTable") if is_inside_tree() else null
	if loot_table == null:
		push_warning("[Chest] LootTable autoload not found, no loot dropped")
		return
	var pickable_scene = load("res://scenes/equipment/pickable_item.tscn")
	if pickable_scene == null:
		push_warning("[Chest] pickable_item.tscn not found")
		return

	var registry: Array = _loot_spawn_registry()
	var drop_index := 0
	var mult := maxi(loot_multiplier, 1)
	for _i in range(mult):
		var drop = loot_table.generate_loot(zone)
		# 1. 装备掉落（含 tier 阶位 + 词缀，攻击与交互均掉）
		if not drop.weapon.is_empty():
			var weapon_data = drop.weapon.get("weapon_data", null)
			if weapon_data:
				var p_item = pickable_scene.instantiate()
				p_item.weapon_data = weapon_data
				var placed := _place_loot_item(p_item, registry, drop_index, "weapon")
				if placed:
					drop_index += 1
				var affix_str := ""
				if weapon_data.affixes.size() > 0:
					affix_str = " [%s]" % ", ".join(weapon_data.affixes)
				print("[Chest] Dropped equipment: %s (tier %d: %s)%s" % [
					drop.weapon.get("id", "?"),
					drop.weapon.get("tier_index", 0),
					drop.weapon.get("tier_name", "?"),
					affix_str,
				])
		# 2. 材料掉落：仅交互开启时掉落（攻击破坏会毁损材料，保留原设计语义）
		for rune_entry in drop.runes:
			var rune_id: String = rune_entry.get("id", "")
			if rune_id == "":
				continue
			var p_item = pickable_scene.instantiate()
			p_item.rune_id = rune_id
			if _place_loot_item(p_item, registry, drop_index, "rune:%s" % rune_id):
				drop_index += 1
				print("[Chest] Dropped rune: %s" % rune_id)
	print("[Chest] Melee attack destroyed all brewing materials! (Only weapon dropped)")
