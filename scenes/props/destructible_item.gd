class_name DestructibleItem
extends Node3D

const EXPLOSION_FORCE := 5.0

@export var furniture_data: FurnitureData

@onready var audio_stream_player_3d: AudioStreamPlayer3D = %AudioStreamPlayer3D

var destructible_object: Node3D = null

func _ready() -> void:
	if furniture_data != null:
		destructible_object = furniture_data.glb_fragments_mesh.instantiate()
	if destructible_object != null:
		add_child(destructible_object)
		for fragment: RigidBody3D in destructible_object.get_children():
			fragment.set_collision_layer_value(1, false)

func explode() -> void:
	if destructible_object != null:
		for fragment: RigidBody3D in destructible_object.get_children():
			fragment.apply_impulse(fragment.position * EXPLOSION_FORCE, global_position)
		GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
