extends GdUnitTestSuite

const VOXEL_PROP := preload("res://scenes/props/voxel_prop.gd")
const DungeonRuntimeConfig := preload("res://scenes/expedition/dungeon_runtime_config.gd")
const DUNGEON_PROPS := [
	"res://scenes/props/dungeon/dungeon_barrel.tscn",
	"res://scenes/props/dungeon/dungeon_crate.tscn",
	"res://scenes/props/dungeon/pillar.tscn",
	"res://scenes/props/dungeon/decor/bones.tscn",
	"res://scenes/props/dungeon/decor/rubble.tscn",
	"res://scenes/props/dungeon/decor/plank.tscn",
	"res://scenes/props/dungeon/decor/floor_candelabrum.tscn",
	"res://scenes/props/dungeon/decor/wall_candelabrum.tscn",
	"res://scenes/props/dungeon/decor/iron_bar_grate.tscn",
	"res://scenes/props/dungeon/decor/spiderweb.tscn",
	"res://scenes/props/dungeon/decor/ritual_totem.tscn",
	"res://scenes/props/dungeon/decor/stalagmite_cluster.tscn",
	"res://scenes/props/dungeon/decor/sarcophagus.tscn",
	"res://scenes/props/dungeon/decor/wall_chain.tscn",
	"res://scenes/props/dungeon/decor/fungus_patch.tscn",
]
const DUNGEON_CONTAINERS := [
	"res://scenes/props/dungeon/dungeon_barrel.tscn",
	"res://scenes/props/dungeon/dungeon_crate.tscn",
]

func test_dungeon_container_scenes_are_separate_from_tavern_pickables() -> void:
	for path in DUNGEON_CONTAINERS:
		var scene := load(path) as PackedScene
		assert_object(scene).is_not_null()
		var instance := scene.instantiate()
		assert_object(instance).is_not_null()
		assert_object(instance.get_script()).is_equal(VOXEL_PROP)
		assert_bool(instance.get_meta("dungeon_only", false)).is_true()
		assert_bool(instance is PickableItem).is_false()
		assert_bool(instance.has_method("get_item_name")).is_false()
		instance.free()

func test_dungeon_catalog_never_points_at_tavern_barrel_or_generic_crate() -> void:
	var cfg := DungeonRuntimeConfig.default()
	assert_str(cfg.dungeon_decor_scene_path_for("barrel")).is_equal(
		"res://scenes/props/dungeon/dungeon_barrel.tscn")
	assert_str(cfg.dungeon_decor_scene_path_for("small_crate")).is_equal(
		"res://scenes/props/dungeon/dungeon_crate.tscn")
	assert_bool(cfg.is_dungeon_scene_path_allowed("res://scenes/props/barrel/barrel.tscn")).is_false()
	assert_bool(cfg.is_dungeon_scene_path_allowed("res://scenes/props/crates/small_crate.tscn")).is_false()

func test_every_dungeon_scene_is_dungeon_only_and_tavern_decor_is_rejected() -> void:
	var cfg := DungeonRuntimeConfig.default()
	for path in DUNGEON_PROPS:
		assert_bool(path.begins_with("res://scenes/props/dungeon/")).is_true()
		assert_bool(cfg.is_dungeon_scene_path_allowed(path)).is_true()
		var instance := (load(path) as PackedScene).instantiate()
		assert_bool(instance.get_meta("dungeon_only", false)).is_true()
		instance.free()
	for tavern_path in [
		"res://scenes/props/decor/bones.tscn",
		"res://scenes/props/decor/ruble.tscn",
		"res://scenes/props/decor/plank.tscn",
		"res://scenes/props/decor/floor_candelabrum.tscn",
		"res://scenes/props/decor/wall_candelabrum.tscn",
		"res://scenes/props/decor/iron_bar_grate.tscn",
		"res://scenes/props/decor/spiderweb.tscn",
		"res://scenes/props/decor/ritual_totem.tscn",
		"res://scenes/props/decor/stalagmite_cluster.tscn",
		"res://scenes/props/decor/sarcophagus.tscn",
		"res://scenes/props/decor/wall_chain.tscn",
		"res://scenes/props/decor/fungus_patch.tscn",
	]:
		assert_bool(cfg.is_dungeon_scene_path_allowed(tavern_path)).is_false()
