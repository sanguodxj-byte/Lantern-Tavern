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

# 阶段 9 条 1 步2：地形 Transform 收集产物（builder 产出，procedural 批渲染复用）
# procedural 的 _build_multi_meshes/_build_merged_collisions 改读这些字段而非旧类字段
var floor_transforms: Array = []
var ceiling_transforms: Array = []
var wall_transforms_by_height: Dictionary = {}  # key="{wx},{wy},{wz}" -> {size:Vector3, transforms:Array}
var batched_decor_transforms: Dictionary = {}  # path -> Array[Transform3D]（pillar 等 batched decor 收集）
var wall_h_map: Dictionary = {}  # Vector2i cell -> float wall_height（预计算，供 torch/lintel 复用）

## 是否已构建（至少 terrain_root 非空）
func is_built() -> bool:
	return terrain_root != null

## 清理引用与注册表。
## 所有权约定：parent 拥有 root 生命周期；BuildResult 只引用 root，不负责 queue_free。
## 调用方应在 parent.queue_free()/free() 后或之前调用 dispose 以断开引用。
func dispose() -> void:
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
	floor_transforms.clear()
	ceiling_transforms.clear()
	wall_transforms_by_height.clear()
	batched_decor_transforms.clear()
	wall_h_map.clear()
