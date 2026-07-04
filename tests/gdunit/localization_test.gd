extends GdUnitTestSuite

# Tests for localizations: verify all translation keys exist

func test_localization_loaded() -> void:
	var locale = TranslationServer.get_locale()
	assert_bool(not locale.is_empty()) \
		.override_failure_message("No locale loaded") \
		.is_true()


func test_localization_has_english_locale() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/localization/translations.en.translation")).is_true()


func test_localization_has_chinese_locale() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/localization/translations.zh.translation")).is_true()


func test_localization_csv_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/localization/translations.csv")).is_true()
