extends RefCounted
## 符文数据与技能修饰器。
## 符文可挂载到主动/被动技能槽，修改数值并附加机制标签。
##
## 命名语言：梵语（天城文 Devanagari），每个符文以梵语词为显示名。
## 符文之语拥有独立主题名，通过配方（recipe）与符文建立关联。

const RUNES: Dictionary = {
	# ── 元素系（common）12 个 ──
	"ember": {
		"id": "ember", "name": "余烬符文", "runic_name": "अग्नि", "rarity": "common",
		"mods": {"damage_mult": {"mul": 1.20}},
		"mechanics": {"burn_chance": 25, "burn_sec": 3.0},
		"desc": "提高伤害，并附加燃烧概率。",
	},
	"hima": {
		"id": "hima", "name": "霜寒符文", "runic_name": "हिम", "rarity": "common",
		"mods": {"damage_mult": {"mul": 1.15}},
		"mechanics": {"slow_chance": 30, "slow_sec": 2.0},
		"desc": "附加冰冷伤害并减速敌人。",
	},
	"vajra": {
		"id": "vajra", "name": "雷霆符文", "runic_name": "वज्र", "rarity": "common",
		"mods": {"damage_mult": {"mul": 1.15}},
		"mechanics": {"stun_chance": 20, "stun_sec": 0.5},
		"desc": "附加雷电伤害并有概率短暂眩晕。",
	},
	"visha": {
		"id": "visha", "name": "剧毒符文", "runic_name": "विष", "rarity": "common",
		"mods": {"damage_mult": {"mul": 1.10}},
		"mechanics": {"poison_chance": 35, "poison_sec": 5.0},
		"desc": "附加毒素伤害并持续扣血。",
	},
	"jala": {
		"id": "jala", "name": "流水符文", "runic_name": "जल", "rarity": "common",
		"mods": {"knockback_m": {"mul": 1.15}},
		"mechanics": {"wet_chance": 40, "slow_sec": 1.5},
		"desc": "附加水流伤害并有概率浸湿敌人。",
	},
	"pavana": {
		"id": "pavana", "name": "疾风符文", "runic_name": "पवन", "rarity": "common",
		"mods": {"knockback_m": {"mul": 1.25}},
		"mechanics": {"wind_push": true},
		"desc": "附加风属性击退效果。",
	},
	"bhumi": {
		"id": "bhumi", "name": "大地符文", "runic_name": "भूमि", "rarity": "common",
		"mods": {"armor_bonus": {"add": 3}},
		"mechanics": {"earth_armor": true},
		"desc": "提升防御力并获得大地护甲。",
	},
	"tejas": {
		"id": "tejas", "name": "炽光符文", "runic_name": "तेजस्", "rarity": "common",
		"mods": {"damage_mult": {"mul": 1.12}},
		"mechanics": {"burn_chance": 15, "blind_chance": 20},
		"desc": "附加光热伤害并有概率致盲。",
	},
	"krishna": {
		"id": "krishna", "name": "暗影符文", "runic_name": "कृष्ण", "rarity": "common",
		"mods": {"crit_chance": {"add": 5}},
		"mechanics": {"blind_chance": 25, "dark_dmg_mult": 1.10},
		"desc": "提高暴击并有概率致盲敌人。",
	},
	"marichi": {
		"id": "marichi", "name": "光芒符文", "runic_name": "मरीचि", "rarity": "common",
		"mods": {"damage_mult": {"mul": 1.08}},
		"mechanics": {"ray_chance": 30, "holy_dmg_mult": 1.10},
		"desc": "攻击有概率释放光芒射线。",
	},
	"kardama": {
		"id": "kardama", "name": "泥土符文", "runic_name": "कर्दम", "rarity": "common",
		"mods": {"knockback_m": {"mul": 0.90}},
		"mechanics": {"ensnare_chance": 25, "ensnare_sec": 2.0},
		"desc": "有概率束缚敌人使其无法移动。",
	},
	"dhuma": {
		"id": "dhuma", "name": "烟雾符文", "runic_name": "धूम", "rarity": "common",
		"mods": {"cooldown": {"mul": 0.95}},
		"mechanics": {"blind_chance": 20, "choke_chance": 15, "choke_sec": 1.5},
		"desc": "有概率致盲并窒息敌人。",
	},
	# ── 战斗系（uncommon）14 个 ──
	"force": {
		"id": "force", "name": "冲击符文", "runic_name": "बल", "rarity": "uncommon",
		"mods": {"knockback_m": {"mul": 1.50}, "stun_sec": {"add": 0.2}},
		"mechanics": {"impact_bonus": true},
		"desc": "强化击退与短暂硬直。",
	},
	"quick": {
		"id": "quick", "name": "迅捷符文", "runic_name": "वेग", "rarity": "uncommon",
		"mods": {"cooldown": {"mul": 0.80}, "cast_time": {"mul": 0.80}},
		"mechanics": {"quickened": true},
		"desc": "降低冷却与前摇。",
	},
	"surge": {
		"id": "surge", "name": "奔涌符文", "runic_name": "प्रवाह", "rarity": "uncommon",
		"mods": {"dash_speed_mps": {"add": 2.0}, "physical_impact_damage_mult": {"add": 0.18}},
		"mechanics": {"charge_impulse_bonus": true},
		"desc": "提高冲撞位移冲量，并强化后续地形撞击伤害。",
	},
	"launch": {
		"id": "launch", "name": "抛掷符文", "runic_name": "क्षेप", "rarity": "uncommon",
		"mods": {"knockback_m": {"mul": 1.35}, "physical_impact_damage_mult": {"add": 0.20}},
		"mechanics": {"launch_distance_bonus": true},
		"desc": "提高踢击给予的位移距离，并强化落点撞击伤害。",
	},
	"echo": {
		"id": "echo", "name": "回响符文", "runic_name": "प्रतिध्वनि", "rarity": "rare",
		"mods": {"cooldown": {"mul": 1.10}},
		"mechanics": {"extra_projectiles": 1, "repeat_count": 1},
		"desc": "额外触发一次机制，但略微增加冷却。",
	},
	"guardian": {
		"id": "guardian", "name": "守护符文", "runic_name": "रक्षा", "rarity": "uncommon",
		"mods": {"buff_value": {"mul": 1.20}, "buff_sec": {"add": 1.0}},
		"mechanics": {"passive_guard": true},
		"desc": "强化被动或增益类技能的数值与持续时间。",
	},
	"para": {
		"id": "para", "name": "穿透符文", "runic_name": "पर", "rarity": "uncommon",
		"mods": {"armor_pierce_percent": {"add": 10}},
		"mechanics": {"pierce_bonus": true},
		"desc": "攻击无视部分护甲。",
	},
	"drava": {
		"id": "drava", "name": "流动符文", "runic_name": "द्रव", "rarity": "uncommon",
		"mods": {"cast_time": {"mul": 0.85}, "cooldown": {"mul": 0.90}},
		"mechanics": {"fluid_motion": true},
		"desc": "使技能更加流畅连贯。",
	},
	"spandana": {
		"id": "spandana", "name": "震颤符文", "runic_name": "स्पंदन", "rarity": "uncommon",
		"mods": {"damage_mult": {"mul": 1.10}},
		"mechanics": {"tremor_chance": 30, "tremor_sec": 1.0},
		"desc": "攻击有概率产生震颤效果。",
	},
	"praghana": {
		"id": "praghana", "name": "前冲符文", "runic_name": "प्रघान", "rarity": "uncommon",
		"mods": {"dash_speed_mps": {"add": 1.5}},
		"mechanics": {"charge_impulse_bonus": true, "forward_momentum": true},
		"desc": "强化向前冲撞的动量。",
	},
	"nighata": {
		"id": "nighata", "name": "猛击符文", "runic_name": "निघात", "rarity": "uncommon",
		"mods": {"damage_mult": {"mul": 1.25}, "stun_sec": {"add": 0.3}},
		"mechanics": {"heavy_strike": true},
		"desc": "大幅提高伤害但增加硬直。",
	},
	"bhedana": {
		"id": "bhedana", "name": "破甲符文", "runic_name": "भेदन", "rarity": "uncommon",
		"mods": {"armor_pierce_percent": {"add": 20}},
		"mechanics": {"armor_break_chance": 25, "armor_break_sec": 3.0},
		"desc": "有概率击破敌人护甲。",
	},
	"aghata": {
		"id": "aghata", "name": "打击符文", "runic_name": "आघात", "rarity": "uncommon",
		"mods": {"damage_mult": {"mul": 1.15}, "knockback_m": {"mul": 1.20}},
		"mechanics": {"impact_bonus": true},
		"desc": "强化攻击的打击感与击退。",
	},
	"vikshepa": {
		"id": "vikshepa", "name": "推移符文", "runic_name": "विक्षेप", "rarity": "uncommon",
		"mods": {"knockback_m": {"mul": 1.40}},
		"mechanics": {"displacement_bonus": true},
		"desc": "大幅强化击退距离。",
	},
	# ── 神秘系（rare）12 个 ──
	"ayu": {
		"id": "ayu", "name": "生命符文", "runic_name": "आयु", "rarity": "rare",
		"mods": {},
		"mechanics": {"lifesteal_pct": 5, "hp_regen_per_sec": 2.0},
		"desc": "攻击吸取生命，并持续恢复生命值。",
	},
	"maya": {
		"id": "maya", "name": "幻象符文", "runic_name": "माया", "rarity": "rare",
		"mods": {"crit_chance": {"add": 8}},
		"mechanics": {"dodge_chance": 10},
		"desc": "提高暴击与闪避概率。",
	},
	"prana": {
		"id": "prana", "name": "生气符文", "runic_name": "प्राण", "rarity": "rare",
		"mods": {},
		"mechanics": {"hp_regen_per_sec": 3.0, "stamina_regen_per_sec": 2.0},
		"desc": "持续恢复生命与体力。",
	},
	"shakti": {
		"id": "shakti", "name": "能量符文", "runic_name": "शक्ति", "rarity": "rare",
		"mods": {"damage_mult": {"mul": 1.30}},
		"mechanics": {"energy_cost_mult": 1.20},
		"desc": "大幅提高伤害但增加能量消耗。",
	},
	"vidya": {
		"id": "vidya", "name": "知识符文", "runic_name": "विद्या", "rarity": "rare",
		"mods": {"crit_chance": {"add": 10}, "crit_mult": {"add": 0.15}},
		"mechanics": {"arcane_insight": true},
		"desc": "提高暴击率与暴击伤害。",
	},
	"tapas": {
		"id": "tapas", "name": "苦行符文", "runic_name": "तपस्", "rarity": "rare",
		"mods": {"damage_mult": {"mul": 1.20}},
		"mechanics": {"overcharge": true, "self_damage_pct": 3},
		"desc": "以自身生命为代价大幅提高伤害。",
	},
	"karma": {
		"id": "karma", "name": "业力符文", "runic_name": "कर्म", "rarity": "rare",
		"mods": {},
		"mechanics": {"stacking_dmg_per_hit": 0.05, "stack_max": 10},
		"desc": "连续命中同一敌人时伤害递增。",
	},
	"dharma": {
		"id": "dharma", "name": "正法符文", "runic_name": "धर्म", "rarity": "rare",
		"mods": {"damage_mult": {"mul": 1.15}},
		"mechanics": {"righteous_dmg_mult": 1.25, "undead_dmg_mult": 1.20},
		"desc": "对邪恶与亡灵造成额外伤害。",
	},
	"virya": {
		"id": "virya", "name": "勇毅符文", "runic_name": "वीर्य", "rarity": "rare",
		"mods": {},
		"mechanics": {"fear_resist": 80, "stun_resist": 50},
		"desc": "大幅抵抗恐惧与眩晕。",
	},
	"mantra": {
		"id": "mantra", "name": "咒语符文", "runic_name": "मन्त्र", "rarity": "rare",
		"mods": {"buff_value": {"mul": 1.30}, "buff_sec": {"mul": 1.20}},
		"mechanics": {"spell_power_bonus": true},
		"desc": "强化增益与法术效果。",
	},
	"yantra": {
		"id": "yantra", "name": "器械符文", "runic_name": "यन्त्र", "rarity": "rare",
		"mods": {"cooldown": {"mul": 0.85}},
		"mechanics": {"construct_summon": true},
		"desc": "有概率召唤自动攻击的构造体。",
	},
	"chitta": {
		"id": "chitta", "name": "心念符文", "runic_name": "चित्त", "rarity": "rare",
		"mods": {"crit_chance": {"add": 6}, "cast_time": {"mul": 0.90}},
		"mechanics": {"focus_mode": true},
		"desc": "进入专注模式，提高暴击与施法速度。",
	},
	# ── 黑暗系（epic）8 个 ──
	"mrityu": {
		"id": "mrityu", "name": "死亡符文", "runic_name": "मृत्यु", "rarity": "epic",
		"mods": {},
		"mechanics": {"execute_threshold": 0.15},
		"desc": "对低血量敌人有概率直接处决。",
	},
	"kala": {
		"id": "kala", "name": "时间符文", "runic_name": "काल", "rarity": "epic",
		"mods": {},
		"mechanics": {"enemy_slow_pct": 0.20},
		"desc": "命中敌人时减缓其行动速度。",
	},
	"tamas": {
		"id": "tamas", "name": "黑暗符文", "runic_name": "तमस्", "rarity": "epic",
		"mods": {"dark_dmg_mult": {"mul": 1.30}},
		"mechanics": {"blind_chance": 40, "life_drain_pct": 8},
		"desc": "强化暗属性伤害并汲取生命。",
	},
	"raudra": {
		"id": "raudra", "name": "暴怒符文", "runic_name": "रौद्र", "rarity": "epic",
		"mods": {"damage_mult": {"mul": 1.40}},
		"mechanics": {"berserk_mode": true, "self_dmg_mult": 1.15},
		"desc": "进入狂暴状态，伤害大增但受伤增加。",
	},
	"bhaya": {
		"id": "bhaya", "name": "恐惧符文", "runic_name": "भय", "rarity": "epic",
		"mods": {},
		"mechanics": {"fear_chance": 30, "fear_sec": 3.0},
		"desc": "有概率使敌人恐惧逃跑。",
	},
	"ghora": {
		"id": "ghora", "name": "可怖符文", "runic_name": "घोर", "rarity": "epic",
		"mods": {"damage_mult": {"mul": 1.20}},
		"mechanics": {"terror_chance": 25, "terror_sec": 2.5, "fear_dmg_mult": 1.30},
		"desc": "对恐惧状态敌人造成额外伤害。",
	},
	"nashana": {
		"id": "nashana", "name": "毁灭符文", "runic_name": "नाशन", "rarity": "epic",
		"mods": {"damage_mult": {"mul": 1.25}},
		"mechanics": {"sunder_chance": 20, "armor_break_sec": 4.0},
		"desc": "有概率粉碎敌人护甲。",
	},
	"vibhatsa": {
		"id": "vibhatsa", "name": "厌恶符文", "runic_name": "विभत्स", "rarity": "epic",
		"mods": {},
		"mechanics": {"corrupt_chance": 20, "corrupt_sec": 5.0, "corrupt_dmg_per_sec": 4.0},
		"desc": "有概率腐蚀敌人，持续受到伤害。",
	},
	# ── 神圣系（legendary）4 个 ──
	"dipa": {
		"id": "dipa", "name": "明灯符文", "runic_name": "दीप", "rarity": "legendary",
		"mods": {},
		"mechanics": {"holy_dmg_mult": 1.30, "undead_dmg_mult": 1.50},
		"desc": "神圣伤害加成，对亡灵造成额外伤害。",
	},
	"siddhi": {
		"id": "siddhi", "name": "成就符文", "runic_name": "सिद्धि", "rarity": "legendary",
		"mods": {"damage_mult": {"mul": 1.35}, "crit_chance": {"add": 12}},
		"mechanics": {"perfection": true},
		"desc": "全面提升战斗能力。",
	},
	"moksha": {
		"id": "moksha", "name": "解脱符文", "runic_name": "मोक्ष", "rarity": "legendary",
		"mods": {},
		"mechanics": {"cc_immune": true, "damage_reduce_pct": 0.15},
		"desc": "免疫控制效果并减免伤害。",
	},
	"amrita": {
		"id": "amrita", "name": "甘露符文", "runic_name": "अमृत", "rarity": "legendary",
		"mods": {},
		"mechanics": {"hp_regen_per_sec": 5.0, "death_save": true},
		"desc": "持续恢复生命，致命伤害时有概率保留1点生命。",
	},
}

