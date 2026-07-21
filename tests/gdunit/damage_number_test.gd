extends GdUnitTestSuite

## 伤害飘字组件测试：样式区分、像素字体、billboard、FxHelper 工厂。

const DamageNumberScript := preload("res://fx/damage_number.gd")
const DAMAGE_NUMBER_SCENE := preload("res://fx/damage_number.tscn")
const PIXEL_FONT_PATH := "res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf"


func test_scene_and_script_exist() -> void:
	assert_bool(ResourceLoader.exists("res://fx/damage_number.gd")).is_true()
	assert_bool(ResourceLoader.exists("res://fx/damage_number.tscn")).is_true()
	assert_object(DAMAGE_NUMBER_SCENE).is_not_null()


func test_kind_from_flags_priority() -> void:
	# miss > block > heal > crit > damage
	assert_int(DamageNumberScript.kind_from_flags(true, true, true, true)).is_equal(DamageNumberScript.Kind.MISS)
	assert_int(DamageNumberScript.kind_from_flags(true, true, true, false)).is_equal(DamageNumberScript.Kind.BLOCK)
	assert_int(DamageNumberScript.kind_from_flags(true, true, false, false)).is_equal(DamageNumberScript.Kind.HEAL)
	assert_int(DamageNumberScript.kind_from_flags(true, false, false, false)).is_equal(DamageNumberScript.Kind.CRIT)
	assert_int(DamageNumberScript.kind_from_flags(false, false, false, false)).is_equal(DamageNumberScript.Kind.DAMAGE)


func test_format_text_for_kinds() -> void:
	assert_str(DamageNumberScript.format_text(12, DamageNumberScript.Kind.DAMAGE)).is_equal("12")
	assert_str(DamageNumberScript.format_text(24, DamageNumberScript.Kind.CRIT)).is_equal("24!")
	assert_str(DamageNumberScript.format_text(8, DamageNumberScript.Kind.HEAL)).is_equal("+8")
	assert_str(DamageNumberScript.format_text(5, DamageNumberScript.Kind.BLOCK)).contains("5")
	assert_str(DamageNumberScript.format_text(0, DamageNumberScript.Kind.BLOCK)).is_not_empty()
	assert_str(DamageNumberScript.format_text(0, DamageNumberScript.Kind.MISS)).is_not_empty()
	# 负数钳制
	assert_str(DamageNumberScript.format_text(-3, DamageNumberScript.Kind.DAMAGE)).is_equal("0")
	assert_str(DamageNumberScript.format_text(-3, DamageNumberScript.Kind.HEAL)).is_equal("+0")


func test_color_and_font_size_distinct() -> void:
	var dmg_c: Color = DamageNumberScript.color_for_kind(DamageNumberScript.Kind.DAMAGE)
	var crit_c: Color = DamageNumberScript.color_for_kind(DamageNumberScript.Kind.CRIT)
	var heal_c: Color = DamageNumberScript.color_for_kind(DamageNumberScript.Kind.HEAL)
	var block_c: Color = DamageNumberScript.color_for_kind(DamageNumberScript.Kind.BLOCK)
	assert_bool(dmg_c.is_equal_approx(crit_c)).is_false()
	assert_bool(dmg_c.is_equal_approx(heal_c)).is_false()
	assert_bool(heal_c.is_equal_approx(block_c)).is_false()
	assert_int(DamageNumberScript.font_size_for_kind(DamageNumberScript.Kind.CRIT)) \
		.is_greater(DamageNumberScript.font_size_for_kind(DamageNumberScript.Kind.DAMAGE))
	assert_int(DamageNumberScript.font_size_for_kind(DamageNumberScript.Kind.DAMAGE)) \
		.is_greater_equal(DamageNumberScript.font_size_for_kind(DamageNumberScript.Kind.BLOCK))


