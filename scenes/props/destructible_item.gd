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
		AudioManager.play("barrel-destroy", audio_stream_player_3d)
		for fragment: RigidBody3D in destructible_object.get_children():
			fragment.apply_impulse(fragment.position * EXPLOSION_FORCE, global_position)
		GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
		
		# Spawning random gatherable brewing material!
		_spawn_random_material()

func _spawn_random_material() -> void:
	var pool = [
		"wild_glowcap", "frost_berry", "fire_bloom", "cave_lichen", 
		"honeycomb", "sweet_grass", "bitter_root", "mountain_barley"
	]
	var mat_id = pool[randi() % pool.size()]
	
	# Delay load to prevent circular dependencies or scene loading conflicts during explosion physics
	var mat_scene = load("res://scenes/equipment/pickable_item.tscn")
	if mat_scene:
		var item_instance = mat_scene.instantiate()
		item_instance.material_id = mat_id
		item_instance.global_position = global_position + Vector3(0, 0.4, 0)
		get_parent().add_child(item_instance)
		print("Dungeon container exploded! Dropped material: ", mat_id)
