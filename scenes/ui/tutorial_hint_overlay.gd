extends Control
class_name TutorialHintOverlay

@onready var hint_label: Label = get_node_or_null("Panel/Margin/HintLabel") as Label

func _ready() -> void:
	theme = preload("res://scenes/ui/lantern_theme.tres")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if hint_label != null:
		hint_label.text = ""

func show_hint(text: String) -> void:
	if hint_label == null:
		return
	hint_label.text = text
	visible = not text.is_empty()

func clear_hint() -> void:
	if hint_label == null:
		return
	hint_label.text = ""
	visible = false


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode in [KEY_ESCAPE, KEY_TAB]:
		get_viewport().set_input_as_handled()
		clear_hint()
