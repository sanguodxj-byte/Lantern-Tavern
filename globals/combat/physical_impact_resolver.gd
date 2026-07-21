extends RefCounted
## 物理撞击结算模块。
## 接收 CharacterBody3D 的 slide collision 信息，按技能撞击参数与目标体型/阶级计算地形撞击伤害。

const CE := preload("res://globals/combat/combat_engine.gd")

const DEFAULT_COOLDOWN_MSEC := 350

static func can_attempt(enabled: bool, last_impact_msec: int, now_msec: int, cooldown_msec: int = DEFAULT_COOLDOWN_MSEC) -> bool:
	if not enabled:
		return false
	return now_msec - last_impact_msec >= cooldown_msec

static func resolve_slide_collisions(
	target: CharacterBody3D,
	impact_velocity: Vector3,
	max_life: int,
	impact_spec: Dictionary,
	last_impact_msec: int,
	now_msec: int = Time.get_ticks_msec()
) -> Dictionary:
	if target == null or not can_attempt(bool(impact_spec.get("enabled", false)), last_impact_msec, now_msec):
		return {"hit": false}
	var profile := get_target_profile(target)
	for index in range(target.get_slide_collision_count()):
		var collision := target.get_slide_collision(index)
		var body := collision.get_collider()
		if not is_impact_collider(body, target):
			continue
		var normal := collision.get_normal()
		var damage := resolve_surface_damage(max_life, impact_velocity, normal, impact_spec, profile)
		if damage <= 0:
			continue
		return {
			"hit": true,
			"damage": damage,
			"normal": normal,
			"body": body,
			"time_msec": now_msec,
			"profile": profile,
		}
	return {"hit": false}

static func resolve_surface_damage(max_life: int, impact_velocity: Vector3, surface_normal: Vector3, impact_spec: Dictionary, target_profile: Dictionary = {}) -> int:
	if surface_normal.y > 0.65:
		return 0
	var incoming_speed := maxf(impact_velocity.dot(-surface_normal), 0.0)
	return CE.compute_physical_impact_damage(
		max_life,
		incoming_speed,
		float(impact_spec.get("min_speed", 4.0)),
		float(impact_spec.get("full_speed", 14.0)),
		float(impact_spec.get("damage_mult", 1.0)),
		target_profile
	)

static func is_impact_collider(body: Object, source: Object = null) -> bool:
	if body == null or body == source:
		return false
	if body is Player or body is Enemy:
		return false
	return body is StaticBody3D or body is AnimatableBody3D or body is RigidBody3D or body is CharacterBody3D

static func get_target_profile(target: Object) -> Dictionary:
	var rank := _read_rank(target)
	var body_size := String(_read_value(target, "body_size", "medium"))
	var rank_mult := _rank_impact_damage_mult(rank)
	var size_profile := get_body_size_profile(body_size)
	return {
		"rank": rank,
		"body_size": body_size,
		"impact_damage_taken_mult": rank_mult * float(size_profile.get("impact_damage_taken_mult", 1.0)),
		"impact_min_speed_add": float(size_profile.get("impact_min_speed_add", 0.0)),
	}

static func get_body_size_profile(body_size: String) -> Dictionary:
	match body_size:
		"small":
			return {"impact_damage_taken_mult": 1.10, "impact_min_speed_add": -0.5}
		"large":
			return {"impact_damage_taken_mult": 0.80, "impact_min_speed_add": 1.0}
		"huge":
			return {"impact_damage_taken_mult": 0.60, "impact_min_speed_add": 2.0}
		_:
			return {"impact_damage_taken_mult": 1.0, "impact_min_speed_add": 0.0}

static func _read_rank(target: Object) -> String:
	var explicit_rank := String(_read_value(target, "enemy_rank", ""))
	if explicit_rank in ["normal", "elite", "boss"]:
		return explicit_rank
	if bool(_read_value(target, "is_boss_type", false)) or bool(_read_value(target, "is_boss", false)):
		return "boss"
	if bool(_read_value(target, "is_elite", false)):
		return "elite"
	return "normal"

static func _rank_impact_damage_mult(rank: String) -> float:
	match rank:
		"boss":
			return 0.65
		"elite":
			return 0.85
		_:
			return 1.0

static func _read_value(target: Object, key: String, fallback: Variant) -> Variant:
	if target == null:
		return fallback
	for property in target.get_property_list():
		if String(property.get("name", "")) == key:
			var value: Variant = target.get(key)
			return fallback if value == null else value
	if target.has_meta(key):
		return target.get_meta(key, fallback)
	return fallback
