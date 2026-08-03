class_name ProgressionAuthority
extends RefCounted

## 服务器权威成长结算（ProgressionAuthority，架构审查 P1-4）。
##
## 背景：单机击杀经验只结算给 GameState.current_player（enemy.gd），联机击杀链
## （SessionRoot._on_entity_killed）只产掉落、不给 killer 加经验；LevelUpPanel 直接
## 修改本地 AttrPanel/GameState——升级选择没有权威闭环，客户端可任意提升属性。
##
## 本类把「击杀归属 → 角色经验 → 待升级队列 → 符文候选」全部收口为服务器权威逻辑：
##   * 经验写入 per-peer PlayerContext.attributes（AttrPanel 实例，服务器权威）；
##   * 客户端面板只发送选择意图（CMD_LEVEL_UP_CHOICE），服务器校验后应用；
##   * 符文候选由服务器确定性掷出（按 player_guid 种子，重连可回放）。
## 单机路径行为不变（本地 AttrPanel/GameState）。
##
## 纯 RefCounted、无场景树依赖，全部方法可单测。

## 击杀经验奖励：与单机 Enemy.get_experience_reward 同语义——
## 基础 max(10, max_life×2)，精英 ×1.5，Boss ×3。
static func compute_kill_reward(max_life: int, is_elite: bool = false, is_boss: bool = false) -> int:
	var reward := maxi(10, maxi(max_life, 1) * 2)
	if is_boss:
		reward = int(ceil(float(reward) * 3.0))
	elif is_elite:
		reward = int(ceil(float(reward) * 1.5))
	return reward

## 授予击杀经验到 per-peer 属性上下文。返回提升的等级数（0=未升级）。
static func award_kill_experience(attributes: Object, reward: int) -> int:
	if attributes == null or not attributes.has_method("accumulate_level_exp") or reward <= 0:
		return 0
	return int(attributes.accumulate_level_exp(reward))

## 客户端升级选择意图的服务器权威应用。
## intent: {"kind":"attribute","attr_key":"str"} 或 {"kind":"rune","rune_id":"..."}。
## inventory: ExpeditionInventory（符文发放目标，可为 null——属性分支不需要）。
## 返回 {"ok":bool, "error_code":String}；失败不消耗任何升级机会。
static func apply_level_up_choice(attributes: Object, inventory: Object, intent: Dictionary) -> Dictionary:
	if attributes == null:
		return {"ok": false, "error_code": "INVALID_STATE"}
	var kind := String(intent.get("kind", ""))
	match kind:
		"attribute":
			var attr_key := String(intent.get("attr_key", ""))
			if not attributes.choose_level_up_attribute(attr_key):
				return {"ok": false, "error_code": "INVALID_TARGET"}
			return {"ok": true, "error_code": ""}
		"rune":
			var rune_id := String(intent.get("rune_id", ""))
			if inventory == null or not inventory.has_method("add_rune"):
				return {"ok": false, "error_code": "INVALID_STATE"}
			var grant := func(id: String, amount: int) -> bool:
				return inventory.add_rune(id, amount)
			if not attributes.choose_level_up_rune(rune_id, grant):
				return {"ok": false, "error_code": "INVALID_TARGET"}
			return {"ok": true, "error_code": ""}
		_:
			return {"ok": false, "error_code": "INVALID_TARGET"}

## 服务器权威符文候选：确定性种子（player_guid.hash()），重连/回放产出同一组。
## 未进入符文分支（pending_level_choices<=0）返回空。
static func roll_rune_candidates(attributes: Object, player_guid: String) -> Array:
	if attributes == null or not attributes.has_method("begin_level_up_rune_choice"):
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(player_guid.hash()) & 0x7FFFFFFF
	return attributes.begin_level_up_rune_choice(rng)
