extends GdUnitTestSuite
const SpellFx := preload("res://fx/pixel_spell_fx.gd")

func test_fx_builds_hard_pixel_chips_and_is_cosmetic() -> void:
	var parent := Node3D.new(); add_child(parent)
	var fx = SpellFx.spawn(parent, {"phase":"hit","imagery":"fireball","color":Color.ORANGE}, Vector3.ZERO)
	assert_object(fx).is_not_null()
	assert_bool(fx._chips.size() > 0 and fx._chips.size() <= SpellFx.MAX_CHIPS).is_true()
	for chip in fx._chips:
		assert_bool(chip.mesh is BoxMesh).is_true()
		assert_bool(chip.get_child_count() == 0).is_true()
	parent.queue_free()

func test_only_energy_imagery_uses_emission() -> void:
	var fx := SpellFx.new()
	assert_bool(fx._is_energy_imagery("fireball")).is_true()
	assert_bool(fx._is_energy_imagery("chain_lightning")).is_true()
	assert_bool(fx._is_energy_imagery("stone_wall")).is_false()
	assert_bool(fx._is_energy_imagery("poison_cloud")).is_false()
	fx.free()

func test_fx_has_bounded_lifetime_and_no_particles_or_gradients() -> void:
	var source := (load("res://fx/pixel_spell_fx.gd") as GDScript).source_code
	assert_bool(source.contains("queue_free()")).is_true()
	assert_bool(source.contains("MAX_CHIPS")).is_true()
	assert_bool(not source.contains("GPUParticles3D")).is_true()
	assert_bool(not source.contains("Gradient")).is_true()
	assert_bool(not source.contains("OmniLight3D")).is_true()
