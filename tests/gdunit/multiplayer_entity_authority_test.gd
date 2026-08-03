extends GdUnitTestSuite

## P0（2124 审查）：服务器权威实体物理节点映射——可受击实体必须有碰撞体 + entity_id
## meta，ray intersect_ray / projectile body_entered 才能命中并写回实体仓。
## 覆盖：桥接层服务器侧装配、祖先 entity_id 查找、非 enemy 不装配。

const Bridge := preload("res://globals/multiplayer/multiplayer_scene_bridge.gd")
const WorldExecutor := preload("res://globals/combat/spell_world_executor.gd")

func _make_bridge(is_server: bool) -> Node:
	var b: Node = auto_free(Bridge.new())
	var ra := Node3D.new()
	ra.name = "RemoteAvatars"
	b.add_child(ra)
	b.set("server_mode_override", 1 if is_server else 0)
	b._ready()
	return b

## 生产装配路径测试：以服务器角色生成 enemy 实体 → 节点带 StaticBody3D + entity_id meta。
func test_server_spawn_enemy_attaches_authoritative_collision_body() -> void:
	var b := _make_bridge(true)
	b._spawn_entity_local(1001, {"kind": "enemy", "current_life": 10, "max_life": 10})
	var ent: Node3D = b.get_entity_node(1001)
	assert_object(ent).is_not_null()
	print("DBG is_server=", b._is_server(), " ent=", ent != null)
	var body: Node = ent.get_node_or_null("AuthoritativeBody")
	print("DBG body=", body)
	assert_object(body) \
		.override_failure_message("服务器侧 enemy 实体必须装配权威碰撞体").is_not_null()
	# entity_id meta 设在碰撞体节点（ray/projectile 命中的 collider 直接携带身份）。
	assert_int(int(body.get_meta("entity_id", 0))).is_equal(1001)
	# 碰撞层为 ENEMY（可被 projectile/ray 命中）。
	assert_int(int(body.collision_layer)).is_equal(PhysicsSetup.LAYER_ENEMY)
	# 碰撞形状为胶囊（人体约定尺寸）。
	var shape := body.get_node_or_null("EntityCollision") as CollisionShape3D
	assert_object(shape).is_not_null()
	assert_bool(shape.shape is CapsuleShape3D).is_true()

func test_loot_entities_do_not_get_authoritative_collision_body() -> void:
	# 掉落/宝箱/门不可被法术命中——不装配碰撞体（保持表现代理，避免误伤 loot）。
	var b := _make_bridge(true)
	b._spawn_entity_local(5001, {"kind": "loot", "item_id": "gold", "amount": 1})
	b._spawn_entity_local(9001, {"kind": "chest", "current_life": 10})
	var loot: Node = b.get_entity_node(5001)
	var chest: Node = b.get_entity_node(9001)
	assert_object(loot.get_node_or_null("AuthoritativeBody")).is_null()
	assert_object(chest.get_node_or_null("AuthoritativeBody")).is_null()

func test_ancestor_entity_id_lookup_finds_meta_on_body() -> void:
	# 命中 collider 是 StaticBody3D（meta 在其上）；祖先查找还应兼容 meta 在实体根。
	var root := Node3D.new()
	root.set_meta("entity_id", 777)
	var child := Node3D.new()
	root.add_child(child)
	assert_int(WorldExecutor.find_entity_id(child)).is_equal(777)
	assert_int(WorldExecutor.find_entity_id(root)).is_equal(777)
	var plain := Node3D.new()
	assert_int(WorldExecutor.find_entity_id(plain)).is_equal(0)
	plain.free()
	assert_int(WorldExecutor.find_entity_id(null)).is_equal(0)
	root.free()

func test_apply_damage_uses_ancestor_lookup_for_nested_collider() -> void:
	# collider 是碰撞体子节点（无 meta），meta 在实体根 → 端口仍命中（单次调用）。
	var world := Node3D.new()
	add_child(world)
	var executor: Node = WorldExecutor.new()
	world.add_child(executor)
	var root := Node3D.new()
	root.set_meta("entity_id", 1001)
	world.add_child(root)
	var collider := StaticBody3D.new()  # 模拟 ray 命中的碰撞体（子节点）
	root.add_child(collider)
	var calls: Array = []
	executor.damage_entity_port = func(eid: int, dmg: int, cp: int) -> Dictionary:
		calls.append(eid)
		return {"ok": true, "killed": false, "events": []}
	var res: Dictionary = executor._apply_damage(collider, null, 5, 1)
	assert_int(calls.size()).is_equal(1)
	assert_int(calls[0]).is_equal(1001)
	assert_bool(bool(res["port_called"])).is_true()
	world.free()
