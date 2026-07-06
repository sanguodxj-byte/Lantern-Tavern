class_name EquipmentPanelCombatStats
## 装备面板战斗数值计算工具（从 tavern_equipment_panel.gd 提取）
## 负责预览战斗属性（命中率、暴击率、伤害骰等）的计算逻辑
extends RefCounted

const CB := preload("res://globals/combat/combat_bridge.gd")
const CE := preload("res://globals/combat/combat_engine.gd")

static func build_stat_lines(player: Player, eq: EquipmentComponent, ap: Node) -> Array[String]:
	var lines: Array[String] = []
	var attrs := _combat_attrs(ap)
	var level := int(ap.get_level()) if ap != null and ap.has_method("get_level") else 1
	var weapon := eq.weapon_data if eq != null and "weapon_data" in eq else null
	var main_type := CB.get_weapon_class(weapon)
	var off_type := "shield" if eq != null and eq.has_shield() else ""
	var attack = CB.build_player_attack(player, weapon, main_type, off_type, attrs, level)
	var defender = CB.build_player_defender_from_equipment(player, attrs, eq != null and eq.has_shield())
	var style_meta: Dictionary = CE.STYLE_META.get(attack.style, {})
	var style_name := String(style_meta.get("name", "未知风格"))
	var dice := "%dd%d" % [int(attack.weapon_damage_dice.get("count", 1)), int(attack.weapon_damage_dice.get("sides", 4))]
	var base_flat := float(attack.weapon_damage_flat)
	var crit_rate := maxf(0.0, 5.0 + attack.attacker_per * 0.5 - defender.per * 0.5 + attack.crit_bonus)
	var attack_interval := CE.compute_attack_interval(attack.style, attack.attacker_dex)
	var move_speed := CE.compute_move_speed(attack.style, attack.attacker_agi)
	if eq != null:
		move_speed *= eq.get_armor_move_speed_mult()
	if ap != null and ap.has_method("compute_move_speed_mult"):
		move_speed *= ap.compute_move_speed_mult()
	if player != null and player.has_method("get_combat_speed_multiplier"):
		move_speed *= player.get_combat_speed_multiplier()
	lines.append("战斗风格 %s  类型 %s" % [style_name, attack.attack_type])
	lines.append("伤害骰 %s %+0.1f  倍率 %.2f" % [dice, base_flat, attack.weapon_damage_mult])
	lines.append("命中修正 %+0.1f%%  暴击率 %.0f%%  暴伤 %+0.2f" % [attack.weapon_hit_bonus, crit_rate, attack.crit_damage_bonus])
	lines.append("穿甲 %.0f%%  击退 %.1fm/s  眩晕 %.1fs" % [attack.ignore_def_percent, attack.knockback_force, attack.bonus_stun_duration])
	lines.append("物防 %d  防具防御 %d" % [defender.armor_def + defender.con, defender.armor_def])
	if defender.has_shield:
		lines.append("持盾  动作格挡（0.3s完美窗口免耐久）")
	elif player != null and player.has_method("is_active_weapon_two_handed") and player.is_active_weapon_two_handed():
		lines.append("双手武器  精确格挡（0.3s窗口）")
	lines.append("攻击间隔 %.2fs  移动速度 %.2fm/s" % [attack_interval, move_speed])
	return lines

static func _combat_attrs(ap: Node) -> Dictionary:
	if ap != null and ap.has_method("get_player_attrs"):
		return ap.get_player_attrs()
	return {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
