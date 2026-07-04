extends GdUnitTestSuite

# Spot-check script indentation: ensure no spaces used where tabs expected.

func test_character_panel_indent_consistency() -> void:
	var file = FileAccess.open("res://scenes/ui/character_panel.gd", FileAccess.READ)
	assert_object(file).is_not_null()
	var text = file.get_as_text()
	file.close()
	var lines = text.split("\n")
	var issue_count = 0
	for i in range(lines.size()):
		var line = lines[i]
		if line.length() > 0 and line[0] == " " and line[0] != "\t":
			issue_count += 1
	assert_int(issue_count).is_equal(0) \
		.override_failure_message("character_panel.gd has %d space-indented lines" % issue_count) \
		.is_equal(0)


func test_weapon_registry_indent_consistency() -> void:
	var file = FileAccess.open("res://data/weapon_registry.gd", FileAccess.READ)
	assert_object(file).is_not_null()
	var text = file.get_as_text()
	file.close()
	var lines = text.split("\n")
	var issue_count = 0
	for i in range(lines.size()):
		var line = lines[i]
		if line.length() > 0 and line[0] == " " and line[0] != "\t":
			issue_count += 1
	assert_int(issue_count).is_equal(0) \
		.override_failure_message("weapon_registry.gd has %d space-indented lines" % issue_count)


func test_main_gdscript_files_have_no_tab_after_space() -> void:
	# Only check the files we actively maintain, not third-party addons
	var files_to_check := [
		"res://data/weapon_data.gd",
		"res://data/shield_data.gd",
		"res://data/furniture_data.gd",
		"res://data/weapon_registry.gd",
		"res://scenes/ui/model_viewer.gd",
		"res://scenes/ui/character_panel.gd",
		"res://scenes/expedition/procedural_dungeon.gd",
		"res://scenes/expedition/wfc_visual_test.gd",
		"res://scenes/props/chest/chest.gd",
		"res://globals/skill_data.gd",
	]
	for path in files_to_check:
		if not ResourceLoader.exists(path):
			continue
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text = file.get_as_text()
		file.close()
		var lines = text.split("\n")
		for i in range(lines.size()):
			var line = lines[i]
			if line.length() > 0 and line[0] == " " and line[0] != "\t":
				assert_str("").override_failure_message(
				"%s:%d uses spaces for indentation" % [path, i + 1]
				).is_not_empty()


func test_critical_scripts_parse_successfully() -> void:
	# 语法冒烟测试：对关键脚本执行 load()，若语法错误（如悬浮 else、缩进混用）
	# Godot 解析器会拒绝加载并返回 null，测试立即失败。
	var scripts_to_check := [
		"res://scenes/expedition/procedural_dungeon.gd",
		"res://scenes/expedition/wfc_visual_test.gd",
		"res://scenes/props/chest/chest.gd",
		"res://globals/skill_data.gd",
		"res://scenes/ui/character_panel.gd",
		"res://data/weapon_registry.gd",
		"res://globals/tavern_manager.gd",
		"res://globals/combat_engine.gd",
		"res://scenes/expedition/bsp_generator.gd",
		"res://globals/localization_manager.gd",
	]
	var failures: Array[String] = []
	for path in scripts_to_check:
		if not ResourceLoader.exists(path):
			failures.append("%s: 资源路径不存在" % path)
			continue
		var script_res = load(path)
		if script_res == null:
			failures.append("%s: load() 返回 null（语法错误或资源损坏）" % path)
			continue
		# GDScript 实例检查：只有有效的脚本才会是 GDScript 类型
		if not (script_res is GDScript):
			failures.append("%s: 加载成功但非 GDScript 类型" % path)
	var report := "\n".join(failures)
	assert_bool(failures.is_empty()) \
		.override_failure_message("以下脚本语法检查失败，请修复后再提交:\n" + report) \
		.is_true()
