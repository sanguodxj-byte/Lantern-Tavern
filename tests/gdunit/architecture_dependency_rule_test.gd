extends GdUnitTestSuite
## 架构依赖规则测试（2026-08-02 架构审查 P1-4 落地）。
## 静态规则扫描：
##   1. 禁止地牢/敌人规则层出现对单机全局当前玩家的非注释代码引用
##      （GameState.current_player），防止 per-player 迁移回退；
##   2. 禁止 TavernHUD 重新读取 CustomerSpawner 私有 _active_customers
##      （0805 审查 P1：UI 只允许走 snapshot_active_visits 公开 API）；
##   3. autoload 数量门禁：未经审批不得增长（08-02 审查 P1-2 治理）；
##   4. /root 绝对路径趋势门禁（1417 审查 P1-2）；
##   5. 方向性依赖规则（1727 审查 P2-1 / 2026-08-06 汇总 #1）：
##      R1  session_* 服务禁引 UI/单机全局；
##      R2  scenes/ui 禁直接变更权威实体仓；
##      R3  globals/core/state 纯数据层禁依赖 Node/SceneTree。

const FORBIDDEN := "GameState.current_player"

## 受规则约束的目录：地牢运行时与敌人规则层。
## 本地相机/HUD/LOD 仍允许持有本机玩家句柄，故不在约束范围。
const SCOPES: Array[String] = [
	"res://scenes/expedition/",
	"res://scenes/characters/enemies/",
]

## autoload 数量上限（2026-08-05 复核：当前 31 个（2026-08-06 移出纯数据表 SkillData/ActionSkills，ADR-005 决策 1）
## MultiplayerSession 生产装配）。
## 新增 autoload 必须经架构审批并同步上调本门禁。
const AUTOLOAD_LIMIT := 31

## 生产源码绝对 /root 路径访问上限（1417 审查 P1-2 趋势门禁）。
## 依赖获取必须统一收敛到 Service.*（或注入）；新增 root 引用需白名单+理由。
## 2026-08-05 基线：client_command_driver 迁移后 11 处。
const ROOT_REF_LIMIT := 11

## 受扫描目录（生产代码；测试/工具/插件不计入）。
const ROOT_SCAN_DIRS: Array[String] = [
	"res://globals/",
	"res://scenes/",
	"res://data/",
]

func test_rule_layers_do_not_reference_global_current_player() -> void:
	var violations: Array = []
	for scope in SCOPES:
		_scan_dir(scope, violations)
	assert_array(violations).is_empty() \
		.override_failure_message("规则层禁止引用单机全局当前玩家（08-02 审查 P1-4）：\n%s" % "\n".join(violations))

func test_tavern_hud_does_not_read_spawner_private_field() -> void:
	# 0805 审查 P1：HUD 只允许通过 snapshot_active_visits() 公开只读 API 取顾客数据，
	# 禁止重新读取 CustomerSpawner 私有 _active_customers 字段（防一次性快照耦合回退）。
	var f := FileAccess.open("res://scenes/ui/tavern_hud.gd", FileAccess.READ)
	assert_bool(f != null).is_true()
	if f == null:
		return
	var violations: Array = []
	var line_no := 1
	while not f.eof_reached():
		var line := f.get_line()
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("#") and "_active_customers" in line:
			violations.append("%s:%d: %s" % ["res://scenes/ui/tavern_hud.gd", line_no, trimmed])
		line_no += 1
	assert_array(violations).is_empty() \
		.override_failure_message("TavernHUD 禁止读取 spawner 私有 _active_customers：\n%s" % "\n".join(violations))

func test_autoload_count_within_approved_limit() -> void:
	# 08-02 审查 P1-2：全局服务面需受控；新增 autoload 必须经架构审批。
	var count := _count_autoloads()
	assert_int(count).is_less_equal(AUTOLOAD_LIMIT) \
		.override_failure_message(
			"autoload 数量 %d 超过审批上限 %d——新增全局服务需架构审批并同步更新本门禁" % [count, AUTOLOAD_LIMIT])

func test_root_path_references_within_trend_limit() -> void:
	# 1417 审查 P1-2：绝对 /root 字符串访问是第四种依赖形式，必须持续下降。
	var offenders: Array = []
	var count := 0
	for scope in ROOT_SCAN_DIRS:
		count += _scan_root_refs(scope, offenders)
	assert_int(count).is_less_equal(ROOT_REF_LIMIT) \
		.override_failure_message("生产源码 /root 引用 %d 处超过趋势上限 %d：\n%s" % [count, ROOT_REF_LIMIT, "\n".join(offenders)])

func _scan_root_refs(dir_path: String, offenders: Array) -> int:
	var count := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var full := dir_path + fname
		if dir.current_is_dir():
			if fname != "." and fname != "..":
				count += _scan_root_refs(full + "/", offenders)
		elif fname.ends_with(".gd"):
			var f := FileAccess.open(full, FileAccess.READ)
			if f == null:
				continue
			var line_no := 1
			while not f.eof_reached():
				var line := f.get_line()
				var trimmed := line.strip_edges()
				if not trimmed.begins_with("#") and '"/root/' in line:
					count += 1
					if offenders.size() < 20:
						offenders.append("%s:%d" % [full, line_no])
				line_no += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return count

