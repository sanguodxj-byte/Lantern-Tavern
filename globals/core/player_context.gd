class_name PlayerContext
extends RefCounted

## 每玩家上下文（联机保险层）。
##
## 背景：当前项目为深度单机，玩家状态散落在两处——
##   1) GameState 的实例字段：current_player / expedition_inventory / equipment_loadout
##   2) 两个全局 autoload 单例：AttrPanel（属性/派生率）、SkillRuntime（技能状态）
## 这隐含“世界里恰好一个玩家”的假设，无法支持 per-peer 联机。
##
## 本类把“一个玩家的全部状态”聚合到一个【可实例化】句柄里。
##   - 单机（现在）：GameState 持有一个实例，经 bind_to_globals() 绑定到既有的
##     全局单例与状态对象——【不改变任何现有行为】，仅提供一个聚合句柄。
##   - 联机（未来）：每个 peer 各 new 一个 PlayerContext，用 for_peer() 传入
##     该 peer 独立的 AttrPanel / SkillRuntime / ExpeditionInventory /
##     EquipmentLoadout 实例（取消对全局单例的依赖）。
##     届时只需把全仓库对 AttrPanel / SkillRuntime 的全局调用改为
##     GameState.player_context().attributes / .skills，无需再拆散逻辑。
##
## 迁移路径见 docs/24-联机架构迁移.md。

const AttrPanelClass := preload("res://globals/combat/attr_panel.gd")
const SkillRuntimeClass := preload("res://globals/combat/skill_runtime.gd")
const ExpeditionInventoryClass := preload("res://globals/core/state/expedition_inventory.gd")
const EquipmentLoadoutClass := preload("res://globals/core/state/equipment_loadout.gd")
const SpellLoadoutClass := preload("res://globals/combat/spell_loadout.gd")
const SpellRuntimeClass := preload("res://globals/combat/spell_runtime.gd")

var player_node: Node3D = null            ## 运行时 Player 节点（可选）
var attributes: AttrPanelClass = null      ## 该玩家的属性/派生率容器
var skills: SkillRuntimeClass = null       ## 该玩家的技能状态
var inventory: ExpeditionInventoryClass = null
var loadout: EquipmentLoadoutClass = null
var spell_loadout: SpellLoadoutClass = SpellLoadoutClass.new()
var spell_runtime: SpellRuntimeClass = SpellRuntimeClass.new()
var spell_mana: int = 100
var spell_max_mana: int = 100
var player_guid: String = ""               ## 稳定身份（§14.2，不随 peer_id 变化），用于重连锚定
## P0（2124 审查）：per-peer 自目标法术效果权威状态（heal/barrier/buff）。
## 远端 avatar 没有 health/buffs 组件，权威效果写这里（而非表现组件）；
## 房主真实 Player 有组件时经 SessionRoot 端口同步到节点（表现层一致）。
## 结构：{"healed_total": int, "absorb": int, "buff_duration": float, "last_effects": Dictionary}
var spell_effect_state: Dictionary = {}

## 记录一次自目标法术效果（权威状态端口，2124 审查）。
func record_spell_effect(effect_type: String, amount: int, duration: float) -> void:
	match effect_type:
		"heal":
			spell_effect_state["healed_total"] = int(spell_effect_state.get("healed_total", 0)) + amount
			spell_effect_state["last_effects"] = {"type": "heal", "amount": amount}
		"barrier":
			spell_effect_state["absorb"] = amount
			spell_effect_state["buff_duration"] = duration
			spell_effect_state["last_effects"] = {"type": "barrier", "absorb": amount, "duration": duration}
		"buff":
			spell_effect_state["buff_duration"] = maxf(float(spell_effect_state.get("buff_duration", 0.0)), duration)
			spell_effect_state["last_effects"] = {"type": "buff", "duration": duration}
	spell_effect_state["updated_at"] = Time.get_ticks_msec()

func serialize_spell_state() -> Dictionary:
	return {"spell_loadout": spell_loadout.serialize(), "spell_mana": spell_mana, "spell_max_mana": spell_max_mana, "spell_runtime": spell_runtime.serialize()}

func deserialize_spell_state(data: Dictionary) -> void:
	spell_max_mana = maxi(1, int(data.get("spell_max_mana", spell_max_mana)))
	spell_mana = clampi(int(data.get("spell_mana", spell_max_mana)), 0, spell_max_mana)
	if data.has("spell_loadout"): spell_loadout.deserialize(Dictionary(data.spell_loadout))
	if data.has("spell_runtime"): spell_runtime.deserialize(Dictionary(data.spell_runtime))

func _init(attrs: AttrPanelClass, sk: SkillRuntimeClass, inv: ExpeditionInventoryClass, lo: EquipmentLoadoutClass, player: Node3D = null, guid: String = "") -> void:
	attributes = attrs
	skills = sk
	inventory = inv
	loadout = lo
	player_node = player
	player_guid = guid
	if player != null and player.get_node_or_null("/root/GameState") != null:
		var gs := player.get_node_or_null("/root/GameState")
		if "spell_loadout" in gs:
			spell_loadout = gs.spell_loadout
		if "mana" in player and player.mana != null:
			spell_mana = int(player.mana.current_mana)
			spell_max_mana = int(player.mana.max_mana)

## 迁移桥接（过渡期）：绑定到当前单机全局单例。行为等价于现状。
## 仅在运行时（所有 autoload 就绪后）调用，避免 autoload 初始化顺序问题。
static func bind_to_globals(player: Node3D = null) -> PlayerContext:
	return PlayerContext.new(AttrPanel, SkillRuntime, GameState.expedition_inventory, GameState.equipment_loadout, player)

## 联机工厂（未来）：传入每个 peer 各自独立、且已初始化完毕的状态实例，
## 由调用方负责实例的创建与初始化（见 docs/24）。
static func for_peer(attrs: AttrPanelClass, sk: SkillRuntimeClass, inv: ExpeditionInventoryClass, lo: EquipmentLoadoutClass, player: Node3D = null, guid: String = "") -> PlayerContext:
	return PlayerContext.new(attrs, sk, inv, lo, player, guid)
