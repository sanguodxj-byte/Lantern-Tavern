extends SceneTree
## Render a standalone visual QA sheet for the four HUD resource bar states.

const OUT_PATH := "res://reports/ui_preview/resource_bars_1280x720.png"
const PixelBarScript := preload("res://scenes/ui/pixel_bar.gd")
const ShieldBarScript := preload("res://scenes/ui/shield_bar.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("#0C0D12")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(background)
	var panel := ColorRect.new()
	panel.color = Color("#171820")
	panel.position = Vector2(64, 54)
	panel.size = Vector2(730, 348)
	viewport.add_child(panel)
	var title := Label.new()
	title.position = Vector2(86, 70)
	title.text = "RESOURCE INSTRUMENTS"
	title.add_theme_font_override("font", load("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf"))
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#E9C57A"))
	viewport.add_child(title)
	_add_bar(viewport, PixelBarScript.BarKind.HEALTH, 227, 310, 420)
	_add_bar(viewport, PixelBarScript.BarKind.MANA, 275, 187, 260)
	_add_shield(viewport, ShieldBarScript.ShieldType.PHYSICAL, 323, 98, 140)
	_add_shield(viewport, ShieldBarScript.ShieldType.MAGIC, 371, 73, 120)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/ui_preview"))
	var err := image.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("[ResourceBarPreview] %s" % ("wrote %s" % OUT_PATH if err == OK else "FAILED"))
	quit(0 if err == OK else 1)


func _add_bar(viewport: SubViewport, kind: int, y: float, current: int, maximum: int) -> void:
	var bar: PixelBar = PixelBarScript.new()
	bar.bar_kind = kind
	bar.label_text = "HP" if kind == PixelBarScript.BarKind.HEALTH else "MP"
	bar.position = Vector2(92, y)
	bar.size = PixelBar.BAR_SIZE
	viewport.add_child(bar)
	bar.set_values(current, maximum)


func _add_shield(viewport: SubViewport, kind: int, y: float, current: int, maximum: int) -> void:
	var bar = ShieldBarScript.new()
	bar.shield_type = kind
	bar.position = Vector2(92, y)
	bar.size = ShieldBarScript.BAR_SIZE
	viewport.add_child(bar)
	bar.set_values(current, maximum)
	bar._fade_t = 1.0
