extends Node
## 技能图标程序化生成器。
## 启动时按 流派色相 + Tier 几何形状 为每个技能生成 64x64 ImageTexture，
## 存入缓存字典，供 skill_bar.gd 查表显示。
##
## 视觉编码：
## - 武器主动技能：流派色相背景圆 + Tier 几何（T1=小方/ T2=三角/ T3=星形）
## - 动作技能（F 槽）：橙色背景圆 + 白色人形剪影
## - 被动里程碑：深灰背景圆 + 流派色相描边

const SD := preload("res://globals/skill_data.gd")
const AS := preload("res://globals/action_skills.gd")

const ICON_SIZE: int = 64

# 10 流派色相（HSV hue 0~1）
const SCHOOL_HUE: Dictionary = {
	SD.School.ONE_HAND_SWORD: 0.08,   # 赭红
	SD.School.TWO_HAND_SWORD: 0.02,   # 暗红
	SD.School.TWO_HAND_AXE: 0.10,     # 橙红
	SD.School.WAR_HAMMER: 0.13,       # 橙黄
	SD.School.SPEAR: 0.33,            # 黄绿
	SD.School.LONGBOW: 0.45,          # 翠绿
	SD.School.LIGHT_CROSSBOW: 0.55,   # 青绿
	SD.School.ENCHANT_WAND: 0.60,     # 青蓝
	SD.School.GRIMOIRE: 0.70,         # 蓝
	SD.School.UNARMED: 0.00,          # 中性灰红
}

# 动作技能色相（橙）
const ACTION_HUE: float = 0.08
# 被动里程碑色相（深灰，描边用流派色）
const PASSIVE_BG_HUE: float = 0.0
const PASSIVE_BG_SAT: float = 0.0
const PASSIVE_BG_VAL: float = 0.25

# 6 主属性 → 流派色相映射（被动描边用）
const ATTR_HUE: Dictionary = {
	"str": 0.05,   # 力量 → 赭红
	"dex": 0.45,   # 敏捷 → 翠绿
	"agi": 0.10,   # 灵巧 → 橙红
	"con": 0.13,   # 体质 → 橙黄
	"per": 0.55,   # 感知 → 青绿
	"mag": 0.65,   # 魔力 → 蓝
}

var _cache: Dictionary = {}

func _ready() -> void:
	_build_all()

## 全量生成并缓存
func _build_all() -> void:
	# 30 武器技能
	for skill in SD.SKILLS:
		var tex: Texture2D = _make_weapon_icon(skill.school, skill.tier)
		_cache[skill.id] = tex
	# 5 动作技能
	for skill in AS.SKILLS:
		var tex: Texture2D = _make_action_icon()
		_cache[skill.id] = tex
	# 18 里程碑被动（按主属性映射描边色相）
	for ms in SD.ATTR_MILESTONES:
		var tex: Texture2D = _make_passive_icon(ms.attr)
		_cache[ms.id] = tex

## 查表：返回技能图标纹理，未命中返回占位灰
func get_icon(skill_id: String) -> Texture2D:
	if _cache.has(skill_id):
		return _cache[skill_id]
	return _make_placeholder()

# ===== 生成器 =====

func _make_weapon_icon(school: int, tier: int) -> Texture2D:
	var hue: float = SCHOOL_HUE.get(school, 0.0)
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	# 背景圆（流派色相）
	_fill_circle(img, ICON_SIZE / 2, ICON_SIZE / 2, ICON_SIZE / 2 - 2, Color.from_hsv(hue, 0.6, 0.7, 1.0))
	# Tier 几何（白色）
	var center: int = ICON_SIZE / 2
	match tier:
		SD.SkillTier.T1:
			_fill_rect(img, center - 8, center - 8, 16, 16, Color(1, 1, 1, 0.9))
		SD.SkillTier.T2:
			_fill_triangle(img, center, center - 10, center - 10, center + 8, center + 10, center + 8, Color(1, 1, 1, 0.9))
		SD.SkillTier.T3:
			_fill_star(img, center, center, 10, 5, Color(1, 1, 1, 0.95))
	var tex := ImageTexture.create_from_image(img)
	return tex

