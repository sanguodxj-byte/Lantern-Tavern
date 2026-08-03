extends GdUnitTestSuite

## 敌人攻击动作档案测试：
## 1) 非人形（body）四种怪物招式两两可区分（动画/前摇/命中窗口/突进）；
## 2) 招式动画必须存在于对应 rig；
## 3) 人形（weapon）按武器流派区分节奏（匕首快、长矛先手、重武器慢而迟）；
## 4) 状态机接入档案（命中窗口同步 + 非人形突进）。

const PROFILE := preload("res://globals/combat/enemy_attack_profile.gd")
const SLASH_ANIM := preload("res://globals/combat/combat_slash_animator.gd")

const BODY_SCENES := {
	"slime": "res://scenes/characters/enemies/slime.tscn",
	"spider": "res://scenes/characters/enemies/spider.tscn",
	"dragon": "res://scenes/characters/enemies/dragon.tscn",
	"rock_golem": "res://scenes/characters/enemies/rock_golem.tscn",
}

## 与战斗 rig 同款直接加载（避免实例化敌人场景产生物理/自动播放副作用）
const BODY_RIGS := {
	"slime": "res://assets/meshes/characters/voxel_slime_24px_rig.glb",
	"spider": "res://assets/meshes/characters/voxel_spider_30px_rig.glb",
	"dragon": "res://assets/meshes/characters/voxel_dragon_256px_rig.glb",
	"rock_golem": "res://assets/meshes/characters/voxel_rock_golem_80px_rig.glb",
}

# ---------- 非人形招式区分 ----------

func test_body_profiles_exist_for_all_non_humanoid() -> void:
	for enemy_id in BODY_SCENES:
		var profile: Dictionary = PROFILE.body_profile(enemy_id)
		assert_bool(not profile.is_empty()) \
			.override_failure_message("%s 缺少身体攻击档案" % enemy_id) \
			.is_true()
		assert_bool(String(profile.get("animation", "")).length() > 0).is_true()

func test_body_profiles_are_pairwise_distinct() -> void:
	var ids: Array = BODY_SCENES.keys()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a: Dictionary = PROFILE.body_profile(String(ids[i]))
			var b: Dictionary = PROFILE.body_profile(String(ids[j]))
			var distinct := String(a.get("animation", "")) != String(b.get("animation", "")) \
				or absf(float(a.get("windup", 0)) - float(b.get("windup", 0))) > 0.01 \
				or absf(float(a.get("hit_start", 0)) - float(b.get("hit_start", 0))) > 0.01 \
				or absf(float(a.get("lunge", 0)) - float(b.get("lunge", 0))) > 0.01
			assert_bool(distinct) \
				.override_failure_message("%s 与 %s 的身体攻击招式未作区分" % [ids[i], ids[j]]) \
				.is_true()

func test_body_profile_animations_exist_in_rigs() -> void:
	for enemy_id in BODY_RIGS:
		var profile: Dictionary = PROFILE.body_profile(String(enemy_id))
		var anim_name := String(profile.get("animation", ""))
		var packed := load(String(BODY_RIGS[enemy_id])) as PackedScene
		assert_object(packed).is_not_null()
		var instance := packed.instantiate()
		var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert_object(animation_player) \
			.override_failure_message("%s rig 缺少 AnimationPlayer" % enemy_id) \
			.is_not_null()
		if animation_player != null:
			assert_bool(animation_player.has_animation(anim_name)) \
				.override_failure_message("%s 的招式动画 %s 不存在于 rig" % [enemy_id, anim_name]) \
				.is_true()
		instance.free()

func test_body_lunge_distinguishes_lunging_vs_standing_attacks() -> void:
	# 史莱姆扑击应有突进；蜘蛛/石魔像原地攻击
	assert_float(float(PROFILE.body_profile("slime").get("lunge", 0.0))).is_greater(1.0)
	assert_float(float(PROFILE.body_profile("spider").get("lunge", 0.0))).is_equal(0.0)
	assert_float(float(PROFILE.body_profile("rock_golem").get("lunge", 0.0))).is_equal(0.0)

func test_dragon_uses_procedural_sweep_for_weak_rig_clip() -> void:
	# 巨龙 rig 的 slash 动画近乎静止，必须由程序化横扫（sweep>0）补偿，
	# 其余身体招式不启用横扫
	assert_float(float(PROFILE.body_profile("dragon").get("sweep", 0.0))).is_greater(0.3)
	assert_float(float(PROFILE.body_profile("slime").get("sweep", 0.0))).is_equal(0.0)
	assert_float(float(PROFILE.body_profile("spider").get("sweep", 0.0))).is_equal(0.0)
	assert_float(float(PROFILE.body_profile("rock_golem").get("sweep", 0.0))).is_equal(0.0)

func test_slashing_state_implements_body_sweep_and_restore() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/enemies/state/enemy_state_slashing.gd")
	assert_bool(source.contains("_apply_body_sweep")).is_true()
	assert_bool(source.contains("body_sweep_rad")).is_true()
	assert_bool(source.contains("_restore_body_pivot")).is_true()
	assert_bool(source.contains("_body_pivot.rotation.y = yaw")).is_true()

