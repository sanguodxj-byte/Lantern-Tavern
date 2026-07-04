extends Control
## 技能快捷栏 UI（2 主动槽 F/G + 5 被动槽）。
## 显示已绑定技能图标、CD 径向扇形遮罩、剩余秒数、媒介不匹配置灰。
## 由 SkillRuntime autoload 驱动，每帧刷新；图标来自 SkillIcons autoload。

const SR := preload("res://globals/skill_runtime.gd")
const SD := preload("res://globals/skill_data.gd")
const AS := preload("res://globals/action_skills.gd")

@onready var slot_f_name: Label = $ActiveRow/SlotF/SkillName
@onready var slot_f_icon: TextureRect = $ActiveRow/SlotF/Icon
@onready var slot_f_cd_overlay: Control = $ActiveRow/SlotF/CDOverlay
@onready var slot_f_cd_label: Label = $ActiveRow/SlotF/CDLabel
@onready var slot_g_name: Label = $ActiveRow/SlotG/SkillName
@onready var slot_g_icon: TextureRect = $ActiveRow/SlotG/Icon
@onready var slot_g_cd_overlay: Control = $ActiveRow/SlotG/CDOverlay
@onready var slot_g_cd_label: Label = $ActiveRow/SlotG/CDLabel
@onready var passive_labels: Array = [
	$PassiveRow/P1, $PassiveRow/P2, $PassiveRow/P3, $PassiveRow/P4, $PassiveRow/P5,
]

func _process(_delta: float) -> void:
	_refresh()

## 全量刷新槽位显示
func _refresh() -> void:
	_refresh_active_slot(SR.SLOT_F_ACTION, slot_f_name, slot_f_icon, slot_f_cd_overlay, slot_f_cd_label)
	_refresh_active_slot(SR.SLOT_G_WEAPON, slot_g_name, slot_g_icon, slot_g_cd_overlay, slot_g_cd_label)
	_refresh_passive_slots()

## 刷新主动槽：图标 + CD 扇形遮罩 + 剩余秒数 + 媒介置灰
func _refresh_active_slot(slot_index: int, name_label: Label, icon_rect: TextureRect, cd_overlay: Control, cd_label: Label) -> void:
	var sr: Node = _get_skill_runtime()
	var icons: Node = _get_skill_icons()
	if sr == null or icons == null:
		name_label.text = "-"
		icon_rect.texture = null
		cd_label.text = ""
		cd_overlay.queue_redraw()
		return
	var skill_id: String = sr.get_slot_skill(slot_index)
	if skill_id == "":
		name_label.text = "-"
		icon_rect.texture = null
		cd_label.text = ""
		cd_overlay.queue_redraw()
		return
	# 技能名 + 图标
	name_label.text = skill_id
	icon_rect.texture = icons.get_icon(skill_id)
	# CD 进度（0=刚释放/冷却中, 1=就绪）
	var progress: float = sr.get_cooldown_progress(skill_id)
	cd_overlay.progress = progress
	cd_overlay.queue_redraw()
	# CD 剩余秒数显示
	var remain: float = sr.get_cooldown_remain(skill_id)
	if remain > 0.0:
		cd_label.text = "%.1f" % remain
	else:
		cd_label.text = ""
	# 媒介置灰（仅 G 槽，F 槽无媒介限制）
	var main_hand := _get_main_hand_type()
	var off_hand := _get_off_hand_type()
	var matched: bool = sr.is_slot_medium_matched(slot_index, main_hand, off_hand)
	icon_rect.modulate = Color(1, 1, 1, 1.0) if matched else Color(1, 1, 1, 0.35)

## 刷新被动槽
func _refresh_passive_slots() -> void:
	var sr: Node = _get_skill_runtime()
	var icons: Node = _get_skill_icons()
	if sr == null:
		return
	for i in range(5):
		var slot_idx: int = SR.SLOT_PASSIVE_1 + i
		var skill_id: String = sr.get_slot_skill(slot_idx)
		passive_labels[i].text = skill_id if skill_id != "" else "-"
		passive_labels[i].modulate = Color(0.8, 0.8, 1.0) if skill_id != "" else Color(0.4, 0.4, 0.4)

## 获取玩家当前主手武器类型（集成期默认 one_hand_melee）
func _get_main_hand_type() -> String:
	return "one_hand_melee"

func _get_off_hand_type() -> String:
	return ""

func _get_skill_runtime() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("SkillRuntime")

func _get_skill_icons() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("SkillIcons")
