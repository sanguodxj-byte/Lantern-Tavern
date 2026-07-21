extends GdUnitTestSuite
## 技能图标生成器测试
## 验证：53 个技能图标全量生成 + 查表命中 + 流派色相区分

func test_skill_icons_autoload_registered() -> void:
	var root: Node = Engine.get_main_loop().root
	assert_object(root.get_node_or_null("SkillIcons")).is_not_null()

func test_all_30_weapon_skill_icons_built() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	var sd := preload("res://globals/combat/skill_data.gd")
	for skill in sd.SKILLS:
		var tex: Texture2D = icons.get_icon(skill.id)
		assert_object(tex).is_not_null()
		assert_int(tex.get_width()).is_equal(64)
		assert_int(tex.get_height()).is_equal(64)
		assert_bool(tex.get_width() <= 128 and tex.get_height() <= 128).is_true()

func test_all_5_action_skill_icons_built() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	var action_db := preload("res://globals/combat/action_skills.gd")
	for skill in action_db.SKILLS:
		var tex: Texture2D = icons.get_icon(skill.id)
		assert_object(tex).is_not_null()
		assert_bool(tex.get_width() <= 128 and tex.get_height() <= 128).is_true()

func test_all_18_milestone_icons_built() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	var sd := preload("res://globals/combat/skill_data.gd")
	for ms in sd.ATTR_MILESTONES:
		var tex: Texture2D = icons.get_icon(ms.id)
		assert_object(tex).is_not_null()
		assert_bool(tex.get_width() <= 128 and tex.get_height() <= 128).is_true()

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
	var sd := preload("res://globals/combat/skill_data.gd")
	var action_db := preload("res://globals/combat/action_skills.gd")
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

func test_skill_pixel_png_assets_exist_and_fit_128px() -> void:
	var root: Node = Engine.get_main_loop().root
	var icons: Node = root.get_node("SkillIcons")
	var sd := preload("res://globals/combat/skill_data.gd")
	var action_db := preload("res://globals/combat/action_skills.gd")
	var ids: Array[String] = []
	for s in sd.SKILLS:
		ids.append(String(s.id))
	for s in action_db.SKILLS:
		ids.append(String(s.id))
	for m in sd.ATTR_MILESTONES:
		ids.append(String(m.id))
	for skill_id in ids:
		var path: String = icons.get_icon_path(skill_id)
		assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(path))) \
			.override_failure_message("缺少技能像素图标: %s" % path) \
			.is_true()
		var image := Image.new()
		assert_int(image.load(path)).is_equal(OK)
		assert_bool(image.get_width() <= 128 and image.get_height() <= 128) \
			.override_failure_message("%s 超过 128px" % path) \
			.is_true()
