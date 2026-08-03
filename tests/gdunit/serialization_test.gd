extends GdUnitTestSuite

## 子系统 serialize/deserialize 直接测试。
## 覆盖 TavernManager、GameState、FermentationSystem 新增的序列化方法。
## AttrPanel 和 SkillRuntime 已有各自测试，此处不再重复。

const TM_SCRIPT := preload("res://globals/tavern/tavern_manager.gd")
const GS_SCRIPT := preload("res://globals/core/game_state.gd")
const FS_SCRIPT := preload("res://globals/tavern/fermentation_system.gd")

# ---------- TavernManager serialize/deserialize ----------

func test_tavern_manager_serialize_contains_all_fields() -> void:
	var tm: Node = auto_free(TM_SCRIPT.new())
	tm.day = 5
	tm.gold = 300
	tm.player_name = "测试"
	tm.save_name = "测试"
	tm.add_material("blackberry", 3)
	var data: Dictionary = tm.serialize()
	assert_bool(data.has("day")).is_true()
	assert_bool(data.has("gold")).is_true()
	assert_bool(data.has("current_phase")).is_true()
	assert_bool(data.has("tutorial_active")).is_true()
	assert_bool(data.has("tutorial_completed")).is_true()
	assert_bool(data.has("player_name")).is_true()
	assert_bool(data.has("save_name")).is_true()
	assert_bool(data.has("has_confirmed_character_name")).is_true()
	assert_bool(data.has("inventory")).is_true()
	assert_bool(data.has("runes_inventory")).is_true()
	assert_bool(data.has("current_brews")).is_true()
	assert_bool(data.has("last_expedition_return")).is_true()
	assert_bool(data.has("missed_tavern_income_nights")).is_true()
	assert_bool(data.has("next_day_expedition_motivation")).is_true()

func test_tavern_manager_deserialize_restores_state() -> void:
	var tm1: Node = auto_free(TM_SCRIPT.new())
	tm1.day = 7
	tm1.gold = 500
	tm1.player_name = "恢复测试"
	tm1.save_name = "恢复测试"
	tm1.tutorial_completed = true
	tm1.add_material("rat_tail", 4)
	var data: Dictionary = tm1.serialize()

	var tm2: Node = auto_free(TM_SCRIPT.new())
	tm2.deserialize(data)
	assert_int(tm2.day).is_equal(7)
	assert_int(tm2.gold).is_equal(500)
	assert_str(tm2.player_name).is_equal("恢复测试")
	assert_bool(tm2.tutorial_completed).is_true()
	assert_int(int(tm2.inventory.get("rat_tail", 0))).is_equal(4)

func test_tavern_manager_reset_state() -> void:
	var tm: Node = auto_free(TM_SCRIPT.new())
	tm.day = 20
	tm.gold = 9999
	tm.player_name = "重置前"
	tm.add_material("blackberry", 10)
	tm.reset_state()
	assert_int(tm.day).is_equal(1)
	assert_int(tm.gold).is_equal(100)
	assert_str(tm.player_name).is_empty()
	assert_bool(tm.inventory.is_empty()).is_true()

# ---------- GameState serialize/deserialize ----------

func test_game_state_serialize_contains_all_fields() -> void:
	var gs: Node = auto_free(GS_SCRIPT.new())
	gs.carried_materials = {"blackberry": 3}
	gs.carried_weapons = 5
	var data: Dictionary = gs.serialize()
	assert_bool(data.has("dungeon_floor")).is_true()
	assert_bool(data.has("expedition_inventory")).is_true()
	assert_bool(data.has("equipment_loadout")).is_true()
	assert_bool(data.has("spell_loadout")).is_true()
	assert_bool(data.has("carried_weapons")).is_true()
	assert_bool(data.has("carried_shields")).is_true()
	var inventory: Dictionary = data["expedition_inventory"]
	assert_bool(inventory.has("materials")).is_true()
	assert_bool(inventory.has("runes")).is_true()
	assert_bool(inventory.has("equipment")).is_true()
	assert_bool(inventory.has("space_limit")).is_true()

