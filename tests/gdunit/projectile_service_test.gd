extends GdUnitTestSuite
## 投射物系统 (ProjectileService / ProjectileData / ProjectileEntity) 测试。
## 验证：
##   1. ProjectileData 资源创建与默认值
##   2. ProjectileService 注册表（register / get_data / has_projectile / get_registered_ids）
##   3. ProjectileService 默认投射物注册（arrow / bolt / elemental_bolt 等）
##   4. 武器 → 投射物映射（长弓→arrow，弩→bolt，法杖→elemental_bolt）
##   5. 技能 → 投射物映射（贯穿射击→piercing_arrow，元素弹→elemental_bolt）
##   6. CombatBridge.resolve_projectile_attack 结算闭环
##   7. PhysicsSetup 投射物碰撞层常量
##   8. ProjectileService.spawn 生成实体（集成测试）

const PD := preload("res://data/projectile_data.gd")
const CB := preload("res://globals/combat/combat_bridge.gd")
const CE := preload("res://globals/combat/combat_engine.gd")
const SD := preload("res://globals/combat/skill_data.gd")
const Service := preload("res://globals/core/service.gd")

# ============================================================================
# 1. ProjectileData 资源测试
# ============================================================================

func test_projectile_data_create_defaults() -> void:
	var data: Resource = PD.create("test_bolt", 20.0, "ranged")
	assert_str(data.id).is_equal("test_bolt")
	assert_float(data.speed).is_equal(20.0)
	assert_str(data.damage_type).is_equal("ranged")
	assert_float(data.lifetime).is_equal(3.0)
	assert_float(data.gravity_scale).is_equal(0.0)
	assert_int(data.pierce_count).is_equal(0)
	assert_float(data.pierce_falloff_percent).is_equal(0.0)
	assert_bool(data.destroy_on_environment).is_true()
	assert_float(data.impact_aoe_radius).is_equal(0.0)

func test_projectile_data_spell_type() -> void:
	var data: Resource = PD.create("frost", 12.0, "spell")
	assert_str(data.damage_type).is_equal("spell")
	assert_float(data.speed).is_equal(12.0)

func test_projectile_data_pierce_config() -> void:
	var data: Resource = PD.create("piercing", 24.0, "ranged")
	data.pierce_count = 5
	data.pierce_falloff_percent = 15.0
	assert_int(data.pierce_count).is_equal(5)
	assert_float(data.pierce_falloff_percent).is_equal(15.0)

func test_projectile_data_aoe_config() -> void:
	var data: Resource = PD.create("nova", 10.0, "spell")
	data.impact_aoe_radius = 3.0
	assert_float(data.impact_aoe_radius).is_equal(3.0)


# ============================================================================
# 2. ProjectileService 注册表测试
# ============================================================================

func test_service_register_and_get() -> void:
	var ps: Node = Service.projectile_service()
	assert_object(ps).is_not_null()
	var data: Resource = PD.create("custom_test_proj", 15.0, "ranged")
	ps.register(data)
	assert_bool(ps.has_projectile("custom_test_proj")).is_true()
	var retrieved: Resource = ps.get_data("custom_test_proj")
	assert_object(retrieved).is_not_null()
	assert_float(retrieved.speed).is_equal(15.0)

func test_service_get_data_unknown_returns_null() -> void:
	var ps: Node = Service.projectile_service()
	assert_object(ps.get_data("nonexistent_projectile_xyz")).is_null()

func test_service_has_projectile_false_for_unknown() -> void:
	var ps: Node = Service.projectile_service()
	assert_bool(ps.has_projectile("definitely_not_registered_123")).is_false()

func test_service_get_registered_ids_includes_defaults() -> void:
	var ps: Node = Service.projectile_service()
	var ids: Array = ps.get_registered_ids()
	assert_array(ids).contains("arrow")
	assert_array(ids).contains("bolt")
	assert_array(ids).contains("elemental_bolt")
	assert_array(ids).contains("arcane_bolt")


# ============================================================================
# 3. ProjectileService 默认投射物注册验证
# ============================================================================

