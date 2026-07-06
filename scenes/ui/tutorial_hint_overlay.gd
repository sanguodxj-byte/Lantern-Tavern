extends Control
class_name TutorialHintOverlay

@onready var hint_label: Label = get_node_or_null("Panel/Margin/HintLabel") as Label

func _ready() -> void:
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
