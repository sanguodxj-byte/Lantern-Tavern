class_name CustomerServeTrigger
extends StaticBody3D
## 顾客服务触发器：玩家手持盛酒器时对准已落座顾客交互 → 走
## CustomerSpawner.serve_entity → serve_seated_customer → 结算链路（策划案 12）。
## 只响应"已落座 + 手持盛酒器"两个条件同时满足的情况。

const LAYER_SCENE_OBJECT := 64

## 所属顾客实体（父节点）
var entity: Node3D = null

func _ready() -> void:
	entity = get_parent() as Node3D
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	var col := CollisionShape3D.new()
	col.name = "ServeShape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.55, 1.5, 0.55)
	col.shape = shape
	col.position = Vector3(0, 0.75, 0)
	add_child(col)

# ============================================================================
# 交互
# ============================================================================

var interaction_name: String = "顾客"
var interaction_verb: String = "端上酒杯"


func can_interact() -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	var state: Variant = entity.get("_state")
	if state == null or String(state) != "seated":
		return false
	var carry := _get_carry()
	return carry != null and carry.is_serving()


func interact(_source_player: Node = null) -> void:
	if not can_interact():
		return
	var carry := _get_carry()
	if carry == null or not carry.is_serving():
		return
	var flavors: Dictionary = carry.serving_flavors.duplicate()
	var price: int = carry.serving_price
	var spawner := _get_spawner()
	var result: Variant = {}
	if spawner != null and spawner.has_method("serve_entity"):
		result = spawner.call("serve_entity", entity, flavors, price)
	elif entity != null and entity.has_method("serve"):
		result = entity.serve(flavors, price)
	carry.clear()

# ============================================================================
# 辅助
# ============================================================================

## 通过全局酿酒 coordinator 组查找玩家手持组件。
func _get_carry() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("tavern_brewing"):
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion() or not "carry" in node:
			continue
		var candidate: Variant = node.get("carry")
		if candidate != null and is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			return candidate
	return null

## 顾客生成器：优先 entity.spawner（spawner 注入），回退到酒馆场景查找。
func _get_spawner() -> Node:
	if entity != null and "spawner" in entity:
		var injected = entity.get("spawner")
		if injected != null and is_instance_valid(injected):
			return injected
	var tavern := _find_tavern()
	if tavern != null:
		return tavern.get_node_or_null("CustomerSpawner")
	return null

func _find_tavern() -> Node:
	var node: Node = self
	while node != null:
		if node.has_meta("is_tavern"):
			return node
		node = node.get_parent()
	return null
