extends GdUnitTestSuite

const STATS_SCRIPT := "res://scenes/ui/equipment_stats_visual.gd"
const VIEW_MODEL_SCRIPT := "res://scenes/ui/equipment_screen_view_model.gd"


func test_stat_line_is_split_into_label_and_value() -> void:
	var view_model = (load(VIEW_MODEL_SCRIPT) as GDScript).new()
	var rows: Array = view_model.make_stat_rows(["生命 78 / 100"])
	var parsed: Dictionary = rows[0]
	assert_str(String(parsed.label)).is_equal("生命")
	assert_str(String(parsed.value)).is_equal("78 / 100")


func test_visual_tracks_hidden_source_label() -> void:
	var root := Control.new()
	add_child(root)
	var source := Label.new()
	source.name = "CharacterStatsText"
	source.text = "等级 8\n力量 STR 5\n生命 78 / 100\n敏捷 DEX 5\n感知 PER 5"
	root.add_child(source)
	var visual: Control = (load(STATS_SCRIPT) as GDScript).new()
	visual.name = "StatsVisual"
	visual.source_label_path = NodePath("../CharacterStatsText")
	root.add_child(visual)
	await await_idle_frame()
	assert_object(visual).is_not_null()
	assert_str(String(visual._source_label.text)).contains("生命")
	assert_int(visual._stat_rows.size()).is_equal(5)
	assert_str(String(visual._stat_rows[1].label)).is_equal("力量")
	assert_str(String(visual._stat_rows[1].value)).is_equal("STR 5")
	root.queue_free()


func test_stats_visual_uses_dense_two_column_readout() -> void:
	var source := FileAccess.get_file_as_string(STATS_SCRIPT)
	assert_str(source).contains("COLUMN_GAP")
	assert_str(source).contains("column_index := index % 2")
	assert_str(source).contains("const PIXEL := 4.0")
	assert_int(int(source.get_slice("const LABEL_FONT_SIZE := ", 1).split("\n")[0])).is_greater_equal(22)


func test_every_attribute_has_a_dedicated_pixel_icon() -> void:
	var visual_script := load(STATS_SCRIPT) as GDScript
	var labels := ["等级", "生命", "攻击", "护甲", "闪避", "暴击", "力量", "敏捷", "体质", "智力", "灵巧", "感知", "法力"]
	for label in labels:
		var pattern: Array = visual_script.pixel_icon_pattern(label)
		assert_int(pattern.size()).is_equal(10)
		assert_bool(pattern.has(".........." )).is_true()
		for row in pattern:
			assert_int(String(row).length()).is_equal(10)
		assert_object(visual_script.pixel_icon_palette(label)).is_not_null()


func test_attribute_icon_patterns_are_centered_and_mirrored() -> void:
	var visual_script := load(STATS_SCRIPT) as GDScript
	var labels := ["等级", "生命", "攻击", "护甲", "闪避", "暴击", "力量", "敏捷", "体质", "智力", "灵巧", "感知", "法力"]
	for label in labels:
		var pattern: Array = visual_script.pixel_icon_pattern(label)
		var filled_cells := 0
		for row_value in pattern:
			var row := String(row_value)
			assert_str(row.substr(0, 1)).is_equal(row.substr(9, 1))
			assert_str(row.substr(1, 1)).is_equal(row.substr(8, 1))
			assert_str(row.substr(2, 1)).is_equal(row.substr(7, 1))
			assert_str(row.substr(3, 1)).is_equal(row.substr(6, 1))
			assert_str(row.substr(4, 1)).is_equal(row.substr(5, 1))
			for cell in row:
				if cell != ".":
					filled_cells += 1
		assert_int(filled_cells).is_greater_equal(18)


func test_attribute_icons_keep_distinct_reference_silhouettes() -> void:
	var visual_script := load(STATS_SCRIPT) as GDScript
	var sword: Array = visual_script.pixel_icon_pattern("攻击")
	var eye: Array = visual_script.pixel_icon_pattern("感知")
	var book: Array = visual_script.pixel_icon_pattern("智力")
	var droplet: Array = visual_script.pixel_icon_pattern("法力")
	assert_str(String(sword[0])).is_equal("op......po")
	assert_str(String(eye[0])).is_equal("..........")
	assert_str(String(eye[4])).contains("ss")
	assert_str(String(book[3])).contains("ss")
	assert_str(String(droplet[7])).contains("ss")


func test_generated_attribute_icon_crops_exist_and_have_transparent_corners() -> void:
	var labels := ["level", "health", "attack", "armor", "evasion", "critical", "strength", "agility", "vitality", "intelligence", "dexterity", "perception", "mana"]
	for label in labels:
		var path := "res://assets/textures/icons/attributes/attribute_%s_aligned.png" % label
		assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(path))) \
			.override_failure_message("图生属性图标缺失: %s" % path).is_true()
		var image := Image.new()
		assert_int(image.load(path)).is_equal(OK)
		assert_int(image.get_width()).is_equal(64)
		assert_int(image.get_height()).is_equal(64)
		assert_float(image.get_pixel(0, 0).a).is_equal_approx(0.0)
		var bounds := image.get_used_rect()
		assert_int(int(bounds.position.x + bounds.size.x / 2.0)).is_equal(32)
		assert_int(int(bounds.position.y + bounds.size.y / 2.0)).is_equal(32)
