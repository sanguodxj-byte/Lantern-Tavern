extends Control
class_name SettingsMenu

@onready var master_volume_slider: HSlider = %MasterVolumeSlider
@onready var master_volume_value: Label = %MasterVolumeValue
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var language_option: OptionButton = %LanguageOption
@onready var back_btn: Button = %BackBtn

func _ready() -> void:
	_setup_language_options()
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	language_option.item_selected.connect(_on_language_selected)
	back_btn.pressed.connect(_on_back_pressed)
	_load_current_settings()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _setup_language_options() -> void:
	language_option.clear()
	language_option.add_item("English", 0)
	language_option.set_item_metadata(0, "en")
	language_option.add_item("简体中文", 1)
	language_option.set_item_metadata(1, "zh")

func _load_current_settings() -> void:
	var bus_index := _master_bus_index()
	var volume_linear := db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	master_volume_slider.value = clampf(volume_linear * 100.0, 0.0, 100.0)
	_update_master_volume_label(master_volume_slider.value)
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	language_option.select(1 if TranslationServer.get_locale().begins_with("zh") else 0)

func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus_index(), _volume_percent_to_db(value))
	_update_master_volume_label(value)

func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func _on_language_selected(index: int) -> void:
	var locale := String(language_option.get_item_metadata(index))
	if not locale.is_empty():
		TranslationServer.set_locale(locale)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _update_master_volume_label(value: float) -> void:
	master_volume_value.text = "%d%%" % int(round(value))

func _volume_percent_to_db(value: float) -> float:
	if value <= 0.0:
		return -80.0
	return linear_to_db(clampf(value, 0.0, 100.0) / 100.0)

func _master_bus_index() -> int:
	return max(0, AudioServer.get_bus_index("Master"))
