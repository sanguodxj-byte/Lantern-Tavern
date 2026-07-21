extends GdUnitTestSuite

const VIEW_MODEL := preload("res://scenes/ui/equipment_screen_view_model.gd")

func test_filter_accepts_equipment_subtypes() -> void:
	assert_bool(VIEW_MODEL.accepts_filter("weapon", VIEW_MODEL.FILTER_EQUIPMENT)).is_true()
	assert_bool(VIEW_MODEL.accepts_filter("armor", VIEW_MODEL.FILTER_EQUIPMENT)).is_true()
	assert_bool(VIEW_MODEL.accepts_filter("material", VIEW_MODEL.FILTER_EQUIPMENT)).is_false()

func test_filter_entries_preserves_order_and_metadata() -> void:
	var entries := [
		{"type": "weapon", "id": "shortsword"},
		{"type": "material", "id": "glowshroom"},
		{"type": "armor", "id": "chain"},
	]
	var filtered: Array = VIEW_MODEL.filter_entries(entries, VIEW_MODEL.FILTER_EQUIPMENT)
	assert_int(filtered.size()).is_equal(2)
	assert_str(String(filtered[0].get("id"))).is_equal("shortsword")
	assert_str(String(filtered[1].get("id"))).is_equal("chain")

func test_unknown_filter_is_explicitly_empty() -> void:
	var entries := [{"type": "weapon", "id": "shortsword"}]
	assert_array(VIEW_MODEL.filter_entries(entries, "missing")).is_empty()

func test_stat_rows_are_structured_for_renderers() -> void:
	var rows: Array = VIEW_MODEL.make_stat_rows(["生命 78 / 100", "攻击 24–31", "未找到实机角色"])
	assert_int(rows.size()).is_equal(3)
	assert_str(String(rows[0].get("label"))).is_equal("生命")
	assert_str(String(rows[0].get("value"))).is_equal("78 / 100")
	assert_str(String(rows[2].get("value"))).is_empty()

func test_quality_bucket_maps_equipment_and_runes_to_shared_visual_tokens() -> void:
	assert_str(VIEW_MODEL.quality_tier_for("weapon", "精良")).is_equal("uncommon")
	assert_str(VIEW_MODEL.quality_tier_for("rune", "", "rare")).is_equal("rare")
	assert_str(VIEW_MODEL.quality_label_for_tier("epic")).is_equal("史诗")
	assert_object(VIEW_MODEL.quality_color_for_tier("rare")).is_not_null()

func test_equipment_comparison_reports_upgrade_delta() -> void:
	var candidate := {
		"damage_min": 24,
		"damage_max": 31,
		"armor_phys_def": 0,
		"reach": 1.2,
	}
	var equipped := {
		"damage_min": 18,
		"damage_max": 25,
		"armor_phys_def": 0,
		"reach": 1.0,
	}
	var rows: Array = VIEW_MODEL.build_equipment_comparison(candidate, equipped)
	assert_int(rows.size()).is_equal(2)
	assert_str(String(rows[0].get("label"))).is_equal("攻击")
	assert_str(String(rows[0].get("delta_text"))).is_equal("+6")
	assert_str(String(rows[0].get("direction"))).is_equal("up")
	assert_str(VIEW_MODEL.format_comparison(rows)).contains("攻击 +6")

func test_equipment_comparison_marks_empty_slot_as_new() -> void:
	var candidate := {"armor_phys_def": 6, "shield_phys_def": 0}
	var rows: Array = VIEW_MODEL.build_equipment_comparison(candidate, null)
	assert_int(rows.size()).is_equal(1)
	assert_str(String(rows[0].get("equipped"))).is_equal("空槽")
	assert_str(String(rows[0].get("delta_text"))).is_equal("新")