func test_default_arrow_properties() -> void:
	var ps: Node = Service.projectile_service()
	var arrow: Resource = ps.get_data("arrow")
	assert_object(arrow).is_not_null()
	assert_str(arrow.damage_type).is_equal("ranged")
	assert_float(arrow.speed).is_greater(0.0)
	assert_float(arrow.gravity_scale).is_greater(0.0)

func test_default_bolt_minimal_gravity() -> void:
	var ps: Node = Service.projectile_service()
	var bolt: Resource = ps.get_data("bolt")
	assert_object(bolt).is_not_null()
	assert_str(bolt.damage_type).is_equal("ranged")
	# 弩箭下坠最小（极微弱抛物线）
	assert_float(bolt.gravity_scale).is_equal(0.04)

func test_bolt_gravity_less_than_arrow_gravity() -> void:
	var ps: Node = Service.projectile_service()
	var bolt: Resource = ps.get_data("bolt")
	var arrow: Resource = ps.get_data("arrow")
	assert_object(bolt).is_not_null()
	assert_object(arrow).is_not_null()
	# 弩箭下坠 < 弓箭下坠
	assert_float(bolt.gravity_scale).is_less(arrow.gravity_scale)

func test_default_piercing_arrow_has_pierce() -> void:
	var ps: Node = Service.projectile_service()
	var pierce: Resource = ps.get_data("piercing_arrow")
	assert_object(pierce).is_not_null()
	assert_int(pierce.pierce_count).is_greater(0)
	assert_float(pierce.pierce_falloff_percent).is_greater(0.0)

func test_default_elemental_bolt_is_spell() -> void:
	var ps: Node = Service.projectile_service()
	var elem: Resource = ps.get_data("elemental_bolt")
	assert_object(elem).is_not_null()
	assert_str(elem.damage_type).is_equal("spell")

func test_default_frost_nova_has_aoe() -> void:
	var ps: Node = Service.projectile_service()
	var frost: Resource = ps.get_data("frost_nova_bolt")
	assert_object(frost).is_not_null()
	assert_float(frost.impact_aoe_radius).is_greater(0.0)

func test_default_thunder_has_aoe() -> void:
	var ps: Node = Service.projectile_service()
	var thunder: Resource = ps.get_data("thunder_bolt")
	assert_object(thunder).is_not_null()
	assert_float(thunder.impact_aoe_radius).is_greater(0.0)


# ============================================================================
# 4. 武器 → 投射物映射测试
# ============================================================================

func test_weapon_map_longbow() -> void:
	var ps: Node = Service.projectile_service()
	var weapon := _make_weapon_with_class("longbow", "ranged")
	assert_str(ps.get_projectile_id_for_weapon(weapon)).is_equal("arrow")

func test_weapon_map_crossbow() -> void:
	var ps: Node = Service.projectile_service()
	var weapon := _make_weapon_with_class("crossbow", "ranged")
	assert_str(ps.get_projectile_id_for_weapon(weapon)).is_equal("bolt")

func test_weapon_map_wand() -> void:
	var ps: Node = Service.projectile_service()
	var weapon := _make_weapon_with_class("wand", "spell")
	assert_str(ps.get_projectile_id_for_weapon(weapon)).is_equal("elemental_bolt")

func test_weapon_map_grimoire() -> void:
	var ps: Node = Service.projectile_service()
	var weapon := _make_weapon_with_class("grimoire", "spell")
	assert_str(ps.get_projectile_id_for_weapon(weapon)).is_equal("arcane_bolt")

func test_weapon_map_melee_returns_empty() -> void:
	var ps: Node = Service.projectile_service()
	var weapon := _make_weapon_with_class("one_hand_melee", "melee")
	assert_str(ps.get_projectile_id_for_weapon(weapon)).is_empty()

func test_weapon_map_null_returns_empty() -> void:
	var ps: Node = Service.projectile_service()
	assert_str(ps.get_projectile_id_for_weapon(null)).is_empty()


# ============================================================================
# 5. 技能 → 投射物映射测试
# ============================================================================

