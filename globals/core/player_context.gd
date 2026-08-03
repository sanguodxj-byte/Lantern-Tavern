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
## P0（2218 审查）：per-peer 权威战斗状态（PlayerCombatState）——
## 远端 avatar 无 health/buffs 组件时，生命/护盾/buff 的权威真值写这里；
## 房主真实 Player 有组件时经 SessionRoot 端口同步到节点（表现层一致）。
## 字段：current_life/max_life、shield（吸收后续伤害）、buffs{id:expiry_ms}。
var current_life: int = 100
var max_life: int = 100
var shield: int = 0
## buff_id -> 过期时刻（毫秒，用 Time.get_ticks_msec 绝对值）。0 表示未过期由外部推进。
var buffs: Dictionary = {}
## 治疗统计（保留兼容键：healed_total 累计治疗量）。
var spell_effect_state: Dictionary = {}

## P0（2218 审查）：应用一次自目标法术效果（真实战斗语义）：
##   heal → 提升当前生命（封顶 max_life）；barrier → 累加吸收盾；buff → 登记带过期时间的增益。
func record_spell_effect(effect_type: String, amount: int, duration: float) -> void:
	match effect_type:
		"heal":
			current_life = mini(max_life, current_life + amount)
			spell_effect_state["healed_total"] = int(spell_effect_state.get("healed_total", 0)) + amount
			spell_effect_state["last_effects"] = {"type": "heal", "amount": amount}
		"barrier":
			shield += maxi(amount, 0)
			spell_effect_state["last_effects"] = {"type": "barrier", "absorb": amount, "duration": duration}
		"buff":
			var expiry: int = Time.get_ticks_msec() + roundi(duration * 1000.0)
			var existing: int = int(buffs.get("spell_power", 0))
			buffs["spell_power"] = maxi(existing, expiry)
			spell_effect_state["last_effects"] = {"type": "buff", "duration": duration}
	spell_effect_state["updated_at"] = Time.get_ticks_msec()

## P0（2218 审查）：对玩家施加权威伤害——先扣吸收盾再扣生命。返回实际损失生命。
## 供敌方/环境伤害接入（阶段 B 敌人 AI 完成后调用）；法术 buff 倍率读取同一状态。
func apply_damage(damage: int) -> int:
	if damage <= 0:
		return 0
	var remaining := damage
	var shield_used := mini(shield, remaining)
	shield -= shield_used
	remaining -= shield_used
	var life_lost := mini(current_life, remaining)
	current_life -= life_lost
	return life_lost

## 当前是否存活。
func is_alive() -> bool:
	return current_life > 0

## 推进 buff 过期（联机会话 tick 调用）。返回被清除的 buff id 列表。
func expire_buffs(now_ms: int) -> Array:
	var expired: Array = []
	for buff_id in buffs.keys():
		var expiry: int = int(buffs[buff_id])
		if expiry > 0 and now_ms >= expiry:
			buffs.erase(buff_id)
			expired.append(buff_id)
	return expired

## 查询法术伤害倍率（spell_power buff 生效时 +20%）。联机权威法术结算读取。
func spell_power_mult() -> float:
	if buffs.has("spell_power"):
		return 1.0 + 0.2
	return 1.0

func serialize_spell_state() -> Dictionary:
	return {
		"spell_loadout": spell_loadout.serialize(), "spell_mana": spell_mana, "spell_max_mana": spell_max_mana,
		"spell_runtime": spell_runtime.serialize(),
		# P0（2218 审查）：权威战斗状态随快照/存档序列化——重连/结算不丢生命/护盾/buff。
		"combat_state": {"current_life": current_life, "max_life": max_life, "shield": shield, "buffs": buffs.duplicate()},
	}

func deserialize_spell_state(data: Dictionary) -> void:
	spell_max_mana = maxi(1, int(data.get("spell_max_mana", spell_max_mana)))
	spell_mana = clampi(int(data.get("spell_mana", spell_max_mana)), 0, spell_max_mana)
	if data.has("spell_loadout"): spell_loadout.deserialize(Dictionary(data.spell_loadout))
	if data.has("spell_runtime"): spell_runtime.deserialize(Dictionary(data.spell_runtime))
	if data.has("combat_state") and data["combat_state"] is Dictionary:
		var cs: Dictionary = data["combat_state"]
		max_life = maxi(1, int(cs.get("max_life", max_life)))
		current_life = clampi(int(cs.get("current_life", current_life)), 0, max_life)
		shield = maxi(0, int(cs.get("shield", 0)))
		if cs.has("buffs") and cs["buffs"] is Dictionary:
			buffs = (cs["buffs"] as Dictionary).duplicate()

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
