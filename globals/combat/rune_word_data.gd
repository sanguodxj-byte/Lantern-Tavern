extends RefCounted
## 符文之语数据与检测系统。
## 符文之语：将特定符文按配方顺序镶嵌到连续槽位中，可激活强力机制类效果。
##
## 命名方式（参考暗黑破坏神2）：
##   - 每个符文之语拥有独立的梵语主题名（runic_name），不依赖配方符文字符拼接。
##   - 符文之语与符文的关联通过配方（recipe）建立，UI 中以配色高亮显示。
##
## 检测规则：
##   1. 把全部 7 个技能槽的已镶嵌符文，按槽位顺序（0..6）、槽内顺序拼接成「符文序列」。
##      空槽位不贡献符文，也不破坏序列连续性（即跨空槽仍可成词）。
##   2. 若某符文之语的配方（rune id 有序列表）是该符文序列的【连续子串】，则该符文之语激活。
##      顺序必须完全一致，且符文之间不得插入其他符文。
##   3. 多个符文之语可同时激活；其授予的机制被动取并集。
##
## 激活的符文之语会授予「机制类被动」(mechanism_passives)，由 SkillRuntime 在
## recompute_mechanism_passives() 中统一授予，运行时通过 has_mechanism_passive(id) 查询。
## 已落地的符文之语机制被动及其代码 hook：
##   rune_word_sprint_impact      → Player._check_sprint_impact（奔跑撞击敌人）
##   charge_free                  → Player.get_melee_charge_multiplier（满蓄力无需蓄力）
##   rune_word_ranged_no_wear     → EquipmentComponent.apply_weapon_damage（远程不耗耐久）
##   rune_word_shield_no_wear     → EquipmentComponent.apply_shield_damage（盾牌不耗耐久）
##   rune_word_extra_projectile   → PlayerSkillDispatcher / PlayerStateShooting（额外投射物）
##   charge / perfect_block_window → 复用既有机制被动 hook
## 以下为新符文之语机制被动（待实现 hook）：
##   rune_word_throw_explosion    → 投掷物命中时产生火焰爆炸
##   rune_word_hit_slow           → 命中时减缓敌人移动与攻击速度
##   rune_word_execute            → 低血量敌人概率直接击杀
##   rune_word_dodge              → 获得固定闪避概率
##   rune_word_holy_bonus         → 对亡灵额外伤害并持续恢复生命

