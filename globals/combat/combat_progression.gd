class_name CombatProgression
extends RefCounted

## 战斗双轨成长结算（docs/05-战斗系统.md §5.1）。
## 只接受已经通过受击方状态机确认的有效最终伤害，避免空挥、闪避和完全格挡发奖。

const Service := preload("res://globals/core/service.gd")

const ATTACK_ATTRIBUTE := {
	"melee": "str",
	"ranged": "dex",
	"spell": "mag",
}


## 最终有效伤害同时转化为武器类别熟练度与对应主属性经验。
static func award_damage(attributes: Object, proficiency_key: String, attack_type: String, final_damage: int) -> int:
	var key := proficiency_key.strip_edges()
	var attr_key := String(ATTACK_ATTRIBUTE.get(attack_type, ""))
	if attributes == null or key.is_empty() or attr_key.is_empty() or final_damage <= 0:
		return 0
	if not attributes.has_method("accumulate_proficiency") or not attributes.has_method("accumulate_attr"):
		return 0
	attributes.accumulate_proficiency(key, final_damage)
	attributes.accumulate_attr(attr_key, final_damage)
	if attributes.has_method("check_skill_unlocks"):
		attributes.check_skill_unlocks()
	return final_damage


## 盾牌架势仅把成功减免的物理伤害转化为 shield 熟练度与 CON 经验。
static func award_shield_block(attributes: Object, attack_type: String, prevented_damage: int) -> int:
	if attack_type != "melee" and attack_type != "ranged":
		return 0
	if attributes == null or prevented_damage <= 0:
		return 0
	if not attributes.has_method("accumulate_proficiency") or not attributes.has_method("accumulate_attr"):
		return 0
	attributes.accumulate_proficiency("shield", prevented_damage)
	attributes.accumulate_attr("con", prevented_damage)
	if attributes.has_method("check_skill_unlocks"):
		attributes.check_skill_unlocks()
	return prevented_damage


## 运行时入口：现阶段只允许本机 current_player 写入其 PlayerContext。
static func award_player_damage(source_player: Node, proficiency_key: String, attack_type: String, final_damage: int) -> int:
	var attributes := _get_local_player_attributes(source_player)
	return award_damage(attributes, proficiency_key, attack_type, final_damage)


static func award_player_shield_block(player: Node, attack_type: String, prevented_damage: int) -> int:
	var attributes := _get_local_player_attributes(player)
	return award_shield_block(attributes, attack_type, prevented_damage)


static func _get_local_player_attributes(player: Node) -> Object:
	if player == null or not is_instance_valid(player):
		return null
	var game_state := Service.game_state()
	if game_state == null or game_state.current_player != player:
		return null
	var context = game_state.player_context() if game_state.has_method("player_context") else null
	return context.attributes if context != null else Service.attr_panel()
