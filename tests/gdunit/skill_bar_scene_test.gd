extends GdUnitTestSuite
## 技能快捷栏 UI 场景测试
## 验证：skill_bar.tscn 节点齐全 + expedition_hud 挂载实例

func test_skill_bar_scene_loads() -> void:
	var scene: PackedScene = load("res://scenes/ui/skill_bar.tscn")
	assert_object(scene).is_not_null()

func test_skill_bar_has_active_slots() -> void:
	var inst: Control = load("res://scenes/ui/skill_bar.tscn").instantiate()
	add_child(inst)
	assert_object(inst.get_node_or_null("ActiveRow/SlotF")).is_not_null()
	assert_object(inst.get_node_or_null("ActiveRow/SlotG")).is_not_null()
	assert_object(inst.get_node_or_null("ActiveRow/SlotF/CDOverlay")).is_not_null()
	assert_object(inst.get_node_or_null("ActiveRow/SlotG/CDOverlay")).is_not_null()
	inst.queue_free()

func test_skill_bar_has_passive_slots() -> void:
	var inst: Control = load("res://scenes/ui/skill_bar.tscn").instantiate()
	add_child(inst)
	for i in range(1, 6):
		assert_object(inst.get_node_or_null("PassiveRow/P%d" % i)).is_not_null()
	inst.queue_free()

func test_skill_bar_f_slot_label() -> void:
	var inst: Control = load("res://scenes/ui/skill_bar.tscn").instantiate()
	add_child(inst)
	assert_str(inst.get_node("ActiveRow/SlotF/KeyLabel").text).is_equal("F")
	assert_str(inst.get_node("ActiveRow/SlotG/KeyLabel").text).is_equal("G")
	inst.queue_free()

func test_expedition_hud_has_skill_bar_instance() -> void:
	var inst: Control = load("res://scenes/ui/expedition_hud.tscn").instantiate()
	add_child(inst)
	assert_object(inst.get_node_or_null("SkillBarInstance")).is_not_null()
	inst.queue_free()

func test_skill_g_input_action_registered() -> void:
	assert_bool(InputMap.has_action("skill_g")).is_true()

func test_kick_input_action_still_exists() -> void:
	# F 键复用现有 kick 输入
	assert_bool(InputMap.has_action("kick")).is_true()

func test_skill_bar_has_icon_texture_rects() -> void:
	var inst: Control = load("res://scenes/ui/skill_bar.tscn").instantiate()
	add_child(inst)
	assert_object(inst.get_node_or_null("ActiveRow/SlotF/Icon")).is_not_null()
	assert_object(inst.get_node_or_null("ActiveRow/SlotG/Icon")).is_not_null()
	assert_str(inst.get_node("ActiveRow/SlotF/Icon").get_class()).is_equal("TextureRect")
	inst.queue_free()

func test_skill_bar_has_cd_overlay_nodes() -> void:
	var inst: Control = load("res://scenes/ui/skill_bar.tscn").instantiate()
	add_child(inst)
	var f_cd: Node = inst.get_node_or_null("ActiveRow/SlotF/CDOverlay")
	var g_cd: Node = inst.get_node_or_null("ActiveRow/SlotG/CDOverlay")
	assert_object(f_cd).is_not_null()
	assert_object(g_cd).is_not_null()
	# CDOverlay 应挂载 cd_overlay.gd 脚本
	assert_bool(f_cd.get_script() != null).is_true()
	assert_bool(g_cd.get_script() != null).is_true()
	inst.queue_free()

func test_cd_overlay_progress_default_ready() -> void:
	var inst: Control = load("res://scenes/ui/skill_bar.tscn").instantiate()
	add_child(inst)
	var f_cd: Node = inst.get_node("ActiveRow/SlotF/CDOverlay")
	# 默认 progress=1.0（就绪，无遮罩）
	assert_float(f_cd.progress).is_equal(1.0)
	inst.queue_free()

func test_skill_bar_has_cd_label_nodes() -> void:
	var inst: Control = load("res://scenes/ui/skill_bar.tscn").instantiate()
	add_child(inst)
	assert_object(inst.get_node_or_null("ActiveRow/SlotF/CDLabel")).is_not_null()
	assert_object(inst.get_node_or_null("ActiveRow/SlotG/CDLabel")).is_not_null()
	inst.queue_free()

func test_skill_bar_uses_readable_pixel_hud_frame() -> void:
	var inst: Control = load("res://scenes/ui/skill_bar.tscn").instantiate()
	add_child(inst)
	await await_idle_frame()
	assert_object(inst.get_node_or_null("Backdrop")).is_not_null()
	assert_str(String(inst.get_node("Backdrop").theme_type_variation)).is_equal("HUDPanel")
	assert_float(inst.get_node("ActiveRow/SlotF").size.x).is_greater_equal(76.0)
	assert_float(inst.get_node("ActiveRow/SlotG").size.y).is_greater_equal(76.0)
	inst.queue_free()
