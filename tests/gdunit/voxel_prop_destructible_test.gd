extends GdUnitTestSuite

# 可破坏地牢场景物体（VoxelProp）契约测试：
# 地牢木箱/酒桶/碎石/石棺/石笋簇可通过 try_receive_hit 受击，
# 累计伤害达到 max_hits 后销毁；其余地牢/酒馆道具保持不可破坏。
# 注：仪式图腾是 GLB 手作道具（非 VoxelProp 代码拼合），其可破坏性
# 由地牢构建器 _configure_scene_object 挂载的 SceneObject 契约提供，
# 不进入本 VoxelProp 可破坏配置。

const VOXEL_PROP := preload("res://scenes/props/voxel_prop.gd")
const DungeonRuntimeConfig := preload("res://scenes/expedition/dungeon_runtime_config.gd")

const DESTRUCTIBLE_SCENES := {
	"res://scenes/props/dungeon/dungeon_crate.tscn": 1,
	"res://scenes/props/dungeon/dungeon_barrel.tscn": 2,
	"res://scenes/props/dungeon/decor/rubble.tscn": 1,
	"res://scenes/props/dungeon/decor/sarcophagus.tscn": 3,
	"res://scenes/props/dungeon/decor/stalagmite_cluster.tscn": 2,
}

const NON_DESTRUCTIBLE_SCENES := [
	"res://scenes/props/dungeon/pillar.tscn",
	"res://scenes/props/dungeon/decor/bones.tscn",
	"res://scenes/props/dungeon/decor/spiderweb.tscn",
]

func test_destructible_dungeon_props_expose_hit_contract() -> void:
	for path in DESTRUCTIBLE_SCENES:
		var scene := load(path) as PackedScene
		assert_object(scene).is_not_null()
		var inst := scene.instantiate()
		assert_object(inst).is_not_null()
		assert_object(inst.get_script()).is_equal(VOXEL_PROP)
		assert_bool(inst.destructible) \
			.override_failure_message("%s 必须标记为可破坏" % path).is_true()
		assert_int(int(inst.max_hits)) \
			.override_failure_message("%s max_hits 配置错误" % path).is_equal(int(DESTRUCTIBLE_SCENES[path]))
		assert_bool(inst.has_method("try_receive_hit")).is_true()
		assert_bool(inst.has_method("destroy")).is_true()
		inst.free()

func test_non_destructible_dungeon_props_ignore_hits() -> void:
	for path in NON_DESTRUCTIBLE_SCENES:
		var inst := (load(path) as PackedScene).instantiate()
		add_child(inst)
		if inst.has_method("try_receive_hit"):
			# VoxelProp 场景（立柱/骨头）：默认 destructible == false，受击为无操作
			assert_bool(inst.destructible) \
				.override_failure_message("%s 必须保持不可破坏" % path).is_false()
			inst.call("try_receive_hit", null, 99)
			assert_bool(inst.is_destroyed).is_false()
			assert_bool(inst.is_queued_for_deletion()).is_false()
			assert_bool(is_instance_valid(inst)).is_true()
		else:
			# 无脚本纯装饰（如蜘蛛网）：不具备受击接口，天然不可破坏
			assert_bool(inst.has_method("destroy")) \
				.override_failure_message("%s 不可破坏，不允许销毁接口" % path).is_false()
		inst.free()

func test_crate_destroyed_by_single_hit() -> void:
	var inst := (load("res://scenes/props/dungeon/dungeon_crate.tscn") as PackedScene).instantiate()
	add_child(inst)
	inst.call("try_receive_hit", null, 1)
	assert_bool(inst.is_destroyed).is_true()
	assert_bool(inst.is_queued_for_deletion()).is_true()

func test_barrel_survives_first_hit_and_breaks_on_second() -> void:
	var inst := (load("res://scenes/props/dungeon/dungeon_barrel.tscn") as PackedScene).instantiate()
	add_child(inst)
	inst.call("try_receive_hit", null, 1)
	assert_bool(inst.is_destroyed).is_false()
	assert_bool(inst.is_queued_for_deletion()).is_false()
	inst.call("try_receive_hit", null, 1)
	assert_bool(inst.is_destroyed).is_true()
	assert_bool(inst.is_queued_for_deletion()).is_true()

func test_high_damage_breaks_barrel_in_one_hit() -> void:
	# 蓄力/踢击等更高伤害按实际数值累计：伤害 3 ≥ 酒桶 max_hits(2) → 一击即碎
	var inst := (load("res://scenes/props/dungeon/dungeon_barrel.tscn") as PackedScene).instantiate()
	add_child(inst)
	inst.call("try_receive_hit", null, 3)
	assert_bool(inst.is_destroyed).is_true()
	assert_bool(inst.is_queued_for_deletion()).is_true()

func test_furniture_impact_instantly_destroys_crate() -> void:
	var inst := (load("res://scenes/props/dungeon/dungeon_crate.tscn") as PackedScene).instantiate()
	add_child(inst)
	inst.call("try_receive_furniture_impact", null)
	assert_bool(inst.is_destroyed).is_true()
	assert_bool(inst.is_queued_for_deletion()).is_true()

func test_double_destroy_guards_against_second_break() -> void:
	var inst := (load("res://scenes/props/dungeon/dungeon_crate.tscn") as PackedScene).instantiate()
	add_child(inst)
	inst.call("destroy")
	assert_bool(inst.is_destroyed).is_true()
	inst.call("destroy")
	assert_bool(inst.is_destroyed).is_true()
	assert_bool(inst.is_queued_for_deletion()).is_true()

func test_crate_is_unbatched_so_individual_crates_can_be_destroyed() -> void:
	var cfg := DungeonRuntimeConfig.default()
	assert_bool(cfg.batched_decor_scenes.has("res://scenes/props/dungeon/dungeon_crate.tscn")) \
		.override_failure_message("木箱必须脱离批量渲染集合，才能被单独销毁").is_false()
	assert_bool(cfg.batched_decor_scenes.has("res://scenes/props/dungeon/pillar.tscn")).is_true()
	# 木箱仍保留在地牢白名单/容器池中，仅脱离批量渲染
	assert_bool(cfg.is_dungeon_scene_path_allowed("res://scenes/props/dungeon/dungeon_crate.tscn")).is_true()
