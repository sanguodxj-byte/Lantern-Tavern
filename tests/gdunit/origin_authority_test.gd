extends GdUnitTestSuite

# 出身状态单一权威测试（架构审查 0804 P2-1 / F3）。
# 规范：出身 id 的持久化权威是 AttrPanel.origin_id（attr_panel.gd serialize/deserialize）。
# TavernManager 不得再维护未序列化的重复写路径 selected_origin_id。

var _sm: Node  # SaveManager autoload
var _tm: Node  # TavernManager autoload
var _ap: Node  # AttrPanel autoload

func before() -> void:
	_sm = Engine.get_main_loop().root.get_node("SaveManager")
	_tm = Engine.get_main_loop().root.get_node("TavernManager")
	_ap = Engine.get_main_loop().root.get_node("AttrPanel")

func after() -> void:
	for i in range(_sm.SLOT_COUNT):
		_sm.delete_save(i)

# 禁止模式守卫：TavernManager 源码不得再出现重复的 selected_origin_id 写路径。
func test_tavern_manager_source_has_no_selected_origin_id() -> void:
	var tm_script := load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source := tm_script.source_code
	assert_bool(source.contains("selected_origin_id")).is_false()

# 单一权威回归锁：新游戏出身通过 AttrPanel.origin_id（唯一持久化字段）流转，
# 经历 save → reset_all → load 后仍应从存档恢复。
func test_origin_survives_save_load_roundtrip_via_attr_panel() -> void:
	_sm.reset_all()
	# 与 start_new_game 内部相同的出身应用路径（不含场景切换副作用）
	_tm._apply_origin_to_game_state("retired_mercenary")
	assert_str(String(_ap.origin_id)).is_equal("retired_mercenary")

	assert_bool(_sm.save_to_slot(0)).is_true()

	_sm.reset_all()
	assert_str(String(_ap.origin_id)).is_equal("")

	assert_bool(_sm.load_from_slot(0)).is_true()
	assert_str(String(_ap.origin_id)).is_equal("retired_mercenary")
