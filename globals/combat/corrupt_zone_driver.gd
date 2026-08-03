extends Node
## 腐蚀区域驱动器 — 挂载到 CorruptZone Area3D 下，每秒对区域内敌人造成腐蚀伤害。
## 由 RuneWordPassiveHooks._create_corrupt_zone 创建，区域到期后由 Timer queue_free。

const SES := preload("res://globals/combat/status_effect_system.gd")

var _tick_accum: float = 0.0
const TICK_INTERVAL := 1.0

func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	_tick_accum -= TICK_INTERVAL
	# 从父节点读取参数
	var zone := get_parent()
	if zone == null or not is_instance_valid(zone):
		return
	var dps := float(zone.get_meta("dps", 5.0))
	var radius := float(zone.get_meta("radius", 2.5))
	# 查找区域内敌人
	var center := (zone as Node3D).global_position if zone is Node3D else Vector3.ZERO
	var enemies := _get_enemies_in_range(center, radius)
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		# 施加腐蚀 DoT
		SES.apply_status(enemy, "se_corrupt", TICK_INTERVAL + 0.5, dps)

func _get_enemies_in_range(center: Vector3, radius: float) -> Array:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return []
	var enemies: Array = tree.root.find_children("*", "Enemy", true, false)
	if enemies.is_empty():
		enemies = tree.root.get_nodes_in_group("enemies")
	var result: Array = []
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		if not (e is Node3D):
			continue
		var dist := (e as Node3D).global_position.distance_to(center)
		if dist <= radius:
			result.append(e)
	return result
