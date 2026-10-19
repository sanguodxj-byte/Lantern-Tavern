extends GdUnitTestSuite

## ServerSaveRepository（P1-1 MVP）—— 服务器可信存档仓。
## 覆盖：GUID 白名单消毒（防路径穿越）、往返持久化、目录注入隔离、删除。

const REPO := preload("res://globals/multiplayer/server_save_repository.gd")

func _tmp_dir() -> String:
	return "user://test_server_saves_%d" % Time.get_ticks_usec()

func _make_repo() -> REPO:
	var repo: REPO = auto_free(REPO.new())
	repo.set_save_dir(_tmp_dir())
	return repo

func test_guid_whitelist_rejects_path_traversal() -> void:
	assert_bool(REPO.is_valid_guid("player_001")).is_true()
	assert_bool(REPO.is_valid_guid("abc-DEF_123")).is_true()
	# 路径穿越/非法字符一律拒绝。
	assert_bool(REPO.is_valid_guid("")).is_false()
	assert_bool(REPO.is_valid_guid("../etc/passwd")).is_false()
	assert_bool(REPO.is_valid_guid("a/b")).is_false()
	assert_bool(REPO.is_valid_guid("a\\b")).is_false()
	assert_bool(REPO.is_valid_guid("a b")).is_false()
	assert_bool(REPO.is_valid_guid("中文")).is_false()
	assert_bool(REPO.is_valid_guid("x".repeat(129))).is_false()

func test_file_name_sanitizes_guid() -> void:
	assert_str(REPO.file_name_for("player_001")).is_equal("player_001.json")
	assert_str(REPO.file_name_for("../evil")).is_equal("")
	assert_str(REPO.file_name_for("")).is_equal("")

func test_save_load_roundtrip() -> void:
	var repo := _make_repo()
	var data := {"materials": {"iron_ore": 3}, "loadout": {"weapon_slots": ["shortsword", "", "", ""]}}
	assert_bool(repo.save_save("player_alpha", data)).is_true()
	var loaded: Dictionary = repo.load_save("player_alpha")
	assert_int(int(loaded["materials"]["iron_ore"])).is_equal(3)
	assert_str(String(loaded["loadout"]["weapon_slots"][0])).is_equal("shortsword")

func test_load_missing_or_invalid_returns_empty() -> void:
	var repo := _make_repo()
	assert_bool(repo.load_save("no_such_player").is_empty()).is_true()
	assert_bool(repo.load_save("../evil").is_empty()).is_true()
	# 非法 guid 绝不落盘。
	assert_bool(repo.save_save("../evil", {"materials": {}})).is_false()

func test_delete_removes_save() -> void:
	var repo := _make_repo()
	repo.save_save("player_beta", {"materials": {"gold": 1}})
	assert_bool(not repo.load_save("player_beta").is_empty()).is_true()
	repo.delete_save("player_beta")
	assert_bool(repo.load_save("player_beta").is_empty()).is_true()

func test_directories_are_isolated() -> void:
	# 不同目录互不干扰（真实 user://server_saves 与测试临时目录隔离）。
	var repo_a := _make_repo()
	var repo_b := _make_repo()
	repo_a.save_save("shared_guid", {"materials": {"a": 1}})
	assert_bool(repo_b.load_save("shared_guid").is_empty()).is_true()

## P1-3（1122 审查）：保存写入 schema 包装，加载解包；三段协议成功后无 .tmp/.bak 残留。
func test_save_wraps_schema_version_and_cleans_backup_files() -> void:
	var repo := _make_repo()
	assert_bool(repo.save_save("player_ver", {"materials": {"gold": 7}})).is_true()
	var loaded: Dictionary = repo.load_save("player_ver")
	assert_int(int(loaded["materials"]["gold"])).is_equal(7)
	assert_bool(FileAccess.file_exists(repo.get_save_dir() + "/player_ver.json")).is_true()
	assert_bool(FileAccess.file_exists(repo.get_save_dir() + "/player_ver.json.tmp")).is_false()
	assert_bool(FileAccess.file_exists(repo.get_save_dir() + "/player_ver.json.bak")).is_false()

## P1-3（1122 审查）：未知未来 schema 版本硬拒绝；旧平铺格式向后兼容。
func test_load_rejects_future_schema_version_and_accepts_legacy() -> void:
	var repo := _make_repo()
	DirAccess.make_dir_recursive_absolute(repo.get_save_dir())
	# 未来版本 → 拒绝（返回 {}）
	var future := FileAccess.open(repo.get_save_dir() + "/player_future.json", FileAccess.WRITE)
	future.store_string(JSON.stringify({"schema_version": 999, "state": {"materials": {"gold": 99}}}))
	future.close()
	assert_bool(repo.load_save("player_future").is_empty()).is_true()
	# 旧平铺格式（无 schema_version）→ 兼容读取
	var legacy := FileAccess.open(repo.get_save_dir() + "/player_legacy.json", FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"materials": {"gold": 5}}))
	legacy.close()
	var loaded: Dictionary = repo.load_save("player_legacy")
	assert_int(int(loaded["materials"]["gold"])).is_equal(5)

## P1-2（1122 审查）：final 缺失时依次回退 .tmp / .bak 恢复。
func test_load_falls_back_to_tmp_then_bak() -> void:
	var repo := _make_repo()
	DirAccess.make_dir_recursive_absolute(repo.get_save_dir())
	# 模拟中断点 2：仅 .tmp 存在
	var tmp := FileAccess.open(repo.get_save_dir() + "/player_rec.json.tmp", FileAccess.WRITE)
	tmp.store_string(JSON.stringify({"schema_version": 1, "state": {"materials": {"gold": 1}}}))
	tmp.close()
	var from_tmp: Dictionary = repo.load_save("player_rec")
	assert_int(int(from_tmp["materials"]["gold"])).is_equal(1)
	# 模拟中断点 1：仅 .bak 存在（tmp 也缺失）
	var bak := FileAccess.open(repo.get_save_dir() + "/player_rec2.json.bak", FileAccess.WRITE)
	bak.store_string(JSON.stringify({"schema_version": 1, "state": {"materials": {"gold": 2}}}))
	bak.close()
	var from_bak: Dictionary = repo.load_save("player_rec2")
	assert_int(int(from_bak["materials"]["gold"])).is_equal(2)
