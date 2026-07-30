extends RefCounted
## 符文图标程序化生成器。
##
## 取代 assets/textures/icons/runes/*.png 的生图方案：每个符文图标由一组
## 归一化(0..1, y 向下)的矢量图元在运行时绘制为 ImageTexture，无需任何位图资源。
##
## 设计要点（便于后续扩展）：
##   - 新增/修改符文只需在 rune_data.gd 注册，图标会自动生成（确定性、按 rune_id 播种），
##     不依赖美术出图，也不受“生图绿底工作流”约束。
##   - 图元格式开放：line / disc / ring / poly / polyline / arc，可自由组合。
##   - 如需为某个符文手工刻画专属符号，登记到 _overrides[rune_id] 即可覆盖自动生成。
##   - 光栅化为纯 CPU（Image），无需渲染器，headless 与导出后均可正常使用。

const RD := preload("res://globals/combat/rune_data.gd")

## 图元覆盖表：rune_id -> 自定义图元数组。留空则全部走 _auto_glyph 确定性生成。
static var _overrides: Dictionary = {}

## 纹理缓存：key = "%s|%d" % [rune_id, size]
static var _cache: Dictionary = {}


## 获取某符文的程序化图标纹理（默认 128px，与旧 PNG 尺寸一致）。
static func get_texture(rune_id: String, size: int = 128) -> Texture2D:
	if size <= 0:
		size = 128
	var key := "%s|%d" % [rune_id, size]
	if _cache.has(key):
		return _cache[key] as Texture2D
	var prims := _build_glyph(rune_id)
	var color := _color_for(rune_id)
	var img := _rasterize(prims, color, size)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## 获取图元定义（供测试/调试）。
static func get_glyph(rune_id: String) -> Array:
	return _build_glyph(rune_id)


static func _color_for(rune_id: String) -> Color:
	var hex := RD.get_rune_color(rune_id)
	return Color.from_string(hex, Color.WHITE)


static func _build_glyph(rune_id: String) -> Array:
	if _overrides.has(rune_id):
		return _overrides[rune_id]
	return _auto_glyph(rune_id)


## 确定性矢量符文：一根中轴（stave）+ 若干支线（branches），
## 由 rune_id 哈希播种，保证同一符文始终生成同一图形且各不相同、呈“如尼文”风格。
static func _auto_glyph(rune_id: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rune_id.hash()
	var prims: Array = []
	# 中轴
	prims.append({"type": "line", "a": Vector2(0.5, 0.14), "b": Vector2(0.5, 0.86)})
	var n_branch := rng.randi_range(2, 4)
	var mirror := rng.randf() < 0.5
	for i in n_branch:
		var ty := 0.22 + 0.56 * (float(i + 1) / float(n_branch + 1))
		ty += (rng.randf() - 0.5) * 0.06
		var side := -1 if rng.randf() < 0.5 else 1
		var ang := deg_to_rad(rng.randf_range(28.0, 70.0))
		var len := rng.randf_range(0.18, 0.32)
		var dx := cos(ang) * len * side
		var dy := sin(ang) * len
		var start := Vector2(0.5, ty)
		var end := Vector2(0.5 + dx, ty - dy)
		prims.append({"type": "line", "a": start, "b": end})
		if mirror:
			prims.append({"type": "line", "a": start, "b": Vector2(0.5 - dx, ty - dy)})
	# 可选的横向短杠
	if rng.randf() < 0.4:
		var cy := 0.34 + rng.randf() * 0.32
		prims.append({"type": "line", "a": Vector2(0.28, cy), "b": Vector2(0.72, cy)})
	# 可选的顶端圆点
	if rng.randf() < 0.3:
		prims.append({"type": "disc", "c": Vector2(0.5, 0.12), "r": 0.05})
	return prims


# ── 光栅化（CPU，无需渲染器，headless/导出均可用）──────────────

static func _rasterize(prims: Array, color: Color, size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var lw := maxf(2.0, float(size) / 14.0)
	for p in prims:
		var t := String(p.get("type", ""))
		match t:
			"line":
				_draw_line(img, p["a"], p["b"], color, lw, size)
			"disc":
				_fill_disc(img, _to_px(p["c"], size), float(p["r"]) * size, color)
			"ring":
				_fill_ring(img, _to_px(p["c"], size), float(p["r"]) * size, color, lw)
			"poly":
				_draw_poly_fill(img, p["pts"], color, size)
			"polyline":
				var pts: Array = p["pts"]
				for i in range(pts.size() - 1):
					_draw_line(img, pts[i], pts[i + 1], color, lw, size)
			"arc":
				_draw_arc(img, _to_px(p["c"], size), float(p["r"]) * size,
					float(p["a0"]), float(p["a1"]), color, lw)
	return img


static func _to_px(v: Vector2, size: int) -> Vector2:
	return Vector2(v.x * size, v.y * size)


static func _draw_line(img: Image, a: Vector2, b: Vector2, color: Color, lw: float, size: int) -> void:
	var ax := a.x * size
	var ay := a.y * size
	var bx := b.x * size
	var by := b.y * size
	var steps := int(ceil(maxf(absf(bx - ax), absf(by - ay)))) + 1
	steps = maxi(steps, 1)
	for i in range(steps + 1):
		var tt := float(i) / float(steps)
		var x := ax + (bx - ax) * tt
		var y := ay + (by - ay) * tt
		_fill_disc(img, Vector2(x, y), lw * 0.5, color)


static func _fill_disc(img: Image, c: Vector2, r: float, color: Color) -> void:
	if r <= 0.0:
		return
	var r2 := r * r
	var x0 := int(floor(c.x - r))
	var x1 := int(ceil(c.x + r))
	var y0 := int(floor(c.y - r))
	var y1 := int(ceil(c.y + r))
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, img.get_width() - 1)
	y1 = mini(y1, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) - c.x
			var dy := float(y) - c.y
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)


