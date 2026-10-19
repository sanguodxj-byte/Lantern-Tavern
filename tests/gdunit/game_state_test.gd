extends GdUnitTestSuite

# Tests for GameState-like key management logic
# GameState is an autoload singleton, so we test the script directly




func test_register_player_ignores_equipment_preview_player() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	var real_player := Player.new()
	var preview_player := Player.new()
	preview_player.set_meta("equipment_preview", true)

	gs.register_player(real_player)
	gs.register_player(preview_player)

	assert_object(gs.current_player).is_equal(real_player)
	preview_player.free()
	real_player.free()
	gs.free()

func test_unregister_player_only_clears_matching_player() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	var player_a := Player.new()
	var player_b := Player.new()
	gs.current_player = player_a
	gs.unregister_player(player_b)
	assert_object(gs.current_player).is_equal(player_a)
	gs.unregister_player(player_a)
	assert_object(gs.current_player).is_null()
	player_a.free()
	player_b.free()
	gs.free()

func test_dungeon_floor_starts_at_l1_and_advances_with_label() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	assert_int(gs.get_dungeon_floor()).is_equal(1)
	assert_str(gs.get_dungeon_floor_label()).is_equal("L1")
	assert_int(gs.advance_dungeon_floor()).is_equal(2)
	assert_str(gs.get_dungeon_floor_label()).is_equal("L2")
	gs.free()

# ---------- 重置一致性（架构审查 0804 P1-1） ----------

## reset_state 替换 spell_loadout 后，缓存的 PlayerContext 必须失效——
## 否则"新 GameState 装配 + 旧 PlayerContext 装配"形成静默状态分叉。
func test_reset_state_invalidates_cached_player_context() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	var ctx_before = gs.player_context()
	var loadout_before = gs.spell_loadout
	assert_object(gs.player_context()).is_equal(ctx_before)

	gs.reset_state()

	assert_bool(gs.spell_loadout != loadout_before).is_true()
	assert_bool(gs.player_context() != ctx_before).is_true()
	gs.free()

## reset_state 清空背包实例与已装备实例数据（0804 P0-2 配套）。
func test_reset_state_clears_equipment_instances() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	var w := WeaponData.new()
	w.id = "shortsword"
	w.condition = 100
	w.affixes = ["sharp"]
	assert_bool(gs.expedition_inventory.add_equipment_instance(w)).is_true()
	gs.equipment_loadout.weapon_slots[0] = "shortsword"
	gs.equipment_loadout.weapon_instances[0] = w.to_save_dict()

	gs.reset_state()

	assert_bool(gs.expedition_inventory.equipment_instances.is_empty()).is_true()
	assert_str(String(gs.equipment_loadout.weapon_slots[0])).is_equal("")
	assert_bool(gs.equipment_loadout.get_weapon_instance(0).is_empty()).is_true()
	gs.free()

func test_dungeon_floor_reset_and_serialization_are_safe() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	gs.set_dungeon_floor(4)
	assert_int(gs.serialize()["dungeon_floor"]).is_equal(4)
	gs.reset_dungeon_floor()
	assert_str(gs.get_dungeon_floor_label()).is_equal("L1")
	gs.deserialize({"dungeon_floor": 3})
	assert_str(gs.get_dungeon_floor_label()).is_equal("L3")
	gs.deserialize({"dungeon_floor": 0})
	assert_int(gs.get_dungeon_floor()).is_equal(1)
	gs.free()
