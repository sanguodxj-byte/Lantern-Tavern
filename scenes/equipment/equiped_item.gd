class_name EquipedItem
extends Node3D

const ZCLIP_MATERIAL := preload("res://materials/zclip_material.tres")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

@export var is_always_in_front: bool
@export var furniture_data: FurnitureData
@export var shield_data: ShieldData
@export var weapon_data: WeaponData

func _ready() -> void:
	var equiped_object : Node = null
	if weapon_data and weapon_data.glb_mesh:
		equiped_object = weapon_data.glb_mesh.instantiate()
	elif shield_data and shield_data.glb_mesh:
		equiped_object = shield_data.glb_mesh.instantiate()
	elif furniture_data and furniture_data.glb_mesh:
		equiped_object = furniture_data.glb_mesh.instantiate()
	if equiped_object != null:
		add_child(equiped_object)
		# 武器/盾保留金属材质；家具走默认体素适配
		if weapon_data != null or shield_data != null:
			var material_tier := weapon_data.material_tier if weapon_data != null else ""
			VOXEL_LIGHTING.apply_weapon_tree(equiped_object, material_tier)
		else:
			VOXEL_LIGHTING.apply_to_tree(equiped_object, true)

		# 检查是否属于玩家的第三人称身体挂载点
		var is_player_third_person := false
		var p := get_parent()
		while p != null:
			if p is Player or p.name.to_lower().contains("player"):
				is_player_third_person = true
				break
			p = p.get_parent()

		if is_player_third_person:
			# 强制隐藏在第 10 渲染层，防止在第一人称主相机（cull_mask=1）中显示穿帮
			_set_render_layer_recursive(equiped_object, 1 << 9) # 1 << 9 即第 10 层
		elif is_always_in_front:
			_apply_z_clip_recursive(equiped_object)

## 递归设置节点及其所有子节点的渲染层
func _set_render_layer_recursive(node: Node, layer: int) -> void:
	if node is GeometryInstance3D:
		node.layers = layer
	for child in node.get_children():
		_set_render_layer_recursive(child, layer)

## 递归为所有 MeshInstance3D 的材质启用 z-clip（防止武器穿墙）。
## 保留原有纹理/颜色，仅在材质副本上添加 z_clip_scale 属性，
## 避免用空白白色材质覆盖 GLB 内嵌纹理导致白色方块。
func _apply_z_clip_recursive(root: Node) -> void:
	if root is MeshInstance3D:
		_apply_z_clip_to_mesh(root as MeshInstance3D)
	for child in root.get_children():
		_apply_z_clip_recursive(child)

## 为单个 MeshInstance3D 的每个 surface 材质叠加 z-clip 属性。
func _apply_z_clip_to_mesh(mesh_inst: MeshInstance3D) -> void:
	if mesh_inst.mesh == null:
		# 无 mesh 时仍处理 material_override（可能由 VoxelLightingAdapter 设置）
		var override_mat := mesh_inst.material_override
		if override_mat is StandardMaterial3D:
			var zclip_copy := (override_mat as StandardMaterial3D).duplicate()
			zclip_copy.use_z_clip_scale = true
			zclip_copy.z_clip_scale = ZCLIP_MATERIAL.z_clip_scale
			mesh_inst.material_override = zclip_copy
		return
	for surface_index in range(mesh_inst.mesh.get_surface_count()):
		var source: Material = mesh_inst.get_surface_override_material(surface_index)
		if source == null:
			source = mesh_inst.mesh.surface_get_material(surface_index)
		if source is StandardMaterial3D:
			var zclip_copy := (source as StandardMaterial3D).duplicate()
			zclip_copy.use_z_clip_scale = true
			zclip_copy.z_clip_scale = ZCLIP_MATERIAL.z_clip_scale
			mesh_inst.set_surface_override_material(surface_index, zclip_copy)
