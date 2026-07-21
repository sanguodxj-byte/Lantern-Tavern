extends GdUnitTestSuite

## 34 项被动技能机制效果全量部署自动化测试

const CE := preload("res://globals/combat/combat_engine.gd")
const SR := preload("res://globals/combat/skill_runtime.gd")
const AS := preload("res://globals/equipment/affix_system.gd")

# 1. 通用扩展被动（汲取）机制测试
func test_passive_lifedrain_mechanic() -> void:
	var attack := CE.AttackInput.new()
	attack.attacker_str = 0
	attack.weapon_damage_dice = {"count": 0, "sides": 0}
	attack.weapon_damage_flat = 50.0
	attack.lifesteal_percent = 10.0 # 汲取被动 10% 吸血
	
	var defender := CE.Defender.new()
	defender.con = 0
	defender.armor_def = 0
	
	var res := CE.resolve_attack(attack, defender)
	assert_int(res.lifesteal_amount).is_equal(5) # 50 伤害的 10% 吸血 = 5 点回复

# 2. 剑类纯被动：突袭背刺 (+30% 额外背刺倍率) 机制测试
func test_passive_weapon_sword_backstab_mechanic() -> void:
	var attack_normal := CE.AttackInput.new()
	attack_normal.attacker_str = 0
	attack_normal.weapon_damage_dice = {"count": 0, "sides": 0}
	attack_normal.weapon_damage_flat = 100.0
	attack_normal.is_backstab = true
	attack_normal.set("has_sword_backstab_passive", false)
	
	var defender := CE.Defender.new()
	defender.con = 0
	var res_normal := CE.resolve_attack(attack_normal, defender)
	assert_int(res_normal.final_damage).is_equal(150) # 基础背刺 1.5 倍 = 150
	
	var attack_passive := CE.AttackInput.new()
	attack_passive.attacker_str = 0
	attack_passive.weapon_damage_dice = {"count": 0, "sides": 0}
	attack_passive.weapon_damage_flat = 100.0
	attack_passive.is_backstab = true
	attack_passive.set("has_sword_backstab_passive", true)
	
	var res_passive := CE.resolve_attack(attack_passive, defender)
	assert_int(res_passive.final_damage).is_equal(180) # 剑背刺被动：1.5 + 0.3 = 1.8 倍 = 180

# 3. 锤类纯被动：骷髅粉碎 (对骷髅 +40% 伤害且无视防御) 机制测试
func test_passive_weapon_hammer_skeleton_smash_mechanic() -> void:
	var attack := CE.AttackInput.new()
	attack.attacker_str = 0
	attack.weapon_damage_dice = {"count": 0, "sides": 0}
	attack.weapon_damage_flat = 100.0
	attack.set("is_skeleton_target", true)
	attack.set("has_skeleton_smash_passive", true)
	
	var defender := CE.Defender.new()
	defender.con = 0
	defender.armor_def = 20 # 原有 20 点物理防御应被完全无视
	
	var res := CE.resolve_attack(attack, defender)
	# 基础 100 * 1.4 = 140，防御被无视 (0 点)，最终伤害为 140
	assert_int(res.final_damage).is_equal(140)

# 4. 斧类纯被动：木质摧碎 (对木质建筑 +50% 破坏力) 机制测试
func test_passive_weapon_axe_wood_chop_mechanic() -> void:
	var attack := CE.AttackInput.new()
	attack.attacker_str = 0
	attack.weapon_damage_dice = {"count": 0, "sides": 0}
	attack.weapon_damage_flat = 100.0
	attack.set("is_wooden_structure", true)
	attack.set("has_wood_chop_passive", true)
	
	var defender := CE.Defender.new()
	defender.con = 0
	var res := CE.resolve_attack(attack, defender)
	assert_int(res.final_damage).is_equal(150) # 100 * 1.5 = 150

# 5. 7 大流派机制 key 在 SkillRuntime 中可授予性与激活校验
func test_all_14_style_passives_registration() -> void:
	var runtime: Node = auto_free(SR.new())
	var style_passives := [
		"passive_style_onehand_duelist",
		"passive_style_onehand_spellblade",
		"passive_style_shield_bash",
		"passive_style_shield_refraction",
		"passive_style_twohand_accumulation",
		"passive_style_twohand_heavy_swing",
		"passive_style_dual_cross_strike",
		"passive_style_dual_cross_counter",
		"passive_style_unarmed_flurry_storm",
		"passive_style_unarmed_over_shoulder_slam",
		"passive_style_ranged_weakpoint_sight",
		"passive_style_ranged_piercing",
		"passive_style_spell_arcane_barrier",
		"passive_style_spell_elemental_ring"
	]
	
	for key in style_passives:
		runtime.grant_mechanism_passive(key)
		assert_bool(runtime.has_mechanism_passive(key)).is_true()

# 6. 断言全量 38 个被动技能在 SkillIcons 中均返回精确 64x64 像素的 ImageTexture
func test_all_38_passive_icons_64x64_dimensions() -> void:
	var skill_icons: Node = auto_free(preload("res://globals/combat/skill_icons.gd").new())
	skill_icons._build_all_passive_icons()
	
	var file = FileAccess.open("res://data/skills.json", FileAccess.READ)
	var txt := file.get_as_text()
	file.close()
	var json := JSON.new()
	json.parse(txt)
	var skills_arr: Array = json.data["skills"]
	
	for skill in skills_arr:
		var skill_id: String = String(skill["id"])
		var tex: Texture2D = skill_icons.get_icon(skill_id)
		assert_object(tex).is_not_null()
		assert_int(tex.get_width()).is_equal(64)
		assert_int(tex.get_height()).is_equal(64)
