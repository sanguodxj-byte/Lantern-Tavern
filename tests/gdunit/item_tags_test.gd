extends GdUnitTestSuite

# Tests for ItemTags constants and utility functions

# ── Tag Constant Validation ──────────────────────────────────

func test_all_tags_includes_all_constants() -> void:
	assert_array(ItemTags.ALL).contains(ItemTags.WEAPON)
	assert_array(ItemTags.ALL).contains(ItemTags.SHIELD)
	assert_array(ItemTags.ALL).contains(ItemTags.MATERIAL)
	assert_array(ItemTags.ALL).contains(ItemTags.FURNITURE)
	assert_array(ItemTags.ALL).contains(ItemTags.CONSUMABLE)
	assert_array(ItemTags.ALL).contains(ItemTags.KEY)
	assert_array(ItemTags.ALL).contains(ItemTags.TREASURE)
	assert_array(ItemTags.ALL).contains(ItemTags.DECOR)
	assert_array(ItemTags.ALL).contains(ItemTags.TRAP)
	assert_array(ItemTags.ALL).contains(ItemTags.CONTAINER)


func test_all_tags_has_expected_count() -> void:
	assert_int(ItemTags.ALL.size()).is_equal(10)


func test_all_tags_returns_copy() -> void:
	var result = ItemTags.all_tags()
	result.clear()
	# Original should not be affected
	assert_int(ItemTags.ALL.size()).is_equal(10)


# ── is_valid ─────────────────────────────────────────────────

func test_is_valid_with_valid_tag() -> void:
	assert_bool(ItemTags.is_valid(ItemTags.WEAPON)).is_true()
	assert_bool(ItemTags.is_valid(ItemTags.MATERIAL)).is_true()
	assert_bool(ItemTags.is_valid(ItemTags.FURNITURE)).is_true()


func test_is_valid_with_invalid_tag() -> void:
	assert_bool(ItemTags.is_valid("invalid_tag")).is_false()
	assert_bool(ItemTags.is_valid("")).is_false()
	assert_bool(ItemTags.is_valid("potato")).is_false()


# ── display_name ─────────────────────────────────────────────

func test_display_name_known_tag() -> void:
	assert_str(ItemTags.display_name(ItemTags.WEAPON)).is_equal("武器")
	assert_str(ItemTags.display_name(ItemTags.MATERIAL)).is_equal("酿造材料")
	assert_str(ItemTags.display_name(ItemTags.DECOR)).is_equal("装饰")


func test_display_name_unknown_tag_returns_tag_itself() -> void:
	assert_str(ItemTags.display_name("unknown")).is_equal("unknown")
	assert_str(ItemTags.display_name("")).is_equal("")


# ── LocationPreference ───────────────────────────────────────

func test_location_preference_values() -> void:
	assert_int(ItemTags.LocationPreference.FLOOR_CENTER).is_equal(0)
	assert_int(ItemTags.LocationPreference.NEAR_WALL).is_equal(1)
	assert_int(ItemTags.LocationPreference.CORNER).is_equal(2)
	assert_int(ItemTags.LocationPreference.SCATTER).is_equal(3)
	assert_int(ItemTags.LocationPreference.ON_TABLE).is_equal(4)
	assert_int(ItemTags.LocationPreference.RANDOM).is_equal(5)


func test_location_names_has_all_entries() -> void:
	assert_int(ItemTags.LOCATION_NAMES.size()).is_equal(6)
	assert_str(ItemTags.LOCATION_NAMES[ItemTags.LocationPreference.FLOOR_CENTER]).is_equal("地面中心")
	assert_str(ItemTags.LOCATION_NAMES[ItemTags.LocationPreference.SCATTER]).is_equal("散布")


# ── PhysicsMode ──────────────────────────────────────────────

func test_physics_mode_values() -> void:
	assert_int(ItemTags.PhysicsMode.STATIC).is_equal(0)
	assert_int(ItemTags.PhysicsMode.RIGID).is_equal(1)
	assert_int(ItemTags.PhysicsMode.TRIGGER).is_equal(2)


func test_physics_mode_names() -> void:
	assert_int(ItemTags.PHYSICS_MODE_NAMES.size()).is_equal(3)
	assert_str(ItemTags.PHYSICS_MODE_NAMES[ItemTags.PhysicsMode.STATIC]).is_equal("静态")
	assert_str(ItemTags.PHYSICS_MODE_NAMES[ItemTags.PhysicsMode.RIGID]).is_equal("刚体")
