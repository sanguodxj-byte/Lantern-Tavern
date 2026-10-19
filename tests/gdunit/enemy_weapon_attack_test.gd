extends GdUnitTestSuite

const ENEMY_SCENES := {
	"goblin": "res://scenes/characters/enemies/goblin.tscn",
	"kobold": "res://scenes/characters/enemies/kobold.tscn",
	"skeleton": "res://scenes/characters/enemies/skeleton.tscn",
	"troll": "res://scenes/characters/enemies/troll.tscn",
	"orc_raider": "res://scenes/characters/enemies/orc_raider.tscn",
	"minotaur": "res://scenes/characters/enemies/minotaur.tscn",
	"drow_blade": "res://scenes/characters/enemies/drow_blade.tscn",
}

const SLASH_ANIMATOR := preload("res://globals/combat/combat_slash_animator.gd")


func test_all_accepted_humanoid_enemy_scenes_have_dynamic_weapon_data() -> void:
	# 文本级校验（不实例化敌人场景）：实例化未入树的 CharacterBody3D 物理体再释放
	# 会触发 Godot 4.7 Windows/headless 的引擎崩溃（SIGSEGV，gdUnit 孤子清理阶段）。
	# 本测试契约只需确认场景声明了动态挂载的武器数据，直接解析 .tscn 文本即可。
	for enemy_id in ENEMY_SCENES:
		var packed := load(ENEMY_SCENES[enemy_id]) as PackedScene
		assert_object(packed).is_not_null()
		var source := FileAccess.get_file_as_string(ENEMY_SCENES[enemy_id])
		assert_bool(source.contains("weapon_data = ExtResource(")) \
			.override_failure_message("%s must declare a weapon for dynamic hand mounting" % enemy_id) \
			.is_true()


func test_enemy_animation_name_uses_humanoid_attack_clips() -> void:
	var one_hand := WeaponData.new()
	one_hand.weapon_class = "one_hand_melee"
	var axe := WeaponData.new()
	axe.skill_school = "two_hand_axe"
	var dagger := WeaponData.new()
	dagger.skill_school = "dagger"
	var spear := WeaponData.new()
	spear.skill_school = "spear"

	assert_str(SLASH_ANIMATOR.enemy_animation_name(one_hand)).is_equal("slash_one_hand")
	assert_str(SLASH_ANIMATOR.enemy_animation_name(axe)).is_equal("slash_heavy")
	assert_str(SLASH_ANIMATOR.enemy_animation_name(dagger)).is_equal("slash_dagger")
	assert_str(SLASH_ANIMATOR.enemy_animation_name(spear)).is_equal("thrust_spear")
	assert_str(SLASH_ANIMATOR.enemy_animation_name(null)).is_equal("claw_swipe")


func test_enemy_attack_windup_defaults_to_half_second() -> void:
	var enemy := Enemy.new()
	assert_float(enemy.attack_windup_seconds).is_equal_approx(0.5, 0.001)
	enemy.free()


func test_enemy_slash_state_has_explicit_windup_phase() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/enemies/state/enemy_state_slashing.gd")
	assert_bool(source.contains("attack_windup_seconds")).is_true()
	assert_bool(source.contains("_play_windup_pose()")) .is_true()
	assert_bool(source.contains("if not strike_started")).is_true()
	assert_bool(source.contains("_start_strike()")).is_true()


func test_spawner_passes_roster_weapon_to_enemy_runtime() -> void:
	var source := FileAccess.get_file_as_string("res://globals/dungeon/dungeon_spawner.gd")
	assert_bool(source.contains('enemy.set_meta("weapon_id", get_weapon_id(base_type))')).is_true()
	assert_bool(source.contains("func get_weapon_id(enemy_type: String) -> String")).is_true()


func test_legacy_enemy_weapon_resources_resolve_to_canonical_registry_data() -> void:
	var legacy_weapon := load("res://data/weapons/axe.tres") as WeaponData
	var resolved := WeaponRegistry.resolve_weapon_data(legacy_weapon)
	assert_object(resolved).is_not_null()
	assert_str(resolved.id).is_equal("axe")
	assert_str(resolved.skill_school).is_equal("two_hand_axe")
