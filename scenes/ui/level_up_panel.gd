class_name LevelUpPanel
extends Control

const RuneData := preload("res://globals/combat/rune_data.gd")
const Service := preload("res://globals/core/service.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

signal reward_chosen(reward_kind: String, reward_id: String)

const ATTRIBUTE_LABELS := {
	"str": "STR 力量",
	"dex": "DEX 敏捷",
	"mag": "MAG 魔力",
	"con": "CON 体质",
	"agi": "AGI 灵巧",
	"per": "PER 感知",
}

@onready var title_label: Label = %TitleLabel
@onready var pending_label: Label = %PendingLabel
@onready var main_choice: VBoxContainer = %MainChoice
@onready var rune_choice: VBoxContainer = %RuneChoice
@onready var rune_opportunity_button: Button = %RuneOpportunityButton
@onready var rune_buttons: Array[Button] = [%RuneOption0, %RuneOption1, %RuneOption2]

var _attr_panel: Node = null
var _game_state: Node = null
var _locked_player: Node = null
var _previous_input_state: Dictionary = {}
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
## P1-4 联机权威成长：待处理升级数/符文候选以服务器事件为准（本地 autoload 不累积联机 XP）。
var _network_pending: int = 0
var _network_candidates: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("character_panel")
	var attribute_buttons := {
		"str": %StrButton,
		"dex": %DexButton,
		"mag": %MagButton,
		"con": %ConButton,
		"agi": %AgiButton,
		"per": %PerButton,
	}
	for attr_key in attribute_buttons.keys():
		(attribute_buttons[attr_key] as Button).pressed.connect(_choose_attribute.bind(String(attr_key)))
	rune_opportunity_button.pressed.connect(_begin_rune_choice)
	for index in range(rune_buttons.size()):
		rune_buttons[index].pressed.connect(_choose_rune.bind(index))
	var nm: Node = _network_manager()
	if nm != null:
		if nm.has_signal("event_received"):
			nm.event_received.connect(_on_network_event)
		if nm.has_signal("event_dispatched"):
			nm.event_dispatched.connect(_on_network_event)
	if _attr_panel == null:
		configure(Service.attr_panel(), Service.game_state())
	else:
		refresh()


func configure(attr_panel: Node, game_state: Node) -> void:
	if _attr_panel != null and _attr_panel.has_signal("level_up_choices_changed"):
		var callback := Callable(self, "_on_pending_choices_changed")
		if _attr_panel.level_up_choices_changed.is_connected(callback):
			_attr_panel.level_up_choices_changed.disconnect(callback)
	_attr_panel = attr_panel
	_game_state = game_state
	if _attr_panel != null and _attr_panel.has_signal("level_up_choices_changed"):
		var callback := Callable(self, "_on_pending_choices_changed")
		if not _attr_panel.level_up_choices_changed.is_connected(callback):
			_attr_panel.level_up_choices_changed.connect(callback)
	if is_node_ready():
		refresh()


func refresh() -> void:
	if _attr_panel == null:
		_hide_panel()
		return
	var pending := _network_pending if _network_mode() else int(_attr_panel.get_pending_level_choices())
	if pending <= 0:
		_network_candidates = []
		_hide_panel()
		return
	pending_label.text = tr("待处理升级：%d") % pending
	_show_panel()
	_sync_player_health()
	var candidates: Array = _network_candidates if _network_mode() else _attr_panel.pending_rune_candidates
	if candidates.is_empty():
		_show_main_choice()
	else:
		_show_rune_choice(candidates)

## 联机权威成长模式：处于激活的联机会话（房主/客户端）时，面板只显示服务器事件状态、
## 只上送选择意图；单机路径保持原样（本地 AttrPanel/GameState）。
func _network_mode() -> bool:
	var nm: Node = _network_manager()
	return nm != null and nm.is_active and (bool(nm.is_host) or nm.is_client())

func _network_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("NetworkManager")

func _network_driver() -> Node:
	if _game_state == null:
		return null
	var player = _game_state.get("current_player")
	if player != null and "multiplayer_driver" in player:
		return player.multiplayer_driver
	return null

## 服务器权威成长事件：只处理本机 peer 的 progression 状态（面板据此刷新/展示符文候选）。
func _on_network_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var kind: String = event.get("event", "")
	if kind != NP.EVT_PROGRESSION_CHANGED and kind != NP.EVT_PROGRESSION_RUNE_CANDIDATES:
		return
	var nm: Node = _network_manager()
	if nm == null:
		return
	if int(event.get("peer_id", -1)) != int(nm.local_peer_id):
		return
	match kind:
		NP.EVT_PROGRESSION_CHANGED:
			_network_pending = int(event.get("pending_level_choices", 0))
			refresh()
		NP.EVT_PROGRESSION_RUNE_CANDIDATES:
			var candidates: Array = event.get("candidates", [])
			_network_candidates = candidates
			if visible:
				_show_rune_choice(candidates)


func _show_panel() -> void:
	if visible:
		return
	visible = true
	_previous_mouse_mode = Input.mouse_mode
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_lock_player_input()
	call_deferred("_focus_first_choice")


func _hide_panel() -> void:
	if not visible:
		return
	visible = false
	_restore_player_input()
	Input.set_mouse_mode(_previous_mouse_mode)


func _lock_player_input() -> void:
	if _game_state == null:
		return
	var player = _game_state.get("current_player")
	if player == null or not is_instance_valid(player):
		return
	_locked_player = player
	_previous_input_state = {
		"movement": bool(player.movement_input_enabled) if "movement_input_enabled" in player else true,
		"interaction": bool(player.interaction_input_enabled) if "interaction_input_enabled" in player else true,
		"combat": bool(player.combat_input_enabled) if "combat_input_enabled" in player else true,
	}
	if "movement_input_enabled" in player:
		player.movement_input_enabled = false
	if "interaction_input_enabled" in player:
		player.interaction_input_enabled = false
	if "combat_input_enabled" in player:
		player.combat_input_enabled = false


func _restore_player_input() -> void:
	if _locked_player == null or not is_instance_valid(_locked_player):
		_locked_player = null
		_previous_input_state.clear()
		return
	if "movement_input_enabled" in _locked_player:
		_locked_player.movement_input_enabled = bool(_previous_input_state.get("movement", true))
	if "interaction_input_enabled" in _locked_player:
		_locked_player.interaction_input_enabled = bool(_previous_input_state.get("interaction", true))
	if "combat_input_enabled" in _locked_player:
		_locked_player.combat_input_enabled = bool(_previous_input_state.get("combat", true))
	_locked_player = null
	_previous_input_state.clear()


func _show_main_choice() -> void:
	title_label.text = tr("升级奖励 · 二选一")
	main_choice.visible = true
	rune_choice.visible = false


func _show_rune_choice(candidates: Array) -> void:
	title_label.text = tr("符文奖励 · 本级不再提升属性")
	main_choice.visible = false
	rune_choice.visible = true
	for index in range(rune_buttons.size()):
		var button := rune_buttons[index]
		if index >= candidates.size():
			button.visible = false
			continue
		button.visible = true
		var rune_id := String(candidates[index])
		var data := RuneData.get_rune(rune_id)
		button.set_meta("rune_id", rune_id)
		button.text = "%s\n%s · %s" % [
			String(data.get("runic_name", rune_id)),
			tr(String(data.get("name", rune_id))),
			tr(String(data.get("rarity", "common")).capitalize()),
		]
		button.tooltip_text = tr(String(data.get("desc", "")))
		button.add_theme_color_override("font_color", Color(RuneData.get_rune_color(rune_id)))
	call_deferred("_focus_first_rune")


func _choose_attribute(attr_key: String) -> void:
	if _network_mode():
		# P1-4：联机只上送意图，服务器权威应用后经 EVT_PROGRESSION_CHANGED 刷新。
		var drv := _network_driver()
		if drv != null and drv.has_method("send_level_up_choice"):
			drv.send_level_up_choice("attribute", attr_key)
		return
	if _attr_panel == null or not _attr_panel.choose_level_up_attribute(attr_key):
		return
	_sync_player_health()
	reward_chosen.emit("attribute", attr_key)
	refresh()


func _begin_rune_choice() -> void:
	if _network_mode():
		# P1-4：符文候选由服务器确定性掷出并经事件下发。
		var drv := _network_driver()
		if drv != null and drv.has_method("request_level_up_rune_candidates"):
			drv.request_level_up_rune_candidates()
		return
	if _attr_panel == null:
		return
	var candidates: Array = _attr_panel.begin_level_up_rune_choice()
	if candidates.size() == 3:
		_show_rune_choice(candidates)


func _choose_rune(index: int) -> void:
	if _network_mode():
		var rune_id := String(rune_buttons[index].get_meta("rune_id", ""))
		var drv := _network_driver()
		if drv != null and drv.has_method("send_level_up_choice"):
			drv.send_level_up_choice("rune", "", rune_id)
		return
	if _attr_panel == null or _game_state == null or index < 0 or index >= rune_buttons.size():
		return
	var rune_id := String(rune_buttons[index].get_meta("rune_id", ""))
	var grant := Callable(_game_state, "add_carried_rune")
	if rune_id.is_empty() or not _attr_panel.choose_level_up_rune(rune_id, grant):
		return
	reward_chosen.emit("rune", rune_id)
	refresh()


func _sync_player_health() -> void:
	# 联机模式：玩家生命由服务器权威管理，本地 autoload 属性为过期镜像，跳过。
	if _network_mode():
		return
	if _attr_panel == null or _game_state == null or not _attr_panel.has_method("compute_max_hp"):
		return
	var player = _game_state.get("current_player")
	if player == null or not is_instance_valid(player) or not "health" in player or player.health == null:
		return
	var old_max := int(player.health.max_life)
	var new_max := int(_attr_panel.compute_max_hp())
	player.health.max_life = new_max
	player.health.current_life = clampi(int(player.health.current_life) + maxi(0, new_max - old_max), 0, new_max)


func _on_pending_choices_changed(_pending_count: int) -> void:
	refresh()


func _focus_first_choice() -> void:
	if visible and main_choice.visible:
		%StrButton.grab_focus()


func _focus_first_rune() -> void:
	if visible and rune_choice.visible and not rune_buttons.is_empty():
		rune_buttons[0].grab_focus()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_restore_player_input()
	if visible:
		Input.set_mouse_mode(_previous_mouse_mode)
	if _attr_panel != null and _attr_panel.has_signal("level_up_choices_changed"):
		var callback := Callable(self, "_on_pending_choices_changed")
		if _attr_panel.level_up_choices_changed.is_connected(callback):
			_attr_panel.level_up_choices_changed.disconnect(callback)