## 每个符文的专属显示色（用于 UI 中符文名称与配方的着色）。
const RUNE_COLORS: Dictionary = {
	# 元素系
	"ember": "#FF5252", "hima": "#448AFF", "vajra": "#FFEA00", "visha": "#69F0AE",
	"jala": "#00B8D4", "pavana": "#80D8FF", "bhumi": "#8D6E63", "tejas": "#FFB300",
	"krishna": "#311B92", "marichi": "#FFF176", "kardama": "#795548", "dhuma": "#9E9E9E",
	# 战斗系
	"force": "#FF9100", "quick": "#00E5FF", "surge": "#76FF03", "launch": "#E040FB",
	"echo": "#FF6E40", "guardian": "#64FFDA", "para": "#FF8A80", "drava": "#26C6DA",
	"spandana": "#FF7043", "praghana": "#66BB6A", "nighata": "#EF5350", "bhedana": "#AB47BC",
	"aghata": "#FFCA28", "vikshepa": "#29B6F6",
	# 神秘系
	"ayu": "#FF80AB", "maya": "#CC66FF", "prana": "#F06292", "shakti": "#FF1744",
	"vidya": "#00BFA5", "tapas": "#FF6F00", "karma": "#FFD600", "dharma": "#00E676",
	"virya": "#C2185B", "mantra": "#7B1FA2", "yantra": "#455A64", "chitta": "#00ACC1",
	# 黑暗系
	"mrityu": "#BDBDBD", "kala": "#7C4DFF", "tamas": "#1A237E", "raudra": "#D84315",
	"bhaya": "#4A148C", "ghora": "#827717", "nashana": "#BF360C", "vibhatsa": "#3E2723",
	# 神圣系
	"dipa": "#FFD740", "siddhi": "#FF3D00", "moksha": "#18FFFF", "amrita": "#B2DFDB",
}