func _make_action_icon() -> Texture2D:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	_fill_circle(img, ICON_SIZE / 2, ICON_SIZE / 2, ICON_SIZE / 2 - 2, Color.from_hsv(ACTION_HUE, 0.7, 0.85, 1.0))
	# 白色人形剪影（简化：头圆 + 身体矩形）
	var c: int = ICON_SIZE / 2
	_fill_circle(img, c, c - 12, 6, Color(1, 1, 1, 0.95))
	_fill_rect(img, c - 5, c - 4, 10, 18, Color(1, 1, 1, 0.95))
	return ImageTexture.create_from_image(img)

func _make_passive_icon(attr: String) -> Texture2D:
	var hue: float = ATTR_HUE.get(attr, 0.0)
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	# 深灰背景
	_fill_circle(img, ICON_SIZE / 2, ICON_SIZE / 2, ICON_SIZE / 2 - 2, Color.from_hsv(PASSIVE_BG_HUE, PASSIVE_BG_SAT, PASSIVE_BG_VAL, 1.0))
	# 流派色相描边环
	_draw_ring(img, ICON_SIZE / 2, ICON_SIZE / 2, ICON_SIZE / 2 - 3, ICON_SIZE / 2 - 6, Color.from_hsv(hue, 0.7, 0.9, 1.0))
	# 中心小菱形（白色）
	var c: int = ICON_SIZE / 2
	_fill_triangle(img, c, c - 6, c - 6, c, c, c + 6, Color(1, 1, 1, 0.9))
	_fill_triangle(img, c, c - 6, c + 6, c, c, c + 6, Color(1, 1, 1, 0.9))
	return ImageTexture.create_from_image(img)

func _make_placeholder() -> Texture2D:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	_fill_circle(img, ICON_SIZE / 2, ICON_SIZE / 2, ICON_SIZE / 2 - 2, Color(0.3, 0.3, 0.3, 1.0))
	return ImageTexture.create_from_image(img)

# ===== 像素绘制工具 =====

func _fill_circle(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	var r2: int = r * r
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r2:
				img.set_pixel(cx + x, cy + y, col)

func _draw_ring(img: Image, cx: int, cy: int, r_outer: int, r_inner: int, col: Color) -> void:
	var ro2: int = r_outer * r_outer
	var ri2: int = r_inner * r_inner
	for y in range(-r_outer, r_outer + 1):
		for x in range(-r_outer, r_outer + 1):
			var d2: int = x * x + y * y
			if d2 <= ro2 and d2 >= ri2:
				img.set_pixel(cx + x, cy + y, col)

func _fill_rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
				img.set_pixel(x, y, col)

func _fill_triangle(img: Image, x1: int, y1: int, x2: int, y2: int, x3: int, y3: int, col: Color) -> void:
	var min_x: int = min(x1, min(x2, x3))
	var max_x: int = max(x1, max(x2, x3))
	var min_y: int = min(y1, min(y2, y3))
	var max_y: int = max(y1, max(y2, y3))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _point_in_triangle(x, y, x1, y1, x2, y2, x3, y3):
				if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
					img.set_pixel(x, y, col)

func _fill_star(img: Image, cx: int, cy: int, r_outer: int, r_inner: int, col: Color) -> void:
	# 五角星：10 个顶点交替外/内半径
	var pts: PackedVector2Array = []
	for i in range(10):
		var angle: float = -PI / 2 + i * PI / 5
		var r: int = r_outer if i % 2 == 0 else r_inner
		pts.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
	# 三角扇填充
	for i in range(0, 9, 2):
		var i2: int = i + 1
		var i3: int = i + 2
		if i3 > 9:
			i3 = 0
		_fill_triangle(img, int(pts[i].x), int(pts[i].y), int(pts[i2].x), int(pts[i2].y), int(pts[i3].x), int(pts[i3].y), col)
	# 中心填充
	_fill_circle(img, cx, cy, r_inner - 1, col)

func _point_in_triangle(px: int, py: int, x1: int, y1: int, x2: int, y2: int, x3: int, y3: int) -> bool:
	var d1: float = (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)
	var d2: float = (px - x3) * (y2 - y3) - (x2 - x3) * (py - y3)
	var d3: float = (px - x1) * (y3 - y1) - (x3 - x1) * (py - y1)
	var has_neg: bool = (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos: bool = (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)
