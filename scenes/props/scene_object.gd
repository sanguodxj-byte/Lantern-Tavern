class_name SceneObject
extends StaticBody3D

@export var interaction_name: String = ""

var was_interacted := false
var is_destroyed := false

func interact(source_player: Node = null) -> void:
	was_interacted = true
	try_receive_hit(source_player, 1)

func try_receive_hit(_source_player: Node, _damage: int) -> void:
	destroy()

func try_receive_furniture_impact(_thrown_item: RigidBody3D) -> void:
	destroy()

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	queue_free()
