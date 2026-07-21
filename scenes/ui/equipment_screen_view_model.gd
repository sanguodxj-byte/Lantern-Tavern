class_name EquipmentScreenViewModel
extends RefCounted

## Pure presentation rules for the equipment screen.
##
## The panel still owns game-state reads and mutations. This module owns the
## small, deterministic decisions that make the inventory view consistent:
## which filter accepts an entry and how stat rows are represented for a
## renderer. Keeping this seam free of SceneTree nodes makes it the primary
## test surface for the next equipment UI iterations.

const FILTER_ALL := "all"
const FILTER_EQUIPMENT := "equipment"
const FILTER_WEAPONS := "weapons"
const FILTER_ARMOR := "armor"
const FILTER_MATERIALS := "materials"
const FILTER_RUNES := "runes"

const QUALITY_COLORS := {
	"common": Color(0.62, 0.56, 0.48, 1.0),
	"uncommon": Color(0.44, 0.72, 0.58, 1.0),
	"rare": Color(0.43, 0.63, 0.88, 1.0),
	"epic": Color(0.78, 0.48, 0.84, 1.0),
}

const QUALITY_LABELS := {
	"common": "普通",
	"uncommon": "优良",
	"rare": "稀有",
	"epic": "史诗",
}

static func accepts_filter(item_type: String, filter_id: String) -> bool:
	if filter_id == FILTER_ALL or filter_id.is_empty():
		return true
	if filter_id == FILTER_EQUIPMENT:
		return item_type == "weapon" or item_type == "armor"
	if filter_id == FILTER_WEAPONS:
		return item_type == "weapon"
	if filter_id == FILTER_ARMOR:
		return item_type == "armor"
	if filter_id == FILTER_MATERIALS:
		return item_type == "material"
	if filter_id == FILTER_RUNES:
		return item_type == "rune"
	return false

static func filter_entries(entries: Array, filter_id: String) -> Array:
	var filtered: Array = []
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		if accepts_filter(String(entry.get("type", "")), filter_id):
			filtered.append(entry)
	return filtered

static func make_stat_rows(lines: Array) -> Array:
	var rows: Array = []
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if line.is_empty():
			continue
		var parts := line.split(" ", false, 1)
		rows.append({
			"label": String(parts[0]),
			"value": String(parts[1]) if parts.size() > 1 else "",
		})
	return rows

static func filter_label(filter_id: String) -> String:
	match filter_id:
		FILTER_EQUIPMENT:
			return "装备"
		FILTER_WEAPONS:
			return "武器"
		FILTER_ARMOR:
			return "防具"
		FILTER_MATERIALS:
			return "材料"
		FILTER_RUNES:
			return "符文"
	return "全部"

## Returns a stable rarity bucket for the inventory renderer. Equipment affix
## labels and rune rarities enter through this small interface; the renderer
## never needs to know how either system stores its data.
static func quality_tier_for(item_type: String, quality_label: String = "", rarity: String = "") -> String:
	var source := rarity if not rarity.is_empty() else quality_label
	match source.to_lower():
		"稀有", "rare":
			return "rare"
		"史诗", "epic", "legendary":
			return "epic"
		"优良", "精良", "uncommon":
			return "uncommon"
		"瑕疵", "common", "普通":
			return "common"
	return "common" if item_type in ["weapon", "armor", "rune"] else ""

static func quality_label_for_tier(tier: String) -> String:
	return String(QUALITY_LABELS.get(tier, ""))

static func quality_color_for_tier(tier: String) -> Color:
	return QUALITY_COLORS.get(tier, Color(0.45, 0.40, 0.35, 1.0))

## Produces comparison rows without depending on SceneTree nodes or UI labels.
## The Interface is deliberately object/dictionary tolerant because runtime
## equipment uses WeaponData while focused tests can use plain dictionaries.
static func build_equipment_comparison(candidate: Variant, equipped: Variant) -> Array:
	var rows: Array = []
	if candidate == null:
		return rows
	_append_numeric_row(rows, "攻击", candidate, equipped, "damage_min", "damage_max", true)
	_append_numeric_row(rows, "物防", candidate, equipped, "armor_phys_def", "armor_phys_def", false)
	_append_numeric_row(rows, "盾防", candidate, equipped, "shield_phys_def", "shield_phys_def", false)
	_append_numeric_row(rows, "距离", candidate, equipped, "reach", "reach", false)
	_append_numeric_row(rows, "暴击", candidate, equipped, "crit_bonus_percent", "crit_bonus_percent", false)
	return rows

static func format_comparison(rows: Array) -> String:
	if rows.is_empty():
		return ""
	var parts: Array[String] = []
	for raw_row in rows:
		if typeof(raw_row) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw_row
		var delta_text := String(row.get("delta_text", ""))
		var candidate_text := String(row.get("candidate", "—"))
		if delta_text.is_empty():
			parts.append("%s %s" % [row.get("label", ""), candidate_text])
		else:
			parts.append("%s %s" % [row.get("label", ""), delta_text])
	return "属性对比  " + "  ·  ".join(parts)

static func _append_numeric_row(rows: Array, label: String, candidate: Variant, equipped: Variant, first_field: String, second_field: String, is_range: bool) -> void:
	var candidate_first = _read_numeric(candidate, first_field)
	var candidate_second = _read_numeric(candidate, second_field)
	if candidate_first == null or candidate_second == null:
		return
	if is_zero_approx(float(candidate_first)) and is_zero_approx(float(candidate_second)):
		return
	var equipped_first = _read_numeric(equipped, first_field)
	var equipped_second = _read_numeric(equipped, second_field)
	var candidate_score := (float(candidate_first) + float(candidate_second)) * 0.5 if is_range else float(candidate_first)
	var equipped_score := (float(equipped_first) + float(equipped_second)) * 0.5 if equipped_first != null and equipped_second != null else 0.0
	var has_equipped := equipped_first != null and equipped_second != null
	var delta := candidate_score - equipped_score
	var delta_text := "新"
	if has_equipped:
		delta_text = _format_delta(delta, is_range)
	rows.append({
		"label": label,
		"candidate": _format_value(candidate_first, candidate_second, is_range),
		"equipped": _format_value(equipped_first, equipped_second, is_range) if has_equipped else "空槽",
		"delta": delta,
		"delta_text": delta_text,
		"direction": "new" if not has_equipped else ("up" if delta > 0.01 else ("down" if delta < -0.01 else "same")),
	})

static func _read_numeric(source: Variant, field: String) -> Variant:
	if source == null:
		return null
	if typeof(source) == TYPE_DICTIONARY:
		var dict: Dictionary = source
		return float(dict[field]) if dict.has(field) else null
	if source is Object and field in source:
		return float(source.get(field))
	return null

static func _format_value(first: Variant, second: Variant, is_range: bool) -> String:
	if first == null or second == null:
		return "—"
	if is_range:
		return "%d–%d" % [int(first), int(second)]
	var value := float(first)
	return "%+.1f" % value if not is_equal_approx(value, round(value)) else "%+d" % int(value)

static func _format_delta(delta: float, is_range: bool) -> String:
	if is_range:
		return "%+.1f" % delta if not is_equal_approx(delta, round(delta)) else "%+d" % int(delta)
	return "%+.1f" % delta if not is_equal_approx(delta, round(delta)) else "%+d" % int(delta)
