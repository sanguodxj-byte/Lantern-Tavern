extends Control
class_name ExpeditionHUD

@onready var hp_bar: ProgressBar = $TopHUD/HPBar
@onready var gold_label: Label = $TopHUD/GoldLabel
@onready var time_label: Label = $TopHUD/TimeLabel
@onready var material_label: Label = $MiddleHUD/MaterialLabel
@onready var pressure_label: Label = $MiddleHUD/PressureLabel
@onready var joystick: TouchScreenButton = $MobileHUD/Joystick
@onready var interact_btn: Button = $MobileHUD/InteractButton
@onready var alert_label: Label = $BottomHUD/AlertLabel
@onready var extraction_panel: Panel = $ExtractionPanel
@onready var extraction_label: Label = $ExtractionPanel/ExtractionLabel
@onready var extraction_bar: ProgressBar = $ExtractionPanel/ExtractionBar
@onready var floor_indicator: Label = $FloorIndicator
@onready var floor_arrival_label: Label = $FloorArrival/FloorArrivalLabel

var collected_materials: Dictionary = {}
var latest_pressure_snapshot: Dictionary = {}
var _extraction_feedback_token := 0
var _floor_arrival_tween: Tween = null
var _floor_arrival_token := 0

const FLOOR_FADE_IN_DURATION := 0.24
const FLOOR_HOLD_DURATION := 1.0
const FLOOR_FADE_OUT_DURATION := 0.34

func _ready() -> void:
	# Hide mobile controls on desktop, show only on Android/iOS
	var os_name = OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		$MobileHUD.visible = true
	else:
		$MobileHUD.visible = false

	# 金币/材料/时间/压力等右侧浮窗移除：tscn 中已 visible=false，
	# 但运行时会被重新置为可见。这里再次强制隐藏，确保不会被任何
	# 外部代码（例如 game_state 同步）意外显示。
	# 同时把 GoldLabel / MaterialLabel / TimeLabel / PressureLabel 也隐藏，
	# 避免它们在 _update_hud() 中通过 set_text 重新点亮。
	$TopHUD.visible = false
	$MiddleHUD.visible = false
	if $TopHUD.has_node("GoldLabel"):
		$TopHUD.get_node("GoldLabel").visible = false
	if $TopHUD.has_node("TimeLabel"):
		$TopHUD.get_node("TimeLabel").visible = false
	if $MiddleHUD.has_node("MaterialLabel"):
		$MiddleHUD.get_node("MaterialLabel").visible = false
	if $MiddleHUD.has_node("PressureLabel"):
		$MiddleHUD.get_node("PressureLabel").visible = false

	# Connect local signals
	interact_btn.pressed.connect(_on_mobile_interact)
	extraction_panel.visible = false
	if GameState != null and GameState.has_method("get_dungeon_floor_label"):
		set_floor_label(String(GameState.get_dungeon_floor_label()))

	_update_hud()

func set_floor_label(floor_label: String) -> void:
	if floor_indicator == null:
		return
	floor_indicator.text = floor_label if not floor_label.is_empty() else "L1"

## 显示一次“区域名称 · 楼层”的到达提示：淡入、保持 1 秒、淡出。
func show_floor_arrival(zone_name: String, floor_label: String) -> void:
	if floor_arrival_label == null:
		return
	_floor_arrival_token += 1
	var token := _floor_arrival_token
	if _floor_arrival_tween != null and _floor_arrival_tween.is_valid():
		_floor_arrival_tween.kill()
	floor_arrival_label.text = "%s · %s" % [zone_name, floor_label]
	floor_arrival_label.visible = true
	floor_arrival_label.modulate.a = 0.0
	if not is_inside_tree():
		floor_arrival_label.modulate.a = 1.0
		return
	_floor_arrival_tween = create_tween()
	_floor_arrival_tween.tween_property(floor_arrival_label, "modulate:a", 1.0, FLOOR_FADE_IN_DURATION)
	_floor_arrival_tween.tween_interval(FLOOR_HOLD_DURATION)
	_floor_arrival_tween.tween_property(floor_arrival_label, "modulate:a", 0.0, FLOOR_FADE_OUT_DURATION)
	_floor_arrival_tween.tween_callback(func() -> void:
		if token == _floor_arrival_token and is_instance_valid(floor_arrival_label):
			floor_arrival_label.visible = false
	)

