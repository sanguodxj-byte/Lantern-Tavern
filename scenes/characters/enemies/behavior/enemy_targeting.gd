class_name EnemyTargeting
extends RefCounted

## 怪物目标感知 Module。
## 目标只有在视野锥 + 视线检测同时通过时才会更新为当前可见目标。
## 失去视线后只允许短暂前往最后已知位置，绝不继续读取玩家实时位置寻路。

const TARGET_MEMORY_DURATION := 1.5

var owner: Node3D
var target: Player = null
var last_seen_position := Vector3.ZERO
var has_last_seen_position := false
var memory_remaining := 0.0
var target_visible := false

func _init(source_enemy: Node3D = null) -> void:
	owner = source_enemy

func observe_external_target(candidate: Player) -> void:
	# 兼容旧的 enemy.player 赋值，但不伪造“已经看见”状态。
	target = candidate if _is_valid_player(candidate) else null
	target_visible = false
	has_last_seen_position = false
	memory_remaining = 0.0

func acquire_visible_target(candidate: Player) -> bool:
	if not _is_valid_player(candidate) or owner == null:
		return false
	if not owner.is_target_in_facing_cone(candidate):
		return false
	if not owner.has_line_of_sight_to(candidate):
		return false
	target = candidate
	_mark_seen()
	return true

func mark_engaged_target(candidate: Player) -> void:
	if not _is_valid_player(candidate):
		return
	target = candidate
	_mark_seen()

func evaluate(candidate: Player, forced: bool = false) -> bool:
	if not _is_valid_player(candidate) or owner == null:
		clear()
		return false
	if forced:
		target = candidate
		_mark_seen()
		return true

	var distance := owner.global_position.distance_to(candidate.global_position)
	if distance > owner.detection_range:
		if target == candidate and has_last_seen_position and memory_remaining > 0.0:
			var was_visible := target_visible
			target_visible = false
			if was_visible:
				memory_remaining = TARGET_MEMORY_DURATION
			return true
		if target == candidate:
			clear()
		return false

	var visible: bool = bool(owner.is_target_in_facing_cone(candidate)) and bool(owner.has_line_of_sight_to(candidate))
	if visible:
		target = candidate
		_mark_seen()
		return true

	# 已登记目标暂时失去视线时，只保留最后已知位置。
	if target == candidate and has_last_seen_position and memory_remaining > 0.0:
		target_visible = false
		return true
	clear()
	return false

func tick(delta: float) -> void:
	if memory_remaining > 0.0 and not target_visible:
		memory_remaining = maxf(0.0, memory_remaining - delta)
	if target != null and not is_instance_valid(target):
		clear()
	if not target_visible and memory_remaining <= 0.0 and target != null:
		clear()

func has_pending_memory() -> bool:
	return target != null and (not is_instance_valid(target) \
		or (not target_visible and memory_remaining > 0.0))

func clear() -> void:
	target = null
	target_visible = false
	has_last_seen_position = false
	memory_remaining = 0.0

func has_navigation_goal() -> bool:
	return target != null and (target_visible or (has_last_seen_position and memory_remaining > 0.0))

func navigation_target_position() -> Vector3:
	if target_visible and _is_valid_player(target):
		return target.global_position
	return last_seen_position

func is_visible() -> bool:
	return target_visible and _is_valid_player(target)

func _mark_seen() -> void:
	if not _is_valid_player(target):
		return
	last_seen_position = target.global_position
	last_seen_position.y = owner.global_position.y
	has_last_seen_position = true
	memory_remaining = TARGET_MEMORY_DURATION
	target_visible = true

func _is_valid_player(candidate: Player) -> bool:
	return candidate != null and is_instance_valid(candidate)
