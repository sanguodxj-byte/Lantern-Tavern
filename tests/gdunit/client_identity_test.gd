extends GdUnitTestSuite

## ClientIdentity（P0-1）—— 客户端持久化稳定身份 GUID。
## 覆盖：生成唯一性、首次创建并持久化、二次加载复用、存储隔离。

const CI := preload("res://globals/multiplayer/client_identity.gd")

func test_generate_produces_non_empty_unique_ids() -> void:
	var a: String = CI.generate()
	var b: String = CI.generate()
	assert_bool(not a.is_empty()).is_true()
	assert_bool(not b.is_empty()).is_true()
	assert_str(a).is_not_equal(b)
	assert_int(a.length()).is_equal(64)

func test_load_or_create_persists_across_calls() -> void:
	var store := "user://test_identity_%d.cfg" % Time.get_ticks_usec()
	var first: String = CI.load_or_create(store)
	var second: String = CI.load_or_create(store)
	# 二次调用必须复用同一 GUID（跨进程/重启稳定，供重连锚定）。
	assert_str(second).is_equal(first)
	assert_bool(not first.is_empty()).is_true()

func test_load_or_create_returns_existing_guid_from_file() -> void:
	var store := "user://test_identity_%d.cfg" % Time.get_ticks_usec()
	var first: String = CI.load_or_create(store)
	# 直接读文件确认已持久化。
	var cfg := ConfigFile.new()
	assert_int(cfg.load(store)).is_equal(OK)
	assert_str(String(cfg.get_value("identity", CI.KEY, ""))).is_equal(first)

func test_separate_stores_produce_independent_guids() -> void:
	var store_a := "user://test_identity_a_%d.cfg" % Time.get_ticks_usec()
	var store_b := "user://test_identity_b_%d.cfg" % Time.get_ticks_usec()
	assert_str(CI.load_or_create(store_a)).is_not_equal(CI.load_or_create(store_b))
