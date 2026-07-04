class_name UI
extends CanvasLayer

const KEY_TEXTURE_PREFAB := preload("res://scenes/ui/key_texture.tscn")

@onready var action_panel: ColorRect = %ActionPanel
@onready var action_label: Label = %ActionLabel
@onready var death_screen: ColorRect = %DeathScreen
@onready var death_label: Label = %DeathScreen.get_node("Label")
@onready var health_indicator: StatIndicator = %HealthIndicator
@onready var hurt_vignette: Panel = %HurtVignette
@onready var key_container: HBoxContainer = %KeyContainer
@onready var shield_icon: TextureRect = %ShieldIcon
@onready var shield_indicator: StatIndicator = %ShieldIndicator
@onready var weapon_icon: TextureRect = %WeaponIcon
@onready var weapon_indicator: StatIndicator = %WeaponIndicator

func _ready() -> void:
	GameEvents.player_hurt.connect(on_player_hurt)
	GameEvents.player_dead.connect(on_player_dead)
	GameEvents.level_restarted.connect(on_level_restart)
	GameEvents.player_spawned.connect(on_player_spawned)
	GameEvents.shield_changed.connect(on_shield_changed)
	GameEvents.weapon_changed.connect(on_weapon_changed)
	GameEvents.possible_action_changed.connect(on_possible_action_changed)
	GameEvents.current_keys_changed.connect(on_current_keys_changed)
	
func on_player_hurt(player: Player) -> void:
	health_indicator.refresh(player.health.current_life, player.health.max_life)
	var tween := create_tween()
	tween.tween_property(hurt_vignette, "modulate:a", 1.0, 0.1)
	tween.tween_property(hurt_vignette, "modulate:a", 0.0, 0.1)

func on_player_dead() -> void:
	if is_instance_valid(death_label):
		death_label.text = tr("YOU DIED") + "\n\n" + tr("PRESS R TO RESTART")
	var tween := create_tween()
	tween.tween_property(death_screen, "modulate", Color.WHITE, 0.5)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)

func on_level_restart() -> void:
	death_screen.modulate = Color.TRANSPARENT

func on_player_spawned(player: Player) -> void:
	health_indicator.refresh(player.health.current_life, player.health.max_life)
	
func on_weapon_changed(weapon_data: WeaponData) -> void:
	weapon_icon.visible = weapon_data != null
	weapon_indicator.visible = weapon_data != null
	if weapon_data:
		weapon_indicator.refresh(weapon_data.condition, weapon_data.max_condition)

func on_shield_changed(shield_data: ShieldData) -> void:
	shield_icon.visible = shield_data != null
	shield_indicator.visible = shield_data != null
	if shield_data:
		shield_indicator.refresh(shield_data.condition, shield_data.max_condition)

func on_possible_action_changed(action: String) -> void:
	action_panel.visible = not action.is_empty()
	action_label.text = action

func on_current_keys_changed(_color: Door.KeyColor) -> void:
	for child: TextureRect in key_container.get_children():
		child.queue_free()
	for key_color: Door.KeyColor in Door.KeyColor.values():
		if GameState.has_key(key_color):
			var texture := KEY_TEXTURE_PREFAB.instantiate() as TextureRect
			key_container.add_child(texture)
			texture.modulate = Door.COLOR_MAP[key_color]

const CHARACTER_PANEL_PREFAB := preload("res://scenes/ui/character_panel.tscn")
var character_panel_instance: CharacterPanel = null

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		# Consume the event to prevent propagation
		get_viewport().set_input_as_handled()
		toggle_character_panel()

func toggle_character_panel() -> void:
	if death_screen and death_screen.modulate.a > 0.5:
		return # Cannot open inventory while dead
		
	if not character_panel_instance:
		character_panel_instance = CHARACTER_PANEL_PREFAB.instantiate() as CharacterPanel
		character_panel_instance.visible = false
		add_child(character_panel_instance)
		
	character_panel_instance.visible = not character_panel_instance.visible
	
	if character_panel_instance.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if "player" in GameState:
			character_panel_instance.current_player = GameState.player
		character_panel_instance._setup_slots_text()
		character_panel_instance._load_attributes()
		character_panel_instance._load_gear_list()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