const RUNE_WORDS: Dictionary = {
	# ── 已落地效果 ──
	"thunder_run": {
		"id": "thunder_run",
		"name": "涌力之语",
		"runic_name": "प्रवेगबल",
		"rarity": "rare",
		"recipe": ["surge", "force", "quick"],
		"grants": ["rune_word_sprint_impact"],
		"desc": "奔跑撞击敌人造成高额撞击伤害，被撞敌人撞墙时受额外地形撞击伤害。",
	},
	"instant_charge": {
		"id": "instant_charge",
		"name": "焰涌之语",
		"runic_name": "अग्निबलप्रवाह",
		"rarity": "rare",
		"recipe": ["ember", "force", "surge"],
		"grants": ["charge", "charge_free"],
		"desc": "无需蓄力即可获得满蓄力增伤。",
	},
	"endless": {
		"id": "endless",
		"name": "回护之语",
		"runic_name": "प्रतिध्वनिरक्षा",
		"rarity": "rare",
		"recipe": ["quick", "echo", "guardian"],
		"grants": ["rune_word_ranged_no_wear"],
		"desc": "远程武器不消耗耐久。",
	},
	"aegis": {
		"id": "aegis",
		"name": "守力之语",
		"runic_name": "रक्षाबल",
		"rarity": "rare",
		"recipe": ["guardian", "guardian", "force"],
		"grants": ["perfect_block_window", "rune_word_shield_no_wear"],
		"desc": "扩大完美格挡窗口，且盾牌不消耗耐久。",
	},
	"echoing": {
		"id": "echoing",
		"name": "涌响之语",
		"runic_name": "प्रतिध्वनिप्रवाह",
		"rarity": "rare",
		"recipe": ["echo", "echo", "surge"],
		"grants": ["rune_word_extra_projectile"],
		"desc": "远程攻击额外发射一枚投射物。",
	},
	# ── 新增（机制被动已定义，效果待实现） ──
	"agnivrishti": {
		"id": "agnivrishti",
		"name": "焰投之语",
		"runic_name": "अग्निक्षेप",
		"rarity": "epic",
		"recipe": ["ember", "ember", "launch"],
		"grants": ["rune_word_throw_explosion"],
		"desc": "踢击/投掷命中的敌人处产生火焰爆炸，波及周围敌人。",
	},
	"nirmoksha": {
		"id": "nirmoksha",
		"name": "霜时之语",
		"runic_name": "हिमकाल",
		"rarity": "epic",
		"recipe": ["hima", "kala", "quick"],
		"grants": ["rune_word_hit_slow"],
		"desc": "所有攻击命中时减缓敌人移动与攻击速度。",
	},
	"mrityuhasta": {
		"id": "mrityuhasta",
		"name": "死投之语",
		"runic_name": "मृत्युक्षेप",
		"rarity": "epic",
		"recipe": ["mrityu", "force", "launch"],
		"grants": ["rune_word_execute"],
		"desc": "击退或抛掷命中的低血量敌人有概率直接处决。",
	},
	"chhayanritya": {
		"id": "chhayanritya",
		"name": "幻响之语",
		"runic_name": "मायाप्रतिध्वनि",
		"rarity": "epic",
		"recipe": ["maya", "maya", "echo"],
		"grants": ["rune_word_dodge"],
		"desc": "获得固定闪避概率，且闪避时产生幻象残影。",
	},
	"dipasamrakshana": {
		"id": "dipasamrakshana",
		"name": "明护之语",
		"runic_name": "दीपायुरक्षा",
		"rarity": "legendary",
		"recipe": ["dipa", "guardian", "ayu"],
		"grants": ["rune_word_holy_bonus"],
		"desc": "对亡灵造成额外伤害，并持续恢复生命值。",
	},
	# ── 新增第二批：元素组合（rare / epic） ──
	"jalapavana": {
		"id": "jalapavana", "name": "风暴之语", "runic_name": "जलपवन",
		"rarity": "rare", "recipe": ["jala", "pavana"],
		"grants": ["rune_word_storm"],
		"desc": "攻击有概率产生范围击退与减速风暴。",
	},
	"bhumiraksha": {
		"id": "bhumiraksha", "name": "地护之语", "runic_name": "भूमिरक्षा",
		"rarity": "rare", "recipe": ["bhumi", "guardian"],
		"grants": ["rune_word_earth_armor"],
		"desc": "受到伤害时减免固定伤害。",
	},
	"tejomarichi": {
		"id": "tejomarichi", "name": "炫光之语", "runic_name": "तेजोमरीचि",
		"rarity": "rare", "recipe": ["tejas", "marichi"],
		"grants": ["rune_word_blinding_light"],
		"desc": "攻击有概率致盲敌人，致盲敌人受到额外伤害。",
	},
	"krishnatamas": {
		"id": "krishnatamas", "name": "暗渊之语", "runic_name": "कृष्णतमस्",
		"rarity": "epic", "recipe": ["krishna", "tamas"],
		"grants": ["rune_word_dark_drain"],
		"desc": "强化暗属性伤害，对致盲敌人汲取生命。",
	},
	"dhumakardama": {
		"id": "dhumakardama", "name": "烟泥之语", "runic_name": "धूमकर्दम",
		"rarity": "rare", "recipe": ["dhuma", "kardama"],
		"grants": ["rune_word_smoke_trap"],
		"desc": "攻击有概率产生烟雾陷阱束缚敌人。",
	},
	"vishajala": {
		"id": "vishajala", "name": "毒流之语", "runic_name": "विषजल",
		"rarity": "rare", "recipe": ["visha", "jala"],
		"grants": ["rune_word_poison_spread"],
		"desc": "毒素效果可蔓延至周围敌人。",
	},
	# ── 新增第三批：战斗组合（rare / epic） ──
	"parabhedana": {
		"id": "parabhedana", "name": "穿透之语", "runic_name": "परभेदन",
		"rarity": "rare", "recipe": ["para", "bhedana"],
		"grants": ["rune_word_armor_pierce"],
		"desc": "攻击无视大量护甲并有概率击破护甲。",
	},
	"dravaspandana": {
		"id": "dravaspandana", "name": "流震之语", "runic_name": "द्रवस्पंदन",
		"rarity": "rare", "recipe": ["drava", "spandana"],
		"grants": ["rune_word_tremor"],
		"desc": "攻击产生范围震颤伤害。",
	},
	"praghananighata": {
		"id": "praghananighata", "name": "冲猛之语", "runic_name": "प्रघाननिघात",
		"rarity": "rare", "recipe": ["praghana", "nighata"],
		"grants": ["rune_word_charge_smash"],
		"desc": "冲刺攻击造成范围猛击伤害。",
	},
	"aghatavikshepa": {
		"id": "aghatavikshepa", "name": "击推之语", "runic_name": "आघातविक्षेप",
		"rarity": "rare", "recipe": ["aghata", "vikshepa"],
		"grants": ["rune_word_impact_knockback"],
		"desc": "命中产生强力击退效果。",
	},
	"nighatabhedana": {
		"id": "nighatabhedana", "name": "猛破之语", "runic_name": "निघातभेदन",
		"rarity": "epic", "recipe": ["nighata", "bhedana"],
		"grants": ["rune_word_sunder_smash"],
		"desc": "猛击有概率直接粉碎敌人护甲。",
	},
	"praghanavikshepa": {
		"id": "praghanavikshepa", "name": "冲推之语", "runic_name": "प्रघानविक्षेप",
		"rarity": "rare", "recipe": ["praghana", "vikshepa", "force"],
		"grants": ["rune_word_charge_knockback"],
		"desc": "冲刺攻击大幅强化击退距离。",
	},
	# ── 新增第四批：神秘组合（epic） ──
	"pranashakti": {
		"id": "pranashakti", "name": "生力之语", "runic_name": "प्राणशक्ति",
		"rarity": "epic", "recipe": ["prana", "shakti"],
		"grants": ["rune_word_vital_power"],
		"desc": "生命值越高伤害越高。",
	},
	"vidyatapas": {
		"id": "vidyatapas", "name": "知苦之语", "runic_name": "विद्यातपस्",
		"rarity": "epic", "recipe": ["vidya", "tapas"],
		"grants": ["rune_word_arcane_focus"],
		"desc": "暴击伤害大幅提升，但消耗生命。",
	},
	"karmadharma": {
		"id": "karmadharma", "name": "业法之语", "runic_name": "कर्मधर्म",
		"rarity": "epic", "recipe": ["karma", "dharma"],
		"grants": ["rune_word_karmic_justice"],
		"desc": "连续命中同一敌人伤害递增。",
	},
	"viryamantra": {
		"id": "viryamantra", "name": "勇咒之语", "runic_name": "वीर्यमन्त्र",
		"rarity": "epic", "recipe": ["virya", "mantra"],
		"grants": ["rune_word_brave_spell"],
		"desc": "生命值越低伤害越高，且免疫恐惧。",
	},
	"yantrachitta": {
		"id": "yantrachitta", "name": "器心之语", "runic_name": "यन्त्रचित्त",
		"rarity": "epic", "recipe": ["yantra", "chitta"],
		"grants": ["rune_word_construct_mind"],
		"desc": "召唤一个自动攻击的构造体。",
	},
	# ── 新增第五批：黑暗组合（epic / legendary） ──
	"raudrabhaya": {
		"id": "raudrabhaya", "name": "怒惧之语", "runic_name": "रौद्रभय",
		"rarity": "epic", "recipe": ["raudra", "bhaya"],
		"grants": ["rune_word_terrible_rage"],
		"desc": "进入狂暴状态，伤害提升但受伤增加，周围敌人恐惧。",
	},
	"ghoranashana": {
		"id": "ghoranashana", "name": "怖毁之语", "runic_name": "घोरनाशन",
		"rarity": "epic", "recipe": ["ghora", "nashana"],
		"grants": ["rune_word_dreadful_destruction"],
		"desc": "对恐惧状态敌人造成毁灭性额外伤害。",
	},
	"vibhatsamrityu": {
		"id": "vibhatsamrityu", "name": "腐死之语", "runic_name": "विभत्समृत्यु",
		"rarity": "epic", "recipe": ["vibhatsa", "mrityu"],
		"grants": ["rune_word_corrupt_death"],
		"desc": "击杀敌人时产生腐蚀区域，持续伤害周围敌人。",
	},
	# ── 新增第六批：神圣组合（legendary） ──
	"siddhimoksha": {
		"id": "siddhimoksha", "name": "成就解脱之语", "runic_name": "सिद्धिमोक्ष",
		"rarity": "legendary", "recipe": ["siddhi", "moksha"],
		"grants": ["rune_word_perfect_liberation"],
		"desc": "免疫控制效果，全面提升属性。",
	},
	"amritayu": {
		"id": "amritayu", "name": "甘露之语", "runic_name": "अमृतायु",
		"rarity": "legendary", "recipe": ["amrita", "ayu"],
		"grants": ["rune_word_immortal_life"],
		"desc": "生命值不会低于1，且持续恢复生命。",
	},
	"vajraparajala": {
		"id": "vajraparajala", "name": "雷穿之语", "runic_name": "वज्रपरजल",
		"rarity": "legendary", "recipe": ["vajra", "para", "jala"],
		"grants": ["rune_word_thunder_stream"],
		"desc": "攻击附加雷电穿透效果，并有概率释放连锁雷电。",
	},
}

