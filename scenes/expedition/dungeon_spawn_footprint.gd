## DungeonSpawnFootprint - conservative horizontal AABB clearance for runtime spawns.
##
## The layout planner separates cells, but the rendered collision envelopes are
## not all the same size. This small data-only helper keeps placement checks
## deterministic and independent from scene instantiation.
class_name DungeonSpawnFootprint
extends RefCounted

const CLEARANCE_M := 0.08

static func half_extents_for(category: String, identifier: String = "") -> Vector2:
	var key := identifier.to_lower()
	match category:
		"chest":
			return Vector2(0.78 if key == "boss_chest" else 0.62, 0.70 if key == "boss_chest" else 0.58)
		"enemy":
			if key.contains("dragon") or key.contains("golem") or key.contains("minotaur") or key.contains("huge"):
				return Vector2(0.86, 0.86)
			if key.contains("troll") or key.contains("ogre") or key.contains("large"):
				return Vector2(0.68, 0.68)
			if key.contains("slime") or key.contains("kobold") or key.contains("small"):
				return Vector2(0.42, 0.42)
			return Vector2(0.52, 0.52)
		"item":
			return Vector2(0.46, 0.46)
		"torch":
			return Vector2(0.28, 0.28)
		"focus":
			return Vector2(0.92, 0.92)
		"decor":
			if key.contains("pillar"):
				return Vector2(1.18, 1.18)
			if key.contains("sarcophagus"):
				return Vector2(0.92, 0.72)
			if key.contains("stalagmite"):
				return Vector2(0.82, 0.72)
			if key.contains("fungus"):
				return Vector2(0.50, 0.42)
			if key.contains("wall_chain") or key.contains("chain"):
				return Vector2(0.38, 0.24)
			if key.contains("barrel"):
				return Vector2(0.72, 0.72)
			if key.contains("crate"):
				return Vector2(0.62, 0.62)
			if key.contains("ritual"):
				return Vector2(0.72, 0.72)
			if key.contains("plank"):
				return Vector2(0.68, 0.48)
			if key.contains("spiderweb"):
				return Vector2(0.70, 0.30)
			if key.contains("candelabrum") or key.contains("grate"):
				return Vector2(0.48, 0.48)
			return Vector2(0.54, 0.54)
	return Vector2(0.45, 0.45)

static func half_extents_for_scene_path(scene_path: String) -> Vector2:
	var path := scene_path.to_lower()
	if path.contains("chest"):
		return half_extents_for("chest", "boss_chest" if path.contains("boss") else "normal_chest")
	if path.contains("torch") or path.contains("candelabrum"):
		return half_extents_for("torch", scene_path)
	return half_extents_for("decor", scene_path)

static func aabb_for(center: Vector3, half_extents: Vector2, clearance: float = CLEARANCE_M) -> Rect2:
	var extents := half_extents + Vector2.ONE * maxf(clearance, 0.0)
	return Rect2(Vector2(center.x - extents.x, center.z - extents.y), extents * 2.0)

static func overlaps(a: Rect2, b: Rect2) -> bool:
	# Strict inequalities mean face contact is allowed; only positive-volume
	# horizontal overlap is rejected.
	return a.position.x < b.end.x and a.end.x > b.position.x \
		and a.position.y < b.end.y and a.end.y > b.position.y

static func can_place(registry: Array, center: Vector3, half_extents: Vector2,
		clearance: float = CLEARANCE_M) -> bool:
	if registry == null:
		return true
	var candidate := aabb_for(center, half_extents, clearance)
	for entry in registry:
		if entry is Dictionary and entry.has("aabb") and overlaps(candidate, entry["aabb"]):
			return false
	return true

static func register(registry: Array, center: Vector3, half_extents: Vector2,
		owner: String = "", clearance: float = CLEARANCE_M) -> void:
	if registry == null:
		return
	registry.append({
		"aabb": aabb_for(center, half_extents, clearance),
		"center": center,
		"owner": owner,
	})

static func spec_category(spec: Dictionary) -> String:
	if spec.has("spawn_category"):
		return String(spec["spawn_category"])
	if spec.has("enemy_type"):
		return "enemy"
	if spec.has("chest_type"):
		return "chest"
	if spec.has("item_type"):
		return "item"
	return "decor"

static func spec_identifier(spec: Dictionary) -> String:
	for key in ["enemy_type", "chest_type", "decor_kind", "item_id", "scene_path"]:
		if spec.has(key):
			return String(spec[key])
	return ""
