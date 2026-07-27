extends Control
class_name ScriptedDialogueBox

var text_label: Label
var speaker_label: Label

func _ready() -> void:
	theme = preload("res://scenes/ui/lantern_theme.tres")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bind_labels()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_line(speaker: String, text: String) -> void:
	_bind_labels()
	if speaker_label == null or text_label == null:
		push_error("ScriptedDialogueBox is missing SpeakerName or DialogueText labels.")
		return
	speaker_label.text = speaker
	text_label.text = text
	visible = true

func hide_line() -> void:
	_bind_labels()
	visible = false
	if speaker_label != null:
		speaker_label.text = ""
	if text_label != null:
		text_label.text = ""


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode in [KEY_ESCAPE, KEY_TAB]:
		get_viewport().set_input_as_handled()
		hide_line()

func _bind_labels() -> void:
	if text_label == null:
		text_label = get_node_or_null("Panel/Margin/VBox/DialogueText") as Label
	if speaker_label == null:
		speaker_label = get_node_or_null("Panel/Margin/VBox/SpeakerName") as Label
