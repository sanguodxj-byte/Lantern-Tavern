extends GdUnitTestSuite
## 生产 HUD（tavern_ui.tscn）场景契约测试（决策 G3 / P0-1）。
## 验证：
## 1. 生产 HUD 不再实例化旧 BrewingPanel —— 酿造写入唯一入口为 3D BrewFlowSystem。
## 2. D5：HUD 材料类型色彩不再消费过期的 data/brewing_materials.json，
##    改为按 BrewingData.MATERIALS_DB（采集）分类，其余（怪物掉落）归为 drop。

const TAVERN_UI_PATH := "res://scenes/ui/tavern_ui.tscn"

# ---------- D1：生产 HUD 无 BrewingPanel ----------

func test_tavern_ui_scene_text_has_no_brewing_panel() -> void:
	var source: String = FileAccess.get_file_as_string(TAVERN_UI_PATH)
	assert_bool(source.find("BrewingPanel") == -1) \
		.override_failure_message("tavern_ui.tscn 仍包含 BrewingPanel 节点文本，决策 G3 要求移除") \
		.is_true()

func test_tavern_ui_instantiated_has_no_brewing_panel_node() -> void:
	var inst: Control = load(TAVERN_UI_PATH).instantiate()
	add_child(inst)
	assert_object(inst.get_node_or_null("BrewingPanel")) \
		.override_failure_message("tavern_ui 实例仍含 BrewingPanel 节点") \
		.is_null()
	assert_object(inst.get_node_or_null("BrewingPanel/BrewingPanelInstance")) \
		.override_failure_message("tavern_ui 实例仍含 BrewingPanel/BrewingPanelInstance") \
		.is_null()
	inst.queue_free()

func test_tavern_ui_still_instantiates_hud_script() -> void:
	var inst: Control = load(TAVERN_UI_PATH).instantiate()
	add_child(inst)
	# 移除 BrewingPanel 后 HUD 主脚本（TavernHUD）必须仍然挂载
	var script: Script = inst.get_script()
	assert_object(script).is_not_null()
	assert_bool(script.resource_path.ends_with("tavern_hud.gd")).is_true()
	inst.queue_free()

# ---------- D5：材料类型分类（不再读取过期 JSON） ----------

func test_material_type_gather_from_brewing_data() -> void:
	var inst: Control = load(TAVERN_UI_PATH).instantiate()
	add_child(inst)
	# 已登记酿酒材料 = 采集类（绿色）
	assert_str(String(inst.call("_material_type_of", "blackberry"))).is_equal("gather")
	assert_str(String(inst.call("_material_type_of", "rat_tail"))).is_equal("gather")
	inst.queue_free()

func test_material_type_drop_for_monster_materials() -> void:
	var inst: Control = load(TAVERN_UI_PATH).instantiate()
	add_child(inst)
	# 怪物掉落（未在 MATERIALS_DB 登记）→ drop（蓝紫色）
	assert_str(String(inst.call("_material_type_of", "goblin_ear"))).is_equal("drop")
	assert_str(String(inst.call("_material_type_of", "skeleton_dust"))).is_equal("drop")
	inst.queue_free()
