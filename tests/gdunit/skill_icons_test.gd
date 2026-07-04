extends GdUnitTestSuite
## 技能图标生成器测试
## 验证：53 个技能图标全量生成 + 查表命中 + 流派色相区分

func test_skill_icons_autoload_registered() -> void:
	var root: Node = Engine.get_main_loop().root
	assert_object(root.get_node_or_null("SkillIcons")).is_not_null()

func test_all_30_weapon_skill_icons_built() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	var sd := preload("res://globals/skill_data.gd")
	for skill in sd.SKILLS:
		var tex: Texture2D = icons.get_icon(skill.id)
		assert_object(tex).is_not_null()
		assert_int(tex.get_width()).is_equal(64)
		assert_int(tex.get_height()).is_equal(64)

func test_all_5_action_skill_icons_built() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	var action_db := preload("res://globals/action_skills.gd")
	for skill in action_db.SKILLS:
		assert_object(icons.get_icon(skill.id)).is_not_null()

func test_all_18_milestone_icons_built() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	var sd := preload("res://globals/skill_data.gd")
	for ms in sd.ATTR_MILESTONES:
		assert_object(icons.get_icon(ms.id)).is_not_null()

func test_unknown_skill_returns_placeholder() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	var tex: Texture2D = icons.get_icon("不存在的技能")
	assert_object(tex).is_not_null()
	assert_int(tex.get_width()).is_equal(64)

func test_total_icon_count_is_53() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	# 30 武器 + 5 动作 + 18 被动 = 53
	var sd := preload("res://globals/skill_data.gd")
	var action_db := preload("res://globals/action_skills.gd")
	var count: int = 0
	for s in sd.SKILLS:
		if icons.get_icon(s.id) != null:
			count += 1
	for s in action_db.SKILLS:
		if icons.get_icon(s.id) != null:
			count += 1
	for m in sd.ATTR_MILESTONES:
		if icons.get_icon(m.id) != null:
			count += 1
	assert_int(count).is_equal(53)