func _exit_tree() -> void:
	_floor_arrival_token += 1
	if _floor_arrival_tween != null and _floor_arrival_tween.is_valid():
		_floor_arrival_tween.kill()

func update_player_hp(current_hp: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp

func add_material(item_id: String) -> void:
	if GameState and not GameState.add_carried_material(item_id, 1):
		return
	if collected_materials.has(item_id):
		collected_materials[item_id] += 1
	else:
		collected_materials[item_id] = 1
		
	_update_hud()

func _update_hud() -> void:
	if TavernManager:
		gold_label.text = tr("Gold: %d") % TavernManager.gold
	else:
		gold_label.text = tr("Gold: 100")

	var total_items = 0
	for count in collected_materials.values():
		total_items += count
	material_label.text = tr("Materials: %d") % total_items

func update_pressure(snapshot: Dictionary) -> void:
	latest_pressure_snapshot = snapshot.duplicate()
	var clock_minutes := int(snapshot.get("clock_minutes", 10 * 60))
	var hour := clock_minutes / 60
	var minute := clock_minutes % 60
	time_label.text = "%02d:%02d / 18:00" % [hour, minute]

	var threat := int(round(float(snapshot.get("threat_level", 0.0))))
	var band := String(snapshot.get("pressure_band", "safe"))
	match band:
		"critical":
			pressure_label.text = tr("Dark Erosion %d - Evacuate Now") % threat
		"leave_soon":
			pressure_label.text = tr("Dark Erosion %d - Time to Leave") % threat
		"tense":
			pressure_label.text = tr("Dark Erosion %d - Surroundings Stirring") % threat
		_:
			pressure_label.text = tr("Dark Erosion %d - Contained") % threat

	if bool(snapshot.get("overtime", false)):
		alert_label.text = tr("18:00 reached - tonight's tavern earnings are lost")
		alert_label.visible = true
	elif bool(snapshot.get("should_extract", false)):
		alert_label.text = tr("Time to leave")
		alert_label.visible = true

func trigger_extraction_available() -> void:
	alert_label.text = tr("EXTRACTION_READY") # Localization
	alert_label.visible = true
	var timer = get_tree().create_timer(4.0)
	await timer.timeout
	alert_label.visible = false


func begin_extraction(duration: float) -> void:
	_extraction_feedback_token += 1
	extraction_panel.visible = true
	extraction_bar.value = 0.0
	extraction_label.text = tr("撤离引导  %.1f 秒") % maxf(duration, 0.0)


func update_extraction_progress(progress: float, remaining: float) -> void:
	_extraction_feedback_token += 1
	extraction_panel.visible = true
	extraction_bar.value = clampf(progress, 0.0, 1.0)
	extraction_label.text = tr("保持警戒  %.1f 秒") % maxf(remaining, 0.0)


func cancel_extraction(reason: String) -> void:
	_extraction_feedback_token += 1
	var token := _extraction_feedback_token
	extraction_panel.visible = true
	extraction_bar.value = 0.0
	match reason:
		"hurt":
			extraction_label.text = tr("受到攻击，撤离中断")
		"left_area", "moved":
			extraction_label.text = tr("离开引导区域，撤离中断")
		"not_inside":
			extraction_label.text = tr("进入符文中心后才能撤离")
		_:
			extraction_label.text = tr("撤离已取消")
	_hide_extraction_feedback_later(token)


func complete_extraction() -> void:
	_extraction_feedback_token += 1
	extraction_panel.visible = true
	extraction_bar.value = 1.0
	extraction_label.text = tr("撤离完成")


func _hide_extraction_feedback_later(token: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(1.2).timeout
	if token == _extraction_feedback_token and is_instance_valid(extraction_panel):
		extraction_panel.visible = false

func _on_mobile_interact() -> void:
	# Emulate "E" key press for mobile Touch interactions
	var ev = InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	
	await get_tree().create_timer(0.1).timeout
	ev.pressed = false
	Input.parse_input_event(ev)
