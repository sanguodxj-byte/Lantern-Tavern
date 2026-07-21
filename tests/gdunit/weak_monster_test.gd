extends GdUnitTestSuite
## 弱怪与精英怪系统测试
## Pending A-D models are represented by roster/tier metadata only. Runtime scene
## behavior uses an accepted S fixture and never loads pending rat/zombie scenes.

const MODEL_TIERS := preload("res://data/character_model_tiers.gd")
const ACCEPTED_FIXTURE := "res://scenes/characters/enemies/goblin.tscn"


func _roster_entry(enemy_id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/enemy_roster.json")
	var parsed = JSON.parse_string(text)
	for entry in parsed.get("enemies", []):
		if String(entry.get("id", "")) == enemy_id:
			return entry
	return {}


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# ---------- Accepted fixture and pending declarations ----------

func test_pending_weak_monsters_remain_unaccepted_queue_entries() -> void:
	assert_str(MODEL_TIERS.tier_for("rat")).is_equal(MODEL_TIERS.A)
	assert_str(MODEL_TIERS.tier_for("zombie")).is_equal(MODEL_TIERS.D)
	assert_bool(MODEL_TIERS.is_accepted("rat")).is_false()
	assert_bool(MODEL_TIERS.is_accepted("zombie")).is_false()


func test_accepted_goblin_fixture_declares_runtime_components() -> void:
	var source := FileAccess.get_file_as_string(ACCEPTED_FIXTURE)
	assert_bool(source.is_empty()).is_false()
	assert_str(source).contains("voxel_goblin_32px_rig.glb")
	assert_str(source).contains('[node name="HealthComponent"')
	assert_str(source).contains('[node name="EquipmentComponent"')
	assert_str(source).contains("speed = 2.0")

func test_claw_weapon_resource_exists() -> void:
	assert_bool(ResourceLoader.exists("res://data/weapons/claw.tres")).is_true()

func test_rat_pending_roster_metadata_preserves_weak_monster_profile() -> void:
	var rat := _roster_entry("rat")
	assert_bool(rat.is_empty()).is_false()
	assert_int(int(rat.get("hp", 0))).is_less(6)
	assert_float(float(rat.get("speed", 0.0))).is_greater_equal(3.0)
	assert_str(String(rat.get("weapon", ""))).is_equal("claw")
	assert_bool(bool(rat.get("has_shield", true))).is_false()
	assert_str(String(rat.get("body_size", ""))).is_equal("small")

func test_claw_weapon_has_low_damage() -> void:
	# Read the resource contract without loading the currently broken WeaponData class.
	var source := FileAccess.get_file_as_string("res://data/weapons/claw.tres")
	assert_str(source).contains("damage_max = 2")
	assert_str(source).contains("reach = 1.8")

# ---------- 精英怪系统 ----------

func test_enemy_has_is_elite_property() -> void:
	var source := _source("res://scenes/characters/enemies/enemy.gd")
	assert_bool(source.contains("is_elite")).is_true()

func test_enemy_applies_spawner_multipliers() -> void:
	var source := _source("res://scenes/characters/enemies/enemy.gd")
	assert_bool(source.contains("_apply_spawner_multipliers")).is_true()
	assert_bool(source.contains("hp_mult")).is_true()
	assert_bool(source.contains("speed_mult")).is_true()

func test_elite_enemy_does_not_add_visual_light() -> void:
	var source := _source("res://scenes/characters/enemies/enemy.gd")
	assert_bool(source.contains("is_elite")).is_true()
	assert_bool(source.contains("presence_light")).is_false()
	assert_bool(source.contains("Color(1.0, 0.3, 0.2)")).is_false()

# ---------- 巡逻逻辑 ----------

func test_moving_state_has_patrol_logic() -> void:
	var source := _source("res://scenes/characters/enemies/state/enemy_state_moving.gd")
	# 必须有巡逻函数
	assert_bool(source.contains("_patrol")).is_true()
	assert_bool(source.contains("_pick_new_patrol_target")).is_true()
	# 巡逻时使用 50% 速度
	assert_bool(source.contains("0.5")).is_true()

func test_moving_state_records_spawn_position() -> void:
	var source := _source("res://scenes/characters/enemies/state/enemy_state_moving.gd")
	# _enter_tree 应记录出生位置
	assert_bool(source.contains("spawn_position")).is_true()

func test_moving_state_patrol_uses_patrol_radius() -> void:
	var source := _source("res://scenes/characters/enemies/state/enemy_state_moving.gd")
	assert_bool(source.contains("patrol_radius")).is_true()

func test_enemy_has_patrol_radius_export() -> void:
	var source := _source("res://scenes/characters/enemies/enemy.gd")
	assert_bool(source.contains("patrol_radius")).is_true()

# ---------- DungeonSpawner 配置 ----------

func test_spawner_does_not_expose_unaccepted_weak_monster_prefabs() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	assert_object(spawner._get_enemy_prefab("rat")).is_null()
	assert_object(spawner._get_enemy_prefab("slime")).is_null()

func test_spawner_has_elite_prefix_logic() -> void:
	var source := _source("res://globals/dungeon/dungeon_spawner.gd")
	assert_bool(source.contains("elite_")).is_true()
	assert_bool(source.contains("trim_prefix")).is_true()
	assert_bool(source.contains("ELITE_HP_MULT")).is_true()
	assert_bool(source.contains("ELITE_SPEED_MULT")).is_true()
	assert_bool(source.contains("ELITE_DMG_MULT")).is_true()

func test_zone_configs_have_normal_monsters() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	var cfg: Dictionary = spawner.get_zone_config(0)
	assert_array(cfg.types.keys()).contains_exactly(["goblin", "orc_raider"])

func test_zone_configs_have_goblin() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	var found_goblin := false
	var found_orc := false
	for zone in range(6):
		var cfg: Dictionary = spawner.get_zone_config(zone)
		if cfg.types.has("goblin"):
			found_goblin = true
		if cfg.types.has("orc_raider"):
			found_orc = true
	assert_bool(found_goblin).is_true()
	assert_bool(found_orc).is_true()

func test_spawner_sets_is_elite_on_enemy() -> void:
	var source := _source("res://globals/dungeon/dungeon_spawner.gd")
	# 精英怪应设置 is_elite = true
	assert_bool(source.contains('enemy.set("is_elite", true)')).is_true()

func test_spawner_marks_enemy_rank_and_body_size() -> void:
	var ds: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	assert_str(ds.get_body_size("rat")).is_empty()
	assert_str(ds.get_body_size("elite_goblin")).is_equal("medium")
	assert_str(ds.get_body_size("troll")).is_empty()
	assert_str(ds.get_body_size("dragon")).is_equal("huge")
	assert_bool(ds.is_boss_type("elite_dragon")).is_true()
	assert_bool(ds.is_boss_type("elite_rock_golem")).is_true()
	assert_bool(ds.is_boss_type("elite_necrolord")).is_false()
	assert_bool(ds.is_boss_type("troll")).is_false()
	assert_bool(ds.is_boss_type("elite_troll")).is_false()

func test_physical_impact_resolver_has_boss_and_body_size_profile() -> void:
	var source := _source("res://globals/combat/physical_impact_resolver.gd")
	assert_bool(source.contains("is_boss_type")).is_true()
	assert_bool(source.contains("body_size")).is_true()
	assert_bool(source.contains("get_target_profile")).is_true()
	assert_bool(source.contains("impact_damage_taken_mult")).is_true()
	assert_bool(source.contains("impact_min_speed_add")).is_true()

func test_spawner_min_count_increased() -> void:
	var source := _source("res://globals/dungeon/dungeon_spawner.gd")
	# 最少 4 只（从 3 提升到 4）
	assert_bool(source.contains("clampi(count, 4, 16)")).is_true()

# ---------- 死亡掉落 ----------

func test_dying_state_drops_rat_material() -> void:
	var source := _source("res://scenes/characters/enemies/state/enemy_state_dying.gd")
	assert_bool(source.contains("giant_rat_tail")).is_true()

func test_dying_state_drops_slime_material() -> void:
	var source := _source("res://scenes/characters/enemies/state/enemy_state_dying.gd")
	assert_bool(source.contains("slime_jelly")).is_true()

func test_dying_state_has_elite_bonus_drop() -> void:
	var source := _source("res://scenes/characters/enemies/state/enemy_state_dying.gd")
	assert_bool(source.contains("_spawn_elite_bonus_drop")).is_true()
	assert_bool(source.contains("is_elite")).is_true()
	assert_bool(source.contains("rune_id")).is_true()
	assert_bool(source.contains("roll_rune")).is_true()
	assert_bool(source.contains("is_boss_type")).is_true()

func test_dying_state_guards_missing_ragdoll_nodes() -> void:
	var source := _source("res://scenes/characters/enemies/state/enemy_state_dying.gd")
	assert_bool(source.contains("func _blood_transform")) \
		.override_failure_message("死亡状态应在缺失头部骨骼时回退到 enemy.global_transform").is_true()
	assert_bool(source.contains("enemy.skeleton_simulator != null")) \
		.override_failure_message("死亡状态启动 ragdoll 前应检查 skeleton_simulator 非空").is_true()
	assert_bool(source.contains("enemy.physical_bone_torso != null and state_data != null")) \
		.override_failure_message("死亡状态施加冲量前应检查躯干骨骼和 state_data 非空").is_true()

func test_dead_state_guards_missing_ragdoll_nodes() -> void:
	var source := _source("res://scenes/characters/enemies/state/enemy_state_dead.gd")
	assert_bool(source.contains("enemy.skeleton_simulator != null")) \
		.override_failure_message("死亡状态应先判 skeleton_simulator 非空再休眠物理骨骼").is_true()
	assert_bool(source.contains("enemy.voxel_ragdoll != null")) \
		.override_failure_message("死亡状态对体素敌人应走 voxel_ragdoll 冻结分支，而非对 null 调 get_children()").is_true()

func test_dying_state_uses_ragdoll_not_death_animation() -> void:
	# 死亡时应直接启用布娃娃，不播放 death 动画
	var source := _source("res://scenes/characters/enemies/state/enemy_state_dying.gd")
	# 不应有播放 death 动画的代码
	assert_bool(source.contains('ap.play("death"')).is_false() \
		.override_failure_message("死亡状态不应播放 death 动画，应直接启用布娃娃")
	# 不应有 has_animation("death") 的判断
	assert_bool(source.contains('has_animation("death")')).is_false() \
		.override_failure_message("死亡状态不应检查 death 动画是否存在")
	# 应始终启用 skeleton_simulator
	assert_bool(source.contains("physical_bones_start_simulation")).is_true() \
		.override_failure_message("死亡状态应始终启用布娃娃物理模拟")
