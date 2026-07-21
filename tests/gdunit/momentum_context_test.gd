extends GdUnitTestSuite

const MC := preload("res://globals/combat/momentum_context.gd")

func test_strength_projects_velocity_onto_next_direction() -> void:
	var ctx := MC.new()
	ctx.velocity = Vector3(0, 0, -6)
	var strength := ctx.compute_strength(Vector3(0, 0, -1))
	assert_float(strength).is_equal(6.0)

func test_strength_ignores_reverse_momentum() -> void:
	var ctx := MC.new()
	ctx.velocity = Vector3(0, 0, 6)
	var strength := ctx.compute_strength(Vector3(0, 0, -1))
	assert_float(strength).is_equal(0.0)

func test_bonus_clamps_damage_and_knockback() -> void:
	var ctx := MC.new()
	ctx.velocity = Vector3(0, 0, -20)
	var skill := {
		"inherit_momentum": true,
		"momentum_damage_scale": 0.1,
		"momentum_knockback_scale": 0.2,
		"momentum_cap": 10.0,
		"momentum_damage_cap": 0.3,
		"momentum_knockback_cap": 0.8,
	}
	var bonus: Dictionary = ctx.build_bonus(skill, Vector3(0, 0, -1))
	assert_float(bonus["strength"]).is_equal(10.0)
	assert_float(bonus["damage_multiplier"]).is_equal(1.3)
	assert_float(bonus["knockback_multiplier"]).is_equal(1.8)

func test_non_inheriting_skill_returns_neutral_bonus() -> void:
	var ctx := MC.new()
	ctx.velocity = Vector3(0, 0, -8)
	var bonus: Dictionary = ctx.build_bonus({"inherit_momentum": false}, Vector3(0, 0, -1))
	assert_float(bonus["damage_multiplier"]).is_equal(1.0)
	assert_float(bonus["knockback_multiplier"]).is_equal(1.0)
