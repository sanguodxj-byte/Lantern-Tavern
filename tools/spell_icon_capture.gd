extends SceneTree
const OUT := "res://reports/ui_preview/spell_codex_128px.png"
const RECIPES := preload("res://globals/combat/spell_recipe_data.gd")
const GLYPHS := preload("res://data/spell_glyphs.gd")
const ICON := 128
const PAD := 10
const COLS := 6

func _init() -> void: call_deferred("_run")
func _run() -> void:
	var spells := RECIPES.get_all_recipes()
	spells.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	var rows := ceili(float(spells.size()) / COLS)
	var cw := ICON + PAD * 2; var ch := ICON + 26
	var img := Image.create(COLS * cw + PAD * 2, rows * ch + 50, false, Image.FORMAT_RGBA8)
	img.fill(Color("#101218"))
	for index in spells.size():
		var col := index % COLS; var row := index / COLS
		var x := PAD + col * cw; var y := 40 + row * ch
		_fill(img, Rect2i(x, y, cw - PAD, ch - PAD), Color("#191C25"))
		var src := GLYPHS.get_texture(String(spells[index].id)).get_image()
		img.blit_rect(src, Rect2i(0, 0, ICON, ICON), Vector2i(x + 5, y + 4))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/ui_preview"))
	var err := img.save_png(ProjectSettings.globalize_path(OUT))
	print("[SpellCodex] wrote %s cells=%d" % [OUT, spells.size()])
	quit(0 if err == OK else 1)
func _fill(img: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x): img.set_pixel(x, y, color)
