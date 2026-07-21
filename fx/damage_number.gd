class_name DamageNumber
extends Node3D

## 3D 伤害/治疗飘字。
## 使用 Label3D + BILLBOARD_ENABLED 永久面向摄像机；像素字体 ark-pixel。
## 通过 Kind 区分普通伤害、暴击、恢复、格挡、未命中。

enum Kind {
	DAMAGE, ## 普通伤害
	CRIT,   ## 暴击
	HEAL,   ## 恢复
	BLOCK,  ## 格挡
	MISS,   ## 未命中
}

const PIXEL_FONT := preload("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf")

const COLOR_DAMAGE := Color(1.0, 0.42, 0.28, 1.0)
const COLOR_CRIT := Color(1.0, 0.88, 0.18, 1.0)
const COLOR_HEAL := Color(0.35, 1.0, 0.48, 1.0)
const COLOR_BLOCK := Color(0.62, 0.78, 1.0, 1.0)
const COLOR_MISS := Color(0.72, 0.72, 0.76, 1.0)
const OUTLINE_COLOR := Color(0.05, 0.03, 0.06, 0.92)

const FONT_SIZE_NORMAL := 42
const FONT_SIZE_CRIT := 56
const FONT_SIZE_HEAL := 40
const FONT_SIZE_BLOCK := 36
const PIXEL_SIZE_NORMAL := 0.012
const PIXEL_SIZE_CRIT := 0.015

const LIFETIME_SEC := 0.85
const RISE_SPEED := 1.15
const FADE_START_RATIO := 0.45
const CRIT_SCALE_PEAK := 1.35
const CRIT_SCALE_SETTLE := 0.18
const HORIZONTAL_JITTER := 0.18
const VERTICAL_SPAWN_OFFSET := 1.55

var amount: int = 0
var kind: Kind = Kind.DAMAGE
var lifetime: float = LIFETIME_SEC
var rise_speed: float = RISE_SPEED

var _age: float = 0.0
var _label: Label3D
var _velocity: Vector3 = Vector3.ZERO
var _base_scale: float = 1.0


func _ready() -> void:
	if _label == null:
		_build_label()
	_apply_visuals()
	# 轻微横向抖动，避免同点叠加完全重叠
	var jitter_x := randf_range(-HORIZONTAL_JITTER, HORIZONTAL_JITTER)
	var jitter_z := randf_range(-HORIZONTAL_JITTER * 0.5, HORIZONTAL_JITTER * 0.5)
	_velocity = Vector3(jitter_x * 0.6, rise_speed, jitter_z * 0.6)
	set_process(true)


func setup(value: int, number_kind: Kind = Kind.DAMAGE) -> void:
	amount = value
	kind = number_kind
	if _label == null:
		_build_label()
	_apply_visuals()


## 工厂：在 parent 下生成飘字并设置世界坐标。parent 为空时返回 null。
static func spawn(parent: Node, world_pos: Vector3, value: int, number_kind: Kind = Kind.DAMAGE) -> DamageNumber:
	if parent == null or not is_instance_valid(parent):
		return null
	var node := DamageNumber.new()
	node.name = "DamageNumber"
	parent.add_child(node)
	node.global_position = world_pos + Vector3(0.0, VERTICAL_SPAWN_OFFSET, 0.0)
	node.setup(value, number_kind)
	return node


static func kind_from_flags(is_crit: bool = false, is_heal: bool = false, is_block: bool = false, is_miss: bool = false) -> Kind:
	if is_miss:
		return Kind.MISS
	if is_block:
		return Kind.BLOCK
	if is_heal:
		return Kind.HEAL
	if is_crit:
		return Kind.CRIT
	return Kind.DAMAGE


static func format_text(value: int, number_kind: Kind) -> String:
	match number_kind:
		Kind.HEAL:
			return "+%d" % maxi(value, 0)
		Kind.CRIT:
			return "%d!" % maxi(value, 0)
		Kind.BLOCK:
			if value > 0:
				return TranslationServer.translate("格挡 %d") % value
			return TranslationServer.translate("格挡")
		Kind.MISS:
			return TranslationServer.translate("未中")
		_:
			return str(maxi(value, 0))


static func color_for_kind(number_kind: Kind) -> Color:
	match number_kind:
		Kind.CRIT:
			return COLOR_CRIT
		Kind.HEAL:
			return COLOR_HEAL
		Kind.BLOCK:
			return COLOR_BLOCK
		Kind.MISS:
			return COLOR_MISS
		_:
			return COLOR_DAMAGE


static func font_size_for_kind(number_kind: Kind) -> int:
	match number_kind:
		Kind.CRIT:
			return FONT_SIZE_CRIT
		Kind.HEAL:
			return FONT_SIZE_HEAL
		Kind.BLOCK, Kind.MISS:
			return FONT_SIZE_BLOCK
		_:
			return FONT_SIZE_NORMAL


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "Label"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.shaded = false
	_label.double_sided = true
	_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.outline_size = 8
	_label.outline_modulate = OUTLINE_COLOR
	_label.font = PIXEL_FONT
	add_child(_label)


func _apply_visuals() -> void:
	if _label == null:
		return
	_label.text = format_text(amount, kind)
	_label.modulate = color_for_kind(kind)
	_label.font_size = font_size_for_kind(kind)
	_label.pixel_size = PIXEL_SIZE_CRIT if kind == Kind.CRIT else PIXEL_SIZE_NORMAL
	_base_scale = 1.0
	if kind == Kind.CRIT:
		_base_scale = 1.0
		scale = Vector3.ONE * CRIT_SCALE_PEAK
	else:
		scale = Vector3.ONE


func _process(delta: float) -> void:
	_age += delta
	global_position += _velocity * delta
	# 上升减速
	_velocity.y = maxf(_velocity.y - delta * 0.35, rise_speed * 0.55)
	_velocity.x = move_toward(_velocity.x, 0.0, delta * 0.8)
	_velocity.z = move_toward(_velocity.z, 0.0, delta * 0.8)

	# 暴击弹出缩放回落
	if kind == Kind.CRIT and _age < CRIT_SCALE_SETTLE:
		var t := clampf(_age / CRIT_SCALE_SETTLE, 0.0, 1.0)
		var s := lerpf(CRIT_SCALE_PEAK, 1.0, t)
		scale = Vector3.ONE * s
	else:
		scale = Vector3.ONE * _base_scale

	# 后半段淡出
	var fade_start := lifetime * FADE_START_RATIO
	if _age >= fade_start and _label != null:
		var fade_t := clampf((_age - fade_start) / maxf(lifetime - fade_start, 0.001), 0.0, 1.0)
		var alpha := 1.0 - fade_t
		var col := color_for_kind(kind)
		col.a = alpha
		_label.modulate = col
		var outline := OUTLINE_COLOR
		outline.a = OUTLINE_COLOR.a * alpha
		_label.outline_modulate = outline

	if _age >= lifetime:
		queue_free()
