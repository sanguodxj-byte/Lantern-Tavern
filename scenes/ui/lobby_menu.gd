extends UiScreen
## 联机大厅 UI（⑩）。
##
## 入口：主菜单「联机」按钮 → change_scene_to_file 到本场景。
## 职责：
##   * 房主：Host Room → MultiplayerSession.host_room() → 等待玩家 → Start Expedition。
##   * 客户端：Join Room → MultiplayerSession.join_room() → 等待房主开始出征。
##   * 真实地牢由 MultiplayerSession 在收到 dungeon_layout / start_expedition 时构建；
##     本 UI 仅负责「连接 / 房间 / 出征」交互，进入地牢后自动退出（queue_free）让 3D 接管。
##
## 不直接引用任何 class_name（与本项目联机脚本约定一致）。

const UI_ROUTES := preload("res://globals/ui/ui_route_catalog.gd")

const DEFAULT_PORT := 28999
const DEFAULT_ADDR := "127.0.0.1"

var _host_panel: PanelContainer
var _join_panel: PanelContainer
var _lobby_panel: PanelContainer
var _port_edit: LineEdit
var _max_edit: LineEdit
var _addr_edit: LineEdit
var _join_port_edit: LineEdit
var _player_list: VBoxContainer
var _start_btn: Button
var _waiting_label: Label
var _status_label: Label
var _back_btn: Button
var _leave_btn: Button


func _ready() -> void:
	super._ready()
	_build_ui()
	_connect_session()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _connect_session() -> void:
	var ms := _session()
	if ms == null:
		return
	if not ms.room_updated.is_connected(_on_room_updated):
		ms.room_updated.connect(_on_room_updated)
	if not ms.dungeon_entered.is_connected(_on_dungeon_entered):
		ms.dungeon_entered.connect(_on_dungeon_entered)
	if not ms.connection_failed.is_connected(_on_connection_failed):
		ms.connection_failed.connect(_on_connection_failed)
	if not ms.host_failed.is_connected(_on_host_failed):
		ms.host_failed.connect(_on_host_failed)


func _session() -> Node:
	return get_node_or_null("/root/MultiplayerSession")


# ---------------------------------------------------------------------------
# UI 构建
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	# 深色背景（本场景是独立场景，背后无内容）。
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.06, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 左上返回按钮。
	_back_btn = Button.new()
	_back_btn.name = "BackBtn"
	_back_btn.text = tr("Back")
	_back_btn.custom_minimum_size = Vector2(120, 48)
	_back_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_back_btn.position = Vector2(24, 24)
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)

	# 居中自适应容器。
	var center_container := CenterContainer.new()
	center_container.name = "CenterContainer"
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(center_container)

	# 居中主容器。
	var center := VBoxContainer.new()
	center.name = "Center"
	center.custom_minimum_size = Vector2(520, 0)
	center.add_theme_constant_override("separation", 18)
	center_container.add_child(center)

	var title := Label.new()
	title.name = "Title"
	title.text = tr("Multiplayer Lobby")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	center.add_child(title)

	# —— 房主面板 ——
	_host_panel = PanelContainer.new()
	_host_panel.name = "HostPanel"
	center.add_child(_host_panel)
	var host_v := VBoxContainer.new()
	host_v.name = "HostVBox"
	host_v.add_theme_constant_override("separation", 10)
	_host_panel.add_child(host_v)
	var host_title := Label.new()
	host_title.text = tr("Host Room")
	host_title.add_theme_font_size_override("font_size", 26)
	host_v.add_child(host_title)
	_port_edit = _labeled_line_edit(tr("Port"), str(DEFAULT_PORT), host_v)
	_max_edit = _labeled_line_edit(tr("Max Players"), "8", host_v)
	var host_btn := Button.new()
	host_btn.name = "CreateBtn"
	host_btn.text = tr("Create Room")
	host_btn.custom_minimum_size = Vector2(0, 56)
	host_btn.pressed.connect(_on_host_pressed)
	host_v.add_child(host_btn)

	# —— 客户端面板 ——
	_join_panel = PanelContainer.new()
	_join_panel.name = "JoinPanel"
	center.add_child(_join_panel)
	var join_v := VBoxContainer.new()
	join_v.name = "JoinVBox"
	join_v.add_theme_constant_override("separation", 10)
	_join_panel.add_child(join_v)
	var join_title := Label.new()
	join_title.text = tr("Join Room")
	join_title.add_theme_font_size_override("font_size", 26)
	join_v.add_child(join_title)
	_addr_edit = _labeled_line_edit(tr("Server Address"), DEFAULT_ADDR, join_v)
	_join_port_edit = _labeled_line_edit(tr("Port"), str(DEFAULT_PORT), join_v)
	var join_btn := Button.new()
	join_btn.name = "JoinBtn"
	join_btn.text = tr("Join")
	join_btn.custom_minimum_size = Vector2(0, 56)
	join_btn.pressed.connect(_on_join_pressed)
	join_v.add_child(join_btn)

	# —— 大厅面板（连接后显示）——
	_lobby_panel = PanelContainer.new()
	_lobby_panel.name = "LobbyPanel"
	_lobby_panel.visible = false
	center.add_child(_lobby_panel)
	var lobby_v := VBoxContainer.new()
	lobby_v.name = "LobbyVBox"
	lobby_v.add_theme_constant_override("separation", 12)
	_lobby_panel.add_child(lobby_v)
	var players_title := Label.new()
	players_title.text = tr("Connected Players")
	players_title.add_theme_font_size_override("font_size", 26)
	lobby_v.add_child(players_title)
	_player_list = VBoxContainer.new()
	_player_list.name = "PlayerList"
	_player_list.add_theme_constant_override("separation", 6)
	lobby_v.add_child(_player_list)
	_start_btn = Button.new()
	_start_btn.name = "StartBtn"
	_start_btn.text = tr("Start Expedition")
	_start_btn.custom_minimum_size = Vector2(0, 56)
	_start_btn.visible = false
	_start_btn.pressed.connect(_on_start_pressed)
	lobby_v.add_child(_start_btn)
	_waiting_label = Label.new()
	_waiting_label.name = "WaitingLabel"
	_waiting_label.text = tr("Waiting for host to start...")
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.visible = false
	lobby_v.add_child(_waiting_label)
	_leave_btn = Button.new()
	_leave_btn.name = "LeaveBtn"
	_leave_btn.text = tr("Leave Room")
	_leave_btn.custom_minimum_size = Vector2(0, 48)
	_leave_btn.pressed.connect(_on_leave_pressed)
	lobby_v.add_child(_leave_btn)

	# —— 状态栏 ——
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_status_label)


