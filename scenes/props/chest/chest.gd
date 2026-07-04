class_name Chest
extends StaticBody3D

## 宝箱当前所在区域（BrewingData.Zone 枚举值）。
## 由 procedural_dungeon 在放置宝箱时注入，决定材料掉落池。
@export var zone: int = 0  # 默认森林

var is_opened := false

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

	# Spawn loot via LootTable autoload (统一掉落表，对接 WeaponRegistry + BrewingData)
	_spawn_loot(by_interact)

	# Destroy chest instance
	queue_free()

func _spawn_loot(by_interact: bool) -> void:
	var loot_table: Node = get_tree().root.get_node_or_null("LootTable") if is_inside_tree() else null
	if loot_table == null:
		push_warning("[Chest] LootTable autoload not found, no loot dropped")
		return
	var drop = loot_table.generate_loot(zone)
	var pickable_scene = load("res://scenes/equipment/pickable_item.tscn")
	if pickable_scene == null:
		push_warning("[Chest] pickable_item.tscn not found")
		return

	# 1. 武器掉落（含 tier 阶位，攻击与交互均掉）
	if not drop.weapon.is_empty():
		var weapon_data = drop.weapon.get("weapon_data", null)
		if weapon_data:
			var p_item = pickable_scene.instantiate()
			p_item.weapon_data = weapon_data
			p_item.global_position = global_position + Vector3(0, 0.4, 0)
			get_parent().add_child(p_item)
			print("[Chest] Dropped weapon: %s (tier %d: %s)" % [
				drop.weapon.get("id", "?"),
				drop.weapon.get("tier_index", 0),
				drop.weapon.get("tier_name", "?"),
			])

	# 2. 材料掉落：仅交互开启时掉落（攻击破坏会毁损材料，保留原设计语义）
	if by_interact:
		for mat_entry in drop.materials:
			var mat_id: String = mat_entry.get("material_id", "")
			if mat_id == "":
				continue
			var p_item = pickable_scene.instantiate()
			p_item.material_id = mat_id
			var offset = Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5))
			p_item.global_position = global_position + offset
			get_parent().add_child(p_item)
			print("[Chest] Dropped material: %s (%s)" % [mat_id, mat_entry.get("name", "")])
	else:
		print("[Chest] Melee attack destroyed all brewing materials! (Only weapon dropped)")
