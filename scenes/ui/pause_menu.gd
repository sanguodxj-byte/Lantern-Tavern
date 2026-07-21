extends CanvasLayer
class_name PauseMenu

const UI_ROUTES := preload("res://globals/ui/ui_route_catalog.gd")

@onready var resume_btn: Button = %ResumeBtn
@onready var main_menu_btn: Button = %MainMenuBtn
@onready var save_btn: Button = %SaveBtn
@onready var exit_btn: Button = %ExitBtn
@onready var save_load_panel: Control = $SaveLoadPanel

var is_paused := false

func _ready() -> void:
	visible = false
	_update_button_texts()
	save_btn.pressed.connect(_on_save_pressed)
	save_load_panel.back_pressed.connect(_on_save_load_back)
	save_load_panel.slot_action_completed.connect(_on_slot_action_completed)

func _update_button_texts() -> void:
	resume_btn.text = tr("Resume")
	main_menu_btn.text = tr("Main Menu")
	save_btn.text = tr("Save Game")
	exit_btn.text = tr("Exit Game")

# 轮询检测 ESC
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		if is_paused:
			resume()
		else:
			pause()

# 手动拦截鼠标点击：绕过暂停后的 Button 信号系统
func _unhandled_input(event: InputEvent) -> void:
	if not is_paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = (event as InputEventMouseButton).position
		if _is_click_on_control(resume_btn, pos):
			_on_resume_pressed()
			_handle_input()
		elif _is_click_on_control(save_btn, pos):
			_on_save_pressed()
			_handle_input()
		elif _is_click_on_control(main_menu_btn, pos):
			_on_main_menu_pressed()
			_handle_input()
		elif _is_click_on_control(exit_btn, pos):
			_on_exit_pressed()
			_handle_input()

func _handle_input() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()

func _is_click_on_control(control: Control, pos: Vector2) -> bool:
	if control == null or not control.visible or not control.is_inside_tree():
		return false
	var rect := Rect2(control.global_position, control.size)
	return rect.has_point(pos)

func pause() -> void:
	is_paused = true
	visible = true
	_pause_tree_except_self(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func resume() -> void:
	is_paused = false
	visible = false
	_pause_tree_except_self(false)
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# 不暂停整棵树，只暂停游戏层（层级<128）
func _pause_tree_except_self(paused: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# 遍历所有节点，暂停非 UI 层
	var root := tree.root
	for child in root.get_children():
		_pause_node_recursive(child, paused, 0)

func _pause_node_recursive(node: Node, paused: bool, depth: int) -> void:
	if depth > 20:
		return
	# 跳过 CanvasLayer 层级 >= 128 的 UI 节点
	if node is CanvasLayer:
		var cl := node as CanvasLayer
		if cl.layer >= 100:
			# 不暂停 UI 层
			for c in node.get_children():
				_pause_node_recursive(c, paused, depth + 1)
			return
	# 对其他节点设置 process_mode
	if paused:
		if node.process_mode == PROCESS_MODE_INHERIT or node.process_mode == PROCESS_MODE_ALWAYS:
			node.set_process_mode(PROCESS_MODE_DISABLED)
	else:
		if node.process_mode == PROCESS_MODE_DISABLED:
			node.set_process_mode(PROCESS_MODE_INHERIT)
	for c in node.get_children():
		_pause_node_recursive(c, paused, depth + 1)

func _on_resume_pressed() -> void:
	resume()

func _on_main_menu_pressed() -> void:
	is_paused = false
	visible = false
	_pause_tree_except_self(false)
	UiNavigation.navigate(UI_ROUTES.MAIN_MENU)

func _on_save_pressed() -> void:
	save_load_panel.set_mode(SaveLoadPanel.Mode.SAVE)
	save_load_panel.visible = true
	save_load_panel.refresh()

func _on_save_load_back() -> void:
	save_load_panel.visible = false

func _on_slot_action_completed(_action: String, _slot_index: int) -> void:
	save_load_panel.visible = false

func _on_exit_pressed() -> void:
	_pause_tree_except_self(false)
	get_tree().quit()
