class_name BodyPartResolver
extends RefCounted

const VOXEL_PALETTE := preload("res://globals/combat/voxel_palette.gd")

## 被击部位解析：命中世界点 → 最近命名骨骼 → 体素颜色。
## 配合 VoxelPalette 实现"被击部位体素纹理相关"特效。

## 纯逻辑：从 {name, pos} 列表里找离 world_pos 最近的骨骼名。
## 抽成数组版以便单测（无需真实 Skeleton3D）。
static func nearest_bone_from(bones: Array, world_pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for b in bones:
		var pos: Vector3 = b.pos if b is Dictionary and b.has("pos") else Vector3.ZERO
		var d := world_pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = b.name if b is Dictionary and b.has("name") else ""
	return best

## 取出 Skeleton3D 全部骨骼的 {name, world_pos}。
static func skeleton_bones(skel: Skeleton3D) -> Array:
	var out: Array = []
	if skel == null:
		return out
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		var pose: Transform3D = skel.get_bone_global_pose(i)
		var wp: Vector3 = (skel.global_transform * pose).origin
		out.append({"name": nm, "pos": wp})
	return out

## 从真实 Skeleton3D 解析最近骨骼名。
static func nearest_bone_name(skel: Skeleton3D, world_pos: Vector3) -> String:
	return nearest_bone_from(skeleton_bones(skel), world_pos)

## 由击退方向估计敌人朝向攻击者的表面命中点。
## impact_direction 是击退方向（攻击者→敌人），命中点在与攻击者相反侧。
static func approx_hit_point(enemy_pos: Vector3, impact_direction: Vector3, body_radius := 0.4, hit_height := 1.0) -> Vector3:
	var dir := impact_direction
	if dir.length() < 0.001:
		return enemy_pos + Vector3(0.0, hit_height, 0.0)
	dir = dir.normalized()
	return enemy_pos - dir * body_radius + Vector3(0.0, hit_height, 0.0)

## 归一化生物 id：取首个连续字母段（小写），剔除 Goblin2 / goblin_2 / "@Goblin@2" 等实例化后缀，
## 使 VoxelPalette 的生物覆盖键稳定匹配（敌人节点实例化后常带数字/括号/@ 后缀）。
static func normalize_creature_id(id: String) -> String:
	var s := id.to_lower()
	var out := ""
	for i in s.length():
		var ch: String = s[i]
		if ch >= "a" and ch <= "z":
			out += ch
		elif out.length() > 0:
			break
	return out

## 完整解析：creature_id + 骨骼 + 命中点 → 体素颜色。
static func resolve_part_color(creature_id: String, skel: Skeleton3D, world_pos: Vector3, material := "") -> Color:
	var part := nearest_bone_name(skel, world_pos)
	return VOXEL_PALETTE.color_for_part(normalize_creature_id(creature_id), part, material)
