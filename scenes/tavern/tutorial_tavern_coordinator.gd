extends Node

const GOBLIN_SCENE := preload("res://scenes/characters/enemies/goblin.tscn")
const BARREL_SCENE := preload("res://scenes/props/barrel/barrel.tscn")
const WEAPON_SCENE := preload("res://scenes/equipment/pickable_item.tscn")
const DIALOGUE_BOX_SCENE := preload("res://scenes/ui/scripted_dialogue_box.tscn")
const HINT_OVERLAY_SCENE := preload("res://scenes/ui/tutorial_hint_overlay.tscn")
const NAME_PROMPT_SCENE := preload("res://scenes/ui/character_name_prompt.tscn")

enum Stage {
	WAIT_LEAVE_DOOR,
	STUN_GOBLIN,
	PICKUP_WEAPON,
	COMBAT,
	NAME_LETTER,
	COMPLETE,
}

var tavern: TavernInterior
var player: Player
var stage: Stage = Stage.WAIT_LEAVE_DOOR
var entrance_point := Vector3.ZERO
var goblin: Enemy
var barrel: PickableItem
var tutorial_weapon: PickableItem
var dialogue_box: ScriptedDialogueBox
var hint_overlay: TutorialHintOverlay
var name_prompt: CharacterNamePrompt

func setup(owner_tavern: TavernInterior, player_node: Player) -> void:
	tavern = owner_tavern
	player = player_node

func _ready() -> void:
	if tavern == null:
		tavern = get_parent() as TavernInterior
	if player == null and tavern != null:
		player = tavern.get_node_or_null("Player") as Player
	if player == null:
		return
	entrance_point = player.global_position
	_mount_overlays()
	_show_dialogue(tr("NPC"), tr("Move away from the door. Something followed us."))
	_show_hint(tr("Step away from the tavern door"))

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	match stage:
		Stage.WAIT_LEAVE_DOOR:
			if player.global_position.distance_to(entrance_point) >= 1.0:
				_spawn_tutorial_goblin()
				_spawn_barrel()
				_show_dialogue(tr("NPC"), tr("Grab the barrel with E and throw it to stun the goblin."))
				_show_hint(tr("[E] Pick Up Barrel  |  [LMB] Throw"))
				stage = Stage.STUN_GOBLIN
		Stage.STUN_GOBLIN:
			if goblin != null and goblin.state == Enemy.State.STUNNED:
				_spawn_weapon_pickup()
				_show_dialogue(tr("NPC"), tr("Behind the bar. Take the weapon."))
				_show_hint(tr("[E] Pick Up Weapon"))
				stage = Stage.PICKUP_WEAPON
		Stage.PICKUP_WEAPON:
			if tutorial_weapon == null or not is_instance_valid(tutorial_weapon):
				_show_dialogue(tr("NPC"), tr("Fight. Left click attacks. Right click blocks. F kicks."))
				_show_hint(tr("[LMB] Attack  |  [RMB] Block  |  [F] Kick"))
				player.set_tutorial_input_enabled(true, true, true)
				stage = Stage.COMBAT
		Stage.COMBAT:
			if goblin == null or not is_instance_valid(goblin) or goblin.state == Enemy.State.DEAD:
				_open_name_prompt()
				stage = Stage.NAME_LETTER

func _mount_overlays() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TutorialOverlayLayer"
	add_child(layer)
	dialogue_box = DIALOGUE_BOX_SCENE.instantiate() as ScriptedDialogueBox
	hint_overlay = HINT_OVERLAY_SCENE.instantiate() as TutorialHintOverlay
	layer.add_child(dialogue_box)
	layer.add_child(hint_overlay)

func _show_dialogue(speaker: String, text: String) -> void:
	if dialogue_box != null:
		dialogue_box.show_line(speaker, text)
	GameEvents.subtitle_changed.emit(text)

func _show_hint(text: String) -> void:
	if hint_overlay != null:
		hint_overlay.show_hint(text)
	GameEvents.tutorial_hint_changed.emit(text)

func _spawn_tutorial_goblin() -> void:
	goblin = GOBLIN_SCENE.instantiate() as Enemy
	goblin.global_position = entrance_point + Vector3(0.0, 0.0, -1.6)
	goblin.player = player
	goblin.duration_stun = 5000
	tavern.add_child(goblin)

func _spawn_barrel() -> void:
	barrel = BARREL_SCENE.instantiate() as PickableItem
	barrel.global_position = entrance_point + Vector3(1.2, 0.0, -0.6)
	tavern.add_child(barrel)

func _spawn_weapon_pickup() -> void:
	tutorial_weapon = WEAPON_SCENE.instantiate() as PickableItem
	tutorial_weapon.weapon_data = load("res://data/weapons/axe.tres")
	tutorial_weapon.global_position = Vector3(0.0, 0.2, -5.6)
	tavern.add_child(tutorial_weapon)

func _open_name_prompt() -> void:
	_show_dialogue(tr("NPC"), tr("The tavern is yours. Sign the inheritance letter."))
	_show_hint(tr("Write your permanent name into the letter"))
	var world := _find_world()
	if world != null and world.has_method("open_overlay_scene"):
		name_prompt = world.call("open_overlay_scene", NAME_PROMPT_SCENE) as CharacterNamePrompt
	else:
		var layer := CanvasLayer.new()
		add_child(layer)
		name_prompt = NAME_PROMPT_SCENE.instantiate() as CharacterNamePrompt
		layer.add_child(name_prompt)
	if name_prompt != null:
		name_prompt.name_confirmed.connect(_on_name_confirmed, CONNECT_ONE_SHOT)

func _on_name_confirmed(_name_text: String) -> void:
	if hint_overlay != null:
		hint_overlay.clear_hint()
	if dialogue_box != null:
		dialogue_box.hide_line()
	GameEvents.subtitle_changed.emit("")
	GameEvents.tutorial_hint_changed.emit("")
	if TavernManager != null:
		TavernManager.tutorial_completed = false
	stage = Stage.COMPLETE

func _find_world() -> Node:
	var node: Node = tavern
	while node != null:
		if node.has_method("load_space") and node.has_method("open_zone_select"):
			return node
		node = node.get_parent()
	return null
