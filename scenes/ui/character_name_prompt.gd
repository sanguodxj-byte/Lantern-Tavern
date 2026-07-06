extends Control
class_name CharacterNamePrompt

signal name_confirmed(name_text: String)

var name_edit: LineEdit
var confirm_button: Button
var handprint: Label
var error_label: Label

func _ready() -> void:
	_bind_controls()
	if confirm_button != null:
		confirm_button.pressed.connect(_on_confirm_pressed)
	if name_edit != null:
		name_edit.text_submitted.connect(_on_name_submitted)
	if handprint != null:
		handprint.visible = false
	if error_label != null:
		error_label.text = ""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if name_edit != null:
		name_edit.grab_focus()

func _on_name_submitted(_text: String) -> void:
	_on_confirm_pressed()

func _on_confirm_pressed() -> void:
	_bind_controls()
	if name_edit == null or confirm_button == null or handprint == null or error_label == null:
		push_error("CharacterNamePrompt is missing required child controls.")
		return
	var trimmed := name_edit.text.strip_edges()
	if trimmed.is_empty():
		error_label.text = tr("Please write your name.")
		return
	if TavernManager:
		TavernManager.confirm_player_name(trimmed)
	handprint.text = tr("[Handprint]")
	handprint.visible = true
	confirm_button.disabled = true
	name_edit.editable = false
	name_confirmed.emit(trimmed)

func _bind_controls() -> void:
	if name_edit == null:
		name_edit = get_node_or_null("LetterPanel/Margin/VBox/NameRow/NameEdit") as LineEdit
	if confirm_button == null:
		confirm_button = get_node_or_null("LetterPanel/Margin/VBox/ConfirmRow/ConfirmButton") as Button
	if handprint == null:
		handprint = get_node_or_null("LetterPanel/Margin/VBox/ConfirmRow/Handprint") as Label
	if error_label == null:
		error_label = get_node_or_null("LetterPanel/Margin/VBox/ErrorLabel") as Label
