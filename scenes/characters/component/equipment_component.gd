class_name EquipmentComponent
extends Node3D

const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")
const PICKABLE_ITEM_PREFAB := preload("res://scenes/equipment/pickable_item.tscn")
const THROWN_ITEM_PREFAB := preload("res://scenes/equipment/thrown_item.tscn")
const Service := preload("res://globals/core/service.gd")

@export var furniture_data: FurnitureData
@export var furniture_placeholder: Node3D
@export var is_always_in_front: bool
@export var is_linked_to_ui: bool
@export var shield_data: ShieldData
@export var shield_placeholder: Node3D
@export var weapon_data: WeaponData
@export var weapon_slots: Array[WeaponData] = []
@export var active_weapon_slot: int = 0
@export var weapon_placeholder: Node3D
@export var weapon_reach_raycast: RayCast3D
@export var weapon_spawn_position: Node3D
@export var armor_head_placeholder: Node3D
@export var armor_body_placeholder: Node3D
@export var armor_hand_l_placeholder: Node3D
@export var armor_hand_r_placeholder: Node3D
@export var armor_foot_l_placeholder: Node3D
@export var armor_foot_r_placeholder: Node3D

var _mounted_weapon_instance: EquipedItem
var _mounted_armor_instances: Dictionary = {}

const WEAPON_SLOT_COUNT := 4
const DEFAULT_WEAPON_REACH := -1.4
const ARMOR_SLOT_NAMES := ["head", "body", "hands", "feet"]

@export var armor_slots: Dictionary = {
	"head": null,
	"body": null,
	"hands": null,
	"feet": null,
}

func _ready() -> void:
	_ensure_weapon_slots()
	_ensure_armor_slots()
	if weapon_data != null:
		weapon_data = WeaponRegistry.resolve_weapon_data(weapon_data)
		configure_weapon_slot(active_weapon_slot, weapon_data, true)
	if shield_data != null:
		equip_shield(shield_data)
	for slot_name in ARMOR_SLOT_NAMES:
		var slot_data: WeaponData = armor_slots.get(slot_name, null)
		if slot_data != null:
			armor_slots[slot_name] = WeaponRegistry.resolve_weapon_data(slot_data)
			_remount_armor_slot(slot_name)

