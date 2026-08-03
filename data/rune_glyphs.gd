extends RefCounted
## 128×128 像素符文图标程序化生成器。
##
## 所有图案先写入 32×32 逻辑栅格，再按整数最近邻扩展。这样在
## headless、桌面端和 Android 上均得到完全一致的硬边像素轮廓。

const RD := preload("res://globals/combat/rune_data.gd")

const DEFAULT_SIZE := 128
const LOGICAL_SIZE := 32
const SAFE_MIN := 2
const SAFE_MAX := 29
const OUTLINE := Color("#15171D")

## rune_id|size -> ImageTexture
static var _cache: Dictionary = {}


static func get_texture(rune_id: String, size: int = DEFAULT_SIZE) -> Texture2D:
	if size <= 0:
		size = DEFAULT_SIZE
	var key := "%s|%d" % [rune_id, size]
	if _cache.has(key):
		return _cache[key] as Texture2D
	var logical := _draw_logical_glyph(rune_id)
	var texture := ImageTexture.create_from_image(_expand_nearest(logical, size))
	_cache[key] = texture
	return texture


## 返回 32×32 的逻辑像素图，供测试、调试及图鉴工具使用。
static func get_logical_image(rune_id: String) -> Image:
	return _draw_logical_glyph(rune_id)


## 保留旧调试接口；返回确定性语义描述，而非矢量曲线图元。
static func get_glyph(rune_id: String) -> Array:
	return [
		{"id": rune_id, "family": _family_for(rune_id), "seed": _stable_seed(rune_id)},
	]


static func clear_cache() -> void:
	_cache.clear()


