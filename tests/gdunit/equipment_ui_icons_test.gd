extends GdUnitTestSuite
## 装备/战利品 UI 图标：路径存在、可加载、材料不再统一回退默认武器图。

const DETAIL := preload("res://scenes/ui/equipment_detail_popup.gd")


func test_all_weapon_registry_icons_exist_on_disk() -> void:
	var wr: Node = Engine.get_main_loop().root.get_node("WeaponRegistry")
	assert_object(wr).is_not_null()
	var missing: Array[String] = []
	for eid in wr.get_all_ids():
		var path: String = wr.get_icon_path(String(eid))
		var abs_path := ProjectSettings.globalize_path(path)
		if path.is_empty() or not FileAccess.file_exists(abs_path):
			missing.append("%s -> %s" % [eid, path])
	assert_array(missing) \
		.override_failure_message("缺少装备图标文件:\n%s" % "\n".join(missing)) \
		.is_empty()


func test_icon_for_equipment_loads_non_null_textures() -> void:
	for eid in ["shortsword", "axe", "greatsword", "shield", "cloth_armor", "plate_armor"]:
		var tex: Texture2D = DETAIL.icon_for_equipment_id(eid)
		assert_object(tex) \
			.override_failure_message("装备图标加载失败: %s" % eid) \
			.is_not_null()
		assert_int(tex.get_width()).is_greater_equal(32)
		assert_int(tex.get_height()).is_greater_equal(32)


func test_material_icons_are_not_all_default_weapon_icon() -> void:
	var default_tex: Texture2D = DETAIL.icon_for_equipment_id("__missing_id__")
	# missing id falls back to default weapon icon
	var mat_tex: Texture2D = DETAIL.icon_for_material("rat_tail")
	assert_object(mat_tex).is_not_null()
	# path should prefer materials dir
	var path: String = DETAIL.material_icon_path("rat_tail")
	assert_str(path).contains("icons/materials/rat_tail.png")
	assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(path))).is_true()


func test_material_icon_path_helper_exists_for_common_materials() -> void:
	for mid in ["rat_tail", "glowshroom", "goblin_nail", "bone_shard", "slime_jelly"]:
		var path: String = DETAIL.material_icon_path(mid)
		assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(path))) \
			.override_failure_message("材料图标缺失: %s" % path) \
			.is_true()
		var tex: Texture2D = DETAIL.icon_for_material(mid)
		assert_object(tex).is_not_null()


func test_chest_and_equipment_panels_use_icon_helpers() -> void:
	var chest := FileAccess.get_file_as_string("res://scenes/ui/chest_loot_panel.gd")
	assert_bool(chest.contains("icon_for_equipment_id")).is_true()
	assert_bool(chest.contains("icon_for_material")).is_true()
	var tavern := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	assert_bool(tavern.contains("icon_for_equipment_id") or tavern.contains("_icon_for_equipment_id")).is_true()
	var char_panel := FileAccess.get_file_as_string("res://scenes/ui/character_panel.gd")
	assert_bool(char_panel.contains("icon_for_equipment_id")).is_true()


func test_equipment_icon_files_are_readable_images() -> void:
	var sample := [
		"res://assets/textures/icons/equipment/weapons_shortsword.png",
		"res://assets/textures/icons/equipment/weapons_axe.png",
		"res://assets/textures/icons/equipment/armor_plate_armor.png",
		"res://assets/textures/icons/materials/rat_tail.png",
	]
	for path in sample:
		var abs_path := ProjectSettings.globalize_path(path)
		assert_bool(FileAccess.file_exists(abs_path)) \
			.override_failure_message("图标文件不存在: %s" % path).is_true()
		var img := Image.new()
		var err := img.load(path)
		assert_int(err).override_failure_message("无法解码图标: %s err=%d" % [path, err]).is_equal(OK)
		assert_int(img.get_width()).is_greater_equal(32)
		# not blank: sample some non-zero alpha pixels
		var visible := false
		for y in range(0, img.get_height(), maxi(1, img.get_height() / 8)):
			for x in range(0, img.get_width(), maxi(1, img.get_width() / 8)):
				if img.get_pixel(x, y).a > 0.1:
					visible = true
					break
			if visible:
				break
		assert_bool(visible).override_failure_message("图标疑似空白: %s" % path).is_true()
