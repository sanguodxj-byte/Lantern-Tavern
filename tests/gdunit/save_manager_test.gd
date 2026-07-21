extends GdUnitTestSuite

## SaveManager 存档系统测试。
## 验证：三槽位管理、序列化/反序列化、存档文件读写、元信息查询。
## 测试中使用独立槽位操作，after_test 清理残留存档文件。

var _sm: Node  # SaveManager autoload 实例
var _tm: Node  # TavernManager autoload 实例
var _gs: Node  # GameState autoload 实例
var _ap: Node  # AttrPanel autoload 实例
var _sr: Node  # SkillRuntime autoload 实例
var _fs: Node  # FermentationSystem autoload 实例

func before() -> void:
	_sm = Engine.get_main_loop().root.get_node("SaveManager")
	_tm = Engine.get_main_loop().root.get_node("TavernManager")
	_gs = Engine.get_main_loop().root.get_node("GameState")
	_ap = Engine.get_main_loop().root.get_node("AttrPanel")
	_sr = Engine.get_main_loop().root.get_node("SkillRuntime")
	_fs = Engine.get_main_loop().root.get_node("FermentationSystem")

func after() -> void:
	# 清理测试中产生的存档文件
	for i in range(_sm.SLOT_COUNT):
		_sm.delete_save(i)

# ---------- 槽位验证 ----------

func test_slot_count_is_3() -> void:
	assert_int(_sm.SLOT_COUNT).is_equal(3)

func test_has_save_false_for_empty_slots() -> void:
	for i in range(_sm.SLOT_COUNT):
		_sm.delete_save(i)
		assert_bool(_sm.has_save(i)).is_false()

func test_has_save_false_for_invalid_slot() -> void:
	assert_bool(_sm.has_save(-1)).is_false()
	assert_bool(_sm.has_save(99)).is_false()

# ---------- 存档写入与读取 ----------

func test_save_to_slot_creates_file() -> void:
	_tm.day = 7
	_tm.gold = 500
	_tm.player_name = "测试勇者"
	_tm.save_name = "测试勇者"
	var ok: bool = _sm.save_to_slot(0)
	assert_bool(ok).is_true()
	assert_bool(_sm.has_save(0)).is_true()

func test_save_to_invalid_slot_returns_false() -> void:
	assert_bool(_sm.save_to_slot(-1)).is_false()
	assert_bool(_sm.save_to_slot(99)).is_false()

func test_load_from_empty_slot_returns_false() -> void:
	_sm.delete_save(1)
	assert_bool(_sm.load_from_slot(1)).is_false()

func test_save_load_roundtrip_tavern_manager() -> void:
	_tm.day = 12
	_tm.gold = 750
	_tm.player_name = "圆桌骑士"
	_tm.save_name = "圆桌骑士"
	_tm.has_confirmed_character_name = true
	_tm.tutorial_completed = true
	_tm.add_material("blackberry", 3)
	_tm.add_material("rat_tail", 2)
	_sm.save_to_slot(0)

	# 修改状态以验证恢复
	_tm.day = 1
	_tm.gold = 0
	_tm.player_name = ""
	_tm.inventory.clear()

	_sm.load_from_slot(0)
	assert_int(_tm.day).is_equal(12)
	assert_int(_tm.gold).is_equal(750)
	assert_str(_tm.player_name).is_equal("圆桌骑士")
	assert_bool(_tm.tutorial_completed).is_true()
	assert_int(int(_tm.inventory.get("blackberry", 0))).is_equal(3)
	assert_int(int(_tm.inventory.get("rat_tail", 0))).is_equal(2)

