class_name SpellInterface
extends Control

const RecipeData := preload("res://globals/combat/spell_recipe_data.gd")
const SpellGlyphs := preload("res://data/spell_glyphs.gd")
const SpellLoadoutScript := preload("res://globals/combat/spell_loadout.gd")
const RuneData := preload("res://globals/combat/rune_data.gd")

signal spell_selected(slot_index: int, spell: Dictionary)

const EMPTY_COLOR := Color(0.48, 0.43, 0.4, 1.0)
const READY_COLOR := Color(1.0, 0.72, 0.28, 1.0)
const MIN_COMPACT_WIDTH := 1000.0
const COMPACT_HEIGHT := 800.0

var loadout: RefCounted
var available_runes: Array[String] = []
var _selected_spell_slot: int = 0
var _spell_buttons: Array[Button] = []
var _rune_slot_buttons: Array[Array] = []
var _rune_list: VBoxContainer
var _hint_label: Label
var _status_label: Label
var _body: BoxContainer
var _spell_column: VBoxContainer
var _rune_panel: PanelContainer
var _main_vbox: VBoxContainer
var _header_desc: Label
var _footer_hint: Label


func _ready() -> void:
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if loadout == null:
		loadout = SpellLoadoutScript.new()
	build_interface()
	loadout.slot_changed.connect(_on_loadout_slot_changed)
	resized.connect(_apply_responsive_layout)
	refresh_all()
	call_deferred("_apply_responsive_layout")
	call_deferred("_focus_selected_spell")


func configure(new_loadout: RefCounted, rune_ids: Array[String] = []) -> void:
	if loadout != null and loadout.slot_changed.is_connected(_on_loadout_slot_changed):
		loadout.slot_changed.disconnect(_on_loadout_slot_changed)
	loadout = new_loadout if new_loadout != null else SpellLoadoutScript.new()
	available_runes = rune_ids.duplicate()
	if is_node_ready():
		loadout.slot_changed.connect(_on_loadout_slot_changed)
		refresh_all()


func build_interface() -> void:
	for child in get_children():
		child.queue_free()
	_spell_buttons.clear()
	_rune_slot_buttons.clear()

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.008, 0.006, 0.012, 0.72)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var safe_margin := MarginContainer.new()
	safe_margin.name = "SafeMargin"
	safe_margin.clip_contents = true
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_margin.add_theme_constant_override("margin_left", 36)
	safe_margin.add_theme_constant_override("margin_top", 28)
	safe_margin.add_theme_constant_override("margin_right", 36)
	safe_margin.add_theme_constant_override("margin_bottom", 28)
	add_child(safe_margin)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe_margin.add_child(center)

	var main_panel := PanelContainer.new()
	main_panel.name = "SpellFrame"
	main_panel.theme_type_variation = &"SpellFrame"
	main_panel.custom_minimum_size = Vector2(0, 0)
	main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(main_panel)

	var outer := VBoxContainer.new()
	_main_vbox = outer
	outer.add_theme_constant_override("separation", 10)
	main_panel.add_child(outer)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	outer.add_child(header_row)

	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 2)
	header_row.add_child(title_stack)

	var title := Label.new()
	title.text = TranslationServer.translate("Spell Weaving")
	title.theme_type_variation = &"ScreenTitle"
	title.add_theme_font_size_override("font_size", 30)
	title_stack.add_child(title)

	var subtitle := Label.new()
	_header_desc = subtitle
	subtitle.text = TranslationServer.translate("Hold right mouse to weave spells. Select a spell slot, then add runes in fixed order.")
	subtitle.theme_type_variation = &"MutedLabel"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_stack.add_child(subtitle)

	_status_label = Label.new()
	_status_label.theme_type_variation = &"StatusBadge"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size = Vector2(188, 38)
	header_row.add_child(_status_label)

	var divider := HSeparator.new()
	outer.add_child(divider)

	_body = BoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	outer.add_child(_body)

	_spell_column = VBoxContainer.new()
	_spell_column.custom_minimum_size = Vector2(650, 0)
	_spell_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spell_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spell_column.add_theme_constant_override("separation", 7)
	_body.add_child(_spell_column)

	for slot_index in range(RecipeData.SPELL_SLOT_COUNT):
		_spell_column.add_child(_build_spell_row(slot_index))

	_rune_panel = PanelContainer.new()
	_rune_panel.name = "RuneListPanel"
	_rune_panel.theme_type_variation = &"SpellSection"
	_rune_panel.custom_minimum_size = Vector2(300, 0)
	_rune_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_rune_panel)

	var rune_outer := VBoxContainer.new()
	rune_outer.add_theme_constant_override("separation", 7)
	_rune_panel.add_child(rune_outer)
	var rune_title := Label.new()
	rune_title.text = TranslationServer.translate("Rune List")
	rune_title.theme_type_variation = &"SectionTitle"
	rune_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rune_outer.add_child(rune_title)
	_hint_label = Label.new()
	_hint_label.text = _selected_slot_text()
	_hint_label.theme_type_variation = &"MutedLabel"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rune_outer.add_child(_hint_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rune_outer.add_child(scroll)
	_rune_list = VBoxContainer.new()
	_rune_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rune_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_rune_list)
	_rebuild_rune_list()

	var footer := Label.new()
	_footer_hint = footer
	footer.text = TranslationServer.translate("Keys 1-5 select a spell slot. Click an equipped rune to clear it. Release right mouse to close.")
	footer.theme_type_variation = &"MutedLabel"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(footer)