func test_setup_applies_pixel_font_and_billboard() -> void:
	var node: Node3D = DAMAGE_NUMBER_SCENE.instantiate() as Node3D
	add_child(node)
	assert_object(node).is_not_null()
	assert_bool(node.has_method("setup")).is_true()
	node.call("setup", 42, DamageNumberScript.Kind.CRIT)
	var label := node.get_node_or_null("Label") as Label3D
	assert_object(label).is_not_null()
	assert_str(label.text).is_equal("42!")
	assert_int(label.billboard).is_equal(BaseMaterial3D.BILLBOARD_ENABLED)
	assert_bool(label.no_depth_test).is_true()
	assert_int(label.texture_filter).is_equal(BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	assert_object(label.font).is_not_null()
	if label.font is FontFile:
		assert_str((label.font as FontFile).resource_path).contains("ark-pixel")
	# 暴击字号更大
	assert_int(label.font_size).is_equal(DamageNumberScript.FONT_SIZE_CRIT)
	node.queue_free()


func test_setup_heal_and_block_text() -> void:
	var heal_node: Node3D = DAMAGE_NUMBER_SCENE.instantiate() as Node3D
	add_child(heal_node)
	heal_node.call("setup", 15, DamageNumberScript.Kind.HEAL)
	var heal_label := heal_node.get_node("Label") as Label3D
	assert_str(heal_label.text).is_equal("+15")
	assert_bool(heal_label.modulate.is_equal_approx(DamageNumberScript.COLOR_HEAL)).is_true()
	heal_node.queue_free()

	var block_node: Node3D = DAMAGE_NUMBER_SCENE.instantiate() as Node3D
	add_child(block_node)
	block_node.call("setup", 9, DamageNumberScript.Kind.BLOCK)
	var block_label := block_node.get_node("Label") as Label3D
	assert_str(block_label.text).contains("9")
	block_node.queue_free()


func test_spawn_static_factory() -> void:
	var parent := Node3D.new()
	add_child(parent)
	var num: Node = DamageNumberScript.spawn(parent, Vector3(1, 2, 3), 7, DamageNumberScript.Kind.DAMAGE)
	assert_object(num).is_not_null()
	assert_bool(num is DamageNumberScript or num.get_script() == DamageNumberScript).is_true()
	assert_vector(num.global_position).is_equal_approx(
		Vector3(1, 2 + DamageNumberScript.VERTICAL_SPAWN_OFFSET, 3), Vector3(0.001, 0.001, 0.001)
	)
	var label := num.get_node("Label") as Label3D
	assert_str(label.text).is_equal("7")
	# parent null → null
	assert_object(DamageNumberScript.spawn(null, Vector3.ZERO, 1)).is_null()
	parent.queue_free()


func test_fx_helper_has_damage_number_api() -> void:
	var source := (load("res://globals/core/fx_helper.gd") as GDScript).source_code
	assert_bool(source.contains("create_damage_number")).is_true()
	assert_bool(source.contains("create_damage_number_flags")).is_true()
	assert_bool(source.contains("create_heal_number")).is_true()
	assert_bool(source.contains("create_block_number")).is_true()
	assert_bool(source.contains("damage_number.tscn")).is_true()


func test_fx_helper_create_damage_number_runtime() -> void:
	# 无 GameState.current_level 时回退到 current_scene / self
	var node: Node3D = FxHelper.create_damage_number(Vector3(0, 1, 0), 33, DamageNumberScript.Kind.DAMAGE)
	assert_object(node).is_not_null()
	assert_bool(is_instance_valid(node)).is_true()
	var label := node.get_node_or_null("Label") as Label3D
	assert_object(label).is_not_null()
	assert_str(label.text).is_equal("33")
	node.queue_free()

	var crit: Node3D = FxHelper.create_damage_number_flags(Vector3.ZERO, 99, true)
	assert_object(crit).is_not_null()
	var crit_label := crit.get_node("Label") as Label3D
	assert_str(crit_label.text).is_equal("99!")
	crit.queue_free()

	var heal: Node3D = FxHelper.create_heal_number(Vector3.ZERO, 4)
	assert_object(heal).is_not_null()
	assert_str((heal.get_node("Label") as Label3D).text).is_equal("+4")
	heal.queue_free()

	var block: Node3D = FxHelper.create_block_number(Vector3.ZERO, 2)
	assert_object(block).is_not_null()
	assert_str((block.get_node("Label") as Label3D).text).contains("2")
	block.queue_free()


func test_combat_paths_emit_damage_numbers() -> void:
	var enemy_hurt := (load("res://scenes/characters/enemies/state/enemy_state_hurt.gd") as GDScript).source_code
	assert_bool(enemy_hurt.contains("create_damage_number_flags")).is_true()
	assert_bool(enemy_hurt.contains("_spawn_damage_number")).is_true()

	var player_hurt := (load("res://scenes/characters/player/state/player_state_hurt.gd") as GDScript).source_code
	assert_bool(player_hurt.contains("create_damage_number_flags")).is_true()

	var enemy_block := (load("res://scenes/characters/enemies/state/enemy_state_blocking.gd") as GDScript).source_code
	assert_bool(enemy_block.contains("create_block_number")).is_true()

	var player_src := (load("res://scenes/characters/player/player.gd") as GDScript).source_code
	assert_bool(player_src.contains("create_block_number")).is_true()
	assert_bool(player_src.contains("set_crit")).is_true()

	var enemy_src := (load("res://scenes/characters/enemies/enemy.gd") as GDScript).source_code
	assert_bool(enemy_src.contains("set_crit")).is_true()
	assert_bool(enemy_src.contains("player_hit_enemy")).is_true()
	assert_bool(enemy_src.contains("create_damage_number_flags")).is_true()

	var skill_src := (load("res://scenes/characters/player/player_skill_dispatcher.gd") as GDScript).source_code
	assert_bool(skill_src.contains("create_heal_number")).is_true()

	var proj_src := (load("res://scenes/equipment/projectile_entity.gd") as GDScript).source_code
	assert_bool(proj_src.contains("create_heal_number")).is_true()


func test_state_data_has_crit_flag() -> void:
	var enemy_data := EnemyStateData.new()
	assert_bool(enemy_data.is_crit).is_false()
	enemy_data.set_crit(true)
	assert_bool(enemy_data.is_crit).is_true()

	var player_data := PlayerStateData.new()
	assert_bool(player_data.is_crit).is_false()
	player_data.set_crit(true)
	assert_bool(player_data.is_crit).is_true()


func test_pixel_font_resource_exists() -> void:
	assert_bool(ResourceLoader.exists(PIXEL_FONT_PATH)).is_true()
	var font := load(PIXEL_FONT_PATH)
	assert_object(font).is_not_null()


func test_lifetime_expires_and_frees() -> void:
	var node: Node3D = DAMAGE_NUMBER_SCENE.instantiate() as Node3D
	add_child(node)
	node.call("setup", 1, DamageNumberScript.Kind.DAMAGE)
	# 缩短寿命并主动推进 _process，避免 headless 下 timer 抖动导致未触发 queue_free
	node.set("lifetime", 0.05)
	if node.has_method("_process"):
		node.call("_process", 0.06)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(is_instance_valid(node)).is_false()
