class_name Door
extends StaticBody3D

@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var collision_shape_3d: CollisionShape3D = %CollisionShape3D

func open(source_transform: Transform3D) -> void:
	collision_shape_3d.disabled = true
	var door_forward := -global_basis.z
	var player_forward := -source_transform.basis.z
	var dot_product := door_forward.dot(player_forward)
	if dot_product > 0:
		animation_player.play("open-right")
	else:
		animation_player.play("open-left")