func _build_spell_row(slot_index: int) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = &"SpellSection"
	row.custom_minimum_size = Vector2(0, 72 if size.y < COMPACT_HEIGHT else 88)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var horizontal := HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", 9)
	row.add_child(horizontal)

	var spell_button := Button.new()
	spell_button.custom_minimum_size = Vector2(390 if size.x < 1400.0 else 490, 58 if size.y < COMPACT_HEIGHT else 72)
	spell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spell_button.theme_type_variation = &"SpellSlotButton"
	spell_button.toggle_mode = true
	spell_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	spell_button.pressed.connect(_select_spell_slot.bind(slot_index))
	horizontal.add_child(spell_button)
	_spell_buttons.append(spell_button)

	var rune_column := VBoxContainer.new()
	rune_column.custom_minimum_size = Vector2(156, 0)
	rune_column.add_theme_constant_override("separation", 3)
	horizontal.add_child(rune_column)
	var buttons: Array = []
	for rune_index in range(RecipeData.RUNES_PER_SPELL):
		var rune_button := Button.new()
		rune_button.custom_minimum_size = Vector2(152, 22)
		rune_button.theme_type_variation = &"RuneSlotButton"
		rune_button.text = _empty_rune_text(rune_index)
		rune_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		rune_button.pressed.connect(_clear_rune.bind(slot_index, rune_index))
		rune_column.add_child(rune_button)
		buttons.append(rune_button)
	_rune_slot_buttons.append(buttons)
	return row


func _rebuild_rune_list() -> void:
	if _rune_list == null:
		return
	for child in _rune_list.get_children():
		child.queue_free()
	if available_runes.is_empty():
		var empty_label := Label.new()
		empty_label.text = TranslationServer.translate("No available runes in your carried inventory.")
		empty_label.theme_type_variation = &"MutedLabel"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.custom_minimum_size = Vector2(0, 96)
		_rune_list.add_child(empty_label)
		return
	for rune_id in available_runes:
		var data: Dictionary = RuneData.get_rune(rune_id)
		if data.is_empty():
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 46)
		button.theme_type_variation = &"SpellSlotButton"
		var remaining: int = loadout.get_remaining_count(rune_id) if loadout.has_method("get_remaining_count") else 1
		button.text = "%s  %s  ×%d" % [
			String(data.get("runic_name", "")),
			TranslationServer.translate(String(data.get("name", rune_id))),
			remaining,
		]
		button.disabled = remaining <= 0
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = TranslationServer.translate(String(data.get("description", data.get("desc", ""))))
		button.pressed.connect(_equip_rune.bind(rune_id))
		_rune_list.add_child(button)


func _equip_rune(rune_id: String) -> void:
	var rune_ids: Array[String] = loadout.get_runes(_selected_spell_slot)
	for rune_index in range(RecipeData.RUNES_PER_SPELL):
		if rune_ids[rune_index].is_empty():
			loadout.set_rune(_selected_spell_slot, rune_index, rune_id)
			return


func _clear_rune(slot_index: int, rune_index: int) -> void:
	_select_spell_slot(slot_index)
	loadout.set_rune(slot_index, rune_index, "")


func _select_spell_slot(slot_index: int) -> void:
	_selected_spell_slot = clampi(slot_index, 0, RecipeData.SPELL_SLOT_COUNT - 1)
	if _hint_label != null:
		_hint_label.text = _selected_slot_text()
	_refresh_spell_selection()
	var spell: Dictionary = loadout.get_spell(_selected_spell_slot)
	if not spell.is_empty():
		spell_selected.emit(_selected_spell_slot, spell)


