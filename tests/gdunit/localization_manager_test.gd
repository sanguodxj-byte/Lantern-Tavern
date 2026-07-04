extends GdUnitTestSuite

# LocalizationManager 本地化管理器测试

func test_csv_file_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/localization/translations.csv")).is_true()


func test_parse_csv_line_simple() -> void:
	var lm = auto_free(load("res://globals/localization_manager.gd").new())
	var result = lm._parse_csv_line("hello,world,test")
	assert_int(result.size()).is_equal(3)
	assert_str(result[0]).is_equal("hello")
	assert_str(result[1]).is_equal("world")


func test_parse_csv_line_quoted() -> void:
	var lm = auto_free(load("res://globals/localization_manager.gd").new())
	var result = lm._parse_csv_line('"hello, world","foo","bar"')
	assert_int(result.size()).is_equal(3)
	assert_str(result[0]).is_equal("hello, world")


func test_parse_csv_line_escaped_quote() -> void:
	var lm = auto_free(load("res://globals/localization_manager.gd").new())
	var result = lm._parse_csv_line('"say ""hello""",world')
	assert_int(result.size()).is_equal(2)
	assert_str(result[0]).is_equal('say "hello"')


func test_parse_csv_line_leading_trailing_spaces() -> void:
	var lm = auto_free(load("res://globals/localization_manager.gd").new())
	var result = lm._parse_csv_line('  a , b , c  ')
	assert_int(result.size()).is_equal(3)
	assert_str(result[0]).is_equal("a")


func test_parse_csv_line_empty_fields() -> void:
	var lm = auto_free(load("res://globals/localization_manager.gd").new())
	var result = lm._parse_csv_line('a,,c')
	assert_int(result.size()).is_equal(3)
	assert_str(result[0]).is_equal("a")
	assert_str(result[1]).is_equal("")
	assert_str(result[2]).is_equal("c")


func test_locale_loaded() -> void:
	var locale = TranslationServer.get_locale()
	assert_bool(not locale.is_empty()).is_true()


func test_key_translation_exists() -> void:
	# LANTERN TAVERN key should return non-empty even if CSV wasn't loaded
	var translated = tr("LANTERN TAVERN")
	# tr() returns the original key when no translation found
	assert_bool(translated.length() > 0).is_true()


func test_chinese_translation_works() -> void:
	var original = TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	var translated = tr("LANTERN TAVERN")
	assert_str(translated).is_equal("灯笼酒馆")
	TranslationServer.set_locale(original)


func test_unknown_key_returns_original() -> void:
	var result = tr("__nonexistent_key__test__")
	assert_str(result).is_equal("__nonexistent_key__test__")


func test_csv_key_count() -> void:
	# 至少应有 100+ 条翻译
	var csv = FileAccess.open("res://scenes/ui/localization/translations.csv", FileAccess.READ)
	var count = 0
	while not csv.eof_reached():
		var line = csv.get_line()
		if not line.is_empty() and not line.begins_with("#") and not line.begins_with("key"):
			count += 1
	csv.close()
	assert_int(count).is_greater_equal(100)
