extends GdUnitTestSuite

# 第二轮性能优化回归测试：
# P0-4: LightingController 缓存闪烁光源
# P0-5: CombatHUD 脏标记驱动刷新
# P1-3: PixelBar 值未变时跳过重绘
# P1-4: Crosshair 仅状态变化时重绘
# P1-5: ProjectileEntity 共享材质缓存

const LIGHTING_CONTROLLER_SCRIPT := "res://globals/lighting/lighting_controller.gd"
const COMBAT_HUD_SCRIPT := "res://scenes/ui/combat_hud.gd"
const CROSSHAIR_SCRIPT := "res://scenes/ui/crosshair.gd"
const PROJECTILE_ENTITY_SCRIPT := "res://scenes/equipment/projectile_entity.gd"


# ── P0-4: LightingController 缓存闪烁光源 ──────────────────

func test_lighting_controller_caches_flicker_lights() -> void:
	var script: GDScript = load(LIGHTING_CONTROLLER_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_cached_flicker_lights")) \
		.override_failure_message("LightingController 必须缓存闪烁光源到 _cached_flicker_lights") \
		.is_true()
	assert_bool(source.contains("_flicker_cache_dirty")) \
		.override_failure_message("LightingController 必须有 _flicker_cache_dirty 脏标记") \
		.is_true()
	# _process 不应每帧调用 get_nodes_in_group
	var proc_start := source.find("func _process")
	assert_int(proc_start).is_greater(-1)
	var proc_end := source.find("\n\n##", proc_start)
	var proc_section := source.substr(proc_start, (proc_end - proc_start) if proc_end > 0 else 600)
	assert_bool(not proc_section.contains("get_nodes_in_group")) \
		.override_failure_message("_process 不应每帧调用 get_nodes_in_group，应使用缓存") \
		.is_true()
	assert_bool(source.contains("_refresh_flicker_cache")) \
		.override_failure_message("LightingController 必须有 _refresh_flicker_cache 函数刷新缓存") \
		.is_true()


func test_lighting_controller_invalidate_marks_dirty() -> void:
	var script: GDScript = load(LIGHTING_CONTROLLER_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("func invalidate_flicker_cache")) \
		.override_failure_message("LightingController 必须有 invalidate_flicker_cache 公共方法") \
		.is_true()


func test_lighting_controller_apply_tavern_profile_marks_dirty() -> void:
	var script: GDScript = load(LIGHTING_CONTROLLER_SCRIPT)
	var source := script.source_code
	var profile_section := source.substr(source.find("func apply_tavern_profile"))
	var profile_end := profile_section.find("\n\n##")
	var profile_body := profile_section.substr(0, profile_end if profile_end > 0 else 600)
	assert_bool(profile_body.contains("_flicker_cache_dirty = true")) \
		.override_failure_message("apply_tavern_profile 添加光源后必须标记 _flicker_cache_dirty = true") \
		.is_true()


# ── P0-5: CombatHUD 脏标记驱动刷新 ──────────────────────────

func test_combat_hud_uses_dirty_flags() -> void:
	var script: GDScript = load(COMBAT_HUD_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_bars_dirty")) \
		.override_failure_message("CombatHUD 必须有 _bars_dirty 脏标记") \
		.is_true()
	assert_bool(source.contains("_shields_dirty")) \
		.override_failure_message("CombatHUD 必须有 _shields_dirty 脏标记") \
		.is_true()
	assert_bool(source.contains("_buffs_dirty")) \
		.override_failure_message("CombatHUD 必须有 _buffs_dirty 脏标记") \
		.is_true()


func test_combat_hud_process_checks_dirty_before_update() -> void:
	var script: GDScript = load(COMBAT_HUD_SCRIPT)
	var source := script.source_code
	var proc_start := source.find("func _process")
	assert_int(proc_start).is_greater(-1)
	var proc_end := source.find("\n\n##", proc_start)
	var proc_section := source.substr(proc_start, (proc_end - proc_start) if proc_end > 0 else 800)
	assert_bool(proc_section.contains("_check_bars_changed")) \
		.override_failure_message("_process 必须调用 _check_bars_changed 检测血量变化") \
		.is_true()
	assert_bool(proc_section.contains("_check_shields_changed")) \
		.override_failure_message("_process 必须调用 _check_shields_changed 检测护盾变化") \
		.is_true()
	assert_bool(proc_section.contains("_check_buffs_changed")) \
		.override_failure_message("_process 必须调用 _check_buffs_changed 检测 buff 变化") \
		.is_true()
	assert_bool(proc_section.contains("if _bars_dirty")) \
		.override_failure_message("_update_bars 必须受 if _bars_dirty 保护") \
		.is_true()
	assert_bool(proc_section.contains("if _shields_dirty")) \
		.override_failure_message("_update_shields 必须受 if _shields_dirty 保护") \
		.is_true()
	assert_bool(proc_section.contains("if _buffs_dirty")) \
		.override_failure_message("_update_buffs 必须受 if _buffs_dirty 保护") \
		.is_true()


func test_combat_hud_caches_last_hp_values() -> void:
	var script: GDScript = load(COMBAT_HUD_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_last_hp_current")) \
		.override_failure_message("CombatHUD 必须缓存 _last_hp_current 用于检测血量变化") \
		.is_true()
	assert_bool(source.contains("_last_mp_current")) \
		.override_failure_message("CombatHUD 必须缓存 _last_mp_current 用于检测蓝量变化") \
		.is_true()


# ── P1-3: PixelBar 值未变时跳过重绘 ──────────────────────────

func test_pixel_bar_skips_redundant_set_values() -> void:
	var script: GDScript = load("res://scenes/ui/pixel_bar.gd")
	var source := script.source_code
	var set_section := source.substr(source.find("func set_values"))
	var set_end := set_section.find("\n\nfunc")
	var set_body := set_section.substr(0, set_end if set_end > 0 else 400)
	assert_bool(set_body.contains("if current == _current and maximum == _max")) \
		.override_failure_message("set_values 必须在值未变时提前返回，跳过格式化与重绘") \
		.is_true()


# ── P1-4: Crosshair 仅状态变化时重绘 ─────────────────────────

func test_crosshair_redraws_only_on_state_change() -> void:
	var script: GDScript = load(CROSSHAIR_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_last_drawn_targeting")) \
		.override_failure_message("Crosshair 必须缓存 _last_drawn_targeting 用于检测状态变化") \
		.is_true()
	assert_bool(source.contains("_last_drawn_aiming")) \
		.override_failure_message("Crosshair 必须缓存 _last_drawn_aiming 用于检测状态变化") \
		.is_true()
	var proc_start := source.find("func _process")
	assert_int(proc_start).is_greater(-1)
	var proc_end := source.find("\n\nfunc", proc_start)
	var proc_section := source.substr(proc_start, (proc_end - proc_start) if proc_end > 0 else 500)
	assert_bool(proc_section.contains("_is_targeting != _last_drawn_targeting")) \
		.override_failure_message("_process 必须比较状态变化后才 queue_redraw") \
		.is_true()


func test_crosshair_no_redraw_when_state_unchanged() -> void:
	var crosshair := Crosshair.new()
	add_child(crosshair)
	crosshair._is_targeting = false
	crosshair._is_aiming = false
	crosshair._last_drawn_targeting = false
	crosshair._last_drawn_aiming = false
	crosshair._process(0.016)
	assert_bool(crosshair._last_drawn_targeting).is_false()
	assert_bool(crosshair._last_drawn_aiming).is_false()
	crosshair.queue_free()


# ── P1-5: ProjectileEntity 共享材质缓存 ─────────────────────

func test_projectile_entity_caches_shared_materials() -> void:
	var script: GDScript = load(PROJECTILE_ENTITY_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_shared_spell_materials")) \
		.override_failure_message("ProjectileEntity 必须有 _shared_spell_materials 共享法术弹材质缓存") \
		.is_true()
	assert_bool(source.contains("_shared_arrow_shaft_materials")) \
		.override_failure_message("ProjectileEntity 必须有 _shared_arrow_shaft_materials 共享箭杆材质缓存") \
		.is_true()
	assert_bool(source.contains("_get_shared_spell_material")) \
		.override_failure_message("ProjectileEntity 必须有 _get_shared_spell_material 获取共享材质") \
		.is_true()
	assert_bool(source.contains("_get_shared_arrow_shaft_material")) \
		.override_failure_message("ProjectileEntity 必须有 _get_shared_arrow_shaft_material 获取共享材质") \
		.is_true()


func test_projectile_entity_spell_visual_uses_shared_material() -> void:
	var script: GDScript = load(PROJECTILE_ENTITY_SCRIPT)
	var source := script.source_code
	var spell_section := source.substr(source.find("func _build_default_spell_visual"))
	var spell_end := spell_section.find("\n\n##")
	var spell_body := spell_section.substr(0, spell_end if spell_end > 0 else 600)
	assert_bool(not spell_body.contains("StandardMaterial3D.new()")) \
		.override_failure_message("_build_default_spell_visual 不应每次创建新 StandardMaterial3D，应使用共享材质") \
		.is_true()
	assert_bool(spell_body.contains("_get_shared_spell_material")) \
		.override_failure_message("_build_default_spell_visual 必须使用 _get_shared_spell_material 获取共享材质") \
		.is_true()


func test_projectile_entity_arrow_visual_uses_shared_material() -> void:
	var script: GDScript = load(PROJECTILE_ENTITY_SCRIPT)
	var source := script.source_code
	var arrow_section := source.substr(source.find("func _build_default_arrow_visual"))
	var arrow_end := arrow_section.find("\n\n##")
	var arrow_body := arrow_section.substr(0, arrow_end if arrow_end > 0 else 800)
	assert_bool(not arrow_body.contains("StandardMaterial3D.new()")) \
		.override_failure_message("_build_default_arrow_visual 不应每次创建新 StandardMaterial3D，应使用共享材质") \
		.is_true()
	assert_bool(arrow_body.contains("_get_shared_arrow_shaft_material")) \
		.override_failure_message("_build_default_arrow_visual 必须使用 _get_shared_arrow_shaft_material 获取共享材质") \
		.is_true()
	assert_bool(arrow_body.contains("_get_shared_arrow_head_material")) \
		.override_failure_message("_build_default_arrow_visual 必须使用 _get_shared_arrow_head_material 获取共享材质") \
		.is_true()
