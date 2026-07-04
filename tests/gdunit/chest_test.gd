extends GdUnitTestSuite

# Tests for Chest — matching actual chest.gd API.
# Chest.open_chest() takes no args, calls queue_free after loot spawn.

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


func test_chest_collision_layers_are_reachable_by_player_rays() -> void:
	var player = load("res://scenes/characters/player/player.tscn").instantiate()
	var chest = load("res://scenes/props/chest/chest.tscn").instantiate()
	var select_raycast: RayCast3D = player.get_node("MainCamera/SelectRaycast")
	var weapon_raycast: RayCast3D = player.get_node("WeaponReachRaycast")

	assert_bool((select_raycast.collision_mask & chest.collision_layer) != 0) \
		.override_failure_message("SelectRaycast cannot detect chest, so Hold E never starts opening it.") \
		.is_true()
	assert_bool((weapon_raycast.collision_mask & chest.collision_layer) != 0) \
		.override_failure_message("WeaponReachRaycast cannot detect chest, so melee attacks cannot break it.") \
		.is_true()

	player.free()
	chest.free()


func test_slashing_dispatches_hits_to_damageable_props() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_slashing.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("try_receive_hit") != -1) \
		.override_failure_message("PlayerStateSlashing only handles Enemy targets; props like Chest are ignored.") \
		.is_true()
