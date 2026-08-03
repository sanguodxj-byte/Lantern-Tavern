class_name SpellAccessPolicy
extends RefCounted

const ARCANE_SWORD_PASSIVE_ID := "passive_style_onehand_spellblade"


static func can_use_spell_interface(weapon: WeaponData, has_arcane_sword: bool) -> bool:
	if weapon == null:
		return false
	var weapon_class := String(weapon.weapon_class).to_lower()
	var skill_school := String(weapon.skill_school).to_lower()
	var weapon_id := String(weapon.id).to_lower()
	if weapon_class == "wand" or weapon_class == "grimoire":
		return true
	if skill_school == "staff" or skill_school == "grimoire" or weapon_id.contains("staff") or weapon_id.contains("grimoire"):
		return true
	var is_one_hand_sword := weapon_class == "one_hand_melee" and (skill_school == "one_hand_sword" or weapon.tags.has("sword") or weapon_id.contains("sword"))
	return is_one_hand_sword and has_arcane_sword