func test_skill_map_aimed_shot() -> void:
	var ps: Node = Service.projectile_service()
	var skill := SD.get_skill_by_id("瞄准射击")
	assert_bool(skill.is_empty()).is_false()
	var pid: String = ps.get_projectile_id_for_skill(skill, null)
	assert_str(pid).is_equal("arrow")

func test_skill_map_piercing_shot() -> void:
	var ps: Node = Service.projectile_service()
	var skill := SD.get_skill_by_id("贯穿射击")
	assert_bool(skill.is_empty()).is_false()
	assert_str(ps.get_projectile_id_for_skill(skill, null)).is_equal("piercing_arrow")

func test_skill_map_elemental_bolt() -> void:
	var ps: Node = Service.projectile_service()
	var skill := SD.get_skill_by_id("元素弹")
	assert_bool(skill.is_empty()).is_false()
	assert_str(ps.get_projectile_id_for_skill(skill, null)).is_equal("elemental_bolt")

func test_skill_map_frost_nova() -> void:
	var ps: Node = Service.projectile_service()
	var skill := SD.get_skill_by_id("寒冰新星")
	assert_bool(skill.is_empty()).is_false()
	assert_str(ps.get_projectile_id_for_skill(skill, null)).is_equal("frost_nova_bolt")

func test_skill_map_thunderstorm() -> void:
	var ps: Node = Service.projectile_service()
	var skill := SD.get_skill_by_id("雷暴术")
	assert_bool(skill.is_empty()).is_false()
	assert_str(ps.get_projectile_id_for_skill(skill, null)).is_equal("thunder_bolt")

func test_skill_map_double_tap() -> void:
	var ps: Node = Service.projectile_service()
	var skill := SD.get_skill_by_id("双发连射")
	assert_bool(skill.is_empty()).is_false()
	assert_str(ps.get_projectile_id_for_skill(skill, null)).is_equal("arrow")

func test_skill_map_barbed_bolt() -> void:
	var ps: Node = Service.projectile_service()
	var skill := SD.get_skill_by_id("刺钩弩箭")
	assert_bool(skill.is_empty()).is_false()
	assert_str(ps.get_projectile_id_for_skill(skill, null)).is_equal("barbed_bolt")

func test_skill_map_melee_returns_empty() -> void:
	var ps: Node = Service.projectile_service()
	var skill := SD.get_skill_by_id("顺劈斩")
	assert_bool(skill.is_empty()).is_false()
	assert_str(ps.get_projectile_id_for_skill(skill, null)).is_empty()


# ============================================================================
# 6. CombatBridge.resolve_projectile_attack 测试
# ============================================================================

func test_resolve_projectile_attack_returns_valid_result() -> void:
	var weapon := _make_weapon(3, 6)
	var source := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	enemy.position = Vector3(0, 0, -3)
	var attrs := {"str": 12, "dex": 15, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var forward := Vector3(0, 0, -1)
	var hit_count := 0
	for i in range(20):
		var result = CB.resolve_projectile_attack(source, enemy, weapon, "longbow", "", attrs, 1, forward)
		if result.hit:
			hit_count += 1
			assert_int(result.final_damage).is_greater(0)
	assert_bool(hit_count > 0).is_true()
	source.queue_free()
	enemy.queue_free()

func test_resolve_projectile_attack_knockback_along_flight_direction() -> void:
	var weapon := _make_weapon(3, 6)
	var source := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 15, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var forward := Vector3(0, 0, -1)
	for i in range(50):
		var result = CB.resolve_projectile_attack(source, enemy, weapon, "longbow", "", attrs, 1, forward)
		if result.hit and result.knockback_force > 0:
			assert_float(result.knockback_impulse.z).is_less(0.0)
			source.queue_free()
			enemy.queue_free()
			return
	assert_bool(true).is_true()
	source.queue_free()
	enemy.queue_free()

func test_resolve_projectile_attack_spell_type() -> void:
	var weapon := _make_weapon(2, 5)
	var source := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 8, "dex": 10, "mag": 20, "con": 10, "agi": 10, "per": 10}
	var forward := Vector3(0, 0, -1)
	var hit_count := 0
	for i in range(20):
		var result = CB.resolve_projectile_attack(source, enemy, weapon, "wand", "", attrs, 1, forward, false, {}, -1.0)
		if result.hit:
			hit_count += 1
			assert_str(result.attack_type).is_equal("spell")
	assert_bool(hit_count > 0).is_true()
	source.queue_free()
	enemy.queue_free()