func test_normalize_type_strips_elite_prefix() -> void:
	assert_str(PROFILE.normalize_type("elite_rock_golem")).is_equal("rock_golem")
	assert_str(PROFILE.normalize_type("boss_dragon")).is_equal("dragon")
	assert_str(PROFILE.normalize_type("slime")).is_equal("slime")

func test_profile_for_enemy_body_uses_type_animation() -> void:
	var profile: Dictionary = PROFILE.profile_for_enemy("rock_golem", null, true)
	assert_str(String(profile.get("animation", ""))).is_equal("slash_heavy")
	var fallback: Dictionary = PROFILE.profile_for_enemy("unknown_beast", null, true)
	assert_str(String(fallback.get("animation", ""))).is_equal(PROFILE.ANIMATION_FALLBACK_BODY)

# ---------- 人形武器节奏 ----------

func test_weapon_profiles_differentiate_timing() -> void:
	var dagger := WeaponData.new()
	dagger.skill_school = "dagger"
	var spear := WeaponData.new()
	spear.skill_school = "spear"
	var heavy := WeaponData.new()
	heavy.skill_school = "two_hand_axe"
	var sword := WeaponData.new()
	sword.weapon_class = "one_hand_melee"
	var shield := WeaponData.new()
	shield.item_tag = "shield"

	var dagger_profile: Dictionary = PROFILE.weapon_profile(dagger)
	var spear_profile: Dictionary = PROFILE.weapon_profile(spear)
	var heavy_profile: Dictionary = PROFILE.weapon_profile(heavy)
	var sword_profile: Dictionary = PROFILE.weapon_profile(sword)
	var shield_profile: Dictionary = PROFILE.weapon_profile(shield)

	# 匕首前摇最短、最快
	assert_float(float(dagger_profile.get("windup", 0))).is_less(float(sword_profile.get("windup", 0)))
	assert_float(float(dagger_profile.get("speed_scale", 1))).is_greater(1.0)
	# 重武器前摇最长、命中窗口最晚
	assert_float(float(heavy_profile.get("windup", 0))).is_greater(float(sword_profile.get("windup", 0)))
	assert_float(float(heavy_profile.get("hit_start", 0))).is_greater(float(sword_profile.get("hit_start", 0)))
	# 长矛先手命中
	assert_float(float(spear_profile.get("hit_start", 0))).is_less(float(sword_profile.get("hit_start", 0)))
	# 盾牌中速
	assert_float(float(shield_profile.get("windup", 0))).is_greater(float(dagger_profile.get("windup", 0)))

func test_profile_for_enemy_weapon_keeps_weapon_timing() -> void:
	var spear := WeaponData.new()
	spear.skill_school = "spear"
	var profile: Dictionary = PROFILE.profile_for_enemy("goblin", spear, false)
	assert_float(float(profile.get("hit_start", 0))).is_less(SLASH_ANIM.ENEMY_HIT_START)
	assert_float(float(profile.get("speed_scale", SLASH_ANIM.ENEMY_SPEED_SCALE))).is_equal(1.0)

# ---------- 状态机接入 ----------

func test_slashing_state_integrates_attack_profile() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/enemies/state/enemy_state_slashing.gd")
	assert_bool(source.contains("ATTACK_PROFILE.profile_for_enemy")).is_true()
	assert_bool(source.contains("hit_start")).is_true()
	assert_bool(source.contains("is_enemy_hit_active(slash_progress, hit_start, hit_end)")).is_true()
	assert_bool(source.contains("_apply_lunge")).is_true()
	assert_bool(source.contains("lunge_speed")).is_true()
	assert_bool(source.contains("enemy.get_enemy_type_id()")).is_true()

func test_slash_animator_accepts_custom_hit_windows() -> void:
	assert_bool(SLASH_ANIM.is_enemy_hit_active(0.25, 0.20, 0.65)).is_true()
	assert_bool(SLASH_ANIM.is_enemy_hit_active(0.70, 0.20, 0.65)).is_false()
	# 默认窗口行为不变（既有敌人/测试）
	assert_bool(SLASH_ANIM.is_enemy_hit_active(SLASH_ANIM.ENEMY_HIT_START)).is_true()
	assert_bool(SLASH_ANIM.is_enemy_hit_active(SLASH_ANIM.ENEMY_HIT_END + 0.01)).is_false()

func test_enemy_reports_type_id_from_scene_or_meta() -> void:
	var enemy: Enemy = (load("res://scenes/characters/enemies/slime.tscn") as PackedScene).instantiate()
	assert_str(enemy.get_enemy_type_id()).is_equal("slime")
	enemy.set_meta("enemy_base_type", "elite_rock_golem")
	assert_str(enemy.get_enemy_type_id()).is_equal("elite_rock_golem")
	enemy.free()
