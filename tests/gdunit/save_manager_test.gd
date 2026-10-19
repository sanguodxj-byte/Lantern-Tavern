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
var _ts: Node  # TavernSettlement autoload 实例
var _arp: Node  # ArmorProficiency autoload 实例
var _zm: Node  # ZoneManager autoload 实例

func before() -> void:
	_sm = Engine.get_main_loop().root.get_node("SaveManager")
	_tm = Engine.get_main_loop().root.get_node("TavernManager")
	_gs = Engine.get_main_loop().root.get_node("GameState")
	_ap = Engine.get_main_loop().root.get_node("AttrPanel")
	_sr = Engine.get_main_loop().root.get_node("SkillRuntime")
	_fs = Engine.get_main_loop().root.get_node("FermentationSystem")
	_ts = Engine.get_main_loop().root.get_node("TavernSettlement")
	_arp = Engine.get_main_loop().root.get_node("ArmorProficiency")
	_zm = Engine.get_main_loop().root.get_node("ZoneManager")

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

## P1-2（1122 审查）：三段恢复协议——保存成功后仅 final 存在，无 .tmp/.bak 残留。
func test_save_three_phase_protocol_cleans_backup() -> void:
	_sm.delete_save(0)
	assert_bool(_sm.save_to_slot(0)).is_true()
	assert_bool(FileAccess.file_exists("user://saves/slot_0.json")).is_true()
	assert_bool(FileAccess.file_exists("user://saves/slot_0.json.tmp")).is_false()
	assert_bool(FileAccess.file_exists("user://saves/slot_0.json.bak")).is_false()

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
	# 隔离（0805）：清掉其他套件/用例（如顾客声望赠礼随机掷骰）残留的
	# 共享 TavernManager 库存，否则 add_material 会在旧值上叠加导致断言漂移。
	_tm.inventory.clear()
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

func test_save_load_roundtrip_tavern_settlement() -> void:
	_ts.reset_state()
	_ts.rumor_reputation = 88
	_ts.faction_reputation["goblin"] = 350
	var cust = _ts.generate_customer("goblin")
	cust.individual_affinity = 45
	cust.is_regular = true
	cust.display_name = cust.real_name
	_ts.regular_customers["goblin"].append(cust)
	_sm.save_to_slot(0)

	_ts.reset_state()
	assert_int(_ts.rumor_reputation).is_equal(0)

	_sm.load_from_slot(0)
	assert_int(_ts.rumor_reputation).is_equal(88)
	assert_int(int(_ts.faction_reputation["goblin"])).is_equal(350)
	assert_int(_ts.regular_customers["goblin"].size()).is_equal(1)
	var restored = _ts.regular_customers["goblin"][0]
	assert_int(restored.individual_affinity).is_equal(45)
	assert_bool(restored.is_regular).is_true()
	assert_str(restored.real_name).is_equal(cust.real_name)

func test_save_load_roundtrip_armor_proficiency() -> void:
	_arp.reset()
	_arp.add_exp("light", 35)
	_arp.add_exp("heavy", 120)
	_sm.save_to_slot(0)

	_arp.reset()
	assert_int(_arp.get_exp("light")).is_equal(0)

	_sm.load_from_slot(0)
	assert_int(_arp.get_exp("light")).is_equal(35)
	assert_int(_arp.get_exp("heavy")).is_equal(120)
	assert_int(_arp.get_level("heavy")).is_equal(13)

func test_save_load_roundtrip_zone_manager() -> void:
	_zm.set_zone(4)
	_sm.save_to_slot(0)

	_zm.set_zone(0)

	_sm.load_from_slot(0)
	assert_int(_zm.get_zone()).is_equal(4)

## 端到端：背包词缀实例 + 已装备实例进存档，读档后完整恢复（0804 P0-2）。
func test_save_load_roundtrip_equipment_instances() -> void:
	_gs.reset_state()  # 隔离：清掉其他用例遗留在共享 autoload 上的背包状态
	var w := WeaponData.new()
	w.id = "shortsword"
	w.affixes = ["sharp"]
	w.condition = 345
	w.tier_index = 2
	w.material_tier = "steel"
	w.is_cursed = true
	assert_bool(_gs.expedition_inventory.add_equipment_instance(w)).is_true()
	_gs.equipment_loadout.weapon_slots[0] = "shortsword"
	_gs.equipment_loadout.weapon_instances[0] = w.to_save_dict()
	assert_bool(_sm.save_to_slot(0)).is_true()

	_gs.reset_state()
	assert_bool(_gs.expedition_inventory.equipment_instances.is_empty()).is_true()
	assert_bool(_gs.equipment_loadout.get_weapon_instance(0).is_empty()).is_true()

	assert_bool(_sm.load_from_slot(0)).is_true()
	assert_int(int(_gs.expedition_inventory.equipment.get("shortsword", 0))).is_equal(1)
	var inst: WeaponData = _gs.expedition_inventory.get_equipment_instance("shortsword")
	assert_object(inst).is_not_null()
	assert_array(inst.affixes).contains("sharp")
	assert_int(inst.condition).is_equal(345)
	assert_int(inst.tier_index).is_equal(2)
	assert_str(inst.material_tier).is_equal("steel")
	assert_bool(inst.is_cursed).is_true()
	assert_str(String(_gs.equipment_loadout.weapon_slots[0])).is_equal("shortsword")
	var w_inst: Dictionary = _gs.equipment_loadout.get_weapon_instance(0)
	assert_int(int(w_inst.get("condition", 0))).is_equal(345)
	assert_array(w_inst.get("affixes", [])).contains("sharp")

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
	assert_bool(data.has("tavern_settlement")).is_true()
	assert_bool(data.has("armor_proficiency")).is_true()
	assert_bool(data.has("selected_zone")).is_true()

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

