class_name EquipmentComponent
extends Node3D

const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")
const THROWN_ITEM_PREFAB := preload("res://scenes/equipment/thrown_item.tscn")

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

func equip_weapon(data: WeaponData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> bool:
	if data == null:
		return false
	_ensure_weapon_slots()
	var target_slot := get_first_empty_weapon_slot()
	if target_slot == -1:
		target_slot = active_weapon_slot
		if weapon_slots[target_slot] != null:
			_spawn_dropped_weapon(weapon_slots[target_slot], weapon_placeholder.global_transform if weapon_placeholder != null else Transform3D.IDENTITY, true)
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
	active_weapon_slot = slot_index
	weapon_data = weapon_slots[active_weapon_slot]
	_clear_weapon_placeholder()
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
	armor_slots[slot_name] = data.duplicate() if data != null else null
	return true

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
	if weapon_placeholder == null:
		return
	var weapon := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	if weapon == null:
		push_error("EquipmentComponent: failed to instantiate EquipedItem")
		return
	weapon.weapon_data = weapon_data
	weapon.is_always_in_front = is_always_in_front
	weapon_placeholder.add_child(weapon)
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
	return weapon_data != null and not _is_shield_weapon(weapon_data) and (weapon_placeholder == null or weapon_placeholder.get_child_count() > 0)

func has_hand_equipment() -> bool:
	return weapon_data != null and (weapon_placeholder == null or weapon_placeholder.get_child_count() > 0)

func hide_weapon() -> void:
	if weapon_placeholder != null:
		weapon_placeholder.visible = false

func show_weapon() -> void:
	if weapon_placeholder != null:
		weapon_placeholder.visible = true

func throw_weapon(is_being_dropped: bool = false, aim_point: Vector3 = Vector3.ZERO) -> void:
	if weapon_data != null and (weapon_placeholder == null or weapon_placeholder.get_child_count() > 0):
		var was_shield := _is_shield_weapon(weapon_data)
		var spawn_transform := _fallback_drop_transform(weapon_placeholder)
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
		weapon_slots[active_weapon_slot] = null
		weapon_data = null
		_clear_weapon_placeholder()
		_reset_weapon_reach()
		if is_linked_to_ui:
			GameEvents.weapon_changed.emit(weapon_data)
			if was_shield:
				GameEvents.shield_changed.emit(null)

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
		var dropped_item := THROWN_ITEM_PREFAB.instantiate()
		dropped_item.shield_data = shield_data
		dropped_item.is_being_dropped = true
		var spawn_transform := _fallback_drop_transform(shield_placeholder)
		dropped_item.global_transform = spawn_transform
		level.add_child(dropped_item)
		shield_data = null
		if shield_placeholder != null and is_instance_valid(shield_placeholder) and shield_placeholder.get_child_count() > 0:
			shield_placeholder.get_child(0).queue_free()
		if is_linked_to_ui:
			GameEvents.shield_changed.emit(shield_data)

func apply_weapon_damage(amount: int) -> void:
	if weapon_data != null and (weapon_placeholder == null or weapon_placeholder.get_child_count() > 0):
		weapon_data.decrease_condition(amount)
		if weapon_data.condition <= 0:
			drop_weapon()
		else:
			weapon_slots[active_weapon_slot] = weapon_data
			GameEvents.weapon_changed.emit(weapon_data)
			if _is_shield_weapon(weapon_data):
				GameEvents.shield_changed.emit(weapon_data)
		
func apply_shield_damage(amount: int) -> void:
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

func _ensure_weapon_slots() -> void:
	while weapon_slots.size() < WEAPON_SLOT_COUNT:
		weapon_slots.append(null)
	if weapon_slots.size() > WEAPON_SLOT_COUNT:
		weapon_slots.resize(WEAPON_SLOT_COUNT)
	active_weapon_slot = clampi(active_weapon_slot, 0, WEAPON_SLOT_COUNT - 1)

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
	var thrown_item := THROWN_ITEM_PREFAB.instantiate()
	thrown_item.weapon_data = data
	thrown_item.is_being_dropped = is_being_dropped
	thrown_item.source = get_parent() as CollisionObject3D
	thrown_item.global_transform = spawn_transform
	level.add_child(thrown_item)

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
	if ["two_hand", "longbow", "crossbow", "wand", "grimoire"].has(weapon_class):
		return true
	return weapon.tags.has("two_hand")

## 当前装备是否可以格挡（持盾或双手武器）
func can_block() -> bool:
	if is_active_weapon_ranged():
		return false
	return has_shield() or is_active_weapon_two_handed()

## 当前装备是否可以双持攻击
func can_dual_wield() -> bool:
	if is_active_weapon_ranged() or can_block():
		return false
	var weapon := weapon_data
	if weapon == null:
		return false
	var weapon_class := CB_LIB_EQ.get_weapon_class(weapon)
	return weapon_class == "one_hand_melee" or weapon.tags.has("dual_wield") or weapon.combat_styles.has("dual_wield")
