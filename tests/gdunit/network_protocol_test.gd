extends GdUnitTestSuite

# NetworkProtocol（docs/25 §12/§19）：版本常量、命令/事件合法性、协议头构造。

const NP := preload("res://globals/multiplayer/network_protocol.gd")

func test_version_constants() -> void:
	assert_int(NP.PROTOCOL_VERSION).is_equal(1)
	assert_int(NP.SAVE_VERSION).is_equal(1)
	assert_int(NP.DUNGEON_LAYOUT_VERSION).is_equal(1)
	assert_int(NP.WEAPON_DATA_VERSION).is_equal(1)

func test_is_valid_command() -> void:
	assert_bool(NP.is_valid_command(NP.CMD_ATTACK)).is_true()
	assert_bool(NP.is_valid_command("not_a_command")).is_false()

func test_is_valid_event() -> void:
	assert_bool(NP.is_valid_event(NP.EVT_COMBAT_RESOLVED)).is_true()
	assert_bool(NP.is_valid_event("not_an_event")).is_false()

## P2（12:40 审查）：遍历所有已声明 CMD_/EVT_ 常量，确保合法性白名单
## 无遗漏——防止新增协议常量后 is_valid_command/is_valid_event 列表不同步。
## 通过解析协议源文件自动发现常量（不硬编码清单，避免漂移）。
func test_all_command_constants_registered() -> void:
	var missing: Array = []
	for entry in _collect_constant_values("CMD_"):
		if not NP.is_valid_command(String(entry["value"])):
			missing.append("%s=%s" % [entry["name"], entry["value"]])
	assert_array(missing).is_empty() \
		.override_failure_message("以下命令常量未登记到 is_valid_command 白名单: %s" % ", ".join(missing))

func test_all_event_constants_registered() -> void:
	var missing: Array = []
	for entry in _collect_constant_values("EVT_"):
		if not NP.is_valid_event(String(entry["value"])):
			missing.append("%s=%s" % [entry["name"], entry["value"]])
	assert_array(missing).is_empty() \
		.override_failure_message("以下事件常量未登记到 is_valid_event 白名单: %s" % ", ".join(missing))

const PROTOCOL_PATH := "res://globals/multiplayer/network_protocol.gd"

## 从协议源文件提取指定前缀的字符串常量（name/value）。
func _collect_constant_values(prefix: String) -> Array:
	var result: Array = []
	var f := FileAccess.open(PROTOCOL_PATH, FileAccess.READ)
	if f == null:
		return result
	var re := RegEx.new()
	re.compile("const (" + prefix + "\\w+) := \"([^\"]+)\"")
	while not f.eof_reached():
		var line := f.get_line()
		for m in re.search_all(line):
			result.append({"name": m.get_string(1), "value": m.get_string(2)})
	return result

func test_make_header() -> void:
	var h = NP.make_header(NP.PROTOCOL_VERSION, 12, 1200, 450)
	assert_int(h["protocol_version"]).is_equal(1)
	assert_int(h["world_revision"]).is_equal(12)
	assert_int(h["client_tick"]).is_equal(1200)
	assert_int(h["sequence"]).is_equal(450)
