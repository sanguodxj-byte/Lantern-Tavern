extends Node

const BLOOD_SPURT_PREFAB := preload("res://fx/blood_spurt.tscn")

func create_blood_fx(blood_transform: Transform3D, show_sparks : bool = true) -> void:
	var blood := BLOOD_SPURT_PREFAB.instantiate()
	blood.is_sparks_shown = show_sparks
	GameState.current_level.add_child(blood)
	blood.global_transform = blood_transform
