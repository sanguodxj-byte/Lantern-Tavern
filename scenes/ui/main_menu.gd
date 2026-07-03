extends Control
class_name MainMenu

@onready var start_button: Button = $MarginContainer/VBoxContainer/StartButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/SettingsButton
@onready var exit_button: Button = $MarginContainer/VBoxContainer/ExitButton
@onready var lang_toggle: Button = $MarginContainer/VBoxContainer/LangToggle

func _ready() -> void:
	# Bind buttons
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	lang_toggle.pressed.connect(_on_lang_toggle_pressed)
	
	# Initial UI updates based on current locale
	_update_lang_label()

func _on_start_pressed() -> void:
	# Transition to day expedition via TavernManager
	if TavernManager:
		TavernManager.gold = 100 # Reset or load gold
		TavernManager.materials_inventory.clear()
		TavernManager.enter_phase(TavernManager.Phase.DAY_EXPEDITION)
	else:
		# Fallback if TavernManager is not autoloaded yet
		get_tree().change_scene_to_file("res://scenes/expedition/expedition.tscn")

func _on_settings_pressed() -> void:
	print("Settings panel toggled! Resolution or scale can be adjusted here.")

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_lang_toggle_pressed() -> void:
	var current_locale = TranslationServer.get_locale()
	if current_locale.begins_with("zh"):
		TranslationServer.set_locale("en")
	else:
		TranslationServer.set_locale("zh")
	_update_lang_label()

func _update_lang_label() -> void:
	var current_locale = TranslationServer.get_locale()
	if current_locale.begins_with("zh"):
		lang_toggle.text = "Language: 简体中文 (CN)"
	else:
		lang_toggle.text = "Language: English (EN)"