static func _draw_logical_glyph(rune_id: String) -> Image:
	var image := Image.create(LOGICAL_SIZE, LOGICAL_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var main := _color_for(rune_id)
	var highlight := main.lerp(Color.WHITE, 0.42)
	var seed := _stable_seed(rune_id)
	var family := _family_for(rune_id)

	# 先铺卡面背景，主体完成后再压回金属边框，确保边界干净而不抢主体。
	_draw_card_background(image, seed)
	match family:
		"elemental":
			_draw_elemental(image, rune_id, seed, OUTLINE, main, highlight)
		"combat":
			_draw_combat(image, rune_id, seed, OUTLINE, main, highlight)
		"mystic":
			_draw_mystic(image, rune_id, seed, OUTLINE, main, highlight)
		"dark":
			_draw_dark(image, rune_id, seed, OUTLINE, main, highlight)
		"holy":
			_draw_holy(image, rune_id, seed, OUTLINE, main, highlight)
		_:
			_draw_debug_unknown(image, seed, OUTLINE, main, highlight)
	_draw_card_frame(image, family, main, highlight)
	return image


static func _draw_card_background(img: Image, seed: int) -> void:
	var outer := Color("#090B10")
	var metal_dark := Color("#34313A")
	var metal_mid := Color("#77717D")
	var inner_dark := Color("#171820")
	var stone_a := Color("#24242D")
	var stone_b := Color("#2B2934")

	# 切角方牌：四角透明，牌体从坐标 2 开始。
	_fill_raw_rect(img, Rect2i(4, 2, 24, 28), outer)
	_fill_raw_rect(img, Rect2i(2, 4, 28, 24), outer)
	_fill_raw_rect(img, Rect2i(4, 3, 24, 26), metal_dark)
	_fill_raw_rect(img, Rect2i(3, 4, 26, 24), metal_dark)
	_fill_raw_rect(img, Rect2i(5, 4, 22, 24), metal_mid)
	_fill_raw_rect(img, Rect2i(4, 5, 24, 22), metal_mid)
	_fill_raw_rect(img, Rect2i(6, 5, 20, 22), inner_dark)
	_fill_raw_rect(img, Rect2i(5, 6, 22, 20), inner_dark)
	_fill_raw_rect(img, Rect2i(7, 6, 18, 20), stone_a)
	_fill_raw_rect(img, Rect2i(6, 7, 20, 18), stone_a)

	# 低对比度像素砖纹/石纹。只在内场出现，不干扰中心符文。
	for y in range(8, 25):
		for x in range(8, 25):
			var pattern := (x * 7 + y * 11 + seed) % 13
			if pattern == 0 or (pattern == 5 and (x + y) % 2 == 0):
				img.set_pixel(x, y, stone_b)
	for y in [10, 15, 20]:
		var offset := 1 if ((seed + y) % 2 == 0) else 0
		for x in range(8 + offset, 24, 5):
			img.set_pixel(x, y, inner_dark)


static func _draw_card_frame(img: Image, family: String, main: Color, high: Color) -> void:
	var metal_light := Color("#AAA3AE")
	var metal_shadow := Color("#201E26")
	# 上左高光、下右暗边，形成硬边金属厚度。
	_fill_raw_rect(img, Rect2i(6, 4, 20, 1), metal_light)
	_fill_raw_rect(img, Rect2i(4, 6, 1, 20), metal_light)
	_fill_raw_rect(img, Rect2i(6, 27, 20, 1), metal_shadow)
	_fill_raw_rect(img, Rect2i(27, 6, 1, 20), metal_shadow)
	# 四颗家族色铆钉。
	for p in [Vector2i(6, 6), Vector2i(25, 6), Vector2i(6, 25), Vector2i(25, 25)]:
		img.set_pixelv(p, OUTLINE)
		var inset := Vector2i(1 if p.x < 16 else -1, 1 if p.y < 16 else -1)
		img.set_pixelv(p + inset, main)

	match family:
		"elemental":
			# 上下能量刻痕。
			for x in [12, 15, 18]:
				img.set_pixel(x, 4, main)
				img.set_pixel(31 - x, 27, high)
		"combat":
			# 左右刃齿。
			for y in [10, 15, 20]:
				_fill_raw_rect(img, Rect2i(3, y, 3, 2), main)
				_fill_raw_rect(img, Rect2i(26, y, 3, 2), main)
		"mystic":
			# 四向菱形节点。
			for p in [Vector2i(16, 4), Vector2i(27, 16), Vector2i(16, 27), Vector2i(4, 16)]:
				_node_raw(img, p, main, high)
		"dark":
			# 下垂裂角与顶部断口。
			_fill_raw_rect(img, Rect2i(9, 27, 3, 2), main)
			_fill_raw_rect(img, Rect2i(20, 27, 3, 2), main)
			img.set_pixel(15, 4, OUTLINE)
			img.set_pixel(16, 5, main)
		"holy":
			# 上冠与底部封印。
			_stroke_raw(img, [Vector2i(11, 5), Vector2i(16, 2), Vector2i(21, 5)], OUTLINE, high)
			_fill_raw_rect(img, Rect2i(12, 27, 8, 2), main)
		_:
			_fill_raw_rect(img, Rect2i(14, 4, 4, 1), main)


static func _node_raw(img: Image, center: Vector2i, main: Color, high: Color) -> void:
	img.set_pixelv(center, high)
	for p in [center + Vector2i(-1, 0), center + Vector2i(1, 0), center + Vector2i(0, -1), center + Vector2i(0, 1)]:
		if p.x >= 0 and p.y >= 0 and p.x < LOGICAL_SIZE and p.y < LOGICAL_SIZE:
			img.set_pixelv(p, main)


static func _stroke_raw(img: Image, points: Array[Vector2i], edge: Color, main: Color) -> void:
	for i in range(points.size() - 1):
		_draw_line_raw(img, points[i], points[i + 1], edge, 3)
	for i in range(points.size() - 1):
		_draw_line_raw(img, points[i], points[i + 1], main, 1)


static func _draw_elemental(img: Image, rune_id: String, seed: int, edge: Color, main: Color, high: Color) -> void:
	# 流动/喷发的中轴；火、雷等少数符文覆盖为更直接的语义轮廓。
	match rune_id:
		"ember", "tejas":
			_stroke(img, [Vector2i(16, 27), Vector2i(11, 21), Vector2i(16, 15), Vector2i(13, 9), Vector2i(20, 5)], edge, main)
			_stroke(img, [Vector2i(16, 23), Vector2i(21, 18), Vector2i(18, 12)], edge, main)
		"hima":
			_stroke(img, [Vector2i(16, 5), Vector2i(16, 27)], edge, main)
			_stroke(img, [Vector2i(7, 16), Vector2i(25, 16)], edge, main)
			_stroke(img, [Vector2i(10, 10), Vector2i(22, 22)], edge, main)
			_stroke(img, [Vector2i(22, 10), Vector2i(10, 22)], edge, main)
		"vajra":
			_stroke(img, [Vector2i(18, 4), Vector2i(12, 15), Vector2i(18, 15), Vector2i(13, 28)], edge, main)
			_stroke(img, [Vector2i(12, 15), Vector2i(9, 12)], edge, main)
		"visha":
			_stroke(img, [Vector2i(16, 5), Vector2i(11, 11), Vector2i(18, 17), Vector2i(13, 24), Vector2i(16, 28)], edge, main)
			_node(img, Vector2i(21, 9), edge, main)
		"jala", "pavana":
			_stroke(img, [Vector2i(8, 10), Vector2i(14, 7), Vector2i(20, 11), Vector2i(15, 16), Vector2i(9, 21), Vector2i(16, 25), Vector2i(23, 20)], edge, main)
		"bhumi", "kardama":
			_stroke(img, [Vector2i(16, 5), Vector2i(16, 25), Vector2i(9, 25), Vector2i(6, 28)], edge, main)
			_stroke(img, [Vector2i(16, 18), Vector2i(23, 23), Vector2i(23, 27)], edge, main)
		"krishna", "dhuma":
			_stroke(img, [Vector2i(20, 5), Vector2i(12, 11), Vector2i(19, 17), Vector2i(11, 25)], edge, main)
			_stroke(img, [Vector2i(12, 11), Vector2i(8, 7)], edge, main)
		_:
			_stroke(img, [Vector2i(16, 5), Vector2i(16, 27)], edge, main)
			_stroke(img, [Vector2i(16, 12), Vector2i(8 + (seed % 4), 8)], edge, main)
			_stroke(img, [Vector2i(16, 19), Vector2i(23 - (seed % 4), 15)], edge, main)
	_highlight_tip(img, Vector2i(16, 5), high)


static func _draw_combat(img: Image, rune_id: String, seed: int, edge: Color, main: Color, high: Color) -> void:
	var tip_x := 22 if seed % 2 == 0 else 10
	_stroke(img, [Vector2i(7 if tip_x == 22 else 25, 24), Vector2i(tip_x, 16), Vector2i(7 if tip_x == 22 else 25, 8)], edge, main)
	_stroke(img, [Vector2i(6, 16), Vector2i(26, 16)], edge, main)
	match rune_id:
		"guardian":
			_stroke(img, [Vector2i(16, 5), Vector2i(9, 10), Vector2i(9, 22), Vector2i(16, 28), Vector2i(23, 22), Vector2i(23, 10), Vector2i(16, 5)], edge, main)
		"quick", "praghana":
			_stroke(img, [Vector2i(7, 11), Vector2i(20, 11), Vector2i(25, 16), Vector2i(20, 21), Vector2i(7, 21)], edge, main)
		"para", "bhedana":
			_stroke(img, [Vector2i(8, 27), Vector2i(22, 7)], edge, main)
			_stroke(img, [Vector2i(14, 7), Vector2i(22, 7), Vector2i(22, 15)], edge, main)
		"echo":
			_stroke(img, [Vector2i(8, 10), Vector2i(16, 5), Vector2i(24, 10)], edge, main)
			_stroke(img, [Vector2i(8, 17), Vector2i(16, 12), Vector2i(24, 17)], edge, main)
	_highlight_tip(img, Vector2i(tip_x, 16), high)


static func _draw_mystic(img: Image, rune_id: String, seed: int, edge: Color, main: Color, high: Color) -> void:
	# 菱形核心与四向支路；不使用连续圆，避免被缩小为平滑徽章。
	_stroke(img, [Vector2i(16, 6), Vector2i(24, 16), Vector2i(16, 26), Vector2i(8, 16), Vector2i(16, 6)], edge, main)
	match rune_id:
		"ayu", "prana":
			_stroke(img, [Vector2i(16, 9), Vector2i(16, 23)], edge, main)
			_stroke(img, [Vector2i(11, 16), Vector2i(21, 16)], edge, main)
		"maya":
			_stroke(img, [Vector2i(8, 10), Vector2i(16, 5), Vector2i(24, 10)], edge, main)
			_stroke(img, [Vector2i(8, 22), Vector2i(16, 27), Vector2i(24, 22)], edge, main)
		"yantra":
			_node(img, Vector2i(16, 16), edge, main)
			_node(img, Vector2i(9, 9), edge, main)
			_node(img, Vector2i(23, 23), edge, main)
		"mantra", "chitta":
			_stroke(img, [Vector2i(10, 16), Vector2i(16, 10), Vector2i(22, 16), Vector2i(16, 22), Vector2i(10, 16)], edge, main)
		_:
			_stroke(img, [Vector2i(16, 6), Vector2i(16 + (seed % 5) - 2, 2)], edge, main)
	_highlight_tip(img, Vector2i(16, 6), high)


static func _draw_dark(img: Image, rune_id: String, seed: int, edge: Color, main: Color, high: Color) -> void:
	# 下坠裂口与内收钩，强调负空间和不稳定感。
	_stroke(img, [Vector2i(10, 5), Vector2i(18, 11), Vector2i(13, 17), Vector2i(21, 23), Vector2i(16, 28)], edge, main)
	_stroke(img, [Vector2i(23, 7), Vector2i(18, 11), Vector2i(25, 15)], edge, main)
	match rune_id:
		"kala":
			_stroke(img, [Vector2i(8, 21), Vector2i(8, 12), Vector2i(16, 7), Vector2i(24, 12), Vector2i(24, 21)], edge, main)
		"mrityu":
			_stroke(img, [Vector2i(16, 5), Vector2i(16, 27)], edge, main)
			_stroke(img, [Vector2i(10, 13), Vector2i(22, 13)], edge, main)
		"bhaya", "ghora":
			_stroke(img, [Vector2i(8, 10), Vector2i(8, 24), Vector2i(16, 28), Vector2i(24, 24), Vector2i(24, 10)], edge, main)
	_highlight_tip(img, Vector2i(10, 5), high)


static func _draw_holy(img: Image, rune_id: String, seed: int, edge: Color, main: Color, high: Color) -> void:
	_stroke(img, [Vector2i(16, 27), Vector2i(16, 7)], edge, main)
	_stroke(img, [Vector2i(8, 14), Vector2i(16, 7), Vector2i(24, 14)], edge, main)
	match rune_id:
		"dipa":
			_stroke(img, [Vector2i(12, 24), Vector2i(16, 19), Vector2i(20, 24)], edge, main)
		"moksha":
			_stroke(img, [Vector2i(9, 21), Vector2i(9, 25), Vector2i(16, 29), Vector2i(23, 25), Vector2i(23, 21)], edge, main)
		"amrita":
			_stroke(img, [Vector2i(9, 20), Vector2i(16, 25), Vector2i(23, 20)], edge, main)
		"siddhi":
			_stroke(img, [Vector2i(9, 11), Vector2i(16, 4), Vector2i(23, 11)], edge, main)
	_highlight_tip(img, Vector2i(16, 7), high)


static func _draw_debug_unknown(img: Image, seed: int, edge: Color, main: Color, high: Color) -> void:
	_stroke(img, [Vector2i(8, 8), Vector2i(24, 8), Vector2i(24, 24), Vector2i(8, 24), Vector2i(8, 8)], edge, main)
	_stroke(img, [Vector2i(10, 22), Vector2i(22, 10)], edge, main)
	_highlight_tip(img, Vector2i(10 + seed % 10, 8), high)


static func _stroke(img: Image, points: Array[Vector2i], edge: Color, main: Color) -> void:
	for i in range(points.size() - 1):
		_draw_line(img, points[i], points[i + 1], edge, 4)
	for i in range(points.size() - 1):
		_draw_line(img, points[i], points[i + 1], main, 2)


static func _node(img: Image, center: Vector2i, edge: Color, main: Color) -> void:
	_fill_rect(img, Rect2i(center - Vector2i(2, 2), Vector2i(5, 5)), edge)
	_fill_rect(img, Rect2i(center - Vector2i(1, 1), Vector2i(3, 3)), main)


static func _highlight_tip(img: Image, pos: Vector2i, high: Color) -> void:
	if pos.x >= SAFE_MIN and pos.x <= SAFE_MAX and pos.y >= SAFE_MIN and pos.y <= SAFE_MAX:
		img.set_pixelv(pos, high)


static func _draw_line(img: Image, a: Vector2i, b: Vector2i, color: Color, width: int) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var point := a
	while true:
		_fill_rect(img, Rect2i(point - Vector2i(width / 2, width / 2), Vector2i(width, width)), color)
		if point == b:
			break
		var twice_error := 2 * err
		if twice_error >= dy:
			err += dy
			point.x += sx
		if twice_error <= dx:
			err += dx
			point.y += sy


static func _draw_line_raw(img: Image, a: Vector2i, b: Vector2i, color: Color, width: int) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var point := a
	while true:
		_fill_raw_rect(img, Rect2i(point - Vector2i(width / 2, width / 2), Vector2i(width, width)), color)
		if point == b:
			break
		var twice_error := 2 * err
		if twice_error >= dy:
			err += dy
			point.x += sx
		if twice_error <= dx:
			err += dx
			point.y += sy


static func _fill_raw_rect(img: Image, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, Vector2i(LOGICAL_SIZE, LOGICAL_SIZE)))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			img.set_pixel(x, y, color)


static func _fill_rect(img: Image, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(SAFE_MIN, SAFE_MIN, SAFE_MAX - SAFE_MIN + 1, SAFE_MAX - SAFE_MIN + 1))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			img.set_pixel(x, y, color)


static func _expand_nearest(logical: Image, size: int) -> Image:
	var image := logical.duplicate()
	image.resize(size, size, Image.INTERPOLATE_NEAREST)
	return image


static func _family_for(rune_id: String) -> String:
	if not RD.has_rune(rune_id):
		return "unknown"
	var rarity := String(RD.get_rune(rune_id).get("rarity", ""))
	match rarity:
		"common": return "elemental"
		"uncommon": return "combat"
		"rare": return "mystic"
		"epic": return "dark"
		"legendary": return "holy"
	return "unknown"


static func _color_for(rune_id: String) -> Color:
	return Color.from_string(RD.get_rune_color(rune_id), Color.WHITE)


static func _stable_seed(value: String) -> int:
	# 不使用 String.hash()：其实现细节不应成为图标跨平台一致性的前提。
	var hash: int = 5381
	for i in value.length():
		hash = ((hash << 5) + hash) ^ value.unicode_at(i)
	return absi(hash)
