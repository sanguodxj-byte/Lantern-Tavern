class_name EquipmentStatsVisual
extends Control

const PIXEL_FONT := preload("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf")
const ROW_HEIGHT := 58.0
const LABEL_FONT_SIZE := 22
const VALUE_FONT_SIZE := 23
const COLUMN_GAP := 12.0
const VIEW_MODEL := preload("res://scenes/ui/equipment_screen_view_model.gd")
const ATTRIBUTE_ICON_PATHS := {
	"等级": "res://assets/textures/icons/attributes/attribute_level_aligned.png",
	"生命": "res://assets/textures/icons/attributes/attribute_health_aligned.png",
	"攻击": "res://assets/textures/icons/attributes/attribute_attack_aligned.png",
	"护甲": "res://assets/textures/icons/attributes/attribute_armor_aligned.png",
	"闪避": "res://assets/textures/icons/attributes/attribute_evasion_aligned.png",
	"暴击": "res://assets/textures/icons/attributes/attribute_critical_aligned.png",
	"力量": "res://assets/textures/icons/attributes/attribute_strength_aligned.png",
	"敏捷": "res://assets/textures/icons/attributes/attribute_agility_aligned.png",
	"体质": "res://assets/textures/icons/attributes/attribute_vitality_aligned.png",
	"智力": "res://assets/textures/icons/attributes/attribute_intelligence_aligned.png",
	"灵巧": "res://assets/textures/icons/attributes/attribute_dexterity_aligned.png",
	"感知": "res://assets/textures/icons/attributes/attribute_perception_aligned.png",
	"法力": "res://assets/textures/icons/attributes/attribute_mana_aligned.png",
}
const PROFICIENCY_ICON_PATHS := {
	"剑": "res://assets/textures/icons/equipment/weapons_sword.png",
	"匕首": "res://assets/textures/icons/equipment/weapons_dagger.png",
	"斧": "res://assets/textures/icons/equipment/weapons_axe.png",
	"锤": "res://assets/textures/icons/equipment/weapons_warhammer.png",
	"枪": "res://assets/textures/icons/equipment/weapons_spear.png",
	"弓": "res://assets/textures/icons/equipment/weapons_longbow.png",
	"弩": "res://assets/textures/icons/equipment/weapons_crossbow.png",
	"法杖": "res://assets/textures/icons/equipment/weapons_staff.png",
	"魔导书": "res://assets/textures/icons/equipment/weapons_grimoire.png",
	"盾牌": "res://assets/textures/icons/equipment/weapons_shield.png",
}

@export var source_label_path: NodePath

var _source_label: Label
var _last_text := ""
var _stat_rows: Array = []
var _attribute_icons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_source_label = get_node_or_null(source_label_path) as Label
	for label in ATTRIBUTE_ICON_PATHS:
		var texture := load(String(ATTRIBUTE_ICON_PATHS[label])) as Texture2D
		if texture != null:
			_attribute_icons[label] = texture
	for label in PROFICIENCY_ICON_PATHS:
		var texture := load(String(PROFICIENCY_ICON_PATHS[label])) as Texture2D
		if texture != null:
			_attribute_icons[label] = texture
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	if _source_label == null or not is_instance_valid(_source_label):
		return
	if _source_label.text == _last_text:
		return
	_last_text = _source_label.text
	_stat_rows = VIEW_MODEL.make_stat_rows(_source_label.text.split("\n", false))
	queue_redraw()


