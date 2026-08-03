extends RefCounted
## 法术意象图标：固定配方数据 + 32×32 像素语义主体 → 128×128 最近邻。
const RECIPE := preload("res://globals/combat/spell_recipe_data.gd")
const LOGICAL := 32
const DEFAULT_SIZE := 128
const INK := Color("#0A0C12")
const FRAME := Color("#5C6272")
static var _cache: Dictionary = {}

static func get_texture(spell_id: String, size: int = DEFAULT_SIZE) -> Texture2D:
	if size <= 0: size = DEFAULT_SIZE
	var key := "%s|%d" % [spell_id, size]
	if _cache.has(key): return _cache[key] as Texture2D
	var image := get_logical_image(spell_id)
	image.resize(size, size, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func get_logical_image(spell_id: String) -> Image:
	var image := Image.create(LOGICAL, LOGICAL, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var spell := RECIPE.get_spell_by_id(spell_id)
	var imagery := String(spell.get("imagery", "unknown"))
	var accent := Color(spell.get("color", Color("#D8B15B")))
	_draw_card(image, imagery, accent, _stable_seed(spell_id))
	return image

static func get_all_spell_ids() -> Array[String]:
	var ids: Array[String] = []
	for spell in RECIPE.get_all_recipes(): ids.append(String(spell.get("id", "")))
	return ids

static func _draw_card(image: Image, imagery: String, accent: Color, seed: int) -> void:
	# 切角卡面与深色材质底纹，连续线条；不使用孤立装饰方块。
	_fill(image, Rect2i(3, 1, 26, 30), Color("#10131B"))
	_fill(image, Rect2i(1, 3, 30, 26), Color("#10131B"))
	_fill(image, Rect2i(5, 4, 22, 24), Color("#252936"))
	_fill(image, Rect2i(7, 6, 18, 20), Color("#171B25"))
	_line(image, Vector2i(5, 4), Vector2i(26, 4), FRAME, 1)
	_line(image, Vector2i(4, 5), Vector2i(4, 26), FRAME, 1)
	for y in [9, 14, 19, 24]:
		_line(image, Vector2i(7, y), Vector2i(9 + (seed % 4), y), Color("#303545"), 1)
		_line(image, Vector2i(22 - (seed % 4), y + 1), Vector2i(25, y + 1), Color("#303545"), 1)
	# 每种意象有独立主体构图，而不是仅换颜色。
	match imagery:
		"ember_bolt", "fire_bolt": _firebolt(image, accent)
		"fireball": _fireball(image, accent)
		"frost_shard", "ice_spear": _ice(image, accent, imagery == "ice_spear")
		"spark_arc", "echo_thunder", "chain_lightning": _lightning(image, accent, imagery)
		"venom_spit", "poison_cloud": _poison(image, accent, imagery)
		"water_jet", "water_shield", "whirlpool", "healing_stream": _water(image, accent, imagery)
		"wind_blade", "gale_step": _wind(image, accent, imagery)
		"stone_spike", "stone_wall", "earthquake": _earth(image, accent, imagery)
		"light_ray", "holy_lantern", "sanctuary", "greater_heal": _holy(image, accent, imagery)
		"shadow_orb", "shadow_clone", "death_orb": _shadow(image, accent, imagery)
		"overcharge_core", "arcane_turret", "resonance_bell", "summon_portal": _arcane(image, accent, imagery)
		_: _unknown(image, accent)
	# 顶部意象标题刻线和底部配方色签名由 spell_id 稳定派生。
	_line(image, Vector2i(10 + seed % 5, 3), Vector2i(21 - seed % 4, 3), accent.lerp(Color.WHITE, 0.35), 1)

static func _firebolt(i: Image, c: Color) -> void:
	_line(i, Vector2i(9, 21), Vector2i(16, 14), INK, 4); _line(i, Vector2i(9, 21), Vector2i(16, 14), c, 2)
	_line(i, Vector2i(16, 14), Vector2i(22, 8), c.lerp(Color.WHITE, .35), 2)
	_line(i, Vector2i(12, 24), Vector2i(22, 24), c.darkened(.3), 1)

static func _fireball(i: Image, c: Color) -> void:
	_circle(i, Vector2i(16, 14), 6, INK); _circle(i, Vector2i(16, 14), 4, c)
	_line(i, Vector2i(11, 20), Vector2i(7, 25), c, 2); _line(i, Vector2i(16, 20), Vector2i(13, 27), c.lerp(Color.WHITE,.3), 2); _line(i, Vector2i(21, 19), Vector2i(25, 24), c, 2)

static func _ice(i: Image, c: Color, spear: bool) -> void:
	if spear:
		_poly(i, [Vector2i(7, 22), Vector2i(24, 8), Vector2i(21, 16), Vector2i(10, 25)], INK); _poly(i, [Vector2i(9, 22), Vector2i(23, 10), Vector2i(20, 16), Vector2i(11, 23)], c)
	else:
		_poly(i, [Vector2i(16, 7), Vector2i(23, 16), Vector2i(16, 25), Vector2i(9, 16)], INK); _poly(i, [Vector2i(16, 9), Vector2i(21, 16), Vector2i(16, 22), Vector2i(11, 16)], c)

static func _lightning(i: Image, c: Color, kind: String) -> void:
	_line(i, Vector2i(18, 7), Vector2i(11, 15), c, 2); _line(i, Vector2i(11, 15), Vector2i(17, 15), c.lerp(Color.WHITE,.35), 2); _line(i, Vector2i(17, 15), Vector2i(12, 24), c, 2)
	if kind == "chain_lightning": _line(i, Vector2i(20, 10), Vector2i(24, 13), c, 1); _line(i, Vector2i(24, 13), Vector2i(21, 21), c, 1)
	if kind == "echo_thunder": _line(i, Vector2i(7, 10), Vector2i(11, 10), c.darkened(.25), 1)

static func _poison(i: Image, c: Color, kind: String) -> void:
	if kind == "poison_cloud":
		_line(i, Vector2i(8, 20), Vector2i(12, 16), c, 3); _line(i, Vector2i(12, 16), Vector2i(17, 19), c, 3); _line(i, Vector2i(17, 19), Vector2i(23, 14), c, 3)
	else:
		_poly(i, [Vector2i(8, 12), Vector2i(24, 12), Vector2i(16, 25)], INK); _poly(i, [Vector2i(10, 13), Vector2i(22, 13), Vector2i(16, 22)], c)

static func _water(i: Image, c: Color, kind: String) -> void:
	_line(i, Vector2i(8, 11), Vector2i(13, 15), c, 2); _line(i, Vector2i(13, 15), Vector2i(9, 20), c, 2); _line(i, Vector2i(9, 20), Vector2i(15, 24), c, 2); _line(i, Vector2i(15, 24), Vector2i(24, 18), c, 2)
	if kind == "water_shield": _line(i, Vector2i(8, 8), Vector2i(24, 8), c.lerp(Color.WHITE,.25), 1)
	if kind == "whirlpool": _line(i, Vector2i(10, 14), Vector2i(21, 14), c.lerp(Color.WHITE,.3), 1); _line(i, Vector2i(13, 18), Vector2i(19, 18), c, 1)
	if kind == "healing_stream": _line(i, Vector2i(16, 8), Vector2i(16, 23), c.lerp(Color.WHITE,.35), 1)

static func _wind(i: Image, c: Color, kind: String) -> void:
	_line(i, Vector2i(8, 12), Vector2i(20, 12), c, 2); _line(i, Vector2i(20, 12), Vector2i(14, 18), c, 2); _line(i, Vector2i(14, 18), Vector2i(23, 18), c, 2); _line(i, Vector2i(23, 18), Vector2i(17, 25), c.lerp(Color.WHITE,.3), 2)
	if kind == "gale_step": _line(i, Vector2i(9, 25), Vector2i(13, 25), c, 1)

static func _earth(i: Image, c: Color, kind: String) -> void:
	if kind == "stone_wall":
		_poly(i, [Vector2i(8, 9), Vector2i(24, 9), Vector2i(24, 24), Vector2i(8, 24)], INK); _line(i, Vector2i(12, 9), Vector2i(12, 24), c, 1); _line(i, Vector2i(19, 9), Vector2i(19, 24), c, 1); _line(i, Vector2i(8, 15), Vector2i(24, 15), c, 1)
	elif kind == "earthquake":
		_line(i, Vector2i(8, 18), Vector2i(12, 14), c, 2); _line(i, Vector2i(12, 14), Vector2i(16, 19), c, 2); _line(i, Vector2i(16, 19), Vector2i(20, 13), c, 2); _line(i, Vector2i(20, 13), Vector2i(24, 18), c, 2)
	else: _poly(i, [Vector2i(16, 7), Vector2i(22, 24), Vector2i(10, 24)], INK); _poly(i, [Vector2i(16, 10), Vector2i(20, 22), Vector2i(12, 22)], c)

static func _holy(i: Image, c: Color, kind: String) -> void:
	if kind == "holy_lantern":
		_poly(i, [Vector2i(11, 12), Vector2i(21, 12), Vector2i(19, 23), Vector2i(13, 23)], INK); _poly(i, [Vector2i(13, 13), Vector2i(19, 13), Vector2i(18, 21), Vector2i(14, 21)], c); _line(i, Vector2i(16, 7), Vector2i(16, 12), c.lerp(Color.WHITE,.35), 1)
	elif kind == "sanctuary": _line(i, Vector2i(8, 19), Vector2i(16, 8), c, 2); _line(i, Vector2i(16, 8), Vector2i(24, 19), c, 2); _line(i, Vector2i(10, 22), Vector2i(22, 22), c.lerp(Color.WHITE,.3), 2)
	elif kind == "greater_heal": _line(i, Vector2i(16, 8), Vector2i(16, 24), c, 3); _line(i, Vector2i(9, 16), Vector2i(23, 16), c.lerp(Color.WHITE,.35), 3)
	else: _line(i, Vector2i(16, 9), Vector2i(16, 24), c, 2); _line(i, Vector2i(11, 14), Vector2i(21, 14), c.lerp(Color.WHITE,.35), 2)

static func _shadow(i: Image, c: Color, kind: String) -> void:
	_circle(i, Vector2i(16, 16), 7, INK); _circle(i, Vector2i(16, 16), 5, c.darkened(.25)); _line(i, Vector2i(10, 10), Vector2i(22, 22), c, 1)
	if kind == "shadow_clone": _line(i, Vector2i(11, 24), Vector2i(16, 9), c.lerp(Color.WHITE,.25), 1)
	if kind == "death_orb": _line(i, Vector2i(8, 9), Vector2i(24, 23), c, 1); _line(i, Vector2i(24, 9), Vector2i(8, 23), c, 1)

static func _arcane(i: Image, c: Color, kind: String) -> void:
	if kind == "resonance_bell": _poly(i, [Vector2i(10, 11), Vector2i(22, 11), Vector2i(24, 22), Vector2i(8, 22)], INK); _line(i, Vector2i(10, 12), Vector2i(22, 12), c, 2); _line(i, Vector2i(8, 25), Vector2i(24, 25), c, 2)
	elif kind == "arcane_turret": _line(i, Vector2i(16, 9), Vector2i(16, 23), c, 2); _line(i, Vector2i(16, 17), Vector2i(9, 23), c, 2); _line(i, Vector2i(16, 17), Vector2i(23, 23), c, 2)
	elif kind == "summon_portal": _line(i, Vector2i(10, 8), Vector2i(22, 8), c, 2); _line(i, Vector2i(22, 8), Vector2i(22, 24), c, 2); _line(i, Vector2i(22, 24), Vector2i(10, 24), c, 2); _line(i, Vector2i(10, 24), Vector2i(10, 8), c, 2); _line(i, Vector2i(13, 16), Vector2i(19, 16), c.lerp(Color.WHITE,.3), 2)
	else: _line(i, Vector2i(16, 8), Vector2i(24, 16), c, 2); _line(i, Vector2i(24, 16), Vector2i(16, 24), c, 2); _line(i, Vector2i(16, 24), Vector2i(8, 16), c, 2); _line(i, Vector2i(8, 16), Vector2i(16, 8), c, 2)

static func _unknown(i: Image, c: Color) -> void:
	_line(i, Vector2i(9, 9), Vector2i(23, 23), c, 2); _line(i, Vector2i(23, 9), Vector2i(9, 23), c, 2)

static func _line(img: Image, a: Vector2i, b: Vector2i, color: Color, width: int) -> void:
	var dx := absi(b.x - a.x); var dy := -absi(b.y - a.y); var sx := 1 if a.x < b.x else -1; var sy := 1 if a.y < b.y else -1; var err := dx + dy; var p := a
	while true:
		_fill(img, Rect2i(p - Vector2i(width / 2, width / 2), Vector2i(width, width)), color)
		if p == b: break
		var e2 := 2 * err
		if e2 >= dy: err += dy; p.x += sx
		if e2 <= dx: err += dx; p.y += sy

static func _poly(img: Image, points: Array[Vector2i], color: Color) -> void:
	for i in range(points.size() - 1): _line(img, points[i], points[i + 1], color, 2)
	_line(img, points[-1], points[0], color, 2)

static func _circle(img: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if Vector2(x - center.x, y - center.y).length_squared() <= radius * radius: img.set_pixel(x, y, color)

static func _fill(img: Image, rect: Rect2i, color: Color) -> void:
	var r := rect.intersection(Rect2i(Vector2i.ZERO, Vector2i(LOGICAL, LOGICAL)))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x): img.set_pixel(x, y, color)

static func _stable_seed(value: String) -> int:
	var hash := 5381
	for i in value.length(): hash = ((hash << 5) + hash) ^ value.unicode_at(i)
	return absi(hash)
