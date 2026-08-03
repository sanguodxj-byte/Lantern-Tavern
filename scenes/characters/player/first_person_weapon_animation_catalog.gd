class_name FirstPersonWeaponAnimationCatalog
extends RefCounted

## Editor-authored first-person animation resources are split by weapon ID and
## variant. The runtime keeps the generated library as a fallback only.

const RESOURCE_ROOT := "res://scenes/characters/player/weapon_animations"
const VARIANTS: Array[StringName] = [&"standard", &"alternate", &"heavy"]
const WEAPON_IDS: Array[StringName] = [
	&"shortsword", &"greatsword", &"axe", &"warhammer", &"spear", &"dagger",
	&"longbow", &"crossbow", &"staff", &"grimoire", &"shield", &"sword",
]

static func resource_path(weapon_id: String, variant: String = "standard") -> String:
	var safe_weapon_id := weapon_id.strip_edges().to_lower()
	var safe_variant := variant.strip_edges().to_lower()
	if safe_variant.is_empty():
		safe_variant = "standard"
	return "%s/%s/%s.tres" % [RESOURCE_ROOT, safe_weapon_id, safe_variant]

static func load_library(weapon_id: String, variant: String = "standard") -> AnimationLibrary:
	var path := resource_path(weapon_id, variant)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as AnimationLibrary

static func has_variant(variant: String) -> bool:
	return StringName(variant.strip_edges().to_lower()) in VARIANTS
