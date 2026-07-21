extends Node

## 存档管理器（autoload: SaveManager）。
## 提供三个存档槽位，序列化保存/恢复全部游戏状态。
##
## 涵盖的子系统：
##   - TavernManager   酒馆经营状态（天数、金币、库存、酿造、教程等）
##   - GameState       角色随身状态（材料、符文、装备槽、背包容量等）
##   - AttrPanel       属性面板（6 主属性、等级、熟练度、技能、里程碑）
##   - SkillRuntime    技能运行时（槽位绑定、符文、冷却）
##   - FermentationSystem 发酵时序（酒桶状态机）
##
## 存档文件格式：JSON，存储于 user://saves/slot_{0..2}.json

# ============================================================================
# 常量
# ============================================================================

const Service := preload("res://globals/core/service.gd")

const SAVE_DIR := "user://saves/"
const SLOT_COUNT: int = 3
const SAVE_VERSION: int = 1

signal save_completed(slot_index: int)
signal load_completed(slot_index: int)
signal save_deleted(slot_index: int)

# ============================================================================
# 公共 API — 存档槽操作
# ============================================================================

## 保存当前游戏状态到指定槽位。成功返回 true。
func save_to_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		push_warning("[SaveManager] 无效的存档槽位: %d" % slot_index)
		return false
	_ensure_save_dir()
	var save_data := serialize_all()
	save_data["slot_index"] = slot_index
	var path := _slot_path(slot_index)
	var json_string := JSON.stringify(save_data, "  ")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] 无法写入存档文件: %s (错误: %s)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(json_string)
	file.close()
	save_completed.emit(slot_index)
	print("[SaveManager] 存档已保存到槽位 %d (%s)" % [slot_index, path])
	return true

## 从指定槽位加载游戏状态。成功返回 true。
func load_from_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		push_warning("[SaveManager] 无效的存档槽位: %d" % slot_index)
		return false
	var path := _slot_path(slot_index)
	if not FileAccess.file_exists(path):
		push_warning("[SaveManager] 槽位 %d 无存档文件" % slot_index)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] 无法读取存档文件: %s" % path)
		return false
	var json_string := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_error("[SaveManager] 存档文件解析失败: %s (行 %d)" % [path, json.get_error_line()])
		return false
	var raw_save_data: Dictionary = json.data
	var SaveGameAdapterClass := preload("res://globals/core/state/save_game_adapter.gd")
	var save_data := SaveGameAdapterClass.adapt(raw_save_data)
	if not save_data.has("version") or int(save_data["version"]) != SAVE_VERSION:
		push_warning("[SaveManager] 存档版本不兼容: 槽位 %d" % slot_index)
		return false
	deserialize_all(save_data)
	load_completed.emit(slot_index)
	print("[SaveManager] 存档已从槽位 %d 加载" % slot_index)
	return true

