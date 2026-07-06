extends SceneTree
## Deterministic 64x64 pixel-art icon generator for skills and runes.

const SD := preload("res://globals/combat/skill_data.gd")
const AS := preload("res://globals/combat/action_skills.gd")
const RD := preload("res://globals/combat/rune_data.gd")

const ICON_SIZE := 64
const SKILL_ICON_DIR := "res://assets/textures/icons/skills"
const RUNE_ICON_DIR := "res://assets/textures/icons/runes"

const SCHOOL_COLORS := {
	SD.School.ONE_HAND_SWORD: Color8(168, 70, 44),
	SD.School.TWO_HAND_SWORD: Color8(124, 48, 52),
	SD.School.TWO_HAND_AXE: Color8(187, 90, 45),
	SD.School.WAR_HAMMER: Color8(182, 130, 55),
	SD.School.SPEAR: Color8(95, 155, 76),
	SD.School.LONGBOW: Color8(58, 142, 95),
	SD.School.LIGHT_CROSSBOW: Color8(54, 145, 140),
	SD.School.ENCHANT_WAND: Color8(58, 128, 175),
	SD.School.GRIMOIRE: Color8(70, 88, 170),
	SD.School.UNARMED: Color8(145, 86, 72),
}

const ATTR_COLORS := {
	"str": Color8(177, 66, 52),
	"dex": Color8(58, 156, 96),
	"agi": Color8(196, 108, 52),
	"con": Color8(184, 145, 62),
	"per": Color8(56, 150, 146),
	"mag": Color8(75, 105, 184),
}

const RUNE_COLORS := {
	"ember": Color8(224, 88, 46),
	"quick": Color8(71, 191, 122),
	"force": Color8(222, 170, 69),
	"surge": Color8(73, 162, 222),
	"launch": Color8(204, 126, 64),
	"echo": Color8(106, 110, 214),
	"guardian": Color8(77, 164, 188),
}

func _initialize() -> void:
	_ensure_dir(SKILL_ICON_DIR)
	_ensure_dir(RUNE_ICON_DIR)
	_generate_skill_icons()
	_generate_rune_icons()
	print("Generated pixel icons: %d skills, %d runes" % [SD.SKILLS.size() + AS.SKILLS.size() + SD.ATTR_MILESTONES.size(), RD.get_all_rune_ids().size()])
	quit(0)

func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

func _generate_skill_icons() -> void:
	for skill in SD.SKILLS:
		var img := _new_icon()
		_draw_skill_background(img, SCHOOL_COLORS.get(skill.school, Color8(120, 120, 120)))
		_draw_school_symbol(img, int(skill.school), Color8(242, 232, 203))
		_draw_tier_marks(img, int(skill.tier), Color8(255, 224, 116))
		_draw_skill_hash_marks(img, String(skill.id))
		_save_icon(img, _skill_icon_path(String(skill.id)))
	for skill in AS.SKILLS:
		var img := _new_icon()
		_draw_skill_background(img, Color8(196, 91, 48))
		_draw_action_symbol(img, String(skill.id), Color8(245, 237, 214))
		_draw_skill_hash_marks(img, String(skill.id))
		_save_icon(img, _skill_icon_path(String(skill.id)))
	for milestone in SD.ATTR_MILESTONES:
		var img := _new_icon()
		var attr := String(milestone.attr)
		_draw_skill_background(img, Color8(47, 49, 57))
		_draw_passive_symbol(img, attr, ATTR_COLORS.get(attr, Color8(150, 150, 150)))
		_draw_skill_hash_marks(img, String(milestone.id))
		_save_icon(img, _skill_icon_path(String(milestone.id)))

func _generate_rune_icons() -> void:
	for raw_id in RD.get_all_rune_ids():
		var rune_id := String(raw_id)
		var img := _new_icon()
		var glow: Color = RUNE_COLORS.get(rune_id, Color8(160, 160, 160))
		_draw_rune_stone(img, glow)
		_draw_rune_glyph(img, rune_id, glow.lightened(0.35))
		_save_icon(img, "%s/%s.png" % [RUNE_ICON_DIR, rune_id])

