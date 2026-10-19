extends GdUnitTestSuite

# 玩家近战挥砍命中不可破坏物体（墙体/地形）时生成金属火花的效果测试。
# 覆盖：命中掩码含环境层、else 分支生成火花、try_receive_hit 幸存判定、
# 环境层跳过弧形过滤，以及 _emit_blocked_hit_spark 每刀最多触发一次。

const SLASH_PATH := "res://scenes/characters/player/state/player_state_slashing.gd"
const BLOCKED_MASK := "PhysicsSetup.LAYER_ENEMY | PhysicsSetup.LAYER_SCENE_OBJECT | PhysicsSetup.LAYER_ENVIRONMENT"

func test_slash_hitbox_mask_includes_environment_layer_in_both_calls() -> void:
	var source := _source(SLASH_PATH)
	assert_bool(source.contains("prepare_attack_hitbox")).is_true()
	# 重挥与普通挥砍两处 prepare_attack_hitbox 都必须包含环境层，墙体才会出现在重叠检测结果中。
	assert_int(source.count(BLOCKED_MASK)) \
		.override_failure_message("两处 prepare_attack_hitbox 调用都必须加入 PhysicsSetup.LAYER_ENVIRONMENT") \
		.is_equal(2)


func test_slash_source_has_blocked_spark_else_branch_and_uses_fx_helper() -> void:
	var source := _source(SLASH_PATH)
	# 无 try_receive_hit 的碰撞体（地形/墙壁等）走 _resolve_hitbox_overlaps 的 else 分支生成火花。
	var overlaps_start := source.find("func _resolve_hitbox_overlaps")
	assert_int(overlaps_start).is_greater(-1)
	var overlaps_end := source.find("func _emit_blocked_hit_spark", overlaps_start)
	var overlaps_body := source.substr(overlaps_start, overlaps_end - overlaps_start)
	var else_pos := overlaps_body.find("\t\telse:")
	assert_int(else_pos) \
		.override_failure_message("player_state_slashing.gd 的命中解析缺少 else 分支") \
		.is_greater(-1)
	assert_bool(overlaps_body.find("_emit_blocked_hit_spark()", else_pos) != -1) \
		.override_failure_message("else 分支必须调用 _emit_blocked_hit_spark()") \
		.is_true()
	# 火花由已有的 FxHelper.create_metal_spark 生成，不新建 prefab。
	assert_bool(source.contains("_emit_blocked_hit_spark")) \
		.override_failure_message("缺少 blocked-spark 辅助函数") \
		.is_true()
	assert_bool(source.contains("FxHelper.create_metal_spark")) \
		.override_failure_message("火花生成必须复用 FxHelper.create_metal_spark") \
		.is_true()


func test_slash_checks_is_destroyed_after_try_receive_hit() -> void:
	var source := _source(SLASH_PATH)
	var receive_call := source.find("body.try_receive_hit(")
	assert_int(receive_call) \
		.override_failure_message("缺少 body.try_receive_hit 调用") \
		.is_greater(-1)
	# 幸存判定必须位于 try_receive_hit 调用之后：被摧毁的物体不再生成火花。
	var tail := source.substr(receive_call, source.length() - receive_call)
	assert_bool(tail.contains("body.get(\"is_destroyed\")")) \
		.override_failure_message("try_receive_hit 之后必须检查 body.get(\"is_destroyed\") 判定是否幸存") \
		.is_true()
	assert_bool(tail.contains("is_instance_valid(body)")) \
		.override_failure_message("幸存判定必须用 is_instance_valid(body) 防护已释放物体") \
		.is_true()
	assert_bool(tail.contains("body.is_queued_for_deletion()")) \
		.override_failure_message("幸存判定必须排除 is_queued_for_deletion 的物体") \
		.is_true()


func test_slash_skips_arc_filter_for_environment_bodies() -> void:
	var source := _source(SLASH_PATH)
	# 环境/墙体是合并碰撞组，中心可能远离玩家，弧形过滤必须跳过以免错误压制火花。
	assert_bool(source.contains("var is_environment: bool = collider is StaticBody3D and collider.collision_layer & PhysicsSetup.LAYER_ENVIRONMENT != 0")) \
		.override_failure_message("缺少环境层判定 is_environment") \
		.is_true()
	assert_bool(source.contains("if not is_environment and not _is_inside_heavy_swing_arc(body):")) \
		.override_failure_message("环境层物体必须跳过 _is_inside_heavy_swing_arc 过滤") \
		.is_true()


func test_emit_blocked_hit_spark_sets_flag_once_when_called_twice() -> void:
	var player := Player.new()
	var state := PlayerStateSlashing.new(player, PlayerStateData.new())
	# 仅将 hitbox 挂入测试树，让 _emit_blocked_hit_spark 能取到 world 坐标；
	# 裸 Player 无场景子节点，不能整体入树（_ready 依赖 %KickRaycast 等节点）。
	var root := Node3D.new()
	add_child(root)
	var hitbox := Area3D.new()
	root.add_child(hitbox)
	hitbox.position = Vector3(1.0, 0.9, 2.0)
	state.hitbox = hitbox
	assert_bool(state.has_emitted_blocked_spark).is_false()
	state._emit_blocked_hit_spark()
	assert_bool(state.has_emitted_blocked_spark) \
		.override_failure_message("首次调用必须将 has_emitted_blocked_spark 置为 true") \
		.is_true()
	# 第二次调用被 has_emitted_blocked_spark 守卫提前返回，不再生成新火花。
	state._emit_blocked_hit_spark()
	assert_bool(state.has_emitted_blocked_spark).is_true()
	root.queue_free()
	state.free()
	player.free()


static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code