## 删除指定槽位的存档。成功返回 true。
func delete_save(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		return false
	var path := _slot_path(slot_index)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_warning("[SaveManager] 删除存档失败: %s (错误: %d)" % [path, err])
		return false
	save_deleted.emit(slot_index)
	print("[SaveManager] 槽位 %d 存档已删除" % slot_index)
	return true

## 检查指定槽位是否有存档。
func has_save(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		return false
	return FileAccess.file_exists(_slot_path(slot_index))

## 获取指定槽位的元信息（不加载完整存档）。
## 返回 { "exists", "save_name", "day", "gold", "timestamp", "player_name" }
func get_slot_info(slot_index: int) -> Dictionary:
	var empty := {
		"exists": false,
		"save_name": "",
		"day": 0,
		"gold": 0,
		"timestamp": "",
		"player_name": "",
	}
	if not _is_valid_slot(slot_index):
		return empty
	var path := _slot_path(slot_index)
	if not FileAccess.file_exists(path):
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return empty
	var json_string := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		return empty
	var raw_data: Dictionary = json.data
	var SaveGameAdapterClass := preload("res://globals/core/state/save_game_adapter.gd")
	var data := SaveGameAdapterClass.adapt(raw_data)
	return {
		"exists": true,
		"save_name": String(data.get("save_name", "")),
		"day": int(data.get("day", 0)),
		"gold": int(data.get("gold", 0)),
		"timestamp": String(data.get("timestamp", "")),
		"player_name": String(data.get("player_name", "")),
	}

## 获取所有槽位的元信息列表。
func get_all_slot_infos() -> Array:
	var infos: Array = []
	for i in range(SLOT_COUNT):
		infos.append(get_slot_info(i))
	return infos

# ============================================================================
# 序列化 — 汇总全部子系统
# ============================================================================

## 将当前游戏全部状态序列化为一个字典。
func serialize_all() -> Dictionary:
	var tm := _get_tavern_manager()
	var gs := _get_game_state()
	var ap := _get_attr_panel()
	var sr := _get_skill_runtime()
	var fs := _get_fermentation_system()
	var data := {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(false, true),
	}
	if tm != null:
		data["save_name"] = tm.save_name
		data["player_name"] = tm.player_name
		data["day"] = tm.day
		data["gold"] = tm.gold
		data["tavern_manager"] = tm.serialize()
	else:
		data["save_name"] = ""
		data["player_name"] = ""
		data["day"] = 0
		data["gold"] = 0
		data["tavern_manager"] = {}
	if gs != null:
		data["game_state"] = gs.serialize()
	else:
		data["game_state"] = {}
	if ap != null:
		data["attr_panel"] = ap.serialize()
	else:
		data["attr_panel"] = {}
	if sr != null:
		data["skill_runtime"] = sr.serialize()
	else:
		data["skill_runtime"] = {}
	if fs != null:
		data["fermentation_system"] = fs.serialize()
	else:
		data["fermentation_system"] = {}
	return data

## 从字典恢复全部游戏状态。
func deserialize_all(data: Dictionary) -> void:
	var tm := _get_tavern_manager()
	var gs := _get_game_state()
	var ap := _get_attr_panel()
	var sr := _get_skill_runtime()
	var fs := _get_fermentation_system()
	if tm != null and data.has("tavern_manager"):
		tm.deserialize(data["tavern_manager"])
	if gs != null and data.has("game_state"):
		gs.deserialize(data["game_state"])
		# 加载后如果玩家已在场景中，刷新装备
		if gs.current_player != null and is_instance_valid(gs.current_player):
			gs.apply_equipment_to_player(gs.current_player)
	if ap != null and data.has("attr_panel"):
		ap.deserialize(data["attr_panel"])
	if sr != null and data.has("skill_runtime"):
		sr.deserialize(data["skill_runtime"])
	if fs != null and data.has("fermentation_system"):
		fs.deserialize(data["fermentation_system"])

# ============================================================================
# 重置 — 新游戏时清除全部子系统状态
# ============================================================================

## 重置全部子系统到初始状态（新游戏时调用）。
func reset_all() -> void:
	var tm := _get_tavern_manager()
	var gs := _get_game_state()
	var ap := _get_attr_panel()
	var sr := _get_skill_runtime()
	var fs := _get_fermentation_system()
	if tm != null:
		tm.reset_state()
	if gs != null:
		gs.reset_state()
	if ap != null:
		ap.reset()
	if sr != null:
		sr.reset()
	if fs != null:
		fs.reset()

# ============================================================================
# 内部辅助
# ============================================================================

func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SLOT_COUNT

func _slot_path(slot_index: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot_index

func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# --- Autoload 获取（容错：测试环境可能缺少部分 autoload） ---

func _get_tavern_manager() -> Node:
	return Service.tavern_manager()

func _get_game_state() -> Node:
	return Service.game_state()

func _get_attr_panel() -> Node:
	return Service.attr_panel()

func _get_skill_runtime() -> Node:
	return Service.skill_runtime()

func _get_fermentation_system() -> Node:
	return Service.fermentation_system()
