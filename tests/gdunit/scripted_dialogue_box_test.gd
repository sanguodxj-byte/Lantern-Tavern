extends GdUnitTestSuite

const DIALOGUE_SCENE := "res://scenes/ui/scripted_dialogue_box.tscn"


func test_show_line_works_before_scene_enters_tree() -> void:
	var scene := load(DIALOGUE_SCENE) as PackedScene
	var dialogue := scene.instantiate() as ScriptedDialogueBox

	dialogue.show_line("NPC", "Move away from the door.")

	assert_bool(dialogue.visible).is_true()
	assert_str(dialogue.get_node("Panel/Margin/VBox/SpeakerName").text).is_equal("NPC")
	assert_str(dialogue.get_node("Panel/Margin/VBox/DialogueText").text).is_equal("Move away from the door.")
	dialogue.free()


func test_hide_line_clears_labels_after_immediate_show() -> void:
	var scene := load(DIALOGUE_SCENE) as PackedScene
	var dialogue := scene.instantiate() as ScriptedDialogueBox

	dialogue.show_line("NPC", "The tavern is yours.")
	dialogue.hide_line()

	assert_bool(dialogue.visible).is_false()
	assert_str(dialogue.get_node("Panel/Margin/VBox/SpeakerName").text).is_empty()
	assert_str(dialogue.get_node("Panel/Margin/VBox/DialogueText").text).is_empty()
	dialogue.free()
