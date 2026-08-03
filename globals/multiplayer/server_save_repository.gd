extends RefCounted
## ServerSaveRepository —— 服务器可信存档仓（架构审查 P1-1 MVP）。
##
## 背景：远端 spawn 的权威材料/装备/法术状态此前没有可信来源——客户端自报 save_state
## 已被忽略，但远端入口只能以空默认状态创建。本仓让服务器按稳定身份 player_guid
## 持久化/加载玩家权威存档，使「远端可信存档来源」成立：
##   * 首次 spawn：以调用方传入的存档摘要播种（房主本地存档 / 空默认）；
##   * 出征结算（_settle_expedition）：把该玩家当前权威背包/装配写回本仓；
##   * 重连/新会话：按 guid 从本仓恢复权威状态（不信任任何客户端字典）。
##
## 纯逻辑、无场景树依赖；存储目录可参数化（测试注入临时目录）。
## GUID 文件名做白名单消毒（防路径穿越：禁止 / \\ .. 及空值）。

const DEFAULT_SAVE_DIR := "user://server_saves"
## GUID 白名单：仅 [A-Za-z0-9_-]，最长 128——防路径穿越（/ \\ .. 与空值一律拒绝）。
const MAX_GUID_LEN := 128

var _save_dir: String = DEFAULT_SAVE_DIR

## 设置存档目录（测试注入；调用方保证目录可写）。
func set_save_dir(dir: String) -> void:
	_save_dir = dir

## 取目录（测试断言用）。
func get_save_dir() -> String:
	return _save_dir

## GUID 白名单校验（逐字符，无正则依赖）。
static func is_valid_guid(guid: String) -> bool:
	if guid.is_empty() or guid.length() > MAX_GUID_LEN:
		return false
	for i in guid.length():
		var c := guid.unicode_at(i)
		var ok: bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
			or c == 45 or c == 95  # '-' '_'
		if not ok:
			return false
	return true

## 身份 → 存档文件名（白名单消毒；非法 guid 返回 ""）。
static func file_name_for(player_guid: String) -> String:
	var guid := String(player_guid).strip_edges()
	if not is_valid_guid(guid):
		return ""
	return guid + ".json"

## 加载某身份的服务器权威存档。不存在/非法返回 {}（调用方按默认状态处理）。
## 原子写窗口期（remove+rename 之间）回退读 .tmp——绝不把半写文件当成功。
func load_save(player_guid: String) -> Dictionary:
	var fname := file_name_for(player_guid)
	if fname.is_empty():
		return {}
	var final_path := _save_dir.path_join(fname)
	var path := final_path
	if not FileAccess.file_exists(path):
		var tmp_path := _save_dir.path_join(fname + ".tmp")
		if FileAccess.file_exists(tmp_path):
			path = tmp_path
		else:
			return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return json.data as Dictionary

## 保存某身份的服务器权威存档。返回是否成功。
## 原子写：先写 <guid>.json.tmp 再 rename——同机多进程（listen-server + dedicated server
## 共享 user://）不会读到半写 JSON（架构检查 2026-08-03）。
func save_save(player_guid: String, data: Dictionary) -> bool:
	var fname := file_name_for(player_guid)
	if fname.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(_save_dir)
	var tmp_path := _save_dir.path_join(fname + ".tmp")
	var final_path := _save_dir.path_join(fname)
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var err := DirAccess.rename_absolute(tmp_path, final_path)
	return err == OK

## 删除某身份的服务器存档（测试清理/主动清档）。
func delete_save(player_guid: String) -> void:
	var fname := file_name_for(player_guid)
	if fname.is_empty():
		return
	var path := _save_dir.path_join(fname)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
