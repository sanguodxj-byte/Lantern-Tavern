extends GdUnitTestSuite

const SaveGameAdapterClass := preload("res://globals/core/state/save_game_adapter.gd")

func test_adapt_empty_data() -> void:
	var input := {}
	var output := SaveGameAdapterClass.adapt(input)
	
	assert_int(int(output.get("version", 0))).is_equal(1)

func test_adapt_v0_migration() -> void:
	var input := {
		"version": 0,
		"tavern_manager": {
			"gold": 500,
			"inventory": {
				"blackberry": 10,
				"rat_tail": 4
			},
			"runes_inventory": {
				"fire_rune": 2
			}
		},
		"game_state": {}
	}
	
	var output := SaveGameAdapterClass.adapt(input)
	
	assert_int(int(output.get("version", 0))).is_equal(1)
	
	var tm = output.get("tavern_manager", {})
	assert_bool(tm.has("inventory")).is_false()
	assert_bool(tm.has("runes_inventory")).is_false()
	
	var gs = output.get("game_state", {})
	assert_bool(gs.has("expedition_inventory")).is_true()
	
	var exp_inv = gs.get("expedition_inventory", {})
	var materials = exp_inv.get("materials", {})
	var runes = exp_inv.get("runes", {})
	
	assert_int(int(materials.get("blackberry", 0))).is_equal(10)
	assert_int(int(materials.get("rat_tail", 0))).is_equal(4)
	assert_int(int(runes.get("fire_rune", 0))).is_equal(2)
