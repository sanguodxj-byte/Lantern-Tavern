class_name WeaponProficiencyCatalog
extends RefCounted

## Player-facing weapon proficiency taxonomy.
##
## Hand usage and skill schools remain combat rules, but they do not create
## separate proficiency tracks. A sword therefore shares one track whether it
## is a shortsword, longsword, or greatsword, and regardless of its style.

const ENTRIES: Array[Dictionary] = [
	{"key": "sword", "label": "剑", "icon_path": "res://assets/textures/icons/equipment/weapons_sword.png"},
	{"key": "dagger", "label": "匕首", "icon_path": "res://assets/textures/icons/equipment/weapons_dagger.png"},
	{"key": "axe", "label": "斧", "icon_path": "res://assets/textures/icons/equipment/weapons_axe.png"},
	{"key": "hammer", "label": "锤", "icon_path": "res://assets/textures/icons/equipment/weapons_warhammer.png"},
	{"key": "spear", "label": "枪", "icon_path": "res://assets/textures/icons/equipment/weapons_spear.png"},
	{"key": "bow", "label": "弓", "icon_path": "res://assets/textures/icons/equipment/weapons_longbow.png"},
	{"key": "crossbow", "label": "弩", "icon_path": "res://assets/textures/icons/equipment/weapons_crossbow.png"},
	{"key": "staff", "label": "法杖", "icon_path": "res://assets/textures/icons/equipment/weapons_staff.png"},
	{"key": "grimoire", "label": "魔导书", "icon_path": "res://assets/textures/icons/equipment/weapons_grimoire.png"},
	# The game treats shields as hand-held combat equipment with its own
	# combat actions, so it remains visible while armor/alchemy do not.
	{"key": "shield", "label": "盾牌", "icon_path": "res://assets/textures/icons/equipment/weapons_shield.png"},
]

const LEGACY_FALLBACKS := {
	"sword": ["one_hand_melee", "two_hand"],
	"dagger": ["one_hand_melee"],
	"axe": ["two_hand"],
	"hammer": ["two_hand"],
	"spear": ["two_hand"],
	"bow": ["longbow"],
	"staff": ["wand"],
}

static func entries() -> Array[Dictionary]:
	return ENTRIES.duplicate(true)

static func keys() -> Array[String]:
	var result: Array[String] = []
	for entry in ENTRIES:
		result.append(String(entry["key"]))
	return result

static func label_for(key: String) -> String:
	for entry in ENTRIES:
		if String(entry["key"]) == key:
			return String(entry["label"])
	return key

static func icon_path_for(key: String) -> String:
	for entry in ENTRIES:
		if String(entry["key"]) == key:
			return String(entry["icon_path"])
	return ""

## Reads the new category key first and falls back to legacy saves.
## Legacy values can be ambiguous because old data grouped by hand count;
## using the maximum preserves visible progress without inventing a reset.
static func value_for(proficiency: Dictionary, key: String) -> int:
	var value := int(proficiency.get(key, 0))
	if value > 0:
		return value
	for legacy_key in LEGACY_FALLBACKS.get(key, []):
		value = maxi(value, int(proficiency.get(legacy_key, 0)))
	return value

