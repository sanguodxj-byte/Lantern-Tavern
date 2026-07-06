class_name PlayerAimHelper
extends RefCounted

## 玩家瞄准辅助工具（纯静态方法）
## 从 player.gd 提取，封装准心射线检测和发射变换构造。
## 不持有状态，不依赖场景树，所有方法均为 static。

const CB_LIB := preload("res://globals/combat/combat_bridge.gd")


## 获取准心瞄准的世界坐标点。
## 从摄像机中心发射射线，命中物体返回命中点；未命中返回远端点。
## exclude_rid: 需要从射线检测中排除的 RID（通常是玩家自身）
static func get_aim_point(camera: Camera3D, origin: Vector3, exclude_rid: RID = RID(), max_distance: float = 100.0) -> Vector3:
	if camera == null or not is_instance_valid(camera):
		return origin - Vector3.FORWARD * max_distance
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z.normalized()
	var to := from + forward * max_distance
	var world := camera.get_world_3d()
	if world == null:
		return to
	var ds := world.direct_space_state
	if ds == null:
		return to
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if exclude_rid != RID():
		query.exclude = [exclude_rid]
	# 碰撞环境+敌人+场景物体，不穿透墙
	query.collision_mask = PhysicsSetup.LAYER_ENVIRONMENT | PhysicsSetup.LAYER_ENEMY | PhysicsSetup.LAYER_SCENE_OBJECT
	var result := ds.intersect_ray(query)
	if result.is_empty():
		return to
	return Vector3(result["position"])


## 构造朝向准心点的发射变换（-Z 指向目标）。
## muzzle_pos: 枪口/弓口世界坐标
## exclude_rid: 需要从射线检测中排除的 RID（通常是玩家自身）
static func get_aim_transform(camera: Camera3D, muzzle_pos: Vector3, exclude_rid: RID = RID()) -> Transform3D:
	var aim_point := get_aim_point(camera, muzzle_pos, exclude_rid)
	var dir := aim_point - muzzle_pos
	# 若瞄准点过于接近枪口，退回摄像机前方
	if dir.length_squared() < 0.25:
		var cam_fwd := -camera.global_transform.basis.z.normalized() if camera != null else Vector3.FORWARD
		aim_point = muzzle_pos + cam_fwd * 50.0
		dir = aim_point - muzzle_pos
	var up := Vector3.UP
	var dir_norm := dir.normalized()
	if absf(dir_norm.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	var t := Transform3D(Basis(), muzzle_pos)
	return t.looking_at(aim_point, up)
