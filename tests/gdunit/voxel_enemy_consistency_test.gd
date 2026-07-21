extends GdUnitTestSuite
## 体素模型怪物种类一致性回归测试
## roster 保留完整重建声明；只有其中已通过 CharacterModelTiers 验收的敌人可进入运行时。

const MODEL_TIERS := preload("res://data/character_model_tiers.gd")

func _roster() -> Dictionary:
	var path := "res://data/enemy_roster.json"
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var json := JSON.new()
	assert_int(json.parse(file.get_as_text())).is_equal(OK)
	file.close()
	return json.data as Dictionary


func _roster_ids() -> Array:
	var ids: Array = []
	for entry in _roster().get("enemies", []):
		ids.append(String(entry["id"]))
	ids.sort()
	return ids


func _accepted_roster_entries() -> Array:
	var entries: Array = []
	for entry in _roster().get("enemies", []):
		if MODEL_TIERS.is_accepted(String(entry.get("id", ""))):
			entries.append(entry)
	return entries


func _accepted_roster_ids() -> Array:
	var ids: Array = []
	for entry in _accepted_roster_entries():
		ids.append(String(entry.get("id", "")))
	ids.sort()
	return ids


func _accepted_roster_types() -> Dictionary:
	var roster := _roster()
	var declared_bosses: Dictionary = {}
	for enemy_id in roster.get("boss_types", []):
		declared_bosses[String(enemy_id)] = true
	var normal: Array = []
	var boss: Array = []
	for entry in roster.get("enemies", []):
		var enemy_id := String(entry.get("id", ""))
		if not MODEL_TIERS.is_accepted(enemy_id):
			continue
		if declared_bosses.has(enemy_id):
			boss.append(enemy_id)
		else:
			normal.append(enemy_id)
	normal.sort()
	boss.sort()
	return {"normal": normal, "boss": boss}


func test_roster_file_exists() -> void:
	assert_bool(FileAccess.file_exists("res://data/enemy_roster.json")).is_true()


func test_roster_has_core_and_roguelike_monsters() -> void:
	var ids := _roster_ids()
	assert_int(ids.size()).is_greater_equal(30)
	for core_id in ["goblin", "rat", "skeleton", "slime", "troll", "necrolord", "dragon", "minotaur", "rock_golem"]:
		assert_bool(ids.has(core_id)) \
			.override_failure_message("roster missing core id: %s" % core_id).is_true()
	for extra in ["orc_raider", "shadow_assassin", "elemental_frost", "animated_armor"]:
		assert_bool(ids.has(extra)).is_true()


func test_all_accepted_roster_scenes_exist() -> void:
	for eid in _accepted_roster_ids():
		var path := "res://scenes/characters/enemies/%s.tscn" % eid
		assert_bool(ResourceLoader.exists(path)) \
			.override_failure_message("敌人场景不存在: %s" % path).is_true()


func test_all_accepted_roster_rig_glbs_exist() -> void:
	for entry in _accepted_roster_entries():
		var path := "res://assets/meshes/characters/%s" % String(entry["rig"])
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("rig GLB 不存在: %s" % path).is_true()


func test_spawner_loads_only_accepted_roster_types() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	assert_object(spawner).is_not_null()
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	var types: Array = spawner.get_all_enemy_types()
	var expected_enemy_ids := _accepted_roster_ids()
	assert_int(types.size()).is_equal(expected_enemy_ids.size())
	for eid in expected_enemy_ids:
		assert_bool(types.has(eid)) \
			.override_failure_message("DungeonSpawner missing type: %s" % eid).is_true()
	for eid in ["necrolord", "rat"]:
		assert_bool(types.has(eid)).is_false()


func test_spawner_rejects_unaccepted_prefabs() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	for eid in ["rat", "necrolord", "shadow_assassin"]:
		assert_object(spawner.call("_get_enemy_prefab", eid)).is_null()