func _new_icon() -> Image:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _save_icon(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Failed to save icon %s: %s" % [path, err])

func _skill_icon_path(skill_id: String) -> String:
	return "%s/skill_%s.png" % [SKILL_ICON_DIR, skill_id.to_utf8_buffer().hex_encode()]

func _draw_skill_background(img: Image, base: Color) -> void:
	_fill_rect(img, 7, 7, 50, 50, Color8(30, 24, 24))
	_fill_rect(img, 9, 9, 46, 46, base.darkened(0.35))
	_fill_rect(img, 11, 11, 42, 42, base)
	for y in range(13, 53, 6):
		for x in range(13, 53, 6):
			if ((x + y) / 6) % 2 == 0:
				_fill_rect(img, x, y, 3, 3, base.lightened(0.12))
	_draw_rect(img, 8, 8, 48, 48, Color8(12, 11, 13))
	_draw_rect(img, 10, 10, 44, 44, Color8(237, 201, 121))
	_set_pixel_safe(img, 9, 9, Color8(255, 238, 172))
	_set_pixel_safe(img, 54, 9, Color8(255, 238, 172))
	_set_pixel_safe(img, 9, 54, Color8(78, 55, 38))
	_set_pixel_safe(img, 54, 54, Color8(78, 55, 38))

func _draw_school_symbol(img: Image, school: int, col: Color) -> void:
	match school:
		SD.School.ONE_HAND_SWORD:
			_line_w(img, 22, 43, 42, 18, col, 3)
			_line_w(img, 20, 38, 30, 46, Color8(67, 44, 36), 3)
			_fill_rect(img, 18, 42, 8, 5, Color8(97, 62, 39))
		SD.School.TWO_HAND_SWORD:
			_line_w(img, 32, 16, 32, 44, col, 4)
			_line_w(img, 24, 36, 40, 36, Color8(75, 48, 37), 3)
			_fill_rect(img, 29, 43, 7, 8, Color8(105, 65, 42))
		SD.School.TWO_HAND_AXE:
			_line_w(img, 24, 46, 38, 18, Color8(91, 58, 38), 3)
			_fill_triangle(img, 34, 17, 48, 25, 34, 32, col)
			_fill_triangle(img, 33, 18, 22, 25, 34, 31, col.darkened(0.1))
		SD.School.WAR_HAMMER:
			_line_w(img, 26, 45, 39, 24, Color8(92, 59, 38), 4)
			_fill_rect(img, 29, 18, 22, 10, col)
			_fill_rect(img, 27, 20, 4, 6, col.darkened(0.25))
		SD.School.SPEAR:
			_line_w(img, 32, 47, 32, 23, Color8(92, 59, 38), 3)
			_fill_triangle(img, 32, 13, 24, 27, 40, 27, col)
			_line_w(img, 25, 35, 39, 35, Color8(72, 47, 35), 2)
		SD.School.LONGBOW:
			_line_w(img, 39, 15, 27, 31, col, 3)
			_line_w(img, 27, 31, 39, 48, col, 3)
			_line_w(img, 39, 15, 39, 48, Color8(241, 231, 205), 1)
			_line_w(img, 18, 32, 36, 32, Color8(241, 231, 205), 2)
		SD.School.LIGHT_CROSSBOW:
			_line_w(img, 17, 27, 47, 27, col, 3)
			_line_w(img, 23, 21, 41, 33, col.darkened(0.15), 3)
			_line_w(img, 32, 24, 32, 46, Color8(95, 61, 39), 4)
			_line_w(img, 22, 36, 42, 36, Color8(241, 231, 205), 2)
		SD.School.ENCHANT_WAND:
			_line_w(img, 22, 44, 42, 22, Color8(101, 63, 43), 3)
			_fill_rect(img, 39, 18, 6, 6, col)
			_line_w(img, 46, 17, 50, 13, Color8(252, 232, 122), 1)
			_line_w(img, 45, 26, 51, 30, Color8(252, 232, 122), 1)
		SD.School.GRIMOIRE:
			_fill_rect(img, 20, 19, 24, 29, col.darkened(0.15))
			_draw_rect(img, 20, 19, 24, 29, Color8(236, 218, 177))
			_line_w(img, 32, 20, 32, 47, Color8(236, 218, 177), 1)
			_fill_rect(img, 35, 31, 5, 5, Color8(235, 191, 92))
		SD.School.UNARMED:
			_fill_rect(img, 22, 25, 19, 18, col)
			_fill_rect(img, 20, 27, 5, 12, col.darkened(0.15))
			_fill_rect(img, 23, 19, 4, 9, col.lightened(0.05))
			_fill_rect(img, 29, 18, 4, 10, col.lightened(0.05))
			_fill_rect(img, 35, 20, 4, 8, col.lightened(0.05))

func _draw_action_symbol(img: Image, skill_id: String, col: Color) -> void:
	match skill_id:
		"踢击":
			_fill_rect(img, 26, 18, 8, 8, col)
			_line_w(img, 30, 27, 30, 40, col, 4)
			_line_w(img, 31, 39, 46, 45, col, 4)
		"冲撞":
			_fill_rect(img, 18, 24, 18, 16, col)
			_fill_triangle(img, 36, 20, 50, 32, 36, 44, col)
			_line_w(img, 15, 32, 9, 32, Color8(255, 220, 106), 2)
		"抓取投掷":
			_line_w(img, 21, 42, 35, 26, col, 4)
			_line_w(img, 35, 26, 48, 21, col, 3)
			_fill_rect(img, 44, 17, 7, 7, Color8(255, 220, 106))
		"滑铲":
			_line_w(img, 17, 43, 45, 43, col, 4)
			_line_w(img, 24, 35, 39, 43, col, 4)
			_fill_rect(img, 19, 27, 8, 8, col)
		"战术滑步":
			_fill_triangle(img, 19, 32, 34, 20, 34, 44, col)
			_fill_triangle(img, 34, 32, 48, 22, 48, 42, col.lightened(0.1))
			_line_w(img, 14, 48, 50, 48, Color8(255, 220, 106), 2)
		_:
			_fill_rect(img, 24, 24, 16, 16, col)

func _draw_passive_symbol(img: Image, attr: String, col: Color) -> void:
	_draw_rect(img, 18, 18, 28, 28, col)
	_draw_rect(img, 22, 22, 20, 20, col.lightened(0.25))
	match attr:
		"str":
			_line_w(img, 22, 42, 42, 22, col.lightened(0.5), 4)
		"dex":
			_line_w(img, 20, 34, 44, 24, col.lightened(0.5), 3)
			_fill_triangle(img, 44, 24, 38, 20, 39, 29, col.lightened(0.5))
		"agi":
			_line_w(img, 21, 43, 43, 21, col.lightened(0.5), 2)
			_line_w(img, 28, 43, 45, 26, col.lightened(0.35), 2)
		"con":
			_fill_rect(img, 25, 24, 14, 18, col.lightened(0.45))
			_draw_rect(img, 25, 24, 14, 18, Color8(39, 37, 34))
		"per":
			_draw_rect(img, 23, 26, 18, 12, col.lightened(0.45))
			_fill_rect(img, 30, 29, 4, 4, col.darkened(0.5))
		"mag":
			_fill_triangle(img, 32, 20, 21, 41, 43, 41, col.lightened(0.45))
		_:
			_fill_rect(img, 26, 26, 12, 12, col.lightened(0.35))

func _draw_tier_marks(img: Image, tier: int, col: Color) -> void:
	for i in range(tier + 1):
		var x := 17 + i * 7
		_fill_rect(img, x, 51, 4, 4, Color8(47, 33, 24))
		_fill_rect(img, x + 1, 50, 3, 3, col)

func _draw_skill_hash_marks(img: Image, skill_id: String) -> void:
	var bytes := skill_id.to_utf8_buffer()
	for i in range(min(4, bytes.size())):
		var value := int(bytes[i])
		var x := 13 + (value % 7) * 5
		var y := 13 + (int(value / 7) % 7) * 5
		_fill_rect(img, x, y, 2, 2, Color(1, 1, 1, 0.36))

func _draw_rune_stone(img: Image, glow: Color) -> void:
	_fill_rect(img, 13, 9, 38, 46, Color8(20, 18, 21))
	_fill_rect(img, 15, 11, 34, 42, Color8(74, 70, 76))
	_fill_rect(img, 18, 14, 28, 36, Color8(104, 100, 104))
	_draw_rect(img, 15, 11, 34, 42, glow.darkened(0.2))
	_draw_rect(img, 18, 14, 28, 36, glow.lightened(0.2))
	_set_pixel_safe(img, 20, 17, Color8(148, 144, 145))
	_set_pixel_safe(img, 43, 47, Color8(48, 45, 49))
	_fill_rect(img, 11, 31, 3, 8, glow.darkened(0.25))
	_fill_rect(img, 50, 25, 3, 8, glow.darkened(0.25))

func _draw_rune_glyph(img: Image, rune_id: String, col: Color) -> void:
	match rune_id:
		"ember":
			_line_w(img, 26, 43, 26, 20, col, 3)
			_line_w(img, 26, 24, 39, 18, col, 2)
			_line_w(img, 26, 32, 38, 28, col, 2)
			_line_w(img, 26, 40, 39, 45, col, 2)
		"quick":
			_line_w(img, 25, 43, 25, 20, col, 3)
			_line_w(img, 25, 31, 40, 20, col, 2)
			_line_w(img, 25, 31, 41, 43, col, 2)
		"force":
			_line_w(img, 26, 44, 26, 19, col, 3)
			_line_w(img, 26, 21, 41, 27, col, 2)
			_line_w(img, 26, 32, 39, 36, col, 2)
		"surge":
			_line_w(img, 24, 43, 36, 19, col, 3)
			_line_w(img, 36, 19, 43, 31, col, 2)
			_line_w(img, 28, 33, 40, 42, col, 2)
		"launch":
			_line_w(img, 25, 44, 25, 20, col, 3)
			_line_w(img, 25, 20, 39, 20, col, 2)
			_line_w(img, 39, 20, 45, 30, col, 2)
			_line_w(img, 25, 33, 40, 43, col, 2)
		"echo":
			_line_w(img, 32, 18, 43, 31, col, 2)
			_line_w(img, 43, 31, 32, 46, col, 2)
			_line_w(img, 32, 46, 21, 31, col, 2)
			_line_w(img, 21, 31, 32, 18, col, 2)
			_fill_rect(img, 30, 29, 5, 5, col.lightened(0.2))
		"guardian":
			_line_w(img, 32, 44, 32, 18, col, 3)
			_line_w(img, 32, 31, 22, 21, col, 2)
			_line_w(img, 32, 31, 42, 21, col, 2)
			_line_w(img, 32, 31, 23, 42, col, 2)
			_line_w(img, 32, 31, 41, 42, col, 2)
		_:
			_line_w(img, 32, 44, 32, 20, col, 3)

func _fill_rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_set_pixel_safe(img, x, y, col)

func _draw_rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	_line_w(img, x0, y0, x0 + w - 1, y0, col, 1)
	_line_w(img, x0, y0 + h - 1, x0 + w - 1, y0 + h - 1, col, 1)
	_line_w(img, x0, y0, x0, y0 + h - 1, col, 1)
	_line_w(img, x0 + w - 1, y0, x0 + w - 1, y0 + h - 1, col, 1)

func _fill_triangle(img: Image, x1: int, y1: int, x2: int, y2: int, x3: int, y3: int, col: Color) -> void:
	var min_x: int = min(x1, min(x2, x3))
	var max_x: int = max(x1, max(x2, x3))
	var min_y: int = min(y1, min(y2, y3))
	var max_y: int = max(y1, max(y2, y3))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _point_in_triangle(x, y, x1, y1, x2, y2, x3, y3):
				_set_pixel_safe(img, x, y, col)

func _point_in_triangle(px: int, py: int, x1: int, y1: int, x2: int, y2: int, x3: int, y3: int) -> bool:
	var d1: float = (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)
	var d2: float = (px - x3) * (y2 - y3) - (x2 - x3) * (py - y3)
	var d3: float = (px - x1) * (y3 - y1) - (x3 - x1) * (py - y1)
	var has_neg: bool = (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos: bool = (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)

func _line_w(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color, width: int) -> void:
	var half := int(width / 2)
	for oy in range(-half, half + 1):
		for ox in range(-half, half + 1):
			_line(img, x0 + ox, y0 + oy, x1 + ox, y1 + oy, col)

func _line(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	var dx: int = abs(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -abs(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		_set_pixel_safe(img, x0, y0, col)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

func _set_pixel_safe(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
		img.set_pixel(x, y, col)
