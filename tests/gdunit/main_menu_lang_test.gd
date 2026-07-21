extends GdUnitTestSuite

# 主菜单语言切换功能测试

var _menu: MainMenu
var _original_locale: String

func before() -> void:
	_original_locale = TranslationServer.get_locale()
	_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(_menu)


func after() -> void:
	TranslationServer.set_locale(_original_locale)


func test_lang_btn_exists() -> void:
	assert_object(_menu.lang_btn).is_not_null()
	assert_bool(_menu.lang_btn.visible).is_true()


func test_lang_btn_connected() -> void:
	assert_bool(_menu.lang_btn.pressed.is_connected(_menu._on_lang_toggle_pressed)).is_true()


func test_lang_btn_initially_shows_current_locale() -> void:
	var locale = TranslationServer.get_locale()
	if locale.begins_with("zh"):
		assert_str(_menu.lang_btn.text).contains("简体中文")
	else:
		assert_str(_menu.lang_btn.text).contains("English")


func test_toggle_switches_to_chinese() -> void:
	TranslationServer.set_locale("en")
	_menu._on_lang_toggle_pressed()
	assert_bool(TranslationServer.get_locale().begins_with("zh")).is_true()
	assert_str(_menu.lang_btn.text).contains("简体中文")
	# 按钮文本也应更新
	assert_str(_menu.start_btn.text).contains("开始")


func test_toggle_back_to_english_resets_text() -> void:
	var original = TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	var result_zh = tr("Start Game")
	assert_str(result_zh).contains("开始")
	TranslationServer.set_locale("en")
	var result_en = tr("Start Game")
	assert_str(result_en).contains("Start")
	TranslationServer.set_locale(original)
