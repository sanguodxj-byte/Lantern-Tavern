class_name SpikesTrap
extends Area3D

func _ready() -> void:
	body_entered.connect(on_body_entered)

func on_body_entered(body: CharacterBody3D) -> void:
	body.take_spike_damage(self)