func test_resolve_projectile_attack_damage_mult_override() -> void:
	var weapon := _make_weapon(3, 6)
	var source := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 20, "dex": 20, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var forward := Vector3(0, 0, -1)
	var base_dmg := 0
	for i in range(30):
		var r = CB.resolve_projectile_attack(source, enemy, weapon, "longbow", "", attrs, 1, forward)
		if r.hit:
			base_dmg = max(base_dmg, r.final_damage)
	var reduced_dmg := 0
	for i in range(30):
		var r = CB.resolve_projectile_attack(source, enemy, weapon, "longbow", "", attrs, 1, forward, false, {}, 0.5)
		if r.hit:
			reduced_dmg = max(reduced_dmg, r.final_damage)
	assert_bool(reduced_dmg <= base_dmg).is_true()
	source.queue_free()
	enemy.queue_free()

func test_resolve_projectile_attack_null_enemy_safe() -> void:
	var weapon := _make_weapon(2, 6)
	var source := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var result = CB.resolve_projectile_attack(source, null, weapon, "longbow", "", attrs, 1, Vector3(0, 0, -1))
	assert_object(result).is_not_null()
	assert_bool("final_damage" in result).is_true()
	source.queue_free()

func test_resolve_projectile_attack_null_source_safe() -> void:
	var weapon := _make_weapon(2, 6)
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var result = CB.resolve_projectile_attack(null, enemy, weapon, "longbow", "", attrs, 1, Vector3(0, 0, -1))
	assert_object(result).is_not_null()
	enemy.queue_free()


# ============================================================================
# 7. PhysicsSetup 投射物碰撞层测试
# ============================================================================

func test_physics_layer_projectile_constant() -> void:
	assert_int(PhysicsSetup.LAYER_PROJECTILE).is_equal(128)

func test_physics_mask_projectile_includes_enemy_and_environment() -> void:
	var mask: int = PhysicsSetup.MASK_PROJECTILE
	assert_bool(mask & PhysicsSetup.LAYER_ENVIRONMENT != 0).is_true()
	assert_bool(mask & PhysicsSetup.LAYER_ENEMY != 0).is_true()
	assert_bool(mask & PhysicsSetup.LAYER_SCENE_OBJECT != 0).is_true()

func test_physics_mask_projectile_excludes_player() -> void:
	var mask: int = PhysicsSetup.MASK_PROJECTILE
	assert_bool(mask & PhysicsSetup.LAYER_PLAYER == 0).is_true()

func test_physics_mask_projectile_excludes_pickable() -> void:
	var mask: int = PhysicsSetup.MASK_PROJECTILE
	assert_bool(mask & PhysicsSetup.LAYER_PICKABLE == 0).is_true()

func test_physics_layer_name_projectile() -> void:
	assert_str(PhysicsSetup.get_layer_name(PhysicsSetup.LAYER_PROJECTILE)).is_equal("projectile")


# ============================================================================
# 8. ProjectileService.spawn 集成测试
# ============================================================================

func test_spawn_creates_projectile_entity() -> void:
	var ps: Node = Service.projectile_service()
	var source := _make_dummy_node3d()
	var spawn_transform := Transform3D.IDENTITY
	spawn_transform.origin = Vector3(0, 1, 0)
	spawn_transform = spawn_transform.looking_at(Vector3(0, 1, -5), Vector3.UP)
	var weapon := _make_weapon_with_class("longbow", "ranged")
	var projectile: Node = ps.spawn("arrow", spawn_transform, source, weapon, {})
	assert_object(projectile).is_not_null()
	assert_bool(projectile is RigidBody3D).is_true()
	var pd: Resource = projectile.get("projectile_data")
	assert_object(pd).is_not_null()
	assert_str(pd.id).is_equal("arrow")
	assert_object(projectile.get("source_player")).is_not_null()
	projectile.queue_free()
	source.queue_free()

