extends GdUnitTestSuite

# PlayerStateSlashing 挥砍移动限制（B3）测试。
# 重武器（巨剑/斧/战锤/长矛）挥砍期间压低移速，轻武器与空手不限制。

func test_light_one_hand_sword_keeps_full_move_speed() -> void:
	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.weapon_class = "one_hand_melee"
	weapon.skill_school = "one_hand_sword"
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(weapon)).is_equal_approx(1.0, 0.001)


func test_dagger_keeps_full_move_speed() -> void:
	var weapon := WeaponData.new()
	weapon.id = "dagger"
	weapon.weapon_class = "one_hand_melee"
	weapon.tags = ["dagger"]
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(weapon)).is_equal_approx(1.0, 0.001)


func test_null_weapon_keeps_full_move_speed() -> void:
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(null)).is_equal_approx(1.0, 0.001)


func test_greatsword_reduces_move_speed_during_slash() -> void:
	var weapon := WeaponData.new()
	weapon.id = "greatsword"
	weapon.weapon_class = "two_hand"
	weapon.skill_school = "two_hand_sword"
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(weapon)).is_less(1.0)


func test_axe_reduces_move_speed_during_slash() -> void:
	var weapon := WeaponData.new()
	weapon.id = "battle_axe"
	weapon.weapon_class = "two_hand"
	weapon.skill_school = "two_hand_axe"
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(weapon)).is_less(1.0)


func test_warhammer_reduces_move_speed_during_slash() -> void:
	var weapon := WeaponData.new()
	weapon.id = "warhammer"
	weapon.weapon_class = "two_hand"
	weapon.skill_school = "war_hammer"
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(weapon)).is_less(1.0)


func test_spear_reduces_move_speed_during_slash() -> void:
	var weapon := WeaponData.new()
	weapon.id = "spear"
	weapon.weapon_class = "two_hand"
	weapon.skill_school = "spear"
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(weapon)).is_less(1.0)


func test_all_heavy_profiles_share_same_multiplier() -> void:
	var greatsword := WeaponData.new()
	greatsword.skill_school = "two_hand_sword"
	var axe := WeaponData.new()
	axe.skill_school = "two_hand_axe"
	var warhammer := WeaponData.new()
	warhammer.skill_school = "war_hammer"
	var spear := WeaponData.new()
	spear.skill_school = "spear"
	var heavy_mult: float = PlayerStateSlashing.slash_move_multiplier_for(greatsword)
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(axe)).is_equal_approx(heavy_mult, 0.001)
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(warhammer)).is_equal_approx(heavy_mult, 0.001)
	assert_float(PlayerStateSlashing.slash_move_multiplier_for(spear)).is_equal_approx(heavy_mult, 0.001)


func test_physics_process_passes_move_multiplier_to_player() -> void:
	var source := (load("res://scenes/characters/player/state/player_state_slashing.gd") as GDScript).source_code
	assert_bool(source.contains("process_movement(delta, slash_move_multiplier_for")).is_true()