func test_save_load_roundtrip_game_state() -> void:
	_gs.carried_materials = {"blackberry": 5, "rat_tail": 3}
	_gs.carried_runes = {"fire_rune": 2}
	_gs.carried_equipment = {"shortsword": 1}
	_gs.carried_weapons = 4
	_gs.carried_shields = 1
	_gs.weapon_slot_ids[0] = "shortsword"
	_gs.weapon_slot_ids[1] = "axe"
	_gs.armor_slot_ids["body"] = "leather_armor"
	_gs.active_weapon_slot = 1
	_gs.carried_space_limit = 40
	_sm.save_to_slot(1)

	# 清空状态以验证恢复
	_gs.reset_state()

	_sm.load_from_slot(1)
	assert_int(int(_gs.carried_materials.get("blackberry", 0))).is_equal(5)
	assert_int(int(_gs.carried_materials.get("rat_tail", 0))).is_equal(3)
	assert_int(int(_gs.carried_runes.get("fire_rune", 0))).is_equal(2)
	assert_int(int(_gs.carried_equipment.get("shortsword", 0))).is_equal(1)
	assert_int(_gs.carried_weapons).is_equal(4)
	assert_int(_gs.carried_shields).is_equal(1)
	assert_str(String(_gs.weapon_slot_ids[0])).is_equal("shortsword")
	assert_str(String(_gs.weapon_slot_ids[1])).is_equal("axe")
	assert_int(_gs.active_weapon_slot).is_equal(1)
	assert_int(_gs.carried_space_limit).is_equal(40)

func test_save_load_roundtrip_attr_panel() -> void:
	_ap.attrs["str"] = 20
	_ap.attrs["dex"] = 15
	_ap.level = 5
	_ap.level_exp = 50
	_ap.accumulate_proficiency("one_hand_melee", 30)
	_ap.unlocked_skills.append("劈斩")
	_ap.unlocked_milestones.append("强健体魄")
	_sm.save_to_slot(2)

	# 重置以验证恢复
	_ap.reset()

	_sm.load_from_slot(2)
	assert_int(_ap.get_attr("str")).is_equal(20)
	assert_int(_ap.get_attr("dex")).is_equal(15)
	assert_int(_ap.get_level()).is_equal(5)
	assert_int(_ap.level_exp).is_equal(50)
	assert_int(_ap.get_proficiency("one_hand_melee")).is_equal(30)
	assert_bool(_ap.has_skill("劈斩")).is_true()
	assert_bool(_ap.has_milestone("强健体魄")).is_true()

