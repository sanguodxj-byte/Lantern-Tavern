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
##   - TavernSettlement  声望与常客名册（传闻声望、势力声望、常客）
##   - ArmorProficiency  护甲熟练度（轻甲/重甲经验）
##   - ZoneManager       当前选定探险区域
##
## 存档文件格式：JSON，存储于 user://saves/slot_{0..2}.json

# ============================================================================
# 常量
# ============================================================================

const Service := preload("res://globals/core/service.gd")

const SAVE_DIR := "user://saves/"
const SLOT_COUNT: int = 3
const SAVE_VERSION: int = 1

const ZoneSaveSectionClass := preload("res://globals/dungeon/zone_save_section.gd")

func _ready() -> void:
	# ADR-005：组合根注册存档分区（首个迁移领域：ZoneManager）。
	# 新增持久化领域在此 register_section，不再向 serialize_all 中央列表追加。
	register_section(ZoneSaveSectionClass.new())

signal save_completed(slot_index: int)
signal load_completed(slot_index: int)
signal save_deleted(slot_index: int)

## 当前活动存档槽位（P1-3/0304 审查）：由 load_from_slot/save_to_slot 维护；
## -1 = 无活动槽位。联机结算等按身份落盘的路径必须使用它，禁止硬编码 0。
var active_slot: int = -1

## ADR-005：SaveSection 注册表——持久化领域自声明 serialize/deserialize/reset，
## SaveManager 只编排清单与槽位 IO。未迁移领域保留旧路径，两者并存兼容。
var _sections: Array = []

## 注册存档分区（ADR-005；组合根/SaveManager._ready 调用；同 key 覆盖）。
## 参数无类型：SaveSection 为新 class_name，headless 缓存未刷新时静态解析失败。
func register_section(section) -> void:
	if section == null or section.section_key.is_empty():
		push_warning("[SaveManager] 拒绝注册无效存档分区")
		return
	for i in range(_sections.size()):
		if String(_sections[i].section_key) == section.section_key:
			_sections[i] = section
			return
	_sections.append(section)

# ============================================================================
# 公共 API — 存档槽操作
# ============================================================================

## 保存当前游戏状态到指定槽位。成功返回 true。
## 原子写：先写 `slot_n.json.tmp`，JSON 校验通过后才替换正式文件；
## 写坏/中断不会破坏既有存档。
func save_to_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		push_warning("[SaveManager] 无效的存档槽位: %d" % slot_index)
		return false
	_ensure_save_dir()
	var save_data := serialize_all()
	save_data["slot_index"] = slot_index
	var path := _slot_path(slot_index)
	var tmp_path := _slot_tmp_path(slot_index)
	var json_string := JSON.stringify(save_data, "  ")
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] 无法写入存档文件: %s (错误: %s)" % [tmp_path, FileAccess.get_open_error()])
		return false
	file.store_string(json_string)
	file.close()
	# 校验写出的内容可解析——半截/损坏 JSON 绝不覆盖正式档。
	var verify := FileAccess.open(tmp_path, FileAccess.READ)
	if verify == null:
		push_error("[SaveManager] 无法校验临时存档: %s" % tmp_path)
		return false
	var written := verify.get_as_text()
	verify.close()
	var json := JSON.new()
	if json.parse(written) != OK:
		push_error("[SaveManager] 存档校验失败，保留原存档: %s (行 %d)" % [tmp_path, json.get_error_line()])
		return false
	# 替换正式文件（1122 审查 P1-2 三段恢复协议，替代旧的 remove+rename 失档窗口）：
	#   final → .bak → tmp → final → 成功后删除 .bak。
	# 任何中断点都保留可恢复副本（.tmp 或 .bak），"删旧档后 rename 失败"不再导致正式档缺失。
	var bak_path := _slot_bak_path(slot_index)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		var err_bak := DirAccess.rename_absolute(path, bak_path)
		if err_bak != OK:
			push_error("[SaveManager] 旧档降级 .bak 失败: %s (错误: %d)" % [path, err_bak])
			DirAccess.remove_absolute(tmp_path)
			return false
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("[SaveManager] 存档提升失败: %s (错误: %d)" % [path, err])
		return false
	# 成功替换后清理 .bak（残留旧档无害，但保持目录干净）
	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(bak_path)
	active_slot = slot_index
	save_completed.emit(slot_index)
	print("[SaveManager] 存档已保存到槽位 %d (%s)" % [slot_index, path])
	return true