func equip_weapon(data: WeaponData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> bool:
	if data == null:
		return false
	_ensure_weapon_slots()
	var target_slot := get_first_empty_weapon_slot()
	if target_slot == -1:
		target_slot = active_weapon_slot
		if weapon_slots[target_slot] != null:
			_spawn_dropped_weapon(
				weapon_slots[target_slot],
				_fallback_drop_transform(get_active_weapon_placeholder()),
				true,
			)
	return configure_weapon_slot(target_slot, data, true, pickup_transform)

func configure_weapon_slot(slot_index: int, data: WeaponData, make_active: bool = true, pickup_transform: Transform3D = Transform3D.IDENTITY) -> bool:
	_ensure_weapon_slots()
	if slot_index < 0 or slot_index >= WEAPON_SLOT_COUNT:
		return false
	if data != null and not _is_hand_equipment(data):
		return false
	weapon_slots[slot_index] = data.duplicate() if data != null else null
	if make_active or slot_index == active_weapon_slot:
		return activate_weapon_slot(slot_index, pickup_transform)
	return true

func activate_weapon_slot(slot_index: int, pickup_transform: Transform3D = Transform3D.IDENTITY) -> bool:
	_ensure_weapon_slots()
	if slot_index < 0 or slot_index >= WEAPON_SLOT_COUNT:
		return false
	_clear_current_weapon_mount()
	active_weapon_slot = slot_index
	weapon_data = weapon_slots[active_weapon_slot]
	if weapon_data == null:
		_reset_weapon_reach()
		if is_linked_to_ui:
			GameEvents.weapon_changed.emit(null)
			GameEvents.shield_changed.emit(get_active_shield_data())
		return true
	_mount_weapon_to_hand(pickup_transform)
	if is_linked_to_ui:
		GameEvents.shield_changed.emit(get_active_shield_data())
	return true

func cycle_weapon_slot(direction: int) -> bool:
	_ensure_weapon_slots()
	if direction == 0 or get_configured_weapon_count() == 0:
		return false
	var step := 1 if direction > 0 else -1
	var start_slot := active_weapon_slot
	for i in range(WEAPON_SLOT_COUNT):
		var candidate := posmod(active_weapon_slot + step * (i + 1), WEAPON_SLOT_COUNT)
		if weapon_slots[candidate] != null:
			if candidate == start_slot:
				return false
			return activate_weapon_slot(candidate)
	return false

func get_first_empty_weapon_slot() -> int:
	_ensure_weapon_slots()
	for i in range(WEAPON_SLOT_COUNT):
		if weapon_slots[i] == null:
			return i
	return -1

func get_configured_weapon_count() -> int:
	_ensure_weapon_slots()
	var count := 0
	for slot_data in weapon_slots:
		if slot_data != null:
			count += 1
	return count

func get_weapon_slot_data(slot_index: int) -> WeaponData:
	_ensure_weapon_slots()
	if slot_index < 0 or slot_index >= WEAPON_SLOT_COUNT:
		return null
	return weapon_slots[slot_index]

func get_weapon_slot_label(slot_index: int) -> String:
	var slot_data := get_weapon_slot_data(slot_index)
	if slot_data == null:
		return "空"
	return slot_data.name

func configure_armor_slot(slot_name: String, data: WeaponData) -> bool:
	_ensure_armor_slots()
	if not armor_slots.has(slot_name):
		return false
	if data != null and not _is_armor_equipment(data):
		return false
	if data != null and not String(data.armor_slot).is_empty() and data.armor_slot != slot_name:
		return false
	armor_slots[slot_name] = data.duplicate() if data != null else null
	_remount_armor_slot(slot_name)
	return true


## 装备护甲到对应护甲槽（拾取入口）。槽位已占用时把旧护甲掉落到拾取点附近。
## 与 equip_weapon 对称：护甲分流入口，避免护甲走 equip_weapon 被 _is_hand_equipment 拒绝。
func equip_armor(data: WeaponData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> bool:
	if data == null:
		return false
	if not _is_armor_equipment(data):
		return false
	_ensure_armor_slots()
	var target_slot := String(data.armor_slot)
	if target_slot.is_empty():
		target_slot = "body"
	if not armor_slots.has(target_slot):
		return false
	var existing: WeaponData = armor_slots.get(target_slot, null)
	if existing != null:
		# 与 equip_weapon 丢旧武器对称：旧护甲掉落到拾取点，避免直接覆盖丢失
		_spawn_dropped_weapon(existing, pickup_transform, true)
	return configure_armor_slot(target_slot, data)


## 判定数据是否为护甲（公开接口，供拾取/UI 流程分流，避免护甲误走武器槽被拒）
func is_armor_equipment(data: WeaponData) -> bool:
	return _is_armor_equipment(data)


func equip_armor_set(set_id: String) -> int:
	## Equip every registered armor piece belonging to set_id. Returns count equipped.
	if set_id.is_empty() or WeaponRegistry == null:
		return 0
	var equipped := 0
	for armor_id in WeaponRegistry.get_all_ids():
		var meta: Dictionary = WeaponRegistry.get_entry_meta(armor_id)
		if String(meta.get("set_id", "")) != set_id:
			continue
		var data: WeaponData = WeaponRegistry.get_weapon_data(armor_id)
		if data == null:
			continue
		var slot_name := String(data.armor_slot)
		if slot_name.is_empty():
			continue
		if configure_armor_slot(slot_name, data):
			equipped += 1
	return equipped

func get_armor_slot_data(slot_name: String) -> WeaponData:
	_ensure_armor_slots()
	if not armor_slots.has(slot_name):
		return null
	return armor_slots[slot_name]

func get_armor_slot_label(slot_name: String) -> String:
	var slot_data := get_armor_slot_data(slot_name)
	if slot_data == null:
		return "空"
	return slot_data.name

func get_equipped_armor_items() -> Array[WeaponData]:
	_ensure_armor_slots()
	var result: Array[WeaponData] = []
	for slot_name in ARMOR_SLOT_NAMES:
		var slot_data: WeaponData = armor_slots.get(slot_name, null)
		if slot_data != null:
			result.append(slot_data)
	return result

func get_armor_defense() -> int:
	var total := 0
	for armor in get_equipped_armor_items():
		total += armor.armor_phys_def
	return total

func get_armor_move_speed_mult() -> float:
	var mult := 1.0
	for armor in get_equipped_armor_items():
		mult *= armor.armor_move_speed_mult
	return mult

func _mount_weapon_to_hand(pickup_transform: Transform3D = Transform3D.IDENTITY) -> void:
	var target_placeholder := get_active_weapon_placeholder()
	if target_placeholder == null:
		return
	var weapon := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	if weapon == null:
		push_error("EquipmentComponent: failed to instantiate EquipedItem")
		return
	weapon.weapon_data = weapon_data
	weapon.is_always_in_front = is_always_in_front
	target_placeholder.add_child(weapon)
	_mounted_weapon_instance = weapon
	if weapon_reach_raycast != null:
		weapon_reach_raycast.target_position.z = -maxf(weapon_data.reach * CombatHitboxBuilder.REACH_SCALE, 0.8)
	if is_linked_to_ui:
		GameEvents.weapon_changed.emit(weapon_data)
	if pickup_transform != Transform3D.IDENTITY:
		weapon.global_transform = pickup_transform
		animate_to_hand(weapon)
		
func equip_shield(data: ShieldData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if data == null or shield_placeholder == null:
		return
	if has_shield():
		drop_shield()
	shield_data = data.duplicate()
	var shield := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	if shield == null:
		push_error("EquipmentComponent: failed to instantiate EquipedItem for shield")
		return
	shield.shield_data = shield_data
	shield.is_always_in_front = is_always_in_front
	shield_placeholder.add_child(shield)
	if is_linked_to_ui:
		GameEvents.shield_changed.emit(shield_data)
	if pickup_transform != Transform3D.IDENTITY:
		shield.global_transform = pickup_transform
		animate_to_hand(shield)

func equip_furniture(data: FurnitureData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if has_shield():
		hide_shield()
	if has_weapon():
		hide_weapon()
	furniture_data = data.duplicate()
	var furniture := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	if furniture == null:
		push_error("EquipmentComponent: failed to instantiate EquipedItem for furniture")
		return
	furniture.furniture_data = furniture_data
	furniture.is_always_in_front = is_always_in_front
	furniture_placeholder.add_child(furniture)
	if pickup_transform != Transform3D.IDENTITY:
		furniture.global_transform = pickup_transform
		animate_to_hand(furniture)

func animate_to_hand(equiped_item: Node3D) -> void:
	var tween := equiped_item.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(equiped_item, "position", Vector3.ZERO, 0.4)
	tween.parallel().tween_property(equiped_item, "rotation", Vector3.ZERO, 0.2)

func has_shield() -> bool:
	if _is_shield_weapon(weapon_data):
		return true
	return shield_data != null and shield_placeholder != null and shield_placeholder.get_child_count() > 0

func get_active_shield_data():
	if _is_shield_weapon(weapon_data):
		return weapon_data
	return shield_data if has_shield() else null

func hide_shield() -> void:
	if shield_placeholder != null:
		shield_placeholder.visible = false

func show_shield() -> void:
	if shield_placeholder != null:
		shield_placeholder.visible = true

func has_furniture() -> bool:
	return furniture_data != null and furniture_placeholder != null and furniture_placeholder.get_child_count() > 0

func has_weapon() -> bool:
	var mount := get_active_weapon_placeholder()
	return weapon_data != null and not _is_shield_weapon(weapon_data) and (mount == null or mount.get_child_count() > 0)

func has_hand_equipment() -> bool:
	var mount := get_active_weapon_placeholder()
	return weapon_data != null and (mount == null or mount.get_child_count() > 0)

## 活动武器实例所在的骨骼挂点。主手使用 Hand.R，盾牌/副手武器使用 Hand.L。
func get_active_weapon_placeholder() -> Node3D:
	if _weapon_uses_off_hand(weapon_data):
		return shield_placeholder
	return weapon_placeholder

func hide_weapon() -> void:
	var mount := get_active_weapon_placeholder()
	if mount != null:
		mount.visible = false

func show_weapon() -> void:
	var mount := get_active_weapon_placeholder()
	if mount != null:
		mount.visible = true

func throw_weapon(is_being_dropped: bool = false, aim_point: Vector3 = Vector3.ZERO) -> void:
	var mount := get_active_weapon_placeholder()
	if weapon_data != null and (mount == null or mount.get_child_count() > 0):
		var was_shield := _is_shield_weapon(weapon_data)
		var spawn_transform := _fallback_drop_transform(mount)
		if not is_being_dropped and weapon_spawn_position != null and is_instance_valid(weapon_spawn_position):
			var muzzle_pos := weapon_spawn_position.global_position
			if aim_point != Vector3.ZERO:
				# 朝准心点发射投掷武器
				var dir := aim_point - muzzle_pos
				if dir.length_squared() > 0.25:
					var up := Vector3.UP
					if absf(dir.normalized().dot(Vector3.UP)) > 0.99:
						up = Vector3.FORWARD
					var t := Transform3D(Basis(), muzzle_pos)
					spawn_transform = t.looking_at(aim_point, up)
				else:
					spawn_transform = weapon_spawn_position.global_transform
			else:
				spawn_transform = weapon_spawn_position.global_transform
		_spawn_dropped_weapon(weapon_data, spawn_transform, is_being_dropped)
		_clear_current_weapon_mount()
		weapon_slots[active_weapon_slot] = null
		weapon_data = null
		_clear_weapon_placeholder()
		_reset_weapon_reach()
		if is_linked_to_ui:
			GameEvents.weapon_changed.emit(weapon_data)
			if was_shield:
				GameEvents.shield_changed.emit(null)
	# 武器离开玩家后必须固化到 GameState，否则场景重载/玩家重注册时
	# apply_equipment_to_player 会从过期的 weapon_slot_ids 恢复已丢弃的武器，
	# 造成"打开 Tab 后主手复制出一把武器"的 bug。
	_persist_equipment_state()

func throw_furniture(is_being_dropped: bool = false) -> void:
	if has_furniture():
		var level: Node = null
		if GameState != null and "current_level" in GameState:
			level = GameState.current_level
		if level == null or not is_instance_valid(level):
			push_warning("EquipmentComponent: current_level 不可用，无法丢弃家具")
			return
		if not level.is_inside_tree():
			return
		var thrown_item := THROWN_ITEM_PREFAB.instantiate()
		thrown_item.furniture_data = furniture_data
		thrown_item.is_being_dropped = is_being_dropped
		thrown_item.source = get_parent() as CollisionObject3D
		var spawn_transform := furniture_placeholder.global_transform
		thrown_item.global_transform = spawn_transform
		level.add_child(thrown_item)
		furniture_data = null
		furniture_placeholder.get_child(0).queue_free()
		# 武器可见性恢复由调用方决定（throw 状态机在动画结束后恢复，drop 立即恢复）

func drop_furniture() -> void:
	throw_furniture(true)
	show_weapon()
	show_shield()

func drop_weapon() -> void:
	throw_weapon(true)

func drop_shield() -> void:
	if _is_shield_weapon(weapon_data):
		drop_weapon()
		return
	if has_shield():
		var level: Node = null
		if GameState != null and "current_level" in GameState:
			level = GameState.current_level
		if level == null or not is_instance_valid(level):
			push_warning("EquipmentComponent: current_level 不可用，无法丢弃盾牌")
			return
		if not level.is_inside_tree():
			return
		var spawn_transform := _fallback_drop_transform(shield_placeholder)
		_spawn_pickable_drop(level, spawn_transform, null, shield_data)
		shield_data = null
		if shield_placeholder != null and is_instance_valid(shield_placeholder) and shield_placeholder.get_child_count() > 0:
			shield_placeholder.get_child(0).queue_free()
		if is_linked_to_ui:
			GameEvents.shield_changed.emit(shield_data)
	# 盾牌离开玩家后同样需要固化到 GameState，防止场景重载时被恢复。
	_persist_equipment_state()

## 将当前装备状态固化到 GameState。
## 在武器/盾牌离开玩家（投掷、丢弃、损坏）后调用，确保 GameState 的
## weapon_slot_ids / armor_slot_ids 与 EquipmentComponent 一致，
## 避免 apply_equipment_to_player 从过期数据恢复已离手的装备。
func _persist_equipment_state() -> void:
	if GameState != null and GameState.has_method("save_equipment_from_player"):
		var player := get_parent()
		if player != null:
			GameState.save_equipment_from_player(player)

func apply_weapon_damage(amount: int) -> void:
	# 符文之语「无耗之语」：远程武器不消耗耐久
	if _has_mechanism_passive("rune_word_ranged_no_wear") and is_active_weapon_ranged():
		return
	# 符文之语「神盾之语」：盾牌武器不消耗耐久
	if _has_mechanism_passive("rune_word_shield_no_wear") and _is_shield_weapon(weapon_data):
		return
	var mount := get_active_weapon_placeholder()
	if weapon_data != null and (mount == null or mount.get_child_count() > 0):
		weapon_data.decrease_condition(amount)
		if weapon_data.condition <= 0:
			drop_weapon()
		else:
			weapon_slots[active_weapon_slot] = weapon_data
			GameEvents.weapon_changed.emit(weapon_data)
			if _is_shield_weapon(weapon_data):
				GameEvents.shield_changed.emit(weapon_data)
func apply_shield_damage(amount: int) -> void:
	# 符文之语「神盾之语」：盾牌不消耗耐久
	if _has_mechanism_passive("rune_word_shield_no_wear"):
		return
	if _is_shield_weapon(weapon_data):
		apply_weapon_damage(amount)
		if is_linked_to_ui:
			GameEvents.shield_changed.emit(weapon_data)
		return
	if has_shield():
		shield_data.decrease_condition(amount)
		if shield_data.condition <= 0:
			drop_shield()
		GameEvents.shield_changed.emit(shield_data)

func apply_armor_damage(slot_name: String, amount: int) -> bool:
	var armor := get_armor_slot_data(slot_name)
	if armor == null:
		return false
	armor.decrease_condition(amount)
	return true

## 查询玩家是否拥有某机制类被动（用于符文之语耐久豁免）。
## 通过 SkillRuntime autoload 查询，无则返回 false。
func _has_mechanism_passive(id: String) -> bool:
	var sr: Node = Service.skill_runtime()
	if sr != null and sr.has_method("has_mechanism_passive"):
		return sr.has_mechanism_passive(id)
	return false

func _ensure_weapon_slots() -> void:
	while weapon_slots.size() < WEAPON_SLOT_COUNT:
		weapon_slots.append(null)
	if weapon_slots.size() > WEAPON_SLOT_COUNT:
		weapon_slots.resize(WEAPON_SLOT_COUNT)
	active_weapon_slot = clampi(active_weapon_slot, 0, WEAPON_SLOT_COUNT - 1)

func _remount_armor_slot(slot_name: String) -> void:
	_clear_armor_slot_mounts(slot_name)
	var data: WeaponData = get_armor_slot_data(slot_name)
	if data == null or data.glb_mesh == null:
		return
	var placeholders := _armor_placeholders_for_slot(slot_name)
	if placeholders.is_empty():
		return
	var ArmorMount := preload("res://globals/visual/armor_mount_profile.gd")
	var VoxelLighting := preload("res://globals/visual/voxel_lighting_adapter.gd")
	for entry in placeholders:
		var placeholder: Node3D = entry.get("node", null)
		var side := String(entry.get("side", ""))
		if placeholder == null or not is_instance_valid(placeholder):
			continue
		var inst: Node3D = data.glb_mesh.instantiate() as Node3D
		if inst == null:
			continue
		placeholder.add_child(inst)
		inst.transform = ArmorMount.local_transform(slot_name, side)
		VoxelLighting.apply_weapon_tree(inst, data.material_tier)
		_set_armor_render_layer(inst)
		if not _mounted_armor_instances.has(slot_name):
			_mounted_armor_instances[slot_name] = []
		(_mounted_armor_instances[slot_name] as Array).append(inst)


func _clear_armor_slot_mounts(slot_name: String) -> void:
	if _mounted_armor_instances.has(slot_name):
		var instances: Array = _mounted_armor_instances[slot_name]
		for inst in instances:
			if is_instance_valid(inst):
				inst.queue_free()
		_mounted_armor_instances.erase(slot_name)
	for entry in _armor_placeholders_for_slot(slot_name):
		var placeholder: Node3D = entry.get("node", null)
		if placeholder == null or not is_instance_valid(placeholder):
			continue
		for child in placeholder.get_children():
			child.queue_free()


func _armor_placeholders_for_slot(slot_name: String) -> Array:
	match slot_name:
		"head":
			return [{"node": armor_head_placeholder, "side": ""}]
		"body":
			return [{"node": armor_body_placeholder, "side": ""}]
		"hands":
			return [
				{"node": armor_hand_l_placeholder, "side": "L"},
				{"node": armor_hand_r_placeholder, "side": "R"},
			]
		"feet":
			return [
				{"node": armor_foot_l_placeholder, "side": "L"},
				{"node": armor_foot_r_placeholder, "side": "R"},
			]
		_:
			return []


func _set_armor_render_layer(root: Node) -> void:
	## Keep third-person armor off the first-person camera layer (bit 0).
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).layers = 1 << 9
	for child in root.get_children():
		_set_armor_render_layer(child)


func _ensure_armor_slots() -> void:
	if armor_slots == null:
		armor_slots = {}
	for slot_name in ARMOR_SLOT_NAMES:
		if not armor_slots.has(slot_name):
			armor_slots[slot_name] = null

func _clear_weapon_placeholder() -> void:
	if weapon_placeholder == null:
		return
	for child in weapon_placeholder.get_children():
		child.queue_free()
	if is_instance_valid(_mounted_weapon_instance):
		_mounted_weapon_instance = null

func _clear_current_weapon_mount() -> void:
	if is_instance_valid(_mounted_weapon_instance):
		_mounted_weapon_instance.queue_free()
		_mounted_weapon_instance = null
		return
	# Compatibility cleanup for instances created before the tracked mount was set.
	var mount := get_active_weapon_placeholder()
	if mount == null:
		return
	for child in mount.get_children():
		if child is EquipedItem and (child as EquipedItem).weapon_data != null:
			child.queue_free()

func _reset_weapon_reach() -> void:
	if weapon_reach_raycast != null:
		weapon_reach_raycast.target_position.z = DEFAULT_WEAPON_REACH

func _spawn_dropped_weapon(data: WeaponData, spawn_transform: Transform3D, is_being_dropped: bool) -> void:
	if data == null:
		return
	var level: Node = null
	if GameState != null and "current_level" in GameState:
		level = GameState.current_level
	if level == null or not is_instance_valid(level) or not level.is_inside_tree():
		return
	if is_being_dropped:
		_spawn_pickable_drop(level, spawn_transform, data)
		return
	var thrown_item := THROWN_ITEM_PREFAB.instantiate()
	thrown_item.weapon_data = data
	thrown_item.is_being_dropped = false
	thrown_item.source = get_parent() as CollisionObject3D
	thrown_item.global_transform = spawn_transform
	level.add_child(thrown_item)

## A normal drop is immediately interactable. Only an intentional throw uses
## the temporary combat body and waits for it to settle before becoming loot.
func _spawn_pickable_drop(level: Node, spawn_transform: Transform3D, weapon: WeaponData = null, shield: ShieldData = null) -> void:
	if level == null or not is_instance_valid(level):
		return
	var pickable := PICKABLE_ITEM_PREFAB.instantiate() as PickableItem
	if pickable == null:
		return
	pickable.weapon_data = weapon
	pickable.shield_data = shield
	pickable.global_transform = spawn_transform
	level.add_child(pickable)

func _is_hand_equipment(data: WeaponData) -> bool:
	if data == null:
		return false
	# Reject armor — armor goes in armor slots, not hand slots
	if _is_armor_equipment(data):
		return false
	# Accept weapons, shields, and legacy .tres resources without tags
	return true

func _is_armor_equipment(data: WeaponData) -> bool:
	if data == null:
		return false
	return data.equipment_category.begins_with("armor") or data.item_tag.begins_with("armor")

func _is_shield_weapon(data: WeaponData) -> bool:
	if data == null:
		return false
	return data.item_tag == "shield" or data.weapon_class == "shield" or data.equipment_category == "shields"

func _weapon_uses_off_hand(data: WeaponData) -> bool:
	if data == null:
		return false
	return _is_shield_weapon(data) or data.hands.to_lower() == "off_hand"

func _fallback_drop_transform(placeholder: Node3D) -> Transform3D:
	if placeholder != null and is_instance_valid(placeholder):
		return placeholder.global_transform if placeholder.is_inside_tree() else placeholder.transform
	return global_transform if is_inside_tree() else transform


# ============================================================================
# 装备查询方法（从 player.gd 下沉，供状态机和 UI 直接调用）
# ============================================================================

const CB_LIB_EQ := preload("res://globals/combat/combat_bridge.gd")

## 获取当前激活的武器数据（无武器时返回 null）
func get_active_weapon_data() -> WeaponData:
	if not has_hand_equipment():
		return null
	return weapon_data

## 获取当前武器的攻击类型（"melee"/"ranged"/"spell"/...）
func get_active_weapon_attack_type() -> String:
	return CB_LIB_EQ.get_weapon_attack_type(weapon_data)

## 当前武器是否为远程武器
func is_active_weapon_ranged() -> bool:
	return get_active_weapon_attack_type() == "ranged"

## 当前武器是否为弩（弩无需拉弓蓄力动画，点击即射）
func is_active_weapon_crossbow() -> bool:
	var weapon := weapon_data
	if weapon == null:
		return false
	var w_class := CB_LIB_EQ.get_weapon_class(weapon)
	if w_class == "crossbow":
		return true
	for tag in weapon.tags:
		if tag == "crossbow":
			return true
	return false

## 当前武器是否为双手武器
func is_active_weapon_two_handed() -> bool:
	var weapon := weapon_data
	if weapon == null:
		return false
	if weapon.hands == "two_hand":
		return true
	var weapon_class := CB_LIB_EQ.get_weapon_class(weapon)
	if ["two_hand", "longbow", "crossbow", "wand"].has(weapon_class):
		return true
	return weapon.tags.has("two_hand")

## 当前装备是否可以格挡（持盾或双手武器）
func can_block() -> bool:
	if is_active_weapon_ranged():
		return false
	# An off-hand grimoire has a short focus-guard window, but is not a
	# two-handed weapon and therefore must keep its own grimoire_guard clip.
	return has_shield() or is_active_weapon_two_handed() or _is_grimoire_weapon(weapon_data)

func _is_grimoire_weapon(data: WeaponData) -> bool:
	return data != null and (data.weapon_class.to_lower() == "grimoire" or data.skill_school.to_lower() == "grimoire")

## 当前装备是否可以双持攻击
func can_dual_wield() -> bool:
	if is_active_weapon_ranged() or can_block():
		return false
	var weapon := weapon_data
	if weapon == null:
		return false
	var weapon_class := CB_LIB_EQ.get_weapon_class(weapon)
	return weapon_class == "one_hand_melee" or weapon.tags.has("dual_wield") or weapon.combat_styles.has("dual_wield")
