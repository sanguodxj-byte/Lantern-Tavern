class_name World
extends Node3D

const TAVERN_SCENE_PATH := "res://scenes/tavern/tavern.tscn"
const DUNGEON_SCENE_PATH := "res://scenes/expedition/procedural_dungeon.tscn"
const INTRO_SCENE_PATH := "res://scenes/intro/new_game_intro.tscn"
const ZONE_SELECT_SCENE_PATH := "res://scenes/ui/zone_select.tscn"

const SPACE_INTRO := "intro"
const SPACE_TAVERN := "tavern"
const SPACE_DUNGEON := "dungeon"

const FPS_OVERLAY_SCENE := preload("res://scenes/ui/fps_overlay.tscn")

var current_loaded_level: Node3D = null
var current_space: String = ""
var overlay_layer: CanvasLayer = null

@onready var world_ui: UI = $UI
@onready var combat_hud: CanvasLayer = $CombatHUD

func _ready() -> void:
	GameEvents.level_restarted.connect(on_level_restarted)
	await _warm_shaders()
	AudioManager.start_music()
	_add_fps_overlay()
	_load_initial_space()

func _add_fps_overlay() -> void:
	# 常驻 World：跨越酒馆/地牢，可见性由 Settings.show_fps 控制。
	var fps_overlay := FPS_OVERLAY_SCENE.instantiate()
	add_child(fps_overlay)

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
	if current_space == SPACE_DUNGEON:
		transition_to_dungeon()

func _load_initial_space() -> void:
	var tm: Node = _get_tavern_manager()
	if tm != null and tm.get("tutorial_active"):
		load_space(SPACE_INTRO)
	elif tm != null and (tm.current_phase == tm.Phase.NIGHT_TAVERN or tm.current_phase == tm.Phase.DAY_EXPEDITION):
		transition_to_tavern()
	else:
		transition_to_dungeon()

func transition_to_tavern() -> void:
	load_space(SPACE_TAVERN)

func transition_to_dungeon() -> void:
	load_space(SPACE_DUNGEON)

func load_space(space: String) -> void:
	_clear_overlay()
	if current_loaded_level != null:
		current_loaded_level.queue_free()
		current_loaded_level = null
	current_space = space
	var scene_path := ""
	match space:
		SPACE_INTRO:
			scene_path = INTRO_SCENE_PATH
		SPACE_TAVERN:
			scene_path = TAVERN_SCENE_PATH
		_:
			scene_path = DUNGEON_SCENE_PATH
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("[World] Cannot load space scene: " + scene_path)
		return
	current_loaded_level = packed.instantiate() as Node3D
	if current_loaded_level == null:
		push_error("[World] Space scene root must be Node3D: " + scene_path)
		return
	add_child(current_loaded_level)
	if GameState and current_loaded_level is BaseLevel:
		GameState.register_level(current_loaded_level)
	_update_shared_ui()

func open_overlay_scene(packed_scene: PackedScene) -> Node:
	_clear_overlay()
	overlay_layer = CanvasLayer.new()
	overlay_layer.name = "WorldOverlayLayer"
	overlay_layer.layer = 32
	var instance := packed_scene.instantiate()
	overlay_layer.add_child(instance)
	add_child(overlay_layer)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	return instance

func open_zone_select() -> void:
	_clear_overlay()
	var packed := load(ZONE_SELECT_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("[World] Cannot load zone select scene")
		return
	overlay_layer = CanvasLayer.new()
	overlay_layer.name = "WorldOverlayLayer"
	overlay_layer.layer = 32
	overlay_layer.add_child(packed.instantiate())
	add_child(overlay_layer)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_overlay() -> void:
	_clear_overlay()

func _clear_overlay() -> void:
	if overlay_layer != null:
		overlay_layer.queue_free()
		overlay_layer = null

func _update_shared_ui() -> void:
	if world_ui != null and world_ui.has_method("set_world_space"):
		world_ui.set_world_space(current_space)
	if combat_hud != null and combat_hud.has_method("set_world_space"):
		combat_hud.set_world_space(current_space)

func _get_tavern_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TavernManager")
