extends Control
class_name ExpeditionHUD

@onready var hp_bar: ProgressBar = $TopHUD/HPBar
@onready var gold_label: Label = $TopHUD/GoldLabel
@onready var material_label: Label = $MiddleHUD/MaterialLabel
@onready var joystick: TouchScreenButton = $MobileHUD/Joystick
@onready var interact_btn: Button = $MobileHUD/InteractButton
@onready var alert_label: Label = $BottomHUD/AlertLabel

var collected_materials: Dictionary = {}

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
	if collected_materials.has(item_id):
		collected_materials[item_id] += 1
	else:
		collected_materials[item_id] = 1
	
	if TavernManager:
		TavernManager.add_material(item_id, 1)
		
	_update_hud()

func _update_hud() -> void:
	if TavernManager:
		gold_label.text = "Gold: %d" % TavernManager.gold
	else:
		gold_label.text = "Gold: 100"
		
	var total_items = 0
	for count in collected_materials.values():
		total_items += count
	material_label.text = "Materials: %d" % total_items

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