func test_save_load_roundtrip_fermentation_system() -> void:
	_fs.setup_kegs(2)
	_fs.start_brewing({"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}, 3)
	_sm.save_to_slot(0)

	# 重置以验证恢复
	_fs.reset()

	_sm.load_from_slot(0)
	assert_int(_fs.max_kegs).is_equal(2)
	assert_int(_fs.kegs.size()).is_equal(2)
	# 第一个桶应该处于发酵中状态
	assert_int(_fs.kegs[0].state).is_equal(_fs.KegState.FERMENTING)
	assert_int(_fs.kegs[0].brew_day).is_equal(3)
	assert_str(_fs.kegs[0].recipe_id).is_equal("glowberry_juice")

func test_save_load_roundtrip_skill_runtime() -> void:
	_sr.slots[_sr.SLOT_G_WEAPON] = "踢击"
	_sr.slot_runes[_sr.SLOT_F_ACTION] = ["fire_rune"]
	_sm.save_to_slot(0)

	# 重置以验证恢复
	_sr.reset()
	assert_str(String(_sr.slots[_sr.SLOT_G_WEAPON])).is_equal("")

	_sm.load_from_slot(0)
	assert_str(String(_sr.slots[_sr.SLOT_G_WEAPON])).is_equal("踢击")

# ---------- 存档删除 ----------

func test_delete_save_removes_file() -> void:
	_sm.save_to_slot(0)
	assert_bool(_sm.has_save(0)).is_true()
	var ok: bool = _sm.delete_save(0)
	assert_bool(ok).is_true()
	assert_bool(_sm.has_save(0)).is_false()

func test_delete_nonexistent_save_returns_false() -> void:
	_sm.delete_save(1)
	assert_bool(_sm.delete_save(1)).is_false()

# ---------- 存档元信息查询 ----------

func test_get_slot_info_empty() -> void:
	_sm.delete_save(2)
	var info: Dictionary = _sm.get_slot_info(2)
	assert_bool(info["exists"]).is_false()

func test_get_slot_info_populated() -> void:
	_tm.day = 9
	_tm.gold = 300
	_tm.player_name = "信息测试"
	_tm.save_name = "信息测试"
	_sm.save_to_slot(1)
	var info: Dictionary = _sm.get_slot_info(1)
	assert_bool(info["exists"]).is_true()
	assert_int(info["day"]).is_equal(9)
	assert_int(info["gold"]).is_equal(300)
	assert_str(info["player_name"]).is_equal("信息测试")
	assert_str(info["save_name"]).is_equal("信息测试")
	assert_bool(String(info["timestamp"]).length() > 0).is_true()

func test_get_all_slot_infos() -> void:
	for i in range(_sm.SLOT_COUNT):
		_sm.delete_save(i)
	_tm.day = 3
	_tm.gold = 200
	_tm.player_name = "槽位A"
	_tm.save_name = "槽位A"
	_sm.save_to_slot(0)
	# slot 1 和 2 保持空
	var infos: Array = _sm.get_all_slot_infos()
	assert_int(infos.size()).is_equal(3)
	assert_bool(infos[0]["exists"]).is_true()
	assert_bool(infos[1]["exists"]).is_false()
	assert_bool(infos[2]["exists"]).is_false()

# ---------- 多槽位独立性 ----------

func test_multiple_slots_independent() -> void:
	_tm.day = 1
	_tm.gold = 100
	_tm.player_name = "玩家一"
	_tm.save_name = "玩家一"
	_sm.save_to_slot(0)

	_tm.day = 10
	_tm.gold = 1000
	_tm.player_name = "玩家二"
	_tm.save_name = "玩家二"
	_sm.save_to_slot(1)

	# 验证两个槽位独立
	var info0: Dictionary = _sm.get_slot_info(0)
	var info1: Dictionary = _sm.get_slot_info(1)
	assert_int(info0["day"]).is_equal(1)
	assert_int(info0["gold"]).is_equal(100)
	assert_int(info1["day"]).is_equal(10)
	assert_int(info1["gold"]).is_equal(1000)

	# 加载槽位0后状态应该恢复为玩家一
	_sm.load_from_slot(0)
	assert_int(_tm.day).is_equal(1)
	assert_int(_tm.gold).is_equal(100)
	assert_str(_tm.player_name).is_equal("玩家一")

# ---------- 覆盖存档 ----------

func test_overwrite_save() -> void:
	_tm.day = 5
	_tm.gold = 500
	_tm.player_name = "原存档"
	_tm.save_name = "原存档"
	_sm.save_to_slot(0)

	_tm.day = 15
	_tm.gold = 999
	_tm.player_name = "覆盖存档"
	_tm.save_name = "覆盖存档"
	_sm.save_to_slot(0)

	_sm.load_from_slot(0)
	assert_int(_tm.day).is_equal(15)
	assert_int(_tm.gold).is_equal(999)
	assert_str(_tm.player_name).is_equal("覆盖存档")

# ---------- 序列化完整性 ----------

func test_serialize_all_contains_all_subsystems() -> void:
	var data: Dictionary = _sm.serialize_all()
	assert_bool(data.has("version")).is_true()
	assert_bool(data.has("timestamp")).is_true()
	assert_bool(data.has("tavern_manager")).is_true()
	assert_bool(data.has("game_state")).is_true()
	assert_bool(data.has("attr_panel")).is_true()
	assert_bool(data.has("skill_runtime")).is_true()
	assert_bool(data.has("fermentation_system")).is_true()

func test_serialize_all_version_correct() -> void:
	var data: Dictionary = _sm.serialize_all()
	assert_int(int(data["version"])).is_equal(_sm.SAVE_VERSION)

# ---------- reset_all ----------

func test_reset_all_clears_state() -> void:
	_tm.day = 20
	_tm.gold = 5000
	_ap.attrs["str"] = 50
	_gs.carried_weapons = 10

	_sm.reset_all()

	assert_int(_tm.day).is_equal(1)
	assert_int(_tm.gold).is_equal(100)
	assert_int(_ap.get_attr("str")).is_equal(5)
	assert_int(_gs.carried_weapons).is_equal(0)
