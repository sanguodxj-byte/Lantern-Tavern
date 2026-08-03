class_name SpellRuntime
extends RefCounted

## 固定法术的单一执行计划边界。
## 本类验证配方/法力/冷却并产出结构化结果；世界伤害、实体生成与网络广播由上层权威执行器处理。

const RecipeData := preload("res://globals/combat/spell_recipe_data.gd")

const DEFAULT_COOLDOWN_SEC := 0.8
const BASE_MANA_BY_LENGTH := {1: 6, 2: 12, 3: 20}
const COOLDOWN_BY_IMPLEMENTATION := {
	"projectile": 0.65, "ray": 0.55, "area": 1.25, "barrier": 1.5,
	"heal": 1.3, "movement": 1.0, "buff": 1.4, "summon": 2.0, "ground": 1.1,
}

var _cooldown_until_ms: Dictionary = {}


func prepare_cast(loadout: RefCounted, slot_index: int, caster: Object, origin: Vector3, direction: Vector3, target_hint: Variant = null) -> Dictionary:
	if loadout == null or not loadout.has_method("get_spell"):
		return _reject("missing_loadout")
	var spell: Dictionary = loadout.get_spell(slot_index)
	if spell.is_empty():
		return _reject("empty_spell_slot")
	var resolved: Dictionary = RecipeData.resolve(spell.get("recipe", []))
	if resolved.is_empty() or String(resolved.get("id", "")) != String(spell.get("id", "")):
		return _reject("recipe_mismatch")
	if direction.length_squared() <= 0.0001:
		return _reject("invalid_direction")
	var spell_id := String(spell.get("id", ""))
	var now_ms := Time.get_ticks_msec()
	if now_ms < int(_cooldown_until_ms.get(spell_id, 0)):
		return _reject("cooldown", {"remaining_ms": int(_cooldown_until_ms[spell_id]) - now_ms})
	var mana_cost := mana_cost_for(spell)
	var mana := _mana_component(caster)
	if mana == null:
		return _reject("missing_mana")
	if int(mana.current_mana) < mana_cost:
		return _reject("insufficient_mana", {"mana_cost": mana_cost})
	return {
		"ok": true,
		"spell": spell.duplicate(true),
		"spell_id": spell_id,
		"implementation": String(spell.get("implementation", "projectile")),
		"imagery": String(spell.get("imagery", "unknown")),
		"mana_cost": mana_cost,
		"cooldown_sec": cooldown_for(spell),
		"origin": origin,
		"direction": direction.normalized(),
		"target_hint": target_hint,
		"visual_event": {
			"phase": "cast",
			"spell_id": spell_id,
			"imagery": String(spell.get("imagery", "unknown")),
			"color": spell.get("color", Color.WHITE),
		},
	}


func commit_cast(plan: Dictionary, caster: Object) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return plan
	var mana := _mana_component(caster)
	if mana == null or not mana.spend(int(plan.get("mana_cost", 0))):
		return _reject("insufficient_mana")
	var spell_id := String(plan.get("spell_id", ""))
	var cooldown_sec := float(plan.get("cooldown_sec", DEFAULT_COOLDOWN_SEC))
	_cooldown_until_ms[spell_id] = Time.get_ticks_msec() + roundi(cooldown_sec * 1000.0)
	return {
		"ok": true,
		"spell_id": spell_id,
		"implementation": String(plan.get("implementation", "projectile")),
		"imagery": String(plan.get("imagery", "unknown")),
		"mana_spent": int(plan.get("mana_cost", 0)),
		"cooldown_sec": cooldown_sec,
		"origin": plan.get("origin", Vector3.ZERO),
		"direction": plan.get("direction", Vector3.FORWARD),
		"target_hint": plan.get("target_hint"),
		"effect_plan": _effect_plan(plan),
		"visual_event": plan.get("visual_event", {}).duplicate(true),
	}


func cast_slot(loadout: RefCounted, slot_index: int, caster: Object, origin: Vector3, direction: Vector3, target_hint: Variant = null) -> Dictionary:
	return commit_cast(prepare_cast(loadout, slot_index, caster, origin, direction, target_hint), caster)


func mana_cost_for(spell: Dictionary) -> int:
	return int(BASE_MANA_BY_LENGTH.get(Array(spell.get("recipe", [])).size(), 20))


func cooldown_for(spell: Dictionary) -> float:
	return float(COOLDOWN_BY_IMPLEMENTATION.get(String(spell.get("implementation", "projectile")), DEFAULT_COOLDOWN_SEC))


func is_on_cooldown(spell_id: String) -> bool:
	return Time.get_ticks_msec() < int(_cooldown_until_ms.get(spell_id, 0))


func remaining_cooldown_ms(spell_id: String) -> int:
	return maxi(0, int(_cooldown_until_ms.get(spell_id, 0)) - Time.get_ticks_msec())


func commit_authoritative_cooldown(spell: Dictionary) -> bool:
	var spell_id := String(spell.get("id", ""))
	if spell_id.is_empty() or is_on_cooldown(spell_id):
		return false
	_cooldown_until_ms[spell_id] = Time.get_ticks_msec() + roundi(cooldown_for(spell) * 1000.0)
	return true


func serialize() -> Dictionary:
	return {"cooldown_until_ms": _cooldown_until_ms.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	_cooldown_until_ms = Dictionary(data.get("cooldown_until_ms", {})).duplicate(true)


func clear_cooldowns() -> void:
	_cooldown_until_ms.clear()


func _effect_plan(plan: Dictionary) -> Dictionary:
	var implementation := String(plan.get("implementation", "projectile"))
	var base := {"type": implementation, "authoritative": true, "fx_is_cosmetic": true}
	# P1（2331 审查）：业务数值单一真相——recipe 的 power 字典（若配置）覆盖默认值；
	# 未配置时使用本文件默认（recipe 层占位，随 ADR-007 数值校准统一由数据驱动）。
	var power: Dictionary = Dictionary(Dictionary(plan.get("spell", {})).get("power", {}))
	match implementation:
		"projectile", "ray":
			base["projectile_id"] = String(Dictionary(plan.get("spell", {})).get("projectile_id", "spell_pixel_bolt"))
			base["speed"] = 18.0
			base["damage"] = int(power.get("damage", 10))
		"area", "ground":
			base["radius"] = float(power.get("radius", 4.0))
			base["duration"] = float(power.get("duration", 3.0))
			base["damage"] = int(power.get("damage", 4))
		"barrier":
			base["duration"] = float(power.get("duration", 5.0))
			base["absorb"] = int(power.get("absorb", 30))
		"heal":
			base["heal"] = int(power.get("heal", 28))
		"movement":
			base["distance"] = float(power.get("distance", 5.0))
		"buff":
			base["duration"] = float(power.get("duration", 6.0))
			base["power_pct"] = float(power.get("power_pct", 20.0))
		"summon":
			base["summon_kind"] = "spell_construct"
			base["duration"] = float(power.get("duration", 12.0))
			base["damage"] = int(power.get("damage", 6))
	return base


func _mana_component(caster: Object) -> Object:
	if caster == null:
		return null
	if "mana" in caster and caster.mana != null:
		return caster.mana
	if caster is Node:
		return caster.get_node_or_null("Mana")
	return null


func _reject(reason: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "reason": reason}
	result.merge(extra, true)
	return result