## 获取符文专属显示色（未知符文回退白色）
static func get_rune_color(rune_id: String) -> String:
	return String(RUNE_COLORS.get(rune_id, "#FFFFFF"))

const SOURCE_WEIGHTS: Dictionary = {
	"chest": {
		# common 元素系 — 高权重
		"ember": 14.0, "hima": 13.0, "vajra": 12.0, "visha": 11.0,
		"jala": 10.0, "pavana": 10.0, "bhumi": 9.0, "tejas": 9.0,
		"krishna": 7.0, "marichi": 7.0, "kardama": 6.0, "dhuma": 6.0,
		# uncommon 战斗系 — 中权重
		"force": 5.0, "quick": 5.0, "surge": 4.0, "launch": 4.0,
		"guardian": 3.0, "para": 3.0, "drava": 2.5, "spandana": 2.5,
		"praghana": 2.0, "nighata": 2.0, "bhedana": 1.5, "aghata": 1.5, "vikshepa": 1.5,
		"echo": 1.2,
		# rare 神秘系 — 低权重
		"ayu": 1.0, "maya": 0.8, "prana": 0.8, "shakti": 0.6,
		"vidya": 0.5, "tapas": 0.5, "karma": 0.4, "dharma": 0.4,
		"virya": 0.3, "mantra": 0.3, "yantra": 0.2, "chitta": 0.2,
		# epic 黑暗系 — 极低权重
		"mrityu": 0.15, "kala": 0.12, "tamas": 0.10, "raudra": 0.08,
		"bhaya": 0.06, "ghora": 0.05, "nashana": 0.04, "vibhatsa": 0.03,
		# legendary 神圣系 — 稀有
		"dipa": 0.02, "siddhi": 0.015, "moksha": 0.01, "amrita": 0.008,
	},
	"elite": {
		"ember": 8.0, "hima": 8.0, "vajra": 8.0, "visha": 7.0,
		"jala": 7.0, "pavana": 7.0, "bhumi": 6.0, "tejas": 6.0,
		"krishna": 5.0, "marichi": 5.0, "kardama": 4.0, "dhuma": 4.0,
		"force": 8.0, "quick": 7.0, "surge": 7.0, "launch": 7.0,
		"guardian": 6.0, "para": 5.0, "drava": 4.0, "spandana": 4.0,
		"praghana": 4.0, "nighata": 3.5, "bhedana": 3.0, "aghata": 3.0, "vikshepa": 3.0,
		"echo": 5.0,
		"ayu": 3.0, "maya": 2.5, "prana": 2.5, "shakti": 2.0,
		"vidya": 2.0, "tapas": 1.5, "karma": 1.5, "dharma": 1.5,
		"virya": 1.2, "mantra": 1.0, "yantra": 1.0, "chitta": 1.0,
		"mrityu": 1.0, "kala": 0.8, "tamas": 0.7, "raudra": 0.6,
		"bhaya": 0.5, "ghora": 0.4, "nashana": 0.3, "vibhatsa": 0.25,
		"dipa": 0.2, "siddhi": 0.15, "moksha": 0.1, "amrita": 0.08,
	},
	"boss": {
		"ember": 3.0, "hima": 3.0, "vajra": 3.0, "visha": 3.0,
		"jala": 3.0, "pavana": 3.0, "bhumi": 3.0, "tejas": 3.0,
		"krishna": 3.0, "marichi": 3.0, "kardama": 2.0, "dhuma": 2.0,
		"force": 6.0, "quick": 5.0, "surge": 6.0, "launch": 6.0,
		"guardian": 5.0, "para": 4.0, "drava": 4.0, "spandana": 4.0,
		"praghana": 4.0, "nighata": 4.0, "bhedana": 3.5, "aghata": 3.5, "vikshepa": 3.5,
		"echo": 8.0,
		"ayu": 5.0, "maya": 4.5, "prana": 4.0, "shakti": 4.0,
		"vidya": 3.5, "tapas": 3.0, "karma": 3.0, "dharma": 3.0,
		"virya": 2.5, "mantra": 2.5, "yantra": 2.5, "chitta": 2.5,
		"mrityu": 4.0, "kala": 3.5, "tamas": 3.0, "raudra": 3.0,
		"bhaya": 2.5, "ghora": 2.0, "nashana": 2.0, "vibhatsa": 1.5,
		"dipa": 1.5, "siddhi": 1.2, "moksha": 1.0, "amrita": 0.8,
	},
}

