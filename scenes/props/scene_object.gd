class_name SceneObject
extends StaticBody3D

@export var interaction_name: String = ""

var was_interacted := false
var is_destroyed := false

## 只有明确声明交互名称的场景物体才进入准心交互提示链。
## 仅挂有 interact() 的静态碰撞体仍可被攻击/碰撞，但不应伪装成可交互物体。
func can_interact() -> bool:
	return not is_destroyed and not interaction_name.strip_edges().is_empty()

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
