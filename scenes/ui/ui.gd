class_name UI
extends CanvasLayer

@onready var death_screen: ColorRect = %DeathScreen
@onready var health_indicator: StatIndicator = %HealthIndicator
@onready var hurt_vignette: Panel = %HurtVignette
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
	
func on_player_hurt(player: Player) -> void:
	health_indicator.refresh(player.health.current_life, player.health.max_life)
	var tween := create_tween()
	tween.tween_property(hurt_vignette, "modulate:a", 1.0, 0.1)
	tween.tween_property(hurt_vignette, "modulate:a", 0.0, 0.1)

func on_player_dead() -> void:
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
	