func _draw() -> void:
	if _source_label == null:
		return
	var rows: Array = _stat_rows
	if rows.is_empty() and not _source_label.text.is_empty():
		rows = VIEW_MODEL.make_stat_rows(_source_label.text.split("\n", false))
	var left := 8.0
	var right := maxf(left + 220.0, size.x - 8.0)
	var top := 4.0
	# Decorative rail and header underline keep the panel visually structured
	# even when the source data is temporarily empty.
	draw_line(Vector2(left, top), Vector2(right, top), Color(0.32, 0.22, 0.15, 0.9), 1.0)
	draw_line(Vector2(left + 8.0, top + 3.0), Vector2(right - 8.0, top + 3.0), Color(0.16, 0.12, 0.10, 0.9), 1.0)
	var column_width := maxf(180.0, (right - left - COLUMN_GAP) * 0.5)
	for index in range(rows.size()):
		var parsed: Dictionary = rows[index]
		var column_index := index % 2
		var row_index := int(index / 2)
		var row_x := left + column_index * (column_width + COLUMN_GAP)
		var row_y := top + 10.0 + row_index * ROW_HEIGHT
		if row_y + ROW_HEIGHT > size.y:
			break
		var row := Rect2(row_x, row_y, column_width, ROW_HEIGHT - 7.0)
		# The parchment remains the only information-area surface. Keep the row
		# geometry for alignment, but do not paint opaque alternating strips over
		# it; the separator lines provide enough grouping at this scale.
		draw_rect(row, Color(0, 0, 0, 0), true)
		draw_line(Vector2(row.position.x, row.end.y), Vector2(row.end.x, row.end.y), Color(0.18, 0.12, 0.095, 0.9), 1.0)
		draw_line(Vector2(row.position.x + 38.0, row.position.y + 7.0), Vector2(row.position.x + 38.0, row.end.y - 7.0), Color(0.19, 0.13, 0.10, 0.8), 1.0)
		_draw_stat_icon(Vector2(row.position.x + 20.0, row.position.y + 25.0), String(parsed.label))
		draw_string(PIXEL_FONT, Vector2(row.position.x + 48.0, row.position.y + 34.0), String(parsed.label), HORIZONTAL_ALIGNMENT_LEFT, column_width - 190.0, LABEL_FONT_SIZE, Color(0.92, 0.84, 0.69, 1.0))
		draw_string(PIXEL_FONT, Vector2(row.end.x - 148.0, row.position.y + 34.0), String(parsed.value), HORIZONTAL_ALIGNMENT_RIGHT, 136.0, VALUE_FONT_SIZE, _value_color(String(parsed.label)))



func _value_color(label: String) -> Color:
	if label == "生命":
		return Color(0.95, 0.40, 0.34, 1.0)
	if label == "法力":
		return Color(0.38, 0.65, 0.95, 1.0)
	if label == "攻击" or label == "暴击":
		return Color(1.0, 0.69, 0.32, 1.0)
	if label == "闪避":
		return Color(0.61, 0.78, 0.67, 1.0)
	if label == "护甲":
		return Color(0.80, 0.84, 0.88, 1.0)
	return Color(0.96, 0.87, 0.69, 1.0)


func _draw_stat_icon(center: Vector2, label: String) -> void:
	var generated_icon := _attribute_icons.get(label) as Texture2D
	if generated_icon != null:
		draw_texture_rect(generated_icon, Rect2(center - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), false)
		return
	var pattern: Array = pixel_icon_pattern(label)
	var palette: Dictionary = pixel_icon_palette(label)
	const PIXEL := 4.0
	var origin := center - Vector2(PIXEL * 5.0, PIXEL * 5.0)
	# Each glyph is authored on a 10x10 logical grid and enlarged with hard
	# edges. The outline receives a one-pixel offset shadow for contrast.
	for y in range(pattern.size()):
		var row: String = pattern[y]
		for x in range(row.length()):
			var cell := row.substr(x, 1)
			if cell == ".":
				continue
			var offset := Vector2(x * PIXEL, y * PIXEL)
			if cell == "o":
				draw_rect(Rect2(origin + offset + Vector2(1.0, 1.0), Vector2(PIXEL, PIXEL)), Color(0.08, 0.055, 0.045, 0.95), true)
			draw_rect(Rect2(origin + offset, Vector2(PIXEL, PIXEL)), palette.get(cell, palette["p"]), true)


