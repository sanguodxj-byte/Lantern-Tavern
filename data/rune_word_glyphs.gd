extends RefCounted
## 符文之语 128×128 华丽像素徽记生成器。
##
## 与普通符文卡不同：符文之语使用八角圣匣轮廓、三层金属框、主题冠饰、
## 中央复合徽记和 2–3 颗配方宝石。全部先绘制到 32×32 逻辑栅格，
## 再以最近邻放大，确保桌面与 Android 输出一致。

const RWD := preload("res://globals/combat/rune_word_data.gd")
const RD := preload("res://globals/combat/rune_data.gd")

const DEFAULT_SIZE := 128
const LOGICAL_SIZE := 32
const TRANSPARENT := Color(0, 0, 0, 0)
const INK := Color("#080A0F")
const SHADOW := Color("#191722")

static var _cache: Dictionary = {}


static func get_texture(word_id: String, size: int = DEFAULT_SIZE) -> Texture2D:
	if size <= 0:
		size = DEFAULT_SIZE
	var key := "%s|%d" % [word_id, size]
	if _cache.has(key):
		return _cache[key] as Texture2D
	var logical := get_logical_image(word_id)
	logical.resize(size, size, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(logical)
	_cache[key] = texture
	return texture


static func get_logical_image(word_id: String) -> Image:
	var image := Image.create(LOGICAL_SIZE, LOGICAL_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(TRANSPARENT)
	var word: Dictionary = RWD.get_rune_word(word_id)
	var seed := _stable_seed(word_id)
	var rarity := String(word.get("rarity", "rare"))
	var recipe: Array = word.get("recipe", [])
	var grants: Array = word.get("grants", [])
	var theme := _theme_for(rarity, grants)
	var accent := _recipe_color(recipe)
	var metal := _metal_for(rarity)
	var metal_high := metal.lerp(Color.WHITE, 0.38)
	var accent_high := accent.lerp(Color.WHITE, 0.48)

	_draw_reliquary(image, seed, theme, rarity, metal, metal_high, accent)
	_draw_word_id_texture(image, word_id, seed, accent, accent_high)
	_draw_theme_crest(image, theme, seed, accent, accent_high)
	_draw_word_signature(image, word_id, seed, accent, accent_high)
	_draw_recipe_gems(image, recipe, metal_high)
	_draw_ornaments(image, theme, rarity, seed, accent, accent_high)
	return image


static func get_style(word_id: String) -> Dictionary:
	var word: Dictionary = RWD.get_rune_word(word_id)
	return {
		"id": word_id,
		"theme": _theme_for(String(word.get("rarity", "rare")), word.get("grants", [])),
		"rarity": String(word.get("rarity", "rare")),
		"seed": _stable_seed(word_id),
		"recipe": word.get("recipe", []).duplicate(),
	}


static func clear_cache() -> void:
	_cache.clear()


static func _draw_reliquary(img: Image, seed: int, theme: String, rarity: String, metal: Color, metal_high: Color, accent: Color) -> void:
	var background_a := _background_for(theme)
	var background_b := background_a.lerp(Color.BLACK, 0.17)
	for y in LOGICAL_SIZE:
		for x in LOGICAL_SIZE:
			if _inside_octagon(x, y, 1, 4):
				img.set_pixel(x, y, INK)
			if _inside_octagon(x, y, 2, 3):
				img.set_pixel(x, y, metal)
			if _inside_octagon(x, y, 3, 3):
				img.set_pixel(x, y, metal_high if x + y < 31 else SHADOW)
			if _inside_octagon(x, y, 5, 2):
				img.set_pixel(x, y, accent.lerp(INK, 0.52))
			if _inside_octagon(x, y, 6, 2):
				img.set_pixel(x, y, INK)
			if _inside_octagon(x, y, 7, 1):
				var pattern := (x * 11 + y * 17 + seed) % 19
				img.set_pixel(x, y, background_b if pattern in [0, 5, 13] else background_a)

	# 内圈与连续分段刻线，让卡面比普通符文更复杂；不使用孤立方块节点。
	_draw_diamond_ring(img, Vector2i(16, 15), 9, accent.lerp(INK, 0.28))
	var notch := 2 + seed % 4
	_draw_line(img, Vector2i(7, 10 + notch), Vector2i(9, 10 + notch), metal_high, 1)
	_draw_line(img, Vector2i(23, 19 - notch), Vector2i(25, 19 - notch), metal_high, 1)

	# 稀有度层级：史诗双链，传奇三重冠线。
	if rarity in ["epic", "legendary"]:
		_draw_line(img, Vector2i(8, 8), Vector2i(12, 6), accent, 1)
		_draw_line(img, Vector2i(20, 6), Vector2i(24, 8), accent, 1)
	if rarity == "legendary":
		_draw_line(img, Vector2i(10, 25), Vector2i(16, 28), metal_high, 1)
		_draw_line(img, Vector2i(16, 28), Vector2i(22, 25), metal_high, 1)


static func _draw_word_id_texture(img: Image, word_id: String, seed: int, accent: Color, high: Color) -> void:
	# 每枚符文之语拥有独立的内场纹章底纹，而非只按主题换色。
	# 8 个稳定比特分别控制左右斜刻、阶梯链、断环和节点布局。
	var texture_dark := accent.lerp(INK, 0.66)
	for row in 4:
		var bits := (seed >> (row * 4)) & 15
		var y := 9 + row * 4
		if bits & 1:
			_draw_line(img, Vector2i(8, y), Vector2i(11, y - 2), texture_dark, 1)
		if bits & 2:
			_draw_line(img, Vector2i(24, y), Vector2i(21, y + 2), texture_dark, 1)
		if bits & 4:
			_draw_line(img, Vector2i(8 + row, 22 - row), Vector2i(11 + row, 22 - row), high, 1)
		if bits & 8:
			_draw_line(img, Vector2i(21 - row, 9 + row), Vector2i(24 - row, 9 + row), accent, 1)
	# ID 长度与首尾字符决定上下两道不同的铭文条，进一步扩大轮廓差异。
	var length_mark := 2 + word_id.length() % 7
	_draw_line(img, Vector2i(12, 7), Vector2i(12 + length_mark, 7), texture_dark, 1)
	var tail := word_id.unicode_at(word_id.length() - 1) if not word_id.is_empty() else 0
	var bottom_start := 11 + tail % 5
	_draw_line(img, Vector2i(bottom_start, 23), Vector2i(bottom_start + 5, 23), texture_dark, 1)


static func _draw_word_signature(img: Image, word_id: String, seed: int, accent: Color, high: Color) -> void:
	# 中央独立签名字形：由 ID 的 4 段哈希直接生成 5 个锚点。
	# 每张卡的主构图都会变化，不再只是同一主题徽记加一个侧印。
	var anchors: Array[Vector2i] = [Vector2i(16, 9)]
	for i in 4:
		var nibble := (seed >> (i * 5)) & 31
		var x := 10 + nibble % 13
		var y := 11 + int(nibble / 4 + i * 3) % 10
		anchors.append(Vector2i(x, y))
	anchors.append(Vector2i(16, 21))
	_stroke(img, anchors, INK, accent)
	# 稳定的分叉与终端宝石。
	var branch_index := seed % 4 + 1
	var branch_from: Vector2i = anchors[branch_index]
	var branch_dir := -1 if ((seed >> 3) & 1) == 0 else 1
	var branch_to := Vector2i(clampi(branch_from.x + branch_dir * (4 + seed % 3), 8, 24), clampi(branch_from.y - 4, 8, 22))
	_stroke(img, [branch_from, branch_to], INK, high)
	# ID 首字符决定核心短刻线偏移，让相似哈希也不共用中心像素。
	var first := word_id.unicode_at(0) if not word_id.is_empty() else 0
	var core := Vector2i(14 + first % 5, 14 + int(first / 5) % 4)
	_draw_line(img, core, core + Vector2i(2, 0), high, 1)


static func _draw_theme_crest(img: Image, theme: String, seed: int, accent: Color, high: Color) -> void:
	match theme:
		"kinetic":
			# 双翼矛徽：速度/冲击。
			_stroke(img, [Vector2i(8, 18), Vector2i(16, 8), Vector2i(24, 18)], INK, accent)
			_stroke(img, [Vector2i(10, 14), Vector2i(16, 20), Vector2i(22, 14)], INK, accent)
			_draw_line(img, Vector2i(16, 8), Vector2i(16, 23), high, 1)
		"ward":
			# 三层盾印：格挡/护甲/闪避。
			_stroke(img, [Vector2i(16, 7), Vector2i(23, 10), Vector2i(22, 19), Vector2i(16, 24), Vector2i(10, 19), Vector2i(9, 10), Vector2i(16, 7)], INK, accent)
			_stroke(img, [Vector2i(12, 13), Vector2i(16, 10), Vector2i(20, 13), Vector2i(16, 20), Vector2i(12, 13)], INK, high)
		"elemental":
			# 四象旋涡：属性组合而非单枚符文线条。
			for points in [
				[Vector2i(16, 8), Vector2i(20, 12), Vector2i(16, 15)],
				[Vector2i(24, 15), Vector2i(20, 19), Vector2i(16, 15)],
				[Vector2i(16, 23), Vector2i(12, 19), Vector2i(16, 15)],
				[Vector2i(8, 15), Vector2i(12, 11), Vector2i(16, 15)],
			]:
				_stroke(img, points, INK, accent)
			_draw_line(img, Vector2i(14, 15), Vector2i(18, 15), high, 1)
		"arcane":
			# 星盘与器械结点。
			_stroke(img, [Vector2i(16, 7), Vector2i(22, 12), Vector2i(20, 20), Vector2i(12, 20), Vector2i(10, 12), Vector2i(16, 7)], INK, accent)
			_draw_line(img, Vector2i(10, 12), Vector2i(22, 12), high, 1)
			_draw_line(img, Vector2i(12, 20), Vector2i(16, 7), high, 1)
			_draw_line(img, Vector2i(20, 20), Vector2i(10, 12), high, 1)
		"dark":
			# 破碎王冠与下坠之眼。
			_stroke(img, [Vector2i(8, 11), Vector2i(12, 7), Vector2i(16, 12), Vector2i(20, 7), Vector2i(24, 11)], INK, accent)
			_stroke(img, [Vector2i(9, 15), Vector2i(16, 10), Vector2i(23, 15), Vector2i(16, 22), Vector2i(9, 15)], INK, accent)
			_draw_line(img, Vector2i(14, 15), Vector2i(18, 15), high, 1)
			_draw_line(img, Vector2i(16, 18), Vector2i(16 + (seed % 3) - 1, 24), high, 1)
		"holy":
			# 圣环、上升翼与核心封印。
			_stroke(img, [Vector2i(8, 15), Vector2i(12, 9), Vector2i(16, 12), Vector2i(20, 9), Vector2i(24, 15)], INK, accent)
			_stroke(img, [Vector2i(10, 20), Vector2i(16, 7), Vector2i(22, 20)], INK, high)
			_stroke(img, [Vector2i(11, 20), Vector2i(16, 24), Vector2i(21, 20)], INK, accent)
		_:
			_stroke(img, [Vector2i(10, 10), Vector2i(22, 22)], INK, accent)
			_stroke(img, [Vector2i(22, 10), Vector2i(10, 22)], INK, high)

	# 每个 word_id 的稳定种子增加一处独有的侧印，防止同主题卡面完全相同。
	var side := 8 if seed % 2 == 0 else 24
	var y := 10 + seed % 11
	var mark_x := side if side == 8 else side - 3
	_draw_line(img, Vector2i(mark_x, y), Vector2i(mark_x + (3 if side == 8 else -3), y), high, 1)


static func _draw_recipe_gems(img: Image, recipe: Array, metal_high: Color) -> void:
	var count := mini(recipe.size(), 3)
	if count <= 0:
		return
	var xs: Array[int] = [16]
	if count == 2:
		xs = [13, 19]
	elif count >= 3:
		xs = [11, 16, 21]
	for i in count:
		var color := Color.from_string(RD.get_rune_color(String(recipe[i])), Color.WHITE)
		var center := Vector2i(xs[i], 25)
		_node(img, center, INK, color)
		img.set_pixelv(center + Vector2i(0, -1), color.lerp(Color.WHITE, 0.55))
		if center.y + 2 < LOGICAL_SIZE:
			img.set_pixel(center.x, center.y + 2, metal_high)


static func _draw_ornaments(img: Image, theme: String, rarity: String, seed: int, accent: Color, high: Color) -> void:
	# 顶部主题冠饰。
	match theme:
		"kinetic":
			_stroke(img, [Vector2i(11, 5), Vector2i(16, 2), Vector2i(21, 5)], INK, accent)
		"ward":
			_stroke(img, [Vector2i(10, 4), Vector2i(16, 2), Vector2i(22, 4)], INK, high)
			_draw_line(img, Vector2i(13, 4), Vector2i(19, 4), accent, 1)
		"elemental":
			for x in [12, 16, 20]:
				_draw_line(img, Vector2i(x, 4), Vector2i(x + ((seed + x) % 3) - 1, 2), accent, 1)
		"arcane":
			_draw_line(img, Vector2i(13, 3), Vector2i(19, 3), high, 1)
			_draw_line(img, Vector2i(10, 5), Vector2i(13, 4), accent, 1)
			_draw_line(img, Vector2i(19, 4), Vector2i(22, 5), accent, 1)
		"dark":
			_stroke(img, [Vector2i(10, 3), Vector2i(13, 6), Vector2i(16, 2), Vector2i(19, 6), Vector2i(22, 3)], INK, accent)
		"holy":
			_stroke(img, [Vector2i(9, 5), Vector2i(13, 2), Vector2i(16, 5), Vector2i(19, 2), Vector2i(23, 5)], INK, high)
	# 传奇卡额外四道边缘光刻，仍保持硬边不做发光。
	if rarity == "legendary":
		for points in [
			[Vector2i(4, 10), Vector2i(4, 13)], [Vector2i(27, 10), Vector2i(27, 13)],
			[Vector2i(4, 18), Vector2i(4, 21)], [Vector2i(27, 18), Vector2i(27, 21)],
		]:
			_draw_line(img, points[0], points[1], high, 1)


static func _inside_octagon(x: int, y: int, inset: int, cut: int) -> bool:
	var lo := inset
	var hi := LOGICAL_SIZE - 1 - inset
	if x < lo or x > hi or y < lo or y > hi:
		return false
	if (x - lo) + (y - lo) < cut:
		return false
	if (hi - x) + (y - lo) < cut:
		return false
	if (x - lo) + (hi - y) < cut:
		return false
	if (hi - x) + (hi - y) < cut:
		return false
	return true


static func _draw_diamond_ring(img: Image, center: Vector2i, radius: int, color: Color) -> void:
	_draw_line(img, center + Vector2i(0, -radius), center + Vector2i(radius, 0), color, 1)
	_draw_line(img, center + Vector2i(radius, 0), center + Vector2i(0, radius), color, 1)
	_draw_line(img, center + Vector2i(0, radius), center + Vector2i(-radius, 0), color, 1)
	_draw_line(img, center + Vector2i(-radius, 0), center + Vector2i(0, -radius), color, 1)


static func _stroke(img: Image, points: Array, edge: Color, main: Color) -> void:
	for i in range(points.size() - 1):
		_draw_line(img, points[i], points[i + 1], edge, 3)
	for i in range(points.size() - 1):
		_draw_line(img, points[i], points[i + 1], main, 1)


static func _node(img: Image, center: Vector2i, edge: Color, main: Color) -> void:
	_fill_rect(img, Rect2i(center - Vector2i(2, 2), Vector2i(5, 5)), edge)
	_fill_rect(img, Rect2i(center - Vector2i(1, 1), Vector2i(3, 3)), main)


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


static func _fill_rect(img: Image, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, Vector2i(LOGICAL_SIZE, LOGICAL_SIZE)))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			img.set_pixel(x, y, color)


static func _theme_for(rarity: String, grants: Array) -> String:
	var joined := "|".join(grants).to_lower()
	if joined.contains("corrupt") or joined.contains("rage") or joined.contains("dreadful"):
		return "dark"
	if rarity == "legendary" or joined.contains("holy") or joined.contains("immortal") or joined.contains("liberation"):
		return "holy"
	if joined.contains("shield") or joined.contains("block") or joined.contains("armor") or joined.contains("dodge") or joined.contains("no_wear"):
		return "ward"
	if joined.contains("storm") or joined.contains("light") or joined.contains("poison") or joined.contains("tremor") or joined.contains("thunder") or joined.contains("explosion") or joined.contains("slow") or joined.contains("drain"):
		return "elemental"
	if joined.contains("charge") or joined.contains("impact") or joined.contains("knockback") or joined.contains("sprint") or joined.contains("execute") or joined.contains("sunder"):
		return "kinetic"
	return "arcane"


static func _recipe_color(recipe: Array) -> Color:
	if recipe.is_empty():
		return Color("#D8B15B")
	var sum := Vector3.ZERO
	for rune_id in recipe:
		var color := Color.from_string(RD.get_rune_color(String(rune_id)), Color.WHITE)
		sum += Vector3(color.r, color.g, color.b)
	sum /= float(recipe.size())
	return Color(sum.x, sum.y, sum.z, 1.0)


static func _metal_for(rarity: String) -> Color:
	match rarity:
		"legendary": return Color("#D7A83E")
		"epic": return Color("#9A6CC6")
	return Color("#7E93AC")


static func _background_for(theme: String) -> Color:
	match theme:
		"kinetic": return Color("#28201C")
		"ward": return Color("#1C2730")
		"elemental": return Color("#1D2630")
		"arcane": return Color("#242034")
		"dark": return Color("#211721")
		"holy": return Color("#302B1D")
	return Color("#22232A")


static func _stable_seed(value: String) -> int:
	var hash: int = 5381
	for i in value.length():
		hash = ((hash << 5) + hash) ^ value.unicode_at(i)
	return absi(hash)