## 获取符文之语定义（返回副本）
static func get_rune_word(word_id: String) -> Dictionary:
	return RUNE_WORDS.get(word_id, {}).duplicate(true)

static func has_rune_word(word_id: String) -> bool:
	return RUNE_WORDS.has(word_id)

static func get_all_rune_word_ids() -> Array:
	return RUNE_WORDS.keys()

## 获取符文之语显示名（优先梵语名，回退中文名，再回退 id）
static func get_rune_word_name(word_id: String) -> String:
	var word: Dictionary = RUNE_WORDS.get(word_id, {})
	if word.is_empty():
		return word_id
	return String(word.get("runic_name", word.get("name", word_id)))

## 把 slot_runes（7 个子数组）拼接为连续符文序列。
## 空槽位与非字符串元素跳过，不破坏连续性。
static func flatten_slot_runes(slot_runes: Array) -> Array:
	var flat: Array = []
	for raw in slot_runes:
		if typeof(raw) != TYPE_ARRAY:
			continue
		for r in raw:
			var rid := String(r)
			if not rid.is_empty():
				flat.append(rid)
	return flat

## 检测当前激活的符文之语 id 列表。
## slot_runes: SkillRuntime.slot_runes 结构（Array of Array[String]）。
## 返回有序 id 列表（按 RUNE_WORDS 定义顺序）。
static func detect_active_rune_words(slot_runes: Array) -> Array:
	var flat := flatten_slot_runes(slot_runes)
	var active: Array = []
	for word_id in RUNE_WORDS.keys():
		var recipe: Array = RUNE_WORDS[word_id].get("recipe", [])
		if _is_contiguous_substring(flat, recipe):
			active.append(String(word_id))
	return active