static func _fill_ring(img: Image, c: Vector2, r: float, color: Color, lw: float) -> void:
	var half := lw * 0.5
	var x0 := int(floor(c.x - r - half))
	var x1 := int(ceil(c.x + r + half))
	var y0 := int(floor(c.y - r - half))
	var y1 := int(ceil(c.y + r + half))
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, img.get_width() - 1)
	y1 = mini(y1, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) - c.x
			var dy := float(y) - c.y
			var d := sqrt(dx * dx + dy * dy)
			if absf(d - r) <= half:
				img.set_pixel(x, y, color)


static func _draw_poly_fill(img: Image, pts: Array, color: Color, size: int) -> void:
	if pts.size() < 3:
		return
	var pxs: Array[Vector2] = []
	for v in pts:
		pxs.append(_to_px(v, size))
	var min_y := 1e9
	var max_y := -1e9
	for p in pxs:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	min_y = maxf(min_y, 0.0)
	max_y = minf(max_y, float(img.get_height() - 1))
	var y0 := int(floor(min_y))
	var y1 := int(ceil(max_y))
	for y in range(y0, y1 + 1):
		var xs: Array[float] = []
		for i in range(pxs.size()):
			var a := pxs[i]
			var b := pxs[(i + 1) % pxs.size()]
			if (a.y <= float(y) and b.y > float(y)) or (b.y <= float(y) and a.y > float(y)):
				var tt := (float(y) - a.y) / (b.y - a.y)
				xs.append(a.x + tt * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			var xa := int(ceil(xs[k]))
			var xb := int(floor(xs[k + 1]))
			xa = maxi(xa, 0)
			xb = mini(xb, img.get_width() - 1)
			for x in range(xa, xb + 1):
				img.set_pixel(x, y, color)
			k += 2


static func _draw_arc(img: Image, c: Vector2, r: float, a0: float, a1: float, color: Color, lw: float) -> void:
	var n := maxi(int(ceil(absf(a1 - a0) / 0.12)), 2)
	for i in range(n + 1):
		var ang := a0 + (a1 - a0) * float(i) / float(n)
		var p := Vector2(c.x + cos(ang) * r, c.y + sin(ang) * r)
		_fill_disc(img, p, lw * 0.5, color)
