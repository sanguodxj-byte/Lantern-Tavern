class_name PlayerStateSlashing
extends PlayerState

const TIME_EMIT_DAMAGE := 200
const WEAPON_CONDITION_WEAR := 2  # 武器耐久损耗（每次命中）
# 命中后累积的主属性经验与武器熟练度
const ATTR_EXP_PER_HIT := 5
const PROFICIENCY_PER_HIT := 1

const CB := preload("res://globals/combat_bridge.gd")
const ME := preload("res://globals/milestone_effects.gd")

var has_emitted_damage := false
var time_start_slash := Time.get_ticks_msec()

func _enter_tree() -> void:
	player.animation_player.play("slash")
	player.animation_player.animation_finished.connect(on_animation_finished)

func _process(_delta: float) -> void:
	var time_elapsed := Time.get_ticks_msec() - time_start_slash
	if not has_emitted_damage and time_elapsed > TIME_EMIT_DAMAGE:
		has_emitted_damage = true
		if player.weapon_reach_raycast.is_colliding():
			var collider := player.weapon_reach_raycast.get_collider() as Node
			var enemy := collider as Enemy
			if enemy != null:
				# ARPG 战斗结算：通过 CombatBridge 调用 CombatEngine.resolve_attack
				var weapon = player.equipment.weapon_data if player.equipment.has_weapon() else null
				var attrs := _get_player_attrs()
				var level := _get_player_level()
				var main_type := "one_hand_melee" if player.equipment.has_weapon() else ""
				var off_type := "shield" if player.equipment.has_shield() else ""
				# 朝向判定背袭/侧击
				var atk_forward := -player.global_transform.basis.z.normalized()
				var def_forward := -enemy.global_transform.basis.z.normalized()
				var is_back := CB.is_backstab(atk_forward, def_forward)
				# 直觉闪避（PER T3）：取消背袭/侧击加成（攻方视角：不再享受背袭伤害倍率）
				if ME.negate_flank_bonus():
					is_back = false
				var result = CB.resolve_player_attack(player, enemy, weapon, main_type, off_type, attrs, level, is_back)
				if result.hit:
					player.equipment.apply_weapon_damage(WEAPON_CONDITION_WEAR)
					# 里程碑被动：震退（STR T1）命中 15% 概率追加击退
					var is_melee: bool = result.attack_type == "melee" if "attack_type" in result else true
					var extra_kb := ME.try_knockback_chance(is_melee)
					if extra_kb > 0.0:
						result.knockback_force += extra_kb
						result.knockback_impulse += atk_forward * extra_kb
					# 里程碑被动：重力击（STR T2）近战伤害 +5%
					result.final_damage = ME.apply_heavy_stride(result.final_damage, is_melee)
					enemy.try_receive_hit_result(player, result)
					# 累积双轨经验：主属性 + 武器熟练度
					_accumulate_combat_exp(main_type, attrs)
				else:
					AudioManager.play("slash-miss", player.action_audio_stream_player)
			elif collider != null and collider.has_method("try_receive_hit"):
				player.equipment.apply_weapon_damage(WEAPON_CONDITION_WEAR)
				collider.try_receive_hit(player, 1)
			else:
				AudioManager.play("slash", player.action_audio_stream_player)
		else:
			AudioManager.play("slash", player.action_audio_stream_player)

func _physics_process(delta: float) -> void:
	player.process_movement(delta)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)

## 从 AttrPanel autoload 读取玩家 6 属性
func _get_player_attrs() -> Dictionary:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		return ap.get_player_attrs()
	# fallback：autoload 未注册时用默认值
	return {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}

## 从 AttrPanel autoload 读取玩家等级
func _get_player_level() -> int:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		return ap.get_level()
	return 1

## 命中后累积主属性经验 + 武器熟练度
func _accumulate_combat_exp(weapon_type: String, attrs: Dictionary) -> void:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap == null:
		return
	# 近战主累积力量，远程主累积敏捷，法术主累积魔力
	match weapon_type:
		"one_hand_melee", "two_hand":
			ap.accumulate_attr("str", ATTR_EXP_PER_HIT)
		"longbow", "crossbow":
			ap.accumulate_attr("dex", ATTR_EXP_PER_HIT)
		"wand", "grimoire":
			ap.accumulate_attr("mag", ATTR_EXP_PER_HIT)
		"":
			ap.accumulate_attr("str", ATTR_EXP_PER_HIT)  # 徒手主累积力量
	# 武器熟练度累积
	var prof_key := weapon_type if weapon_type != "" else "unarmed"
	ap.accumulate_proficiency(prof_key, PROFICIENCY_PER_HIT)
	# 检查技能领悟
	ap.check_skill_unlocks()