func _count_autoloads() -> int:
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	if f == null:
		return 999
	var in_autoload := false
	var count := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("[") and not in_autoload:
			in_autoload = line == "[autoload]"
			continue
		if in_autoload:
			if line.begins_with("["):
				break
			if line.begins_with(";") or line.begins_with("#") or line.is_empty():
				continue
			count += 1
	return count

func _scan_dir(dir_path: String, violations: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		# 目录不存在：报告为失败（契约要求这些目录受约束）
		violations.append("无法打开受约束目录: %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var full := dir_path + fname
		if dir.current_is_dir():
			if fname != "." and fname != "..":
				_scan_dir(full + "/", violations)
		elif fname.ends_with(".gd"):
			_scan_script(full, violations)
		fname = dir.get_next()
	dir.list_dir_end()

func _scan_script(path: String, violations: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		violations.append("无法读取脚本: %s" % path)
		return
	var line_no := 1
	while not f.eof_reached():
		var line := f.get_line()
		var trimmed := line.strip_edges()
		# 跳过注释行（含缩进注释）；只检查真实代码引用
		if not trimmed.begins_with("#") and FORBIDDEN in line:
			violations.append("%s:%d: %s" % [path, line_no, trimmed])
		line_no += 1

# ============================================================================
# 方向性依赖规则（1727 审查 P2-1 / 2026-08-06 汇总 #1）
# ============================================================================

## R1：session 编排服务禁止引用 UI 场景与单机全局（TavernManager/TavernSettlement/
## GameState.current_player）——联机权威层只能经 root 端口访问共享容器。
func test_session_services_do_not_touch_ui_or_solo_globals() -> void:
	var violations: Array = []
	var dir := DirAccess.open("res://globals/multiplayer/")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.begins_with("session_") and fname.ends_with(".gd"):
				_scan_for_patterns("res://globals/multiplayer/" + fname, violations,
					["scenes/ui", "TavernManager", "TavernSettlement", "GameState.current_player"])
			fname = dir.get_next()
		dir.list_dir_end()
	assert_array(violations).is_empty() \
		.override_failure_message("session_* 服务禁止引用 UI/单机全局（依赖方向 R1）：\n%s" % "\n".join(violations))

## R2：scenes/ui 禁止直接变更权威实体仓（set_entity/remove_entity/update_entity）。
func test_ui_never_mutates_authoritative_entity_registry() -> void:
	var violations: Array = []
	_scan_dir_for_patterns("res://scenes/ui/", violations,
		["set_entity(", "remove_entity(", "update_entity("])
	assert_array(violations).is_empty() \
		.override_failure_message("scenes/ui 禁止直接变更权威实体仓（依赖方向 R2）：\n%s" % "\n".join(violations))

## R3：globals/core/state 纯数据层禁止依赖 Node/SceneTree。
func test_state_layer_has_no_node_dependency() -> void:
	var violations: Array = []
	_scan_dir_for_patterns("res://globals/core/state/", violations,
		["extends Node", "get_tree()"])
	assert_array(violations).is_empty() \
		.override_failure_message("globals/core/state 纯数据层禁止依赖 Node/SceneTree（依赖方向 R3）：\n%s" % "\n".join(violations))

## R4：session_* 服务禁止直接访问 root 私有字段（`_r._`）——必须经窄端口
## （live_state()/entities()/reject()/bump_world() 等，1727 审查 P2-3）。
func test_session_services_use_narrow_ports_not_private_fields() -> void:
	var violations: Array = []
	var dir := DirAccess.open("res://globals/multiplayer/")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.begins_with("session_") and fname.ends_with(".gd"):
				_scan_for_patterns("res://globals/multiplayer/" + fname, violations,
					["_r._"])
			fname = dir.get_next()
		dir.list_dir_end()
	assert_array(violations).is_empty() \
		.override_failure_message("session_* 服务禁止直接访问 root 私有字段（窄端口 R4）：\n%s" % "\n".join(violations))

## 单文件多模式扫描（跳过注释行）。
func _scan_for_patterns(path: String, violations: Array, patterns: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		violations.append("无法读取脚本: %s" % path)
		return
	var line_no := 1
	while not f.eof_reached():
		var line := f.get_line()
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("#"):
			for p in patterns:
				if String(p) in line:
					violations.append("%s:%d: %s" % [path, line_no, trimmed])
					break
		line_no += 1

## 目录递归多模式扫描。
func _scan_dir_for_patterns(dir_path: String, violations: Array, patterns: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		violations.append("无法打开受约束目录: %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var full := dir_path + fname
		if dir.current_is_dir():
			if fname != "." and fname != "..":
				_scan_dir_for_patterns(full + "/", violations, patterns)
		elif fname.ends_with(".gd"):
			_scan_for_patterns(full, violations, patterns)
		fname = dir.get_next()
	dir.list_dir_end()
