class_name MomentumContext
extends RefCounted
## 技能打断时传递的运动上下文。

const DEFAULT_MOMENTUM_CAP := 10.0
const DEFAULT_DAMAGE_BONUS_CAP := 0.3
const DEFAULT_KNOCKBACK_BONUS_CAP := 0.8
const ACCELERATION_WEIGHT := 0.15

var velocity: Vector3 = Vector3.ZERO
var acceleration: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO
var source_skill_id: String = ""
var source_skill_type: String = ""
var strength: float = 0.0
var inherited_at_msec: int = 0

static func from_actor(actor: Node, source_id: String = "", source_type: String = ""):
	var ctx = load("res://globals/combat/momentum_context.gd").new()
	ctx.source_skill_id = source_id
	ctx.source_skill_type = source_type
	ctx.inherited_at_msec = Time.get_ticks_msec()
	if actor == null:
		return ctx
	if "velocity" in actor:
		ctx.velocity = actor.velocity
	if "pushback_force" in actor:
		ctx.acceleration += actor.pushback_force
	var horizontal_velocity := Vector3(ctx.velocity.x, 0.0, ctx.velocity.z)
	var horizontal_accel := Vector3(ctx.acceleration.x, 0.0, ctx.acceleration.z)
	if horizontal_velocity.length() > 0.01:
		ctx.direction = horizontal_velocity.normalized()
	elif horizontal_accel.length() > 0.01:
		ctx.direction = horizontal_accel.normalized()
	elif actor is Node3D:
		ctx.direction = -actor.global_transform.basis.z.normalized()
	ctx.strength = ctx.compute_strength(ctx.direction)
	return ctx

func compute_strength(next_direction: Vector3) -> float:
	var dir := Vector3(next_direction.x, 0.0, next_direction.z)
	if dir.length() <= 0.001:
		return 0.0
	dir = dir.normalized()
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var horizontal_accel := Vector3(acceleration.x, 0.0, acceleration.z)
	var projected_velocity := maxf(horizontal_velocity.dot(dir), 0.0)
	var projected_accel := maxf(horizontal_accel.dot(dir), 0.0) * ACCELERATION_WEIGHT
	return projected_velocity + projected_accel

func build_bonus(skill: Dictionary, next_direction: Vector3) -> Dictionary:
	if not bool(skill.get("inherit_momentum", false)):
		return {
			"strength": 0.0,
			"damage_multiplier": 1.0,
			"knockback_multiplier": 1.0,
		}
	var cap := float(skill.get("momentum_cap", DEFAULT_MOMENTUM_CAP))
	var usable_strength := minf(compute_strength(next_direction), cap)
	var damage_scale := float(skill.get("momentum_damage_scale", 0.0))
	var knockback_scale := float(skill.get("momentum_knockback_scale", 0.0))
	var damage_cap := float(skill.get("momentum_damage_cap", DEFAULT_DAMAGE_BONUS_CAP))
	var knockback_cap := float(skill.get("momentum_knockback_cap", DEFAULT_KNOCKBACK_BONUS_CAP))
	return {
		"strength": usable_strength,
		"damage_multiplier": 1.0 + minf(usable_strength * damage_scale, damage_cap),
		"knockback_multiplier": 1.0 + minf(usable_strength * knockback_scale, knockback_cap),
	}
