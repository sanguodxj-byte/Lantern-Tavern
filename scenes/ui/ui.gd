class_name UI
extends CanvasLayer

@onready var death_screen: ColorRect = %DeathScreen
@onready var hurt_vignette: Panel = %HurtVignette

func _ready() -> void:
	GameEvents.player_hurt.connect(on_player_hurt)
	GameEvents.player_dead.connect(on_player_dead)
	GameEvents.level_restarted.connect(on_level_restart)
	
func on_player_hurt(_player: Player) -> void:
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