func _labeled_line_edit(label_text: String, default: String, parent: Control) -> LineEdit:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	row.add_child(lbl)
	var le := LineEdit.new()
	le.text = default
	le.custom_minimum_size = Vector2(0, 40)
	row.add_child(le)
	parent.add_child(row)
	return le


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------
func _on_host_pressed() -> void:
	var ms := _session()
	if ms == null:
		_status_label.text = "MultiplayerSession 未就绪"
		return
	var port := int(_port_edit.text) if _port_edit.text.is_valid_int() else DEFAULT_PORT
	var maxp := int(_max_edit.text) if _max_edit.text.is_valid_int() else 8
	ms.host_room(port, maxp)
	_status_label.text = tr("Host room created. Waiting for players...")
	_show_lobby(true)


func _on_join_pressed() -> void:
	var ms := _session()
	if ms == null:
		_status_label.text = "MultiplayerSession 未就绪"
		return
	var addr := _addr_edit.text if _addr_edit.text.strip_edges() != "" else DEFAULT_ADDR
	var port := int(_join_port_edit.text) if _join_port_edit.text.is_valid_int() else DEFAULT_PORT
	ms.join_room(addr, port)
	_status_label.text = tr("Connecting...")
	_show_lobby(false)


func _show_lobby(is_host: bool) -> void:
	_host_panel.visible = false
	_join_panel.visible = false
	_lobby_panel.visible = true
	_start_btn.visible = is_host
	_waiting_label.visible = not is_host
	_refresh_players()


func _refresh_players() -> void:
	for c in _player_list.get_children():
		c.queue_free()
	var ms := _session()
	var peers: Array = []
	if ms != null and ms.has_method("connected_peers"):
		peers = ms.connected_peers()
	if peers.is_empty():
		var hint := Label.new()
		hint.text = "…"
		_player_list.add_child(hint)
		return
	var local := 0
	if ms != null and "local_peer_id" in ms:
		local = int(ms.local_peer_id)
	for p in peers:
		var pid: int = int(p)
		var row := Label.new()
		if pid == local:
			row.text = "%d  —  %s" % [pid, tr("You (Host)") if ms != null and bool(ms.is_host_mode) else tr("You")]
		else:
			row.text = "%d" % pid
		_player_list.add_child(row)


# ---------------------------------------------------------------------------
# 会话信号
# ---------------------------------------------------------------------------
func _on_room_updated(_peer_ids: Array) -> void:
	if _lobby_panel == null:
		return
	if not _lobby_panel.visible:
		_show_lobby(_session() != null and bool(_session().is_host_mode))
	_refresh_players()


func _on_dungeon_entered(_seed_value: int) -> void:
	# 真实地牢已构建（在 MultiplayerSession 下），释放本 UI 让 3D 接管。
	queue_free()


func _on_connection_failed(reason: String) -> void:
	_status_label.text = tr("Connection failed: ") + reason
	_host_panel.visible = true
	_join_panel.visible = true
	_lobby_panel.visible = false


func _on_host_failed(reason: String) -> void:
	_status_label.text = tr("Failed to create room: ") + reason
	_host_panel.visible = true
	_join_panel.visible = true
	_lobby_panel.visible = false


func _on_start_pressed() -> void:
	var ms := _session()
	if ms == null:
		return
	ms.start_expedition()


func _on_leave_pressed() -> void:
	_leave_session()
	request_navigation(UI_ROUTES.MAIN_MENU)


func _on_back_pressed() -> void:
	_leave_session()
	request_navigation(UI_ROUTES.MAIN_MENU)


func _leave_session() -> void:
	var ms := _session()
	if ms != null and ms.has_method("leave_room"):
		ms.leave_room()