func test_zone_configs_only_use_roster_types() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	var expected := _accepted_roster_types()
	for zone in range(6):
		var cfg: Dictionary = spawner.get_zone_config(zone)
		for key in cfg.types.keys():
			assert_bool(MODEL_TIERS.is_accepted(String(key))) \
				.override_failure_message("zone %d unaccepted type %s" % [zone, key]).is_true()
			assert_bool(expected["normal"].has(String(key))) \
				.override_failure_message("zone %d accepted non-enemy normal %s" % [zone, key]).is_true()
		for key in cfg.boss.keys():
			assert_bool(MODEL_TIERS.is_accepted(String(key))) \
				.override_failure_message("zone %d unaccepted boss %s" % [zone, key]).is_true()
			assert_bool(expected["boss"].has(String(key))) \
				.override_failure_message("zone %d accepted non-enemy boss %s" % [zone, key]).is_true()


func test_spawner_difficulty_scales() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	var hp_0: float = float(spawner.get_zone_config(0).hp_mult)
	var hp_5: float = float(spawner.get_zone_config(5).hp_mult)
	assert_bool(hp_5 > hp_0).is_true()


func test_boss_types_only_include_accepted_bosses() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	var bosses: Array = spawner.get_boss_types()
	assert_array(bosses).contains_exactly(_accepted_roster_types()["boss"])


func test_l0_temporarily_contains_full_normal_roster() -> void:
	# 临时 playtest：全部普通怪等权出现在 L0；更高区 types 为空
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	var l0: Dictionary = spawner.get_zone_config(0)
	var normals: Array = spawner.get_normal_types()
	assert_int(l0.types.size()).is_equal(normals.size())
	for nid in normals:
		assert_bool(l0.types.has(nid)) \
			.override_failure_message("L0 missing normal type: %s" % nid).is_true()
	for z in range(1, 6):
		var cfg: Dictionary = spawner.get_zone_config(z)
		assert_int(cfg.types.size()) \
			.override_failure_message("zone %d should have empty normals during L0 playtest" % z) \
			.is_equal(0)


func test_monster_preferences_cover_roster() -> void:
	var path := "res://data/monster_preferences.json"
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var json := JSON.new()
	assert_int(json.parse(file.get_as_text())).is_equal(OK)
	file.close()
	var data: Array = json.data
	var ids: Array = []
	for entry in data:
		ids.append(entry["id"])
	for eid in _roster_ids():
		assert_bool(ids.has(eid)) \
			.override_failure_message("monster_preferences missing: %s" % eid).is_true()


func test_json_entries_have_voxel_model_field() -> void:
	var path := "res://data/monster_preferences.json"
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var data: Array = json.data
	for entry in data:
		assert_bool(entry.has("voxel_model")).is_true()
		if not MODEL_TIERS.is_accepted(String(entry.get("id", ""))):
			continue
		# 只有已验收模型必须在工作树中保留可加载资产。
		var vpath: String = entry["voxel_model"]
		var rig_guess := vpath.replace(".glb", "_rig.glb")
		var ok := FileAccess.file_exists(vpath) or FileAccess.file_exists(rig_guess)
		assert_bool(ok).override_failure_message("voxel path missing for %s: %s" % [entry.get("id", "?"), vpath]).is_true()


func test_dying_state_uses_spawner_drop_or_name_fallback() -> void:
	var content := FileAccess.get_file_as_string("res://scenes/characters/enemies/state/enemy_state_dying.gd")
	assert_bool(content.contains("get_drop_id") or content.contains("enemy_base_type")).is_true()
	assert_bool(content.contains("dragon_scale")).is_true()
	assert_bool(content.contains("soul_gem")).is_true()


func test_display_name_helpers_use_roster() -> void:
	var bar := FileAccess.get_file_as_string("res://scenes/ui/enemy_health_bar.gd")
	assert_bool(bar.contains("get_display_name") or bar.contains("rock_golem")).is_true()
	var log_src := FileAccess.get_file_as_string("res://scenes/ui/combat_log.gd")
	assert_bool(log_src.contains("get_display_name") or log_src.contains("rock_golem")).is_true()


func test_spawn_planner_reads_roster() -> void:
	var content := FileAccess.get_file_as_string("res://scenes/expedition/dungeon_spawn_planner.gd")
	assert_bool(content.contains("enemy_roster.json")).is_true()
	assert_bool(content.contains("_ensure_roster")).is_true()
