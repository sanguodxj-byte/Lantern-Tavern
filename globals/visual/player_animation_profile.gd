class_name PlayerAnimationProfile
extends RefCounted

## Canonical player animation taxonomy.  Weapon data may use broad combat
## classes, but presentation is resolved per authored weapon style.

const PROFILES: Array[StringName] = [
	&"unarmed", &"shortsword", &"sword", &"dagger", &"greatsword", &"axe",
	&"warhammer", &"spear", &"bow", &"crossbow", &"staff", &"grimoire", &"shield",
]

static func profile_for_weapon(weapon: Variant) -> StringName:
	if weapon == null:
		return &"unarmed"
	var item_tag := String(weapon.item_tag) if "item_tag" in weapon else ""
	var weapon_class := String(weapon.weapon_class).to_lower() if "weapon_class" in weapon else ""
	var skill_school := String(weapon.skill_school).to_lower() if "skill_school" in weapon else ""
	var weapon_id := String(weapon.id).to_lower() if "id" in weapon else ""
	var tags: Array = weapon.tags if "tags" in weapon else []
	var explicit_profile := String(weapon.view_model_profile).to_lower() if "view_model_profile" in weapon else ""

	if item_tag == "shield" or weapon_class == "shield":
		return &"shield"
	# Dagger data historically carries the sword view-model profile.  Its
	# semantic tag must win so it cannot silently reuse the sword animation.
	if tags.has("dagger") or skill_school == "dagger":
		return &"dagger"
	if tags.has("spear") or skill_school == "spear" or "spear" in weapon_class:
		return &"spear"
	if weapon_class == "crossbow" or tags.has("crossbow") or skill_school == "light_crossbow":
		return &"crossbow"
	if weapon_class == "longbow" or tags.has("bow") or skill_school == "longbow":
		return &"bow"
	if weapon_class == "wand" or skill_school == "enchant_wand":
		return &"staff"
	if weapon_class == "grimoire" or skill_school == "grimoire":
		return &"grimoire"
	if skill_school == "two_hand_axe" or tags.has("two_hand_axe"):
		return &"axe"
	if skill_school == "war_hammer" or tags.has("war_hammer"):
		return &"warhammer"
	if skill_school == "two_hand_sword" or tags.has("two_hand_sword"):
		return &"greatsword"
	if explicit_profile in ["shortsword", "sword"]:
		return StringName(explicit_profile)
	if weapon_id == "shortsword":
		return &"shortsword"
	if weapon_class == "one_hand_melee" or tags.has("one_hand_sword"):
		return &"sword"
	if weapon_class == "two_hand":
		return &"greatsword"
	return &"sword"


static func hold_animation(weapon: Variant) -> StringName:
	return StringName("%s_hold" % profile_for_weapon(weapon))


static func defense_animation(weapon: Variant, has_shield: bool = false) -> StringName:
	if has_shield:
		return &"shield_block"
	var profile := profile_for_weapon(weapon)
	if profile == &"bow":
		return &"bow_aim"
	if profile == &"crossbow":
		return &"crossbow_aim"
	return StringName("%s_guard" % profile)


static func uses_off_hand(weapon: Variant) -> bool:
	if weapon == null:
		return false
	var item_tag := String(weapon.item_tag).to_lower() if "item_tag" in weapon else ""
	var weapon_class := String(weapon.weapon_class).to_lower() if "weapon_class" in weapon else ""
	var hands := String(weapon.hands).to_lower() if "hands" in weapon else ""
	return item_tag == "shield" or weapon_class == "shield" or hands == "off_hand"


static func attack_animation(weapon: Variant, heavy_swing: bool = false) -> StringName:
	var profile := profile_for_weapon(weapon)
	if profile == &"unarmed":
		return &"claw_swipe"
	if profile == &"shield":
		return &"bash_shield"
	if profile == &"bow":
		return &"bow_release"
	if profile == &"crossbow":
		return &"crossbow_fire"
	if heavy_swing and profile in [&"greatsword", &"axe", &"warhammer", &"spear"]:
		return StringName("%s_heavy_swing" % profile)
	return StringName("%s_attack" % profile)


static func release_animation(weapon: Variant) -> StringName:
	var profile := profile_for_weapon(weapon)
	if profile == &"bow":
		return &"bow_release"
	if profile == &"crossbow":
		return &"crossbow_fire"
	return attack_animation(weapon)


static func view_model_action(animation_name: StringName) -> StringName:
	# First-person actions have their own visual vocabulary where the old
	# third-person action name was too broad or historically different.
	match animation_name:
		&"shortsword_attack": return &"vm_shortsword_thrust"
		&"sword_attack": return &"vm_sword_slash"
		&"dagger_attack": return &"vm_stab_dagger"
		&"spear_attack": return &"vm_thrust_spear"
	return StringName("vm_%s" % String(animation_name))