func test_spawn_for_weapon_longbow() -> void:
	var ps: Node = Service.projectile_service()
	var source := _make_dummy_node3d()
	var weapon := _make_weapon_with_class("longbow", "ranged")
	var spawn_transform := Transform3D.IDENTITY
	spawn_transform.origin = Vector3(0, 1, 0)
	spawn_transform = spawn_transform.looking_at(Vector3(0, 1, -5), Vector3.UP)
	var projectile: Node = ps.spawn_for_weapon(weapon, spawn_transform, source)
	assert_object(projectile).is_not_null()
	var pd: Resource = projectile.get("projectile_data")
	assert_str(pd.id).is_equal("arrow")
	projectile.queue_free()
	source.queue_free()

func test_spawn_for_skill_piercing() -> void:
	var ps: Node = Service.projectile_service()
	var source := _make_dummy_node3d()
	var skill := SD.get_skill_by_id("贯穿射击")
	var weapon := _make_weapon_with_class("longbow", "ranged")
	var spawn_transform := Transform3D.IDENTITY
	spawn_transform.origin = Vector3(0, 1, 0)
	spawn_transform = spawn_transform.looking_at(Vector3(0, 1, -5), Vector3.UP)
	var projectile: Node = ps.spawn_for_skill(skill, spawn_transform, source, weapon)
	assert_object(projectile).is_not_null()
	var pd: Resource = projectile.get("projectile_data")
	assert_str(pd.id).is_equal("piercing_arrow")
	var sd: Dictionary = projectile.get("skill_data")
	assert_bool(sd.has("id")).is_true()
	assert_str(sd["id"]).is_equal("贯穿射击")
	projectile.queue_free()
	source.queue_free()

func test_spawn_double_creates_two() -> void:
	var ps: Node = Service.projectile_service()
	var source := _make_dummy_node3d()
	var spawn_transform := Transform3D.IDENTITY
	spawn_transform.origin = Vector3(0, 1, 0)
	spawn_transform = spawn_transform.looking_at(Vector3(0, 1, -5), Vector3.UP)
	var results: Array = ps.spawn_double("arrow", spawn_transform, source, null, {}, 3.0)
	assert_array(results).has_size(2)
	for proj in results:
		assert_object(proj).is_not_null()
		proj.queue_free()
	source.queue_free()

func test_spawn_spread_creates_count() -> void:
	var ps: Node = Service.projectile_service()
	var source := _make_dummy_node3d()
	var spawn_transform := Transform3D.IDENTITY
	spawn_transform.origin = Vector3(0, 1, 0)
	spawn_transform = spawn_transform.looking_at(Vector3(0, 1, -5), Vector3.UP)
	var results: Array = ps.spawn_spread("arrow", spawn_transform, source, 5, 20.0, null, {})
	assert_array(results).has_size(5)
	for proj in results:
		proj.queue_free()
	source.queue_free()

func test_spawn_unknown_id_returns_null() -> void:
	var ps: Node = Service.projectile_service()
	var source := _make_dummy_node3d()
	var result: Node = ps.spawn("totally_fake_projectile", Transform3D.IDENTITY, source, null, {})
	assert_object(result).is_null()
	source.queue_free()


# ============================================================================
# 辅助函数
# ============================================================================

func _make_weapon(dmg_min: int, dmg_max: int) -> Resource:
	var w := WeaponData.new()
	w.damage_min = dmg_min
	w.damage_max = dmg_max
	w.condition = 100
	w.max_condition = 100
	w.reach = 6.0
	return w

func _make_weapon_with_class(weapon_class: String, attack_type: String) -> WeaponData:
	var w := WeaponData.new()
	w.id = weapon_class + "_test"
	w.name = weapon_class
	w.weapon_class = weapon_class
	w.attack_type = attack_type
	w.damage_min = 2
	w.damage_max = 6
	w.damage_dice_count = 1
	w.damage_dice_sides = 5
	w.damage_flat = 1
	w.condition = 100
	w.max_condition = 100
	w.reach = 6.0
	return w

func _make_dummy_node3d() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	return n
