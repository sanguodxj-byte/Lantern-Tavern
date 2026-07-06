extends Node3D

const PLAYER_PREFAB := preload("res://scenes/characters/player/player.tscn")
const DIALOGUE_BOX_SCENE := preload("res://scenes/ui/scripted_dialogue_box.tscn")
const HINT_OVERLAY_SCENE := preload("res://scenes/ui/tutorial_hint_overlay.tscn")

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var intro_door: Door = $IntroDoor
@onready var blink_overlay: ColorRect = $IntroCanvas/BlinkOverlay

var player: Player
var dialogue_box: ScriptedDialogueBox
var hint_overlay: TutorialHintOverlay

func _ready() -> void:
	_spawn_player()
	_mount_overlays()
	if intro_door != null:
		intro_door.opened.connect(on_intro_door_opened, CONNECT_ONE_SHOT)
	_run_intro_sequence()

func _spawn_player() -> void:
	player = PLAYER_PREFAB.instantiate() as Player
	player.global_transform = player_spawn.global_transform
	add_child(player)
	player.set_tutorial_input_enabled(false, false, false)

func _mount_overlays() -> void:
	dialogue_box = DIALOGUE_BOX_SCENE.instantiate() as ScriptedDialogueBox
	hint_overlay = HINT_OVERLAY_SCENE.instantiate() as TutorialHintOverlay
	$IntroCanvas.add_child(dialogue_box)
	$IntroCanvas.add_child(hint_overlay)

func _run_intro_sequence() -> void:
	await get_tree().process_frame
	if player != null and player.camera != null and player.camera.has_method("play_wakeup_blink"):
		player.camera.play_wakeup_blink()
	var tween := create_tween()
	tween.tween_property(blink_overlay, "modulate:a", 0.0, 0.45)
	dialogue_box.show_line(tr("NPC"), tr("hey! you! finally wake"))
	GameEvents.subtitle_changed.emit(tr("hey! you! finally wake"))
	await get_tree().create_timer(1.2).timeout
	hint_overlay.show_hint(tr("WASD Move  |  Shift Run"))
	GameEvents.tutorial_hint_changed.emit(tr("WASD Move  |  Shift Run"))
	player.set_tutorial_input_enabled(true, true, false)
	intro_door.tutorial_locked_message = tr("It will not push open.")
	intro_door.requires_kick_to_open = true
	intro_door.tutorial_kick_prompt = tr("[F] Kick Door")

func on_intro_door_opened() -> void:
	dialogue_box.hide_line()
	hint_overlay.clear_hint()
	GameEvents.subtitle_changed.emit("")
	GameEvents.tutorial_hint_changed.emit("")
	if TavernManager:
		TavernManager.complete_intro_and_enter_tavern()
