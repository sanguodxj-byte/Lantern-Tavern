class_name SpellRecipeData
extends RefCounted

## 固定法术配方表：符文顺序即法术语法，精确匹配 1~3 个有序符文。
## 每项必须提供可直接绘制的 imagery；配方在运行时不随机生成。

const SPELL_SLOT_COUNT: int = 5
const RUNES_PER_SPELL: int = 3

const RECIPES: Dictionary = {
	"ember": {"id":"spell_ember_bolt","name":"余烬弹","recipe":["ember"],"description":"发射一枚拖曳火星的基础余烬弹。","imagery":"ember_bolt","implementation":"projectile","projectile_id":"elemental_bolt","status":"projectile_ready_not_wired","color":Color("#ff684d")},
	"hima": {"id":"spell_frost_shard","name":"霜晶碎片","recipe":["hima"],"description":"射出一枚尖锐的寒霜晶片。","imagery":"frost_shard","implementation":"projectile","projectile_id":"elemental_bolt","status":"projectile_ready_not_wired","color":Color("#72c8ff")},
	"vajra": {"id":"spell_spark_arc","name":"雷弧","recipe":["vajra"],"description":"释放一道短促的锯齿雷弧。","imagery":"spark_arc","implementation":"projectile","projectile_id":"thunder_bolt","status":"projectile_ready_not_wired","color":Color("#ffe55c")},
	"visha": {"id":"spell_venom_spit","name":"毒液飞沫","recipe":["visha"],"description":"喷射一团带毒滴的腐蚀液。","imagery":"venom_spit","implementation":"projectile","status":"not_wired","color":Color("#69f0ae")},
	"jala": {"id":"spell_water_jet","name":"水流冲击","recipe":["jala"],"description":"喷射一束弯曲的高压水流。","imagery":"water_jet","implementation":"projectile","status":"not_wired","color":Color("#35cbe4")},
	"pavana": {"id":"spell_wind_blade","name":"风刃","recipe":["pavana"],"description":"掷出一片新月形风刃。","imagery":"wind_blade","implementation":"projectile","status":"not_wired","color":Color("#a9e9ff")},
	"bhumi": {"id":"spell_stone_spike","name":"岩刺","recipe":["bhumi"],"description":"从地面刺出一根破碎岩柱。","imagery":"stone_spike","implementation":"ground","status":"not_wired","color":Color("#a9866e")},
	"marichi": {"id":"spell_light_ray","name":"辉光射线","recipe":["marichi"],"description":"射出一束穿透黑暗的金白光线。","imagery":"light_ray","implementation":"ray","status":"not_wired","color":Color("#fff176")},
	"krishna": {"id":"spell_shadow_orb","name":"暗影球","recipe":["krishna"],"description":"凝成一颗吞噬光线的暗影球。","imagery":"shadow_orb","implementation":"projectile","status":"not_wired","color":Color("#7652bd")},
	"ayu": {"id":"spell_minor_heal","name":"生命愈合","recipe":["ayu"],"description":"以叶片与生命滴修复伤势。","imagery":"healing_leaf","implementation":"heal","status":"not_wired","color":Color("#ff80ab")},
	"ember>force": {"id":"spell_fire_bolt","name":"火焰冲击","recipe":["ember","force"],"description":"将余烬压缩成带冲击环的火焰矢。","imagery":"fire_bolt","implementation":"projectile","projectile_id":"elemental_bolt","status":"projectile_ready_not_wired","color":Color("#ff9a3d")},
	"hima>para": {"id":"spell_ice_spear","name":"冰矛术","recipe":["hima","para"],"description":"塑成一支长柄冰矛贯穿目标。","imagery":"ice_spear","implementation":"projectile","status":"not_wired","color":Color("#75c7ff")},
	"vajra>echo": {"id":"spell_echo_thunder","name":"回声雷击","recipe":["vajra","echo"],"description":"雷击命中后在后方留下第二道回声。","imagery":"echo_thunder","implementation":"projectile","projectile_id":"thunder_bolt","status":"projectile_ready_not_wired","color":Color("#f8e65b")},
	"visha>drava": {"id":"spell_poison_cloud","name":"毒雾","recipe":["visha","drava"],"description":"释放翻涌毒雾与下坠毒滴。","imagery":"poison_cloud","implementation":"area","status":"not_wired","color":Color("#77d98f")},
	"jala>guardian": {"id":"spell_water_shield","name":"水幕护盾","recipe":["jala","guardian"],"description":"召出环绕施法者的弧形水幕。","imagery":"water_shield","implementation":"barrier","status":"not_wired","color":Color("#48cde7")},
	"pavana>quick": {"id":"spell_gale_step","name":"疾风步","recipe":["pavana","quick"],"description":"以三道风痕推动施法者瞬步。","imagery":"gale_step","implementation":"movement","status":"not_wired","color":Color("#b8efff")},
	"bhumi>guardian": {"id":"spell_stone_wall","name":"石墙术","recipe":["bhumi","guardian"],"description":"升起由三块巨石组成的壁垒。","imagery":"stone_wall","implementation":"barrier","status":"not_wired","color":Color("#9d826e")},
	"marichi>guardian": {"id":"spell_holy_lantern","name":"守护明灯","recipe":["marichi","guardian"],"description":"召唤一盏金色明灯形成庇护圈。","imagery":"holy_lantern","implementation":"buff","status":"not_wired","color":Color("#ffe79a")},
	"krishna>maya": {"id":"spell_shadow_clone","name":"影分身","recipe":["krishna","maya"],"description":"从黑镜中分离一道人形影像。","imagery":"shadow_clone","implementation":"summon","status":"not_wired","color":Color("#9c70d9")},
	"ayu>jala": {"id":"spell_healing_stream","name":"治疗之泉","recipe":["ayu","jala"],"description":"从圣杯中涌出上升的治疗水流。","imagery":"healing_stream","implementation":"heal","status":"not_wired","color":Color("#7ee6c1")},
	"tapas>shakti": {"id":"spell_overcharge","name":"超载法印","recipe":["tapas","shakti"],"description":"以破裂的能量核心换取爆发力量。","imagery":"overcharge_core","implementation":"buff","status":"not_wired","color":Color("#ff5a39")},
	"mantra>echo": {"id":"spell_resonance_bell","name":"共鸣咒钟","recipe":["mantra","echo"],"description":"敲响一口释放同心声波的咒钟。","imagery":"resonance_bell","implementation":"area","status":"not_wired","color":Color("#bb75d9")},
	"yantra>shakti": {"id":"spell_arcane_turret","name":"奥术炮台","recipe":["yantra","shakti"],"description":"展开一座三足奥术炮台。","imagery":"arcane_turret","implementation":"summon","status":"not_wired","color":Color("#55b5c5")},
	"ember>force>launch": {"id":"spell_fireball","name":"火球术","recipe":["ember","force","launch"],"description":"掷出带燃烧尾迹与爆炸环的大型火球。","imagery":"fireball","implementation":"projectile","projectile_id":"elemental_bolt","status":"projectile_ready_not_wired","color":Color("#ffb238")},
	"hima>force>guardian": {"id":"spell_frost_barrier","name":"寒霜屏障","recipe":["hima","force","guardian"],"description":"升起排列成弧形的锯齿冰晶屏障。","imagery":"frost_barrier","implementation":"barrier","status":"not_wired","color":Color("#75c7ff")},
	"vajra>surge>echo": {"id":"spell_chain_lightning","name":"连锁闪电","recipe":["vajra","surge","echo"],"description":"一道闪电在三个目标节点间连续跳跃。","imagery":"chain_lightning","implementation":"projectile","projectile_id":"thunder_bolt","status":"projectile_ready_not_wired","color":Color("#f8e65b")},
	"visha>surge>launch": {"id":"spell_acid_meteor","name":"酸蚀陨星","recipe":["visha","surge","launch"],"description":"坠下一颗开裂并飞溅酸液的毒陨石。","imagery":"acid_meteor","implementation":"projectile","status":"not_wired","color":Color("#8ce56e")},
	"jala>pavana>surge": {"id":"spell_whirlpool","name":"涡流术","recipe":["jala","pavana","surge"],"description":"形成吸入碎片的旋转水涡。","imagery":"whirlpool","implementation":"area","status":"not_wired","color":Color("#45c8e8")},
	"bhumi>spandana>force": {"id":"spell_earthquake","name":"震地术","recipe":["bhumi","spandana","force"],"description":"拳形冲击砸裂地面并扩散震波。","imagery":"earthquake","implementation":"area","status":"not_wired","color":Color("#ba7d52")},
	"marichi>dharma>guardian": {"id":"spell_sanctuary","name":"神圣庇护所","recipe":["marichi","dharma","guardian"],"description":"展开带立柱与光冠的神圣穹顶。","imagery":"sanctuary","implementation":"barrier","status":"not_wired","color":Color("#fff0a5")},
	"krishna>mrityu>shakti": {"id":"spell_death_orb","name":"死亡黑洞","recipe":["krishna","mrityu","shakti"],"description":"制造环绕残月与骸骨的吞噬黑洞。","imagery":"death_orb","implementation":"area","status":"not_wired","color":Color("#6f4da2")},
	"ayu>amrita>dharma": {"id":"spell_greater_heal","name":"甘露圣疗","recipe":["ayu","amrita","dharma"],"description":"圣杯倾下甘露，在十字光印中大幅治疗。","imagery":"greater_heal","implementation":"heal","status":"not_wired","color":Color("#baf1d7")},
	"yantra>mantra>echo": {"id":"spell_summon_portal","name":"召唤之门","recipe":["yantra","mantra","echo"],"description":"开启带符文支架与漩涡核心的召唤门。","imagery":"summon_portal","implementation":"summon","status":"not_wired","color":Color("#9d70cf")},
}


static func recipe_key(rune_ids: Array) -> String:
	var normalized: Array[String] = []
	for raw_id in rune_ids:
		var rune_id := String(raw_id).strip_edges()
		if rune_id.is_empty():
			break
		normalized.append(rune_id)
	return ">".join(normalized)


static func resolve(rune_ids: Array) -> Dictionary:
	var key := recipe_key(rune_ids)
	if key.is_empty():
		return {}
	return Dictionary(RECIPES.get(key, {})).duplicate(true)


static func has_recipe(rune_ids: Array) -> bool:
	return not resolve(rune_ids).is_empty()


static func get_all_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in RECIPES.keys():
		result.append(Dictionary(RECIPES[key]).duplicate(true))
	return result


static func get_spell_by_id(spell_id: String) -> Dictionary:
	for spell in RECIPES.values():
		if String(spell.get("id", "")) == spell_id:
			return Dictionary(spell).duplicate(true)
	return {}
