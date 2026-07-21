extends GdUnitTestSuite

const PIR := preload("res://globals/combat/physical_impact_resolver.gd")

func test_can_attempt_requires_enabled_and_cooldown() -> void:
	assert_bool(PIR.can_attempt(false, 0, 1000)).is_false()
	assert_bool(PIR.can_attempt(true, 900, 1000)).is_false()
	assert_bool(PIR.can_attempt(true, 600, 1000)).is_true()

func test_target_profile_reads_boss_and_huge_body_size() -> void:
	var enemy := Enemy.new()
	enemy.is_boss_type = true
	enemy.body_size = "huge"
	var profile := PIR.get_target_profile(enemy)
	assert_str(profile["rank"]).is_equal("boss")
	assert_str(profile["body_size"]).is_equal("huge")
	assert_float(float(profile["impact_damage_taken_mult"])).is_equal_approx(0.39, 0.001)
	assert_float(float(profile["impact_min_speed_add"])).is_equal(2.0)
	enemy.free()

func test_target_profile_reads_spawner_meta() -> void:
	var target := CharacterBody3D.new()
	target.set_meta("enemy_rank", "elite")
	target.set_meta("body_size", "small")
	var profile := PIR.get_target_profile(target)
	assert_str(profile["rank"]).is_equal("elite")
	assert_str(profile["body_size"]).is_equal("small")
	assert_float(float(profile["impact_damage_taken_mult"])).is_equal_approx(0.935, 0.001)
	assert_float(float(profile["impact_min_speed_add"])).is_equal(-0.5)
	target.free()

func test_surface_damage_ignores_floor_normals() -> void:
	var spec := {"enabled": true, "min_speed": 4.0, "full_speed": 14.0, "damage_mult": 1.0}
	var damage := PIR.resolve_surface_damage(100, Vector3(-10, 0, 0), Vector3(0, 1, 0), spec)
	assert_int(damage).is_equal(0)

func test_surface_damage_uses_wall_incoming_speed() -> void:
	var spec := {"enabled": true, "min_speed": 4.0, "full_speed": 14.0, "damage_mult": 1.0}
	var damage := PIR.resolve_surface_damage(200, Vector3(-10, 0, 0), Vector3(1, 0, 0), spec)
	assert_int(damage).is_greater(0)

func test_impact_collider_accepts_scene_objects_and_rejects_enemies() -> void:
	var wall := StaticBody3D.new()
	var enemy := Enemy.new()
	assert_bool(PIR.is_impact_collider(wall)).is_true()
	assert_bool(PIR.is_impact_collider(enemy)).is_false()
	wall.free()
	enemy.free()