func test_game_state_deserialize_restores_state() -> void:
	var gs1: Node = auto_free(GS_SCRIPT.new())
	gs1.carried_materials = {"rat_tail": 5}
	gs1.carried_runes = {"ember": 1, "force": 1, "launch": 1}
	gs1.refresh_spell_rune_inventory()
	gs1.spell_loadout.set_rune(0, 0, "ember")
	gs1.spell_loadout.set_rune(0, 1, "force")
	gs1.spell_loadout.set_rune(0, 2, "launch")
	gs1.carried_equipment = {"axe": 2}
	gs1.carried_weapons = 3
	gs1.weapon_slot_ids[0] = "axe"
	gs1.weapon_slot_ids[2] = "shield"
	gs1.active_weapon_slot = 0
	gs1.set_dungeon_floor(3)
	var data: Dictionary = gs1.serialize()

	var gs2: Node = auto_free(GS_SCRIPT.new())
	gs2.deserialize(data)
	assert_int(int(gs2.carried_materials.get("rat_tail", 0))).is_equal(5)
	assert_int(int(gs2.carried_runes.get("ember", 0))).is_equal(1)
	assert_array(gs2.spell_loadout.get_runes(0)).is_equal(["ember", "force", "launch"])
	assert_str(String(gs2.spell_loadout.get_spell(0).get("id", ""))).is_equal("spell_fireball")
	assert_int(int(gs2.carried_equipment.get("axe", 0))).is_equal(2)
	assert_int(gs2.carried_weapons).is_equal(3)
	assert_str(gs2.weapon_slot_ids[0]).is_equal("axe")
	assert_str(gs2.weapon_slot_ids[2]).is_equal("shield")
	assert_int(gs2.active_weapon_slot).is_equal(0)
	assert_str(gs2.get_dungeon_floor_label()).is_equal("L3")

func test_game_state_reset_state() -> void:
	var gs: Node = auto_free(GS_SCRIPT.new())
	gs.carried_materials = {"blackberry": 10}
	gs.carried_weapons = 5
	gs.weapon_slot_ids[0] = "sword"
	gs.set_dungeon_floor(4)
	gs.reset_state()
	assert_bool(gs.carried_materials.is_empty()).is_true()
	assert_int(gs.carried_weapons).is_equal(0)
	assert_str(gs.weapon_slot_ids[0]).is_empty()
	assert_str(gs.get_dungeon_floor_label()).is_equal("L1")

# ---------- FermentationSystem serialize/deserialize ----------

func test_fermentation_serialize_contains_kegs_and_max() -> void:
	var fs: Node = auto_free(FS_SCRIPT.new())
	fs.setup_kegs(3)
	var data: Dictionary = fs.serialize()
	assert_bool(data.has("kegs")).is_true()
	assert_bool(data.has("max_kegs")).is_true()
	assert_int(int(data["max_kegs"])).is_equal(3)
	assert_int((data["kegs"] as Array).size()).is_equal(3)

func test_fermentation_deserialize_restores_keg_state() -> void:
	var fs1: Node = auto_free(FS_SCRIPT.new())
	fs1.setup_kegs(2)
	fs1.start_brewing({"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}, 3)
	var data: Dictionary = fs1.serialize()

	var fs2: Node = auto_free(FS_SCRIPT.new())
	fs2.deserialize(data)
	assert_int(fs2.max_kegs).is_equal(2)
	assert_int(fs2.kegs.size()).is_equal(2)
	assert_int(fs2.kegs[0].state).is_equal(FS_SCRIPT.KegState.FERMENTING)
	assert_int(fs2.kegs[0].brew_day).is_equal(3)
	assert_str(fs2.kegs[0].recipe_id).is_equal("glowberry_juice")
	assert_int(fs2.kegs[1].state).is_equal(FS_SCRIPT.KegState.EMPTY)

func test_fermentation_reset_clears_kegs() -> void:
	var fs: Node = auto_free(FS_SCRIPT.new())
	fs.setup_kegs(3)
	fs.start_brewing({"blackberry": 1}, 1)
	fs.reset()
	assert_int(fs.max_kegs).is_equal(1)
	assert_int(fs.kegs.size()).is_equal(1)
	assert_int(fs.kegs[0].state).is_equal(FS_SCRIPT.KegState.EMPTY)

func test_fermentation_serialize_preserves_aging_state() -> void:
	var fs1: Node = auto_free(FS_SCRIPT.new())
	fs1.setup_kegs(1)
	fs1.start_brewing({"blackberry": 1}, 1)
	fs1.advance_day()  # FERMENTING → READY
	fs1.seal_for_aging(0)  # READY → AGING
	fs1.advance_day()  # aging_days → 1
	var data: Dictionary = fs1.serialize()

	var fs2: Node = auto_free(FS_SCRIPT.new())
	fs2.deserialize(data)
	assert_int(fs2.kegs[0].state).is_equal(FS_SCRIPT.KegState.AGING)
	assert_int(fs2.kegs[0].aging_days).is_equal(1)
	assert_bool(fs2.kegs[0].sealed).is_true()
