extends GdUnitTestSuite
## 顾客 3D 表现与对话气泡系统测试。
## 验证 customer_entity.gd / customer_spawner.gd / customer_entity.tscn 完整性。

const CE_SCENE := "res://scenes/tavern/customer_entity.tscn"
const CS_SCENE := "res://scenes/tavern/customer_spawner.gd"
var ts: Node

func before_test() -> void:
	ts = Engine.get_main_loop().root.get_node("TavernSettlement")
	ts.rumor_reputation = 0
	for race in ts.faction_reputation.keys():
		ts.faction_reputation[race] = 0
	for race in ts.regular_customers.keys():
		ts.regular_customers[race].clear()

# ---------- 资源存在性 ----------

func test_customer_entity_scene_exists() -> void:
	assert_bool(ResourceLoader.exists(CE_SCENE)).is_true()

func test_customer_spawner_script_exists() -> void:
	assert_bool(ResourceLoader.exists(CS_SCENE)).is_true()

func test_customer_entity_scene_instantiable() -> void:
	var packed: PackedScene = load(CE_SCENE)
	var inst: Node3D = packed.instantiate()
	assert_object(inst).is_not_null()
	assert_bool(inst is Node3D).is_true()
	inst.free()

# ---------- 顾客实体行为 ----------

func test_customer_entity_has_chat_label_after_ready() -> void:
	var inst: Node3D = load(CE_SCENE).instantiate()
	add_child(inst)
	await await_idle_frame()
	assert_bool(inst.has_node("ChatBubble")).is_true()
	var lbl: Label3D = inst.get_node("ChatBubble")
	assert_bool(lbl is Label3D).is_true()
	assert_bool(lbl.visible).is_false()  # 初始隐藏
	inst.free()

func test_customer_entity_assign_seat() -> void:
	var inst: Node3D = load(CE_SCENE).instantiate()
	add_child(inst)
	var marker := Marker3D.new()
	add_child(marker)
	marker.global_position = Vector3(2, 0, 3)
	inst.assign_seat(marker)
	assert_object(inst.seat_marker).is_not_null()
	marker.free()
	inst.free()

func test_customer_entity_serve_returns_result() -> void:
	var inst: Node3D = load(CE_SCENE).instantiate()
	add_child(inst)
	inst.customer_data = ts.generate_customer("goblin")
	inst.customer_data.liked = {"腐败": 2, "甜美": 1}
	inst.customer_data.hated = ["苦涩"]
	inst.customer_data.hated_levels = {"苦涩": 0}
	var brew := {"腐败": 6, "甜美": 5}  # 极佳
	var result: Variant = inst.serve(brew, 0)
	assert_str(result["tier"]).is_equal("极佳")
	# 气泡应显示且含台词
	var lbl: Label3D = inst.get_node("ChatBubble")
	assert_bool(lbl.visible).is_true()
	assert_bool(lbl.text.length() > 0).is_true()
	inst.free()

func test_customer_entity_human_refuse_line() -> void:
	var inst: Node3D = load(CE_SCENE).instantiate()
	add_child(inst)
	inst.customer_data = ts.generate_customer("human")
	var brew := {"恶臭": 1}  # 摔杯拒付
	var result: Variant = inst.serve(brew, 10)
	assert_str(result["tier"]).is_equal("摔杯拒付")
	var lbl: Label3D = inst.get_node("ChatBubble")
	assert_bool(lbl.text.length() > 0).is_true()
	inst.free()

func test_customer_entity_leave_state() -> void:
	var inst: Node3D = load(CE_SCENE).instantiate()
	add_child(inst)
	inst.leave()
	assert_str(inst._state).is_equal("leaving")
	inst.free()

# ---------- 生成器 ----------

func test_spawner_start_service_initializes() -> void:
	# 纯逻辑测试：不依赖 @onready，直接构造 spawner 实例
	var spawner: Node3D = Node3D.new()
	spawner.set_script(load(CS_SCENE))
	add_child(spawner)
	# 手动注入 seats（绕过 @onready 依赖）
	var m1 := Marker3D.new(); var m2 := Marker3D.new()
	add_child(m1); add_child(m2)
	spawner._seats = [m1, m2]
	spawner.start_service()
	assert_bool(spawner._is_open).is_true()
	m1.free(); m2.free()
	spawner.free()


