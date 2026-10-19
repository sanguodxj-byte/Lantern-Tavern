extends GdUnitTestSuite

const RecipeData := preload("res://globals/combat/spell_recipe_data.gd")
const SpellLoadoutScript := preload("res://globals/combat/spell_loadout.gd")
const AccessPolicy := preload("res://globals/combat/spell_access_policy.gd")
const SpellInterfaceScene := preload("res://scenes/ui/spell_interface.tscn")
const RuneData := preload("res://globals/combat/rune_data.gd")


func test_fixed_recipe_resolves_exact_order() -> void:
	var spell := RecipeData.resolve(["ember", "force", "launch"])
	assert_str(String(spell.get("id", ""))).is_equal("spell_fireball")
	assert_str(String(spell.get("name", ""))).is_equal("火球术")
	assert_str(String(spell.get("projectile_id", ""))).is_equal("elemental_bolt")
	assert_str(String(spell.get("status", ""))).is_equal("projectile_ready_not_wired")
	assert_bool(RecipeData.resolve(["force", "ember", "launch"]).is_empty()).is_true()


func test_every_spell_recipe_is_unique_fixed_and_has_imagery() -> void:
	var ids: Dictionary = {}
	for spell in RecipeData.get_all_recipes():
		var spell_id := String(spell.get("id", ""))
		var recipe: Array = spell.get("recipe", [])
		assert_bool(not spell_id.is_empty()).is_true()
		assert_bool(not ids.has(spell_id)) \
			.override_failure_message("法术 ID 重复: %s" % spell_id).is_true()
		ids[spell_id] = true
		assert_bool(recipe.size() >= 1 and recipe.size() <= RecipeData.RUNES_PER_SPELL).is_true()
		assert_str(String(spell.get("imagery", ""))) \
			.override_failure_message("法术缺少可绘制意象: %s" % spell_id).is_not_empty()
		assert_dict(RecipeData.resolve(recipe)).is_equal(spell)
		for rune_id in recipe:
			assert_bool(RuneData.has_rune(String(rune_id))) \
				.override_failure_message("法术 %s 引用了未知符文 %s" % [spell_id, rune_id]).is_true()


func test_loadout_has_five_spell_slots_and_three_runes_each() -> void:
	var loadout := SpellLoadoutScript.new()
	assert_int(loadout.slot_runes.size()).is_equal(5)
	for rune_ids in loadout.slot_runes:
		assert_int(rune_ids.size()).is_equal(3)


func test_loadout_updates_spell_automatically_when_recipe_completes() -> void:
	var loadout := SpellLoadoutScript.new()
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_bool(loadout.set_rune(0, 1, "force")).is_true()
	assert_bool(loadout.set_rune(0, 2, "launch")).is_true()
	assert_str(String(loadout.get_spell(0).get("id", ""))).is_equal("spell_fireball")


func test_loadout_rejects_gapped_rune_placement_and_clears_following_runes() -> void:
	var loadout := SpellLoadoutScript.new()
	assert_bool(loadout.set_rune(0, 1, "force")).is_false()
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_bool(loadout.set_rune(0, 1, "force")).is_true()
	assert_bool(loadout.set_rune(0, 0, "")).is_true()
	assert_array(loadout.get_runes(0)).is_equal(["", "", ""])


func test_loadout_inventory_limits_equipped_rune_copies() -> void:
	var loadout := SpellLoadoutScript.new()
	loadout.set_rune_inventory({"ember": 1, "force": 2})
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_int(loadout.get_remaining_count("ember")).is_equal(0)
	assert_bool(loadout.set_rune(1, 0, "ember")).is_false()
	assert_bool(loadout.set_rune(1, 0, "force")).is_true()
	assert_int(loadout.get_remaining_count("force")).is_equal(1)


func test_loadout_reconciles_slots_when_inventory_shrinks() -> void:
	var loadout := SpellLoadoutScript.new()
	loadout.set_rune_inventory({"ember": 2})
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_bool(loadout.set_rune(1, 0, "ember")).is_true()
	loadout.set_rune_inventory({"ember": 1})
	assert_array(loadout.get_runes(0)).is_equal(["ember", "", ""])
	assert_array(loadout.get_runes(1)).is_equal(["", "", ""])


func test_loadout_emits_inventory_changed_on_set_rune_inventory() -> void:
	# 拾取/消耗符文后 game_state 会重新 set_rune_inventory：
	# 必须发出 inventory_changed，法术界面才能刷新右侧符文列表。
	var loadout := SpellLoadoutScript.new()
	var emitted := {"n": 0}
	loadout.inventory_changed.connect(func() -> void: emitted["n"] += 1)
	loadout.set_rune_inventory({"ember": 1, "force": 1})
	assert_int(emitted["n"]).is_equal(1)
	loadout.set_rune_inventory({"ember": 1})
	assert_int(emitted["n"]).is_equal(2)


