# SaveGameAdapter - 存档版本迁移与兼容性适配器
# 职责：在载入存档数据的第一时间，对字典进行字段级清洗与迁移，升级至当前最新数据结构。
class_name SaveGameAdapter
extends RefCounted

## 将传入的 save_data 字典原地（或返回新字典）升级。
## 修复旧字段，对老旧存档进行结构重映射。
static func adapt(save_data: Dictionary) -> Dictionary:
	var result := save_data.duplicate(true)
	
	# 如果没有 version 字段，或者是旧版
	var version: int = int(result.get("version", 0))
	
	if version < 1:
		var tm_data: Dictionary = result.get("tavern_manager", {}).duplicate()
		var gs_data: Dictionary = result.get("game_state", {}).duplicate()
		
		# 1. 迁移材料 (TavernManager.inventory -> GameState.expedition_inventory.materials)
		if tm_data.has("inventory") and tm_data["inventory"] is Dictionary:
			var old_inv: Dictionary = tm_data["inventory"]
			if not gs_data.has("expedition_inventory"):
				gs_data["expedition_inventory"] = {}
			var exp_inv: Dictionary = gs_data["expedition_inventory"]
			if not exp_inv.has("materials"):
				exp_inv["materials"] = {}
			for k in old_inv.keys():
				exp_inv["materials"][k] = int(old_inv[k])
			tm_data.erase("inventory")
			
		# 2. 迁移符文 (TavernManager.runes_inventory -> GameState.expedition_inventory.runes)
		if tm_data.has("runes_inventory") and tm_data["runes_inventory"] is Dictionary:
			var old_runes: Dictionary = tm_data["runes_inventory"]
			if not gs_data.has("expedition_inventory"):
				gs_data["expedition_inventory"] = {}
			var exp_inv: Dictionary = gs_data["expedition_inventory"]
			if not exp_inv.has("runes"):
				exp_inv["runes"] = {}
			for k in old_runes.keys():
				exp_inv["runes"][k] = int(old_runes[k])
			tm_data.erase("runes_inventory")
			
		# 3. 金币字段同步
		if tm_data.has("gold") and not result.has("gold"):
			result["gold"] = int(tm_data["gold"])
			
		# 写回子字典
		result["tavern_manager"] = tm_data
		result["game_state"] = gs_data
		
		# 升级版本
		result["version"] = 1
		
	return result
