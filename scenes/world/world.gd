class_name World
extends Node3D

const LEVELS := [preload("res://scenes/expedition/procedural_dungeon.tscn")]

var current_level_index := 0
var current_loaded_level: BaseLevel = null

func _ready() -> void:
	GameEvents.level_restarted.connect(on_level_restarted)
	await _warm_shaders()
	AudioManager.start_music()
	load_level(current_level_index)

func _warm_shaders() -> void:
	var overlay := _create_loading_overlay()
	var warmer := ShaderWarmer.new()
	add_child(warmer)
	await warmer.finished
	warmer.queue_free()
	overlay.queue_free()

func _create_loading_overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var label := Label.new()
	label.text = tr("Computing shaders, please wait...")
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rect.add_child(label)
	add_child(layer)
	return layer

func on_level_restarted() -> void:
	load_level(current_level_index)

func load_level(index: int) -> void:
	if current_loaded_level != null:
		current_loaded_level.queue_free()
	if LEVELS.size() > index:
		current_loaded_level = LEVELS[index].instantiate()
		GameState.register_level(current_loaded_level)
		add_child(current_loaded_level)