# ---------- 原子写（架构审查 0804 P1-2） ----------

func test_save_leaves_no_tmp_file_behind() -> void:
	_tm.day = 3
	_tm.gold = 100
	_tm.player_name = "原子写"
	_tm.save_name = "原子写"
	assert_bool(_sm.save_to_slot(0)).is_true()
	var tmp_path := "user://saves/slot_0.json.tmp"
	assert_bool(FileAccess.file_exists(tmp_path)).is_false()
	assert_bool(_sm.has_save(0)).is_true()


func test_saved_file_is_valid_json() -> void:
	assert_bool(_sm.save_to_slot(0)).is_true()
	var file := FileAccess.open("user://saves/slot_0.json", FileAccess.READ)
	assert_object(file).is_not_null()
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	assert_int(json.parse(text)).is_equal(OK)


func test_load_falls_back_to_tmp_during_replace_window() -> void:
	# 模拟原子替换窗口期：正式文件缺失但 .tmp 完整 → 读档应成功回退。
	var tmp_path := "user://saves/slot_0.json.tmp"
	var formal_path := "user://saves/slot_0.json"
	if FileAccess.file_exists(formal_path):
		DirAccess.remove_absolute(formal_path)
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)
	_tm.day = 11
	_tm.gold = 330
	_tm.player_name = "回退档"
	_tm.save_name = "回退档"
	# 直接写 tmp 完整 JSON（模拟保存中断前已完成 tmp 写入）
	var payload: Dictionary = _sm.serialize_all()
	payload["version"] = _sm.SAVE_VERSION
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(JSON.stringify(payload))
	file.close()

	_tm.day = 1
	_tm.gold = 0
	_tm.player_name = ""
	assert_bool(_sm.load_from_slot(0)).is_true()
	assert_int(_tm.day).is_equal(11)
	assert_int(_tm.gold).is_equal(330)
	assert_str(_tm.player_name).is_equal("回退档")
	DirAccess.remove_absolute(tmp_path)


func test_delete_save_also_removes_tmp() -> void:
	assert_bool(_sm.save_to_slot(0)).is_true()
	var tmp_path := "user://saves/slot_0.json.tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string("{}")
	file.close()
	assert_bool(_sm.delete_save(0)).is_true()
	assert_bool(FileAccess.file_exists(tmp_path)).is_false()

## ADR-005：SaveSection 注册协议——注册的 section 参与 serialize/deserialize/reset。
class StubSection:
	extends "res://globals/core/state/save_section.gd"
	var serialize_calls := 0
	var deserialize_calls := 0
	var reset_calls := 0
	func _init() -> void:
		section_key = "stub_test"
	func serialize() -> Dictionary:
		serialize_calls += 1
		return {"stub": 7}
	func deserialize(_data: Dictionary) -> void:
		deserialize_calls += 1
	func reset() -> void:
		reset_calls += 1

func test_save_section_registry_invokes_serialize_deserialize_reset() -> void:
	var stub := StubSection.new()
	_sm.register_section(stub)
	_sm.delete_save(0)
	assert_bool(_sm.save_to_slot(0)).is_true()
	assert_int(stub.serialize_calls).is_greater(0)
	_sm.reset_all()
	assert_int(stub.reset_calls).is_greater(0)
	assert_bool(_sm.load_from_slot(0)).is_true()
	assert_int(stub.deserialize_calls).is_greater(0)
	# 恢复后 stub 值被 section 协议处理（存档 sections 块存在）
	var json := JSON.new()
	var f := FileAccess.open("user://saves/slot_0.json", FileAccess.READ)
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		var sections: Dictionary = (json.data as Dictionary).get("sections", {})
		assert_int(int(sections.get("stub_test", {}).get("stub", 0))).is_equal(7)

## ADR-005：ZoneManager 迁移验证——经 sections 协议 roundtrip 恢复选区。
func test_zone_save_section_roundtrip_via_sections() -> void:
	_zm.set_zone(4)
	_sm.delete_save(0)
	assert_bool(_sm.save_to_slot(0)).is_true()
	_zm.set_zone(0)
	assert_bool(_sm.load_from_slot(0)).is_true()
	assert_int(_zm.get_zone()).is_equal(4)
