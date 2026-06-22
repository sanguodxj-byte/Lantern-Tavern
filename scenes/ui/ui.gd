class_name UI
extends CanvasLayer

@onready var hurt_vignette: Panel = %HurtVignette

func _ready() -> void:
	GameEvents.player_hurt.connect(on_player_hurt)
	
func on_player_hurt(_player: Player) -> void:
	var tween := create_tween()
	tween.tween_property(hurt_vignette, "modulate:a", 1.0, 0.1)
	tween.tween_property(hurt_vignette, "modulate:a", 0.0, 0.1)
