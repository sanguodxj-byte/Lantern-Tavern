class_name AcidTrap
extends Area3D

func _ready() -> void:
	body_entered.connect(on_body_entered)

func on_body_entered(body: Node3D) -> void:
	if body is Enemy or body is Player:
		body.take_acid_damage()