static func pixel_icon_pattern(label: String) -> Array:
	# Shared 10x10 grid: o=outline, p=primary, h=highlight, s=shadow.
	var patterns: Dictionary = {
		"等级": ["....oo....", "...oppo...", "..oppppo..", ".oppppppo.", "oppphhhppo", "oppppppppo", ".oppppppo.", "..oppppo..", "...oppo...", "....oo...."],
		"生命": ["..oo..oo..", ".oppooppo.", "oppppppppo", "oppphhhppo", ".oppppppo.", "..oppppo..", "...oppo...", "....oo....", "..........", ".........."],
		# Sword: pointed blade, guard, grip and pommel.
		"攻击": ["....oo....", "....pp....", "...oppo...", "...oppo...", "...oppo...", "..opsspo..", ".oppppppo.", "....oo....", "...oooo...", ".........."],
		# Shield: broad shoulders tapering into a protected point.
		"护甲": ["...oooo...", "..oppppo..", ".opphhppo.", "oppphhhppo", "opppsspppo", "oppppppppo", ".oppppppo.", "..oppppo..", "...oppo...", "....oo...."],
		# Wings: negative space makes evasion readable instead of a blob.
		"闪避": ["..oo..oo..", ".oppooppo.", "oppp..pppo", ".oppppppo.", "..oppppo..", "...oppo...", "..oppppo..", ".oppppppo.", "oppp..pppo", ".........."],
		# Four-point critical-hit star/crosshair.
		"暴击": ["....oo....", "...oppo...", "....pp....", "..oppppo..", "oppphhhppo", "..oppppo..", "....pp....", "...oppo...", "....oo....", ".........."],
		# Gauntlet/fist: a heavy cuff gives strength a unique base.
		"力量": ["..oppppo..", ".oppppppo.", "oppphhhppo", "oppppppppo", "opppsspppo", ".oppppppo.", "..oppppo..", "..oppppo..", "...oppo...", "...oooo..."],
		# Speed/feather mark for agility.
		"敏捷": ["....oo....", "...oppo...", "..oppppo..", ".oppppppo.", "opppsspppo", ".oppppppo.", "..oppppo..", "...oppo...", "....oo....", ".........."],
		# Torso: neck, shoulders, chest and waist.
		"体质": ["...oooo...", "..oppppo..", ".oppppppo.", "oppphhhppo", "opppsspppo", "oppppppppo", ".oppppppo.", ".oppppppo.", "..oppppo..", "...oooo..."],
		# Open book: paired pages with a visible center seam.
		"智力": ["..oo..oo..", ".oppooppo.", "opppsspppo", ".opphhppo.", "oppppppppo", "opppsspppo", "oppppppppo", ".oppppppo.", "..oppppo..", "...oooo..."],
		# Dexterity glove: fingers at the top and a narrow wrist.
		"灵巧": ["..oo..oo..", ".oppooppo.", "oppppppppo", "oppphhhppo", "opppsspppo", ".oppppppo.", "..oppppo..", "..oppppo..", "...oppo...", "....oo...."],
		"感知": ["...oooo...", "..oppppo..", ".oppppppo.", "oppppppppo", "oppphhpppo", "oppppppppo", ".oppppppo.", "..oppppo..", "...oppo...", "....oo...."],
		"法力": ["....oo....", "...oppo...", "..oppppo..", ".oppppppo.", "oppphhhppo", "oppppppppo", ".oppppppo.", "..oppppo..", "...oppo...", "....oo...."],
		"default": ["..oooooo..", ".oppppppo.", "oppppppppo", "oppphhpppo", "oppppppppo", ".oppppppo.", "..oooooo..", "..........", "..........", ".........."],
	}
	# Semantic overrides kept together so each icon can be reviewed as a
	# vocabulary entry without changing the shared 10x10 renderer.
	patterns["敏捷"] = ["....oo....", "...oppo...", "..oppppo..", ".oppppppo.", "opppsspppo", ".oppppppo.", "..oppppo..", "...oppo...", "....oo....", ".........."]
	patterns["体质"] = ["...oooo...", "..oppppo..", ".oppppppo.", "oppphhhppo", "opppsspppo", "oppppppppo", ".oppppppo.", ".oppppppo.", "..oppppo..", "...oooo..."]
	patterns["智力"] = ["..oo..oo..", ".oppooppo.", "opppsspppo", ".opphhppo.", "oppppppppo", "opppsspppo", "oppppppppo", ".oppppppo.", "..oppppo..", "...oooo..."]
	patterns["灵巧"] = ["..oo..oo..", ".oppooppo.", "oppppppppo", "oppphhhppo", "opppsspppo", ".oppppppo.", "..oppppo..", "..oppppo..", "...oppo...", "....oo...."]
	patterns["感知"] = ["..........", "...oooo...", "..oppppo..", ".opphhppo.", "oppphhhppo", ".opphhppo.", "..oppppo..", "...oooo...", "..........", ".........."]
	patterns["法力"] = ["....oo....", "...oppo...", "..oppppo..", ".oppppppo.", "oppppppppo", "oppphhhppo", ".oppppppo.", ".oppssppo.", "..oppppo..", "...oppo..."]
	patterns["攻击"] = ["op......po", ".op....po.", "..op..po..", "...oppo...", "....oo....", "...oppo...", "..op..po..", ".op....po.", "op......po", ".........."]
	patterns["闪避"] = ["..oo..oo..", ".oppooppo.", "oppp..pppo", "oppp..pppo", ".oppppppo.", "..oppppo..", "...oppo...", "....oo....", "..........", ".........."]
	patterns["暴击"] = ["....oo....", "...oppo...", "....pp....", "..oppppo..", "oppphhhppo", "..oppppo..", "....pp....", "...oppo...", "....oo....", ".........."]
	patterns["智力"] = ["..........", "..op..po..", ".oppppppo.", "opppsspppo", "oppphhpppo", "opppsspppo", ".oppppppo.", "..oppppo..", "...oppo...", ".........."]
	patterns["感知"] = ["..........", "...oooo...", "..oppppo..", ".opphhppo.", "opppsspppo", ".opphhppo.", "..oppppo..", "...oooo...", "..........", ".........."]
	return patterns.get(label, patterns["default"])