static func get_rune(rune_id: String) -> Dictionary:
	return RUNES.get(rune_id, {}).duplicate(true)

static func has_rune(rune_id: String) -> bool:
	return RUNES.has(rune_id)

static func get_all_rune_ids() -> Array:
	return RUNES.keys()

## 按指定来源权重无放回抽取互不重复的符文候选。
## rng 可由测试或确定性玩法注入；运行时省略时使用全局随机源。
static func roll_unique_rune_ids(
	source: String = "chest",
	count: int = 3,
	rng: RandomNumberGenerator = null
) -> Array[String]:
	var result: Array[String] = []
	if count <= 0:
		return result
	var pool: Dictionary = SOURCE_WEIGHTS.get(source, SOURCE_WEIGHTS["chest"]).duplicate()
	while result.size() < mini(count, pool.size()):
		var total := 0.0
		for rune_id in pool.keys():
			total += maxf(float(pool[rune_id]), 0.0)
		if total <= 0.0:
			break
		var roll := (rng.randf() if rng != null else randf()) * total
		var cursor := 0.0
		var selected_id := ""
		for raw_id in pool.keys():
			cursor += maxf(float(pool[raw_id]), 0.0)
			if roll <= cursor:
				selected_id = String(raw_id)
				break
		if selected_id.is_empty():
			selected_id = String(pool.keys()[0])
		result.append(selected_id)
		pool.erase(selected_id)
	return result

