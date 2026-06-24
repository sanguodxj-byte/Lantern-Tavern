class_name AcidTrap
extends Node3D

@onready var body_detection_area: Area3D = %BodyDetectionArea

func _ready() -> void:
	body_detection_area.body_entered.connect(on_body_entered)

func on_body_entered(body: CharacterBody3D) -> void:
	body.take_acid_damage()
