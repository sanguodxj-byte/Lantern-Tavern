extends Node3D

## Editor/debug-only first-person action preview. It never writes registry data or assets.
@onready var view_model: ViewModel = $Camera3D/ViewModel
@onready var weapon_selector: OptionButton = $CanvasLayer/Panel/WeaponSelector
@onready var action_selector: OptionButton = $CanvasLayer/Panel/ActionSelector
@onready var progress: HSlider = $CanvasLayer/Panel/Progress
@onready var aim_toggle: CheckButton = $CanvasLayer/Panel/AimToggle
@onready var status: Label = $CanvasLayer/Panel/Status
@onready var muzzle_marker: MeshInstance3D = $Camera3D/ViewModel/MuzzleMarker

func _ready() -> void:
	for action_name in ViewModelAnimator.REQUIRED_ACTIONS:
		action_selector.add_item(String(action_name))
	_populate_weapons()
	weapon_selector.item_selected.connect(_on_weapon_selected)
	action_selector.item_selected.connect(_on_action_selected)
	progress.value_changed.connect(_on_progress_changed)
	aim_toggle.toggled.connect(set_aim_preview)
	_update_status()

func _process(_delta: float) -> void:
	muzzle_marker.global_transform = view_model.get_muzzle_global_transform()

func _populate_weapons() -> void:
	var registry := get_node_or_null("/root/WeaponRegistry")
	if registry == null:
		status.text = "WeaponRegistry unavailable"
		return
	for weapon_id in registry.get_all_ids():
		weapon_selector.add_item(weapon_id)
		weapon_selector.set_item_metadata(weapon_selector.item_count - 1, weapon_id)
	if weapon_selector.item_count > 0:
		_on_weapon_selected(0)

func set_weapon_id(weapon_id: String) -> void:
	var registry := get_node_or_null("/root/WeaponRegistry")
	if registry != null:
		view_model.set_weapon(registry.get_weapon_data(weapon_id))
		_update_status()

func preview_action(action_name: StringName, normalized_progress: float = -1.0) -> void:
	if normalized_progress >= 0.0:
		view_model.sample_action(action_name, normalized_progress)
	else:
		view_model.play_action(action_name)
	_update_status()

func set_aim_preview(enabled: bool) -> void:
	view_model.set_aiming(enabled)
	_update_status()

func _on_weapon_selected(index: int) -> void:
	set_weapon_id(String(weapon_selector.get_item_metadata(index)))

func _on_action_selected(index: int) -> void:
	preview_action(StringName(action_selector.get_item_text(index)), progress.value)

func _on_progress_changed(value: float) -> void:
	preview_action(StringName(action_selector.get_item_text(action_selector.selected)), value)

func _update_status() -> void:
	status.text = "profile=%s  action=%s  sample=%.2f" % [view_model.resolve_weapon_profile(view_model._current_weapon_data), action_selector.get_item_text(action_selector.selected), progress.value]
