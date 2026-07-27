extends GdUnitTestSuite


func test_terminology_table_defines_backpack_grid_separately_from_slots() -> void:
	var table := FileAccess.get_file_as_string("res://docs/术语表.md")
	assert_bool(table.contains("右侧物品页中的背包物品网格")).is_true()
	assert_bool(table.contains("不指左侧防具槽、武器主副手槽，也不指技能槽")).is_true()
	assert_bool(table.contains("整理")).is_true()
	assert_bool(table.contains("淡暗金色正方形色块")).is_true()
	assert_bool(table.contains("物品图标、文字和品质线可以叠加")).is_true()
	assert_bool(table.contains("严格等宽等高")).is_true()
	assert_bool(table.contains("左右外边距必须分别与列间隙完全一致")).is_true()
	assert_bool(table.contains("上下外边距必须分别与行间隙完全一致")).is_true()
	assert_bool(table.contains("文字不得与选中框重叠")).is_true()


func test_agents_requires_reading_and_live_updates_to_terminology_table() -> void:
	var instructions := FileAccess.get_file_as_string("res://AGENTS.md")
	assert_bool(instructions.contains("在每次会话开始时") or instructions.contains("At the start of every session")).is_true()
	assert_bool(instructions.contains("docs/术语表.md")).is_true()
	assert_bool(instructions.contains("update `docs/术语表.md` immediately")).is_true()