## recipe 是否为 sequence 的连续子串（顺序与连续性均须满足）。
static func _is_contiguous_substring(sequence: Array, recipe: Array) -> bool:
	if recipe.is_empty():
		return false
	var recipe_size := recipe.size()
	if sequence.size() < recipe_size:
		return false
	for start in range(sequence.size() - recipe_size + 1):
		var matched := true
		for i in range(recipe_size):
			if String(sequence[start + i]) != String(recipe[i]):
				matched = false
				break
		if matched:
			return true
	return false

## 取激活符文之语授予的全部机制被动 id（并集，去重，保持顺序）。
static func get_granted_passives(active_word_ids: Array) -> Array:
	var result: Array = []
	for raw in active_word_ids:
		var word: Dictionary = RUNE_WORDS.get(String(raw), {})
		for g in word.get("grants", []):
			var gid := String(g)
			if not result.has(gid):
				result.append(gid)
	return result

## 取单个符文之语授予的机制被动列表（副本）
static func get_word_grants(word_id: String) -> Array:
	var word: Dictionary = RUNE_WORDS.get(word_id, {})
	return word.get("grants", []).duplicate()

## 取包含指定符文的所有符文之语 id 列表（按定义顺序）。
## 用于 UI 悬浮提示：展示某符文参与哪些符文之语。
static func get_rune_words_containing_rune(rune_id: String) -> Array:
	var result: Array = []
	for word_id in RUNE_WORDS.keys():
		var recipe: Array = RUNE_WORDS[word_id].get("recipe", [])
		if recipe.has(rune_id):
			result.append(String(word_id))
	return result

## 取激活符文之语的显示信息列表（供 UI 使用）
static func get_active_word_infos(active_word_ids: Array) -> Array:
	var infos: Array = []
	for raw in active_word_ids:
		var word: Dictionary = RUNE_WORDS.get(String(raw), {})
		if word.is_empty():
			continue
		infos.append({
			"id": String(word.get("id", "")),
			"name": String(word.get("name", "")),
			"runic_name": String(word.get("runic_name", "")),
			"desc": String(word.get("desc", "")),
			"recipe": word.get("recipe", []).duplicate(),
			"grants": word.get("grants", []).duplicate(),
		})
	return infos
