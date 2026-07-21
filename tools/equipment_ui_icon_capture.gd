extends SceneTree
## Capture equipment panel + chest loot panel grids with real icons for visual QA.
## Output: reports/ui_preview/equipment_icons_sheet.png, chest_loot_icons_sheet.png

const OUT_DIR := "res://reports/ui_preview"
const DETAIL := preload("res://scenes/ui/equipment_detail_popup.gd")
const ICON_SIZE := 72
const PAD := 10
const COLS := 6

var _had_error := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	await _capture_equipment_icons()
	await _capture_material_icons()
	await _capture_loot_panel_like_grid()

	if _had_error:
		print("[UIIconCapture] finished WITH ERRORS")
		quit(1)
		return
	print("[UIIconCapture] done -> %s" % OUT_DIR)
	quit(0)


func _capture_equipment_icons() -> void:
	var wr: Node = root.get_node_or_null("WeaponRegistry")
	if wr == null:
		_fail("WeaponRegistry missing")
		return
	var ids: Array = wr.get_all_ids()
	ids.sort()
	var cells: Array = []
	for eid in ids:
		var tex: Texture2D = DETAIL.icon_for_equipment_id(String(eid))
		var label: String = String(wr.get_display_name(String(eid))) if wr.has_method("get_display_name") else String(eid)
		cells.append({"id": String(eid), "label": label, "tex": tex})
	var img := _compose_sheet(cells, "Equipment Icons")
	var path := "%s/equipment_icons_sheet.png" % OUT_DIR
	var err := img.save_png(path)
	if err != OK:
		_fail("save failed %s" % path)
	else:
		print("[UIIconCapture] wrote %s cells=%d" % [path, cells.size()])
		# sanity: not mostly default-only
		var missing := 0
		for c in cells:
			var t: Texture2D = c["tex"]
			if t == null:
				missing += 1
		if missing > 0:
			print("[UIIconCapture] WARNING missing textures: %d" % missing)


func _capture_material_icons() -> void:
	var ids: Array[String] = [
		"rat_tail", "moldy_bread", "rusty_nail", "dungeon_moss", "bone_shard",
		"blackberry", "glowshroom", "moongrass", "goblin_nail", "mistflower",
		"soul_gem", "dragon_scale", "slime_jelly", "troll_blood", "skeleton_dust",
	]
	var cells: Array = []
	for mid in ids:
		var tex: Texture2D = DETAIL.icon_for_material(mid)
		cells.append({"id": mid, "label": mid, "tex": tex})
	var img := _compose_sheet(cells, "Material Icons")
	var path := "%s/material_icons_sheet.png" % OUT_DIR
	var err := img.save_png(path)
	if err != OK:
		_fail("save failed %s" % path)
	else:
		print("[UIIconCapture] wrote %s" % path)


func _capture_loot_panel_like_grid() -> void:
	## Simulate chest loot row: mix of weapons + materials + runes
	var cells: Array = []
	var wr: Node = root.get_node_or_null("WeaponRegistry")
	for eid in ["shortsword", "axe", "greatsword", "shield", "dagger", "staff"]:
		var tex: Texture2D = DETAIL.icon_for_equipment_id(eid)
		var display_name: String = eid
		if wr != null and wr.has_method("get_display_name"):
			display_name = String(wr.call("get_display_name", eid))
		cells.append({"id": eid, "label": display_name, "tex": tex})
	for mid in ["rat_tail", "glowshroom", "goblin_nail"]:
		cells.append({"id": mid, "label": mid, "tex": DETAIL.icon_for_material(mid)})
	for rid in ["ember", "frost"]:
		cells.append({"id": rid, "label": rid, "tex": DETAIL.icon_for_rune(rid)})
	var img := _compose_sheet(cells, "Loot Grid Preview")
	var path := "%s/loot_grid_icons_sheet.png" % OUT_DIR
	var err := img.save_png(path)
	if err != OK:
		_fail("save failed %s" % path)
	else:
		print("[UIIconCapture] wrote %s" % path)


func _compose_sheet(cells: Array, title: String) -> Image:
	var rows := ceili(float(cells.size()) / float(COLS))
	var cell_w := ICON_SIZE + PAD * 2
	var cell_h := ICON_SIZE + 28
	var width := COLS * cell_w + PAD * 2
	var height := rows * cell_h + 40 + PAD
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.11, 0.13, 1.0))

	# title bar
	_fill_rect(img, Rect2i(0, 0, width, 32), Color(0.16, 0.17, 0.20, 1.0))

	var i := 0
	for cell in cells:
		var col := i % COLS
		var row := i / COLS
		var x := PAD + col * cell_w
		var y := 40 + row * cell_h
		_fill_rect(img, Rect2i(x, y, cell_w - PAD, cell_h - PAD), Color(0.14, 0.15, 0.17, 1.0))
		var tex: Texture2D = cell.get("tex")
		if tex != null:
			var src := tex.get_image()
			if src != null:
				if src.get_format() != Image.FORMAT_RGBA8:
					src.convert(Image.FORMAT_RGBA8)
				var scaled := src.duplicate()
				scaled.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
				var ix := x + (cell_w - PAD - ICON_SIZE) / 2
				var iy := y + 4
				img.blit_rect(scaled, Rect2i(0, 0, ICON_SIZE, ICON_SIZE), Vector2i(ix, iy))
		else:
			_fill_rect(img, Rect2i(x + 12, y + 12, ICON_SIZE - 8, ICON_SIZE - 8), Color(0.5, 0.15, 0.15, 1.0))
		i += 1
	# note: Godot Image has no text draw; titles are in filename. Mark non-null count via corner pixel pattern
	img.set_pixel(2, 2, Color(0.2, 0.9, 0.4, 1.0) if cells.size() > 0 else Color(0.9, 0.2, 0.2, 1.0))
	return img


func _fill_rect(img: Image, rect: Rect2i, color: Color) -> void:
	for yy in range(rect.position.y, rect.position.y + rect.size.y):
		for xx in range(rect.position.x, rect.position.x + rect.size.x):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
				img.set_pixel(xx, yy, color)


func _fail(msg: String) -> void:
	printerr("[UIIconCapture] ", msg)
	_had_error = true