## 从指定槽位加载游戏状态。成功返回 true。
## 原子替换窗口期内正式文件缺失时，回退读取 .tmp 完整内容。
func load_from_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		push_warning("[SaveManager] 无效的存档槽位: %d" % slot_index)
		return false
	var path := _slot_path(slot_index)
	var read_path := path
	if not FileAccess.file_exists(path):
		# 恢复顺序（1122 审查 P1-2）：final → .tmp → .bak
		var tmp_path := _slot_tmp_path(slot_index)
		if FileAccess.file_exists(tmp_path):
			read_path = tmp_path
		else:
			var bak_path := _slot_bak_path(slot_index)
			if FileAccess.file_exists(bak_path):
				read_path = bak_path
			else:
				push_warning("[SaveManager] 槽位 %d 无存档文件" % slot_index)
				return false
	var file := FileAccess.open(read_path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] 无法读取存档文件: %s" % read_path)
		return false
	var json_string := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_error("[SaveManager] 存档文件解析失败: %s (行 %d)" % [read_path, json.get_error_line()])
		return false
	var raw_save_data: Dictionary = json.data
	var SaveGameAdapterClass := preload("res://globals/core/state/save_game_adapter.gd")
	var save_data := SaveGameAdapterClass.adapt(raw_save_data)
	if not save_data.has("version") or int(save_data["version"]) != SAVE_VERSION:
		push_warning("[SaveManager] 存档版本不兼容: 槽位 %d" % slot_index)
		return false
	deserialize_all(save_data)
	active_slot = slot_index
	load_completed.emit(slot_index)
	print("[SaveManager] 存档已从槽位 %d 加载" % slot_index)
	return true

## 删除指定槽位的存档。成功返回 true。
func delete_save(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		return false
	var path := _slot_path(slot_index)
	var tmp_path := _slot_tmp_path(slot_index)
	var removed_any := false
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			push_warning("[SaveManager] 删除存档失败: %s (错误: %d)" % [path, err])
			return false
		removed_any = true
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)
	if active_slot == slot_index:
		active_slot = -1
	save_deleted.emit(slot_index)
	if removed_any:
		print("[SaveManager] 槽位 %d 存档已删除" % slot_index)
	return removed_any

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
	var bfs := _get_brew_flow_system()
	data["brew_flow_system"] = bfs.serialize() if bfs != null else {}
	var ts := _get_tavern_settlement()
	data["tavern_settlement"] = ts.serialize() if ts != null else {}
	var arp := _get_armor_proficiency()
	data["armor_proficiency"] = arp.to_dict() if arp != null else {}
	var zm := _get_zone_manager()
	data["selected_zone"] = int(zm.selected_zone) if zm != null else 0
	# ADR-005：已迁移领域经 sections 注册表序列化（追加，不删除旧路径，保持兼容）
	if not _sections.is_empty():
		var sections_out: Dictionary = {}
		for section in _sections:
			sections_out[String(section.section_key)] = section.serialize()
		data["sections"] = sections_out
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
	var bfs := _get_brew_flow_system()
	if bfs != null and data.has("brew_flow_system"):
		bfs.deserialize(data["brew_flow_system"])
	var ts := _get_tavern_settlement()
	if ts != null and data.has("tavern_settlement"):
		ts.deserialize(data["tavern_settlement"])
	var arp := _get_armor_proficiency()
	if arp != null and data.has("armor_proficiency"):
		arp.from_dict(data["armor_proficiency"])
	var zm := _get_zone_manager()
	if zm != null and data.has("selected_zone"):
		zm.set_zone(int(data["selected_zone"]))
	# ADR-005：sections 注册表恢复（后于旧路径执行，迁移领域以新协议为准）
	if data.has("sections") and data["sections"] is Dictionary:
		var sections_in: Dictionary = data["sections"]
		for section in _sections:
			var key := String(section.section_key)
			if sections_in.has(key) and sections_in[key] is Dictionary:
				section.deserialize(sections_in[key])

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
	var bfs := _get_brew_flow_system()
	if bfs != null:
		bfs.reset()
	var ts := _get_tavern_settlement()
	if ts != null:
		ts.reset_state()
	var arp := _get_armor_proficiency()
	if arp != null:
		arp.reset()
	var zm := _get_zone_manager()
	if zm != null:
		zm.set_zone(0)
	# ADR-005：sections 注册表重置
	for section in _sections:
		section.reset()

# ============================================================================
# 内部辅助
# ============================================================================

func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SLOT_COUNT

func _slot_path(slot_index: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot_index

func _slot_tmp_path(slot_index: int) -> String:
	return SAVE_DIR + "slot_%d.json.tmp" % slot_index

func _slot_bak_path(slot_index: int) -> String:
	return SAVE_DIR + "slot_%d.json.bak" % slot_index

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

func _get_brew_flow_system() -> Node:
	return Service.brew_flow_system()

func _get_tavern_settlement() -> Node:
	return Service.tavern_settlement()

func _get_armor_proficiency() -> Node:
	return Service.armor_proficiency()

func _get_zone_manager() -> Node:
	return Service.zone_manager()
