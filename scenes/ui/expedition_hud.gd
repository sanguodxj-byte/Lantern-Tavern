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

var collected_materials: Dictionary = {}
var latest_pressure_snapshot: Dictionary = {}

func _ready() -> void:
	# Hide mobile controls on desktop, show only on Android/iOS
	var os_name = OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		$MobileHUD.visible = true
	else:
		$MobileHUD.visible = false
		
	# Connect local signals
	interact_btn.pressed.connect(_on_mobile_interact)
	
	_update_hud()

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
			pressure_label.text = "暗蚀 %d - 立刻撤离" % threat
		"leave_soon":
			pressure_label.text = "暗蚀 %d - 差不多该撤了" % threat
		"tense":
			pressure_label.text = "暗蚀 %d - 周围开始躁动" % threat
		_:
			pressure_label.text = "暗蚀 %d - 可控" % threat

	if bool(snapshot.get("overtime", false)):
		alert_label.text = "18:00 已到，今晚经营收入归零"
		alert_label.visible = true
	elif bool(snapshot.get("should_extract", false)):
		alert_label.text = "差不多该撤了"
		alert_label.visible = true

func trigger_extraction_available() -> void:
	alert_label.text = tr("EXTRACTION_READY") # Localization
	alert_label.visible = true
	var timer = get_tree().create_timer(4.0)
	await timer.timeout
	alert_label.visible = false

func _on_mobile_interact() -> void:
	# Emulate "E" key press for mobile Touch interactions
	var ev = InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	
	await get_tree().create_timer(0.1).timeout
	ev.pressed = false
	Input.parse_input_event(ev)