## 获取符文显示名（梵语天城文）。
static func get_rune_name(rune_id: String) -> String:
	var rune := get_rune(rune_id)
	if rune.is_empty():
		return rune_id
	return String(rune.get("runic_name", rune_id))

## 将拉丁字母文本转换为古弗萨克 (Elder Futhark) 如尼文字。
## 保留用于历史兼容；当前符文显示名使用梵语 runic_name 字段。
static func to_runic(text: String) -> String:
	var result := ""
	for ch in text.to_lower():
		result += _latin_to_runic(ch)
	return result

static func _latin_to_runic(ch: String) -> String:
	match ch:
		"a": return "ᚨ"
		"b": return "ᛒ"
		"c": return "ᚲ"
		"d": return "ᛞ"
		"e": return "ᛖ"
		"f": return "ᚠ"
		"g": return "ᚷ"
		"h": return "ᚺ"
		"i": return "ᛁ"
		"j": return "ᛃ"
		"k": return "ᚲ"
		"l": return "ᛚ"
		"m": return "ᛗ"
		"n": return "ᚾ"
		"o": return "ᛟ"
		"p": return "ᛈ"
		"q": return "ᚲ"
		"r": return "ᚱ"
		"s": return "ᛋ"
		"t": return "ᛏ"
		"u": return "ᚢ"
		"v": return "ᚹ"
		"w": return "ᚹ"
		"x": return "ᚲ"
		"y": return "ᛁ"
		"z": return "ᛉ"
		_: return ch