func test_spell_interface_rune_list_refreshes_on_inventory_change() -> void:
	# 界面打开期间符文库存变化（拾取/消耗）→ 右侧符文列表自动重建，
	# 数量与实际持有保持一致，无需重新打开界面。
	var loadout := SpellLoadoutScript.new()
	loadout.set_rune_inventory({"ember": 1, "force": 1})
	var ui := SpellInterfaceScene.instantiate()
	auto_free(ui)
	add_child(ui)
	await get_tree().process_frame
	ui.configure(loadout, loadout.get_available_rune_ids())
	await get_tree().process_frame

	var buttons: Array = []
	for child in ui._rune_list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child)
	assert_int(buttons.size()).is_equal(2)
	assert_str((buttons[1] as Button).text).contains("×1")

	# 拾取 guardian：库存变化信号 → 列表自动出现新符文
	loadout.set_rune_inventory({"ember": 1, "force": 2, "guardian": 1})
	await get_tree().process_frame
	buttons.clear()
	for child in ui._rune_list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child)
	assert_int(buttons.size()).is_equal(3)
	# 数量同步：force 增加到 2
	assert_str((buttons[1] as Button).text).contains("×2")

	# 全部消耗：列表变为空提示
	loadout.set_rune_inventory({})
	await get_tree().process_frame
	var has_button := false
	for child in ui._rune_list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			has_button = true
	assert_bool(has_button).is_false()


# ── 技能界面：符文图标 + 拖拽装备（数据格式与装备面板一致）─────────────

func _make_configured_spell_ui() -> Array:
	var loadout := SpellLoadoutScript.new()
	loadout.set_rune_inventory({"ember": 2, "force": 1})
	var ui := SpellInterfaceScene.instantiate()
	auto_free(ui)
	add_child(ui)
	await get_tree().process_frame
	ui.configure(loadout, loadout.get_available_rune_ids())
	await get_tree().process_frame
	return [loadout, ui]


func test_spell_interface_rune_list_buttons_show_icons() -> void:
	# 需求：所有有图标的符文必须显示图标，禁止纯文字展示。
	var setup: Array = await _make_configured_spell_ui()
	var ui: Node = setup[1]
	var shown := 0
	for child in ui._rune_list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			assert_object((child as Button).icon).is_not_null()
			shown += 1
	assert_int(shown).is_equal(2)


func test_spell_interface_socket_buttons_show_icons_after_equip() -> void:
	var setup: Array = await _make_configured_spell_ui()
	var loadout: RefCounted = setup[0]
	var ui: Node = setup[1]
	# 空槽显示 "-" 且无图标
	var socket := ui._rune_slot_buttons[0][0] as Button
	assert_str(socket.text).is_equal("-")
	assert_object(socket.icon).is_null()
	# 装配后：文本清空、显示符文图标
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	await get_tree().process_frame
	assert_str(socket.text).is_equal("")
	assert_object(socket.icon).is_not_null()


func test_spell_interface_socket_accepts_drag_payload() -> void:
	# 拖拽装备：符文列表（kind=rune 载荷）拖到空槽位 → 装配成功
	var setup: Array = await _make_configured_spell_ui()
	var ui: Node = setup[1]
	var socket: Variant = ui._rune_slot_buttons[0][0]
	var payload := {"kind": "rune", "id": "ember", "count": 1}
	assert_bool(ui.rune_button_can_drop(socket, payload)).is_true()
	ui.rune_button_drop(socket, payload)
	assert_array(ui.loadout.get_runes(0)).is_equal(["ember", "", ""])
	# 拖拽后列表数量同步（1 枚 ember 已被占用）
	for child in ui._rune_list.get_children():
		if child is Button and not child.is_queued_for_deletion() and (child as Button).text.contains("余烬"):
			assert_str((child as Button).text).contains("×1")


