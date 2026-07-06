extends Control
class_name ScriptedDialogueBox

var text_label: Label
var speaker_label: Label

func _ready() -> void:
	_bind_labels()
	visible = false

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

func _bind_labels() -> void:
	if text_label == null:
		text_label = get_node_or_null("Panel/Margin/VBox/DialogueText") as Label
	if speaker_label == null:
		speaker_label = get_node_or_null("Panel/Margin/VBox/SpeakerName") as Label