func refresh_all() -> void:
	for slot_index in range(RecipeData.SPELL_SLOT_COUNT):
		_refresh_slot(slot_index)
	_refresh_spell_selection()
	_rebuild_rune_list()
	_update_status_label()


func _on_loadout_slot_changed(slot_index: int, _spell: Dictionary) -> void:
	_refresh_slot(slot_index)
	_rebuild_rune_list()
	_update_status_label()


func _refresh_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _spell_buttons.size():
		return
	var spell: Dictionary = loadout.get_spell(slot_index)
	var spell_button := _spell_buttons[slot_index]
	if spell.is_empty():
		spell_button.icon = null
		spell_button.text = "%s %d\n%s" % [TranslationServer.translate("Spell Slot"), slot_index + 1, TranslationServer.translate("No fixed recipe formed")]
		spell_button.add_theme_color_override("font_color", EMPTY_COLOR)
	else:
		spell_button.icon = SpellGlyphs.get_texture(String(spell.get("id", "")), 64)
		spell_button.icon_max_width = 64
		spell_button.expand_icon = true
		spell_button.text = "%s %d  ·  %s\n%s" % [
			TranslationServer.translate("Spell Slot"),
			slot_index + 1,
			TranslationServer.translate(String(spell.get("name", "Unknown Spell"))),
			TranslationServer.translate(String(spell.get("description", ""))),
		]
		spell_button.add_theme_color_override("font_color", Color(spell.get("color", Color.WHITE)))
	var rune_ids: Array[String] = loadout.get_runes(slot_index)
	for rune_index in range(RecipeData.RUNES_PER_SPELL):
		var rune_button: Button = _rune_slot_buttons[slot_index][rune_index]
		var rune_id: String = rune_ids[rune_index]
		if rune_id.is_empty():
			rune_button.text = _empty_rune_text(rune_index)
			rune_button.add_theme_color_override("font_color", EMPTY_COLOR)
		else:
			var rune_data: Dictionary = RuneData.get_rune(rune_id)
			rune_button.text = "%d. %s" % [
				rune_index + 1,
				TranslationServer.translate(String(rune_data.get("name", rune_id))),
			]
			rune_button.add_theme_color_override("font_color", Color(String(RuneData.get_rune_color(rune_id))))


func _refresh_spell_selection() -> void:
	for slot_index in range(_spell_buttons.size()):
		var button := _spell_buttons[slot_index]
		button.set_pressed_no_signal(slot_index == _selected_spell_slot)
		var spell: Dictionary = loadout.get_spell(slot_index)
		if spell.is_empty():
			button.add_theme_color_override("font_color", EMPTY_COLOR)
		elif slot_index == _selected_spell_slot:
			button.add_theme_color_override("font_color", READY_COLOR)
		else:
			button.add_theme_color_override("font_color", Color(spell.get("color", Color.WHITE)))


func _update_status_label() -> void:
	if _status_label == null:
		return
	var formed := 0
	for slot_index in range(RecipeData.SPELL_SLOT_COUNT):
		if not loadout.get_spell(slot_index).is_empty():
			formed += 1
	_status_label.text = TranslationServer.translate("Recipes Ready: %d / %d") % [formed, RecipeData.SPELL_SLOT_COUNT]


func _apply_responsive_layout() -> void:
	if _body == null or _spell_column == null or _rune_panel == null:
		return
	var vertical_layout := size.x <= MIN_COMPACT_WIDTH
	var compact_height := size.y < COMPACT_HEIGHT
	_body.vertical = vertical_layout
	_spell_column.custom_minimum_size = Vector2(0 if vertical_layout else 650, 0)
	_rune_panel.custom_minimum_size = Vector2(0 if vertical_layout else 300, 180 if vertical_layout else 0)
	_rune_panel.visible = not compact_height
	_header_desc.visible = not compact_height
	_footer_hint.visible = not compact_height
	if _main_vbox != null:
		_main_vbox.add_theme_constant_override("separation", 8 if compact_height else 12)


func _focus_selected_spell() -> void:
	if visible and _selected_spell_slot >= 0 and _selected_spell_slot < _spell_buttons.size():
		_spell_buttons[_selected_spell_slot].grab_focus()


func _selected_slot_text() -> String:
	return TranslationServer.translate("Editing Spell Slot %d") % (_selected_spell_slot + 1)


func _empty_rune_text(rune_index: int) -> String:
	return "%d. %s" % [rune_index + 1, TranslationServer.translate("Empty Rune")]


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_5:
		_select_spell_slot(event.keycode - KEY_1)
		_focus_selected_spell()
		get_viewport().set_input_as_handled()
