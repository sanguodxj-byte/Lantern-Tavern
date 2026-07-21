extends GdUnitTestSuite

# Tests for Chest — matching actual chest.gd API.
# Chest.open_chest() takes no args, calls queue_free after loot spawn.

const LT := preload("res://globals/tavern/loot_table.gd")

func test_chest_starts_closed() -> void:
	var chest = Chest.new()
	assert_bool(chest.is_opened).is_false()
	chest.free()


func test_chest_open_sets_opened() -> void:
	var chest = Chest.new()
	chest.open_chest()
	assert_bool(chest.is_opened).is_true()
	chest.free()


func test_chest_cannot_open_twice() -> void:
	var chest = Chest.new()
	chest.open_chest()
	assert_bool(chest.is_opened).is_true()
	# Second open does nothing (early return)
	chest.open_chest()
	assert_bool(chest.is_opened).is_true()
	chest.free()


func test_chest_collision_layers_are_reachable_by_player_selection_and_melee_hitbox() -> void:
	var player = load("res://scenes/characters/player/player.tscn").instantiate()
	var chest = load("res://scenes/props/chest/chest.tscn").instantiate()
	var select_raycast: RayCast3D = player.get_node("MainCamera/SelectRaycast")

	assert_bool((select_raycast.collision_mask & 64) != 0) \
		.override_failure_message("SelectRaycast must detect generic scene objects, not only pickable items.") \
		.is_true()
	assert_bool((select_raycast.collision_mask & chest.collision_layer) != 0) \
		.override_failure_message("SelectRaycast cannot detect chest, so Hold E never starts opening it.") \
		.is_true()
	var slash_source := _source("res://scenes/characters/player/state/player_state_slashing.gd")
	assert_bool(slash_source.contains("PhysicsSetup.LAYER_SCENE_OBJECT")) \
		.override_failure_message("Melee hitbox must include scene objects, so chests can be hit by weapon collision.") \
		.is_true()

	player.free()
	chest.free()

static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code


func test_slashing_dispatches_hits_to_damageable_props() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_slashing.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("try_receive_hit") != -1) \
		.override_failure_message("PlayerStateSlashing only handles Enemy targets; props like Chest are ignored.") \
		.is_true()


func test_boss_chest_scene_is_large_reward_chest() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/props/chest/boss_chest.tscn")).is_true()
	var chest := (load("res://scenes/props/chest/boss_chest.tscn") as PackedScene).instantiate() as Chest
	assert_object(chest).is_not_null()
	assert_int(chest.loot_multiplier).is_equal(3)
	assert_str(String(chest.get_meta("decor_kind"))).is_equal("boss_chest")
	chest.free()


func test_boss_chest_interactive_loot_generates_three_reward_rolls() -> void:
	var chest := (load("res://scenes/props/chest/boss_chest.tscn") as PackedScene).instantiate() as Chest
	add_child(chest)
	await await_idle_frame()
	chest.open_chest(true)
	assert_bool(chest.is_opened).is_true()
	assert_bool(chest.loot_data.has("weapon")).is_true()
	assert_bool(chest.loot_data.has("weapons")).is_true()
	assert_bool(chest.loot_data.has("materials")).is_true()
	assert_int((chest.loot_data["materials"] as Array).size()) \
		.override_failure_message("boss 奖励大箱应提供 3 倍材料掉落轮数") \
		.is_greater_equal(LT.MATERIAL_DROP_MIN * 3)
	assert_int((chest.loot_data["weapons"] as Array).size()) \
		.override_failure_message("boss 奖励大箱应保留多件装备奖励数组") \
		.is_greater_equal(1)
	chest.free()
