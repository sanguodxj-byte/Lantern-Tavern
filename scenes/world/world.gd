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
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

var current_loaded_level: Node3D = null
var current_space: String = ""
var overlay_layer: CanvasLayer = null
var _default_environment: Environment = null

@onready var world_ui: UI = $UI
@onready var combat_hud: CanvasLayer = $CombatHUD
@onready var world_environment: WorldEnvironment = $WorldEnvironment

func _ready() -> void:
	_default_environment = world_environment.environment
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

## 进入当前区域的下一楼层，不触发撤离结算或酒馆结算。
## 楼层状态由 GameState 持有，场景重载后由 DungeonRuntime 挂载新的 HUD。
func transition_to_next_floor() -> void:
	if current_space != SPACE_DUNGEON:
		return
	if GameState != null and GameState.has_method("advance_dungeon_floor"):
		GameState.advance_dungeon_floor()
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
	_adopt_level_environment(current_loaded_level)
	# 同步全局像素着色开关到新加载的场景树。
	# 酒馆/地牢场景内嵌大量 ShaderMaterial（dungeon_terrain.gdshader），
	# 其 pixel_lighting_enabled 默认值为 1.0（toon 光照）。
	# 若不调用 apply_to_tree，关闭像素着色后这些材质仍显示 toon 光照。
	VOXEL_LIGHTING.apply_to_tree(current_loaded_level, true)
	if GameState and current_loaded_level is BaseLevel:
		GameState.register_level(current_loaded_level)
	_update_shared_ui()


func _adopt_level_environment(level: Node) -> void:
	var target := world_environment
	if target == null:
		target = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if target == null:
		return
	var level_environment := _find_level_environment(level)
	if level_environment == null or level_environment.environment == null:
		target.environment = _default_environment
		return
	target.environment = level_environment.environment
	level_environment.environment = null


func _find_level_environment(node: Node) -> WorldEnvironment:
	if node == null:
		return null
	for child in node.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
	for child in node.get_children():
		var found := _find_level_environment(child)
		if found != null:
			return found
	return null

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
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