static func pixel_icon_palette(label: String) -> Dictionary:
	var palettes: Dictionary = {
		"等级": {"o": Color("#5c351c"), "p": Color("#d88b39"), "h": Color("#ffd27a"), "s": Color("#a85c25")},
		"生命": {"o": Color("#5d241f"), "p": Color("#d24e43"), "h": Color("#ff9a68"), "s": Color("#8c302c")},
		"攻击": {"o": Color("#5c351c"), "p": Color("#d88b39"), "h": Color("#ffd27a"), "s": Color("#a85c25")},
		"护甲": {"o": Color("#3b414b"), "p": Color("#9aa4af"), "h": Color("#e0e6e8"), "s": Color("#596571")},
		"闪避": {"o": Color("#254a42"), "p": Color("#63b89b"), "h": Color("#b7f0c6"), "s": Color("#37806f")},
		"暴击": {"o": Color("#59321a"), "p": Color("#e29a37"), "h": Color("#ffe18a"), "s": Color("#a85f23")},
		"力量": {"o": Color("#5d241f"), "p": Color("#d24e43"), "h": Color("#ff9a68"), "s": Color("#8c302c")},
		"敏捷": {"o": Color("#254a42"), "p": Color("#63b89b"), "h": Color("#b7f0c6"), "s": Color("#37806f")},
		"体质": {"o": Color("#5c351c"), "p": Color("#d88b39"), "h": Color("#ffd27a"), "s": Color("#a85c25")},
		"智力": {"o": Color("#243d5c"), "p": Color("#5da7d9"), "h": Color("#c2edff"), "s": Color("#3974a5")},
		"灵巧": {"o": Color("#254a42"), "p": Color("#63b89b"), "h": Color("#b7f0c6"), "s": Color("#37806f")},
		"感知": {"o": Color("#493b70"), "p": Color("#9e7bd0"), "h": Color("#e6c6ff"), "s": Color("#6d4ba2")},
		"法力": {"o": Color("#243d5c"), "p": Color("#5da7d9"), "h": Color("#c2edff"), "s": Color("#3974a5")},
	}
	return palettes.get(label, {"o": Color("#5c351c"), "p": Color("#d88b39"), "h": Color("#ffd27a"), "s": Color("#a85c25")})