static func apply_runes(skill: Dictionary, rune_ids: Array) -> Dictionary:
	if skill.is_empty():
		return {}
	var result: Dictionary = skill.duplicate(true)
	var applied: Array = []
	var mechanics: Dictionary = result.get("rune_effects", {}).duplicate(true)
	for raw_id in rune_ids:
		var rune_id := String(raw_id)
		var rune := get_rune(rune_id)
		if rune.is_empty():
			continue
		applied.append(rune_id)
		var mods: Dictionary = rune.get("mods", {})
		for key in mods.keys():
			_apply_mod(result, String(key), mods[key])
		var rune_mechanics: Dictionary = rune.get("mechanics", {})
		for key in rune_mechanics.keys():
			mechanics[key] = rune_mechanics[key]
	result["rune_ids"] = applied
	result["rune_effects"] = mechanics
	return result

static func roll_rune(source: String = "chest") -> Dictionary:
	var weights: Dictionary = SOURCE_WEIGHTS.get(source, SOURCE_WEIGHTS["chest"])
	var total := 0.0
	for rune_id in weights.keys():
		total += float(weights[rune_id])
	if total <= 0.0:
		return {}
	var roll := randf() * total
	var cursor := 0.0
	for rune_id in weights.keys():
		cursor += float(weights[rune_id])
		if roll <= cursor:
			return get_rune(String(rune_id))
	return get_rune(String(weights.keys()[0]))

static func _apply_mod(skill: Dictionary, key: String, mod: Dictionary) -> void:
	var current = skill.get(key, 0)
	if typeof(current) == TYPE_DICTIONARY:
		var updated: Dictionary = current.duplicate(true)
		for child_key in updated.keys():
			if typeof(updated[child_key]) == TYPE_INT or typeof(updated[child_key]) == TYPE_FLOAT:
				updated[child_key] = _apply_number(float(updated[child_key]), mod)
		skill[key] = updated
	elif typeof(current) == TYPE_INT or typeof(current) == TYPE_FLOAT:
		skill[key] = _apply_number(float(current), mod)

static func _apply_number(value: float, mod: Dictionary) -> float:
	var result := value
	if mod.has("mul"):
		result *= float(mod["mul"])
	if mod.has("add"):
		result += float(mod["add"])
	return result
