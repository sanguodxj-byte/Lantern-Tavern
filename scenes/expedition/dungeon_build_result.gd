## DungeonBuildResult — 场景实例化产物容器（阶段 7）。
#
# 由 DungeonSceneBuilder.build() 返回，集中持有所有生成的 Godot 节点引用。
# streaming controller 与 runtime 通过它访问节点，不反向依赖 layout 或 builder。
class_name DungeonBuildResult
extends RefCounted

# 场景树分 root（由 builder 创建并 add_child 到 parent）
var terrain_root: Node3D = null       # 地板/天花板/墙体 MultiMesh 容器
var collision_root: Node3D = null     # 合并碰撞体容器
var doors_root: Node3D = null         # 门面板 + 门墙包围
var hazards_root: Node3D = null       # 陷阱 prefab（spikes/acid/flame_vent）
var decor_root: Node3D = null         # 装饰物 + 大房间特征
var spawn_root: Node3D = null         # 敌人节点容器
var interaction_root: Node3D = null   # 宝箱 + 撤离传送门 + 楼梯
var streamed_visual_root: Node3D = null  # streaming 视觉根
var streamed_physics_root: Node3D = null # streaming 物理根

# streaming 注册表（controller 按此增量激活/停用）
var streamed_visual_nodes: Array[Node3D] = []
var streamed_physics_nodes: Array[Node] = []
var terrain_chunks: Dictionary = {}  # Vector2i chunk -> Array[Node3D]

## 是否已构建（至少 terrain_root 非空）
func is_built() -> bool:
	return terrain_root != null

## 清理：释放所有 root 子树（调用方负责从 parent 移除）
func dispose() -> void:
	for root in [terrain_root, collision_root, doors_root, hazards_root, decor_root,
				spawn_root, interaction_root, streamed_visual_root, streamed_physics_root]:
		if is_instance_valid(root):
			root.queue_free()
	terrain_root = null
	collision_root = null
	doors_root = null
	hazards_root = null
	decor_root = null
	spawn_root = null
	interaction_root = null
	streamed_visual_root = null
	streamed_physics_root = null
	streamed_visual_nodes.clear()
	streamed_physics_nodes.clear()
	terrain_chunks.clear()