func test_spell_interface_socket_rejects_invalid_drag() -> void:
	var setup: Array = await _make_configured_spell_ui()
	var ui: Node = setup[1]
	var loadout: RefCounted = setup[0]
	# 目标槽已被占用
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	await get_tree().process_frame
	assert_bool(ui.rune_button_can_drop(ui._rune_slot_buttons[0][0], {"kind": "rune", "id": "force", "count": 1})).is_false()
	# 悬空装配：第 3 位无前驱符文
	assert_bool(ui.rune_button_can_drop(ui._rune_slot_buttons[0][2], {"kind": "rune", "id": "force", "count": 1})).is_false()
	# 库存不足：force 仅 1 枚且已占用后，再拖入第二枚
	assert_bool(loadout.set_rune(1, 0, "force")).is_true()
	await get_tree().process_frame
	assert_bool(ui.rune_button_can_drop(ui._rune_slot_buttons[1][1], {"kind": "rune", "id": "force", "count": 1})).is_false()
	# 非法载荷
	assert_bool(ui.rune_button_can_drop(ui._rune_slot_buttons[1][1], {"kind": "skill", "id": "x"})).is_false()
	# 连续且库存充足的空槽位正确接受（[1][0] 已装 force，[1][1] 空且余 1 枚 ember）
	assert_bool(ui.rune_button_can_drop(ui._rune_slot_buttons[1][1], {"kind": "rune", "id": "ember", "count": 1})).is_true()


func test_spell_interface_socket_move_between_slots() -> void:
	# 槽位间移动：拖出符文到另一空槽（携带 source_slot），不消耗库存且清空源槽
	var setup: Array = await _make_configured_spell_ui()
	var ui: Node = setup[1]
	var loadout: RefCounted = setup[0]
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_bool(loadout.set_rune(1, 0, "ember")).is_true()
	await get_tree().process_frame
	# 源槽(0,0) 与目标槽(1,1)：两枚 ember 均已占用，若按"新装备"判断库存不足；
	# 移动语义（source_slot）应允许。
	var payload := {"kind": "rune", "id": "ember", "count": 1, "source_slot": 0, "source_rune_index": 0}
	assert_bool(ui.rune_button_can_drop(ui._rune_slot_buttons[1][1], payload)).is_true()
	ui.rune_button_drop(ui._rune_slot_buttons[1][1], payload)
	assert_array(loadout.get_runes(0)).is_equal(["", "", ""])
	assert_array(loadout.get_runes(1)).is_equal(["ember", "ember", ""])


func test_spell_access_policy_accepts_staff_and_grimoire() -> void:
	var staff := WeaponData.new()
	staff.id = "staff"
	staff.weapon_class = "wand"
	staff.skill_school = "staff"
	assert_bool(AccessPolicy.can_use_spell_interface(staff, false)).is_true()
	var grimoire := WeaponData.new()
	grimoire.id = "grimoire"
	grimoire.weapon_class = "grimoire"
	assert_bool(AccessPolicy.can_use_spell_interface(grimoire, false)).is_true()


func test_spell_access_policy_requires_arcane_sword_for_one_hand_sword() -> void:
	var sword := WeaponData.new()
	sword.id = "shortsword"
	sword.weapon_class = "one_hand_melee"
	sword.skill_school = "one_hand_sword"
	assert_bool(AccessPolicy.can_use_spell_interface(sword, false)).is_false()
	assert_bool(AccessPolicy.can_use_spell_interface(sword, true)).is_true()


func test_spell_access_policy_rejects_unrelated_weapon_even_with_passive() -> void:
	var bow := WeaponData.new()
	bow.id = "longbow"
	bow.weapon_class = "longbow"
	bow.skill_school = "longbow"
	assert_bool(AccessPolicy.can_use_spell_interface(bow, true)).is_false()


func test_spell_interface_builds_five_spell_rows_and_three_runes_per_row() -> void:
	var ui := SpellInterfaceScene.instantiate()
	auto_free(ui)
	add_child(ui)
	await get_tree().process_frame
	assert_int(ui._spell_buttons.size()).is_equal(5)
	assert_int(ui._rune_slot_buttons.size()).is_equal(5)
	for row in ui._rune_slot_buttons:
		assert_int(row.size()).is_equal(3)


func test_spell_interface_switches_body_orientation_at_compact_width() -> void:
	var ui := SpellInterfaceScene.instantiate()
	auto_free(ui)
	add_child(ui)
	await get_tree().process_frame
	ui.size = Vector2(1600, 900)
	ui._apply_responsive_layout()
	assert_bool(ui._body is BoxContainer).is_true()
	assert_bool(ui._body.vertical).is_false()
	assert_bool(ui._rune_panel.visible).is_true()
	ui.size = Vector2(1280, 720)
	ui._apply_responsive_layout()
	assert_bool(ui._body.vertical).is_false()
	assert_bool(ui._rune_panel.visible).is_false()
	ui.size = Vector2(960, 900)
	ui._apply_responsive_layout()
	assert_bool(ui._body.vertical).is_true()
	assert_bool(ui._rune_panel.visible).is_true()
	assert_float(ui._rune_panel.custom_minimum_size.y).is_equal(180.0)
