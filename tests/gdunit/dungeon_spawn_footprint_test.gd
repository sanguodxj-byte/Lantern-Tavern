extends GdUnitTestSuite

const FOOTPRINT := preload("res://scenes/expedition/dungeon_spawn_footprint.gd")
const DungeonGenerator := preload("res://scenes/expedition/dungeon_generator.gd")
const DungeonGenerationConfig := preload("res://scenes/expedition/dungeon_generation_config.gd")
const DungeonHazardPlanner := preload("res://scenes/expedition/dungeon_hazard_planner.gd")
const DungeonRoomFocusPlanner := preload("res://scenes/expedition/dungeon_room_focus_planner.gd")
const DungeonSpawnPlanner := preload("res://scenes/expedition/dungeon_spawn_planner.gd")

func test_positive_aabb_overlap_is_rejected_but_face_contact_is_allowed() -> void:
	var registry: Array = []
	var half := Vector2(0.6, 0.6)
	FOOTPRINT.register(registry, Vector3.ZERO, half, "chest")
	assert_bool(FOOTPRINT.can_place(registry, Vector3(1.0, 0.0, 0.0), half)).is_false()
	assert_bool(FOOTPRINT.can_place(registry, Vector3(1.36, 0.0, 0.0), half)).is_true()

func test_category_profiles_keep_chest_and_item_separated_in_same_cell() -> void:
	var registry: Array = []
	var chest_half := FOOTPRINT.half_extents_for("chest", "normal_chest")
	var item_half := FOOTPRINT.half_extents_for("item", "blackberry")
	FOOTPRINT.register(registry, Vector3.ZERO, chest_half, "chest")
	assert_bool(FOOTPRINT.can_place(registry, Vector3.ZERO, item_half)).is_false()


func test_new_dungeon_decor_profiles_reserve_distinct_envelopes() -> void:
	var registry: Array = []
	var sarcophagus_half := FOOTPRINT.half_extents_for("decor", "sarcophagus")
	var wall_chain_half := FOOTPRINT.half_extents_for("decor", "wall_chain")
	assert_bool(sarcophagus_half.x > wall_chain_half.x).is_true()
	FOOTPRINT.register(registry, Vector3.ZERO, sarcophagus_half, "sarcophagus")
	assert_bool(FOOTPRINT.can_place(registry, Vector3(0.0, 0.0, 0.0), wall_chain_half)).is_false()
	assert_bool(FOOTPRINT.can_place(registry, Vector3(2.0, 0.0, 0.0), wall_chain_half)).is_true()

func test_generated_population_specs_have_non_overlapping_conservative_aabbs() -> void:
	var config := DungeonGenerationConfig.new()
	config.algorithm = "isaac"
	config.seed = 94021
	var layout := DungeonGenerator.new().generate(config)
	DungeonHazardPlanner.new().plan(layout)
	DungeonRoomFocusPlanner.new().plan(layout)
	var planner := DungeonSpawnPlanner.new()
	planner.plan_enemy_spawns(layout)
	planner.plan_item_spawns(layout)
	planner.plan_chest_spawns(layout)
	var registry: Array = []
	var indexes := {"enemy": 0, "item": 0, "chest": 0, "decor": 0}
	for spec in layout.enemy_spawn_specs + layout.item_spawn_specs + layout.chest_spawn_specs + layout.decor_specs:
		var category := FOOTPRINT.spec_category(spec)
		var identifier := FOOTPRINT.spec_identifier(spec)
		var cell: Vector2i = spec.get("cell", Vector2i(-1, -1))
		var index := int(indexes.get(category, 0))
		indexes[category] = index + 1
		var position := layout.cell_to_world(cell, 0.0, category, index)
		var half := FOOTPRINT.half_extents_for(category, identifier)
		assert_bool(FOOTPRINT.can_place(registry, position, half)) \
			.override_failure_message("生成 AABB 重叠: %s %s" % [category, str(cell)]).is_true()
		FOOTPRINT.register(registry, position, half, "%s:%s" % [category, identifier])