func test_spawner_stop_service_makes_customers_leave() -> void:
	var spawner: Node3D = Node3D.new()
	spawner.set_script(load(CS_SCENE))
	add_child(spawner)
	var m1 := Marker3D.new(); add_child(m1)
	spawner._seats = [m1]
	spawner._is_open = true
	# 用真实 customer_entity 场景实例（避免 set_script class_name 冲突）
	var fake_cust: Node3D = load(CE_SCENE).instantiate()
	add_child(fake_cust)
	spawner._active_customers.append(fake_cust)
	spawner.stop_service()
	assert_bool(spawner._is_open).is_false()
	assert_str(fake_cust._state).is_equal("leaving")
	fake_cust.free(); m1.free()
	spawner.free()


func test_spawner_find_free_seat() -> void:
	var spawner: Node3D = Node3D.new()
	spawner.set_script(load(CS_SCENE))
	add_child(spawner)
	var m1 := Marker3D.new(); var m2 := Marker3D.new(); var m3 := Marker3D.new()
	add_child(m1); add_child(m2); add_child(m3)
	spawner._seats = [m1, m2, m3]
	spawner._occupied_seats = {0: null}
	assert_int(spawner._find_free_seat()).is_equal(1)
	spawner._occupied_seats[1] = null
	assert_int(spawner._find_free_seat()).is_equal(2)
	spawner._occupied_seats[2] = null
	assert_int(spawner._find_free_seat()).is_equal(-1)
	m1.free(); m2.free(); m3.free()
	spawner.free()


func test_spawner_pick_race_by_visit_rate_returns_valid_race() -> void:
	var spawner: Node3D = Node3D.new()
	spawner.set_script(load(CS_SCENE))
	add_child(spawner)
	for i in range(50):
		var r: String = spawner._pick_race_by_visit_rate()
		assert_bool(["goblin", "minotaur", "cyclops", "ghost", "elf", "human"].has(r)).is_true()
	spawner.free()

# ---------- 台词池完整性 ----------

func test_all_tier_lines_defined() -> void:
	# 确保四档满意度 + 人类四档 + 入场台词全部非空
	const CE := preload("res://scenes/tavern/customer_entity.gd")
	assert_bool(CE.LINES_PERFECT.size() > 0).is_true()
	assert_bool(CE.LINES_SATISFIED.size() > 0).is_true()
	assert_bool(CE.LINES_NORMAL.size() > 0).is_true()
	assert_bool(CE.LINES_REFUSE.size() > 0).is_true()
	assert_bool(CE.LINES_HUMAN_CHEAP.size() > 0).is_true()
	assert_bool(CE.LINES_HUMAN_NORMAL.size() > 0).is_true()
	assert_bool(CE.LINES_HUMAN_EXPENSIVE.size() > 0).is_true()
	assert_bool(CE.LINES_HUMAN_REFUSE.size() > 0).is_true()
	assert_bool(CE.LINES_ENTER.size() > 0).is_true()

func test_all_lines_are_chinese_strings() -> void:
	# 隐性化表达：台词必须是中文（策划案 12 §5.0）
	const CE := preload("res://scenes/tavern/customer_entity.gd")
	for arr in [CE.LINES_PERFECT, CE.LINES_SATISFIED, CE.LINES_NORMAL, CE.LINES_REFUSE, CE.LINES_HUMAN_CHEAP, CE.LINES_HUMAN_NORMAL, CE.LINES_HUMAN_EXPENSIVE, CE.LINES_HUMAN_REFUSE, CE.LINES_ENTER]:
		for line in arr:
			assert_bool(line is String and line.length() > 0).is_true()
			# 中文检测：含至少一个 CJK 字符
			var has_cjk: bool = false
			for ch in line:
				if ch.unicode_at(0) >= 0x4E00 and ch.unicode_at(0) <= 0x9FFF:
					has_cjk = true
					break
			assert_bool(has_cjk) \
				.override_failure_message("台词无中文字符: %s" % line) \
				.is_true()
