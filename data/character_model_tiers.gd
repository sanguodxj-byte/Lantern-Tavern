## 角色/怪物体素建模质量档位（图鉴子标签）。
##
## 档位依据当前真实 3D 模型视觉审核结果：
##   - S：旗舰级体块、轮廓和材质层次
##   - A：高完成度、具备稳定三视图识别度
##   - B：可用但存在明显平面化或细节密度不足
##   - C：基础可辨识，整体层次较弱
##   - D：需要优先重做
##   - other：图鉴扫描到的非名单模型
##
## 注意：档位是图鉴质量子标签，不直接授予运行时资格。模型是否可交付由
## ACCEPTED_IDS 在完成逐只独立验收后明确决定，已验收模型仍保留其历史档位。

class_name CharacterModelTiers

const S := "S"
const A := "A"
const B := "B"
const C := "C"
const D := "D"
const OTHER := "other"

## 已通过独立美术验收、允许进入运行时的模型。
## A-D 仍保留在 BY_ID 作为重建队列；完成独立验收前不得加入这里。
const ACCEPTED_IDS: Array[String] = [
	"goblin",
	"dragon",
	"rock_golem",
	"orc_raider",
	"skeleton",
	"troll",
	"player",
	"minotaur",
	"slime",
	"spider",
	"drow_blade",
]

## 图鉴侧栏展示顺序
const TIER_ORDER: Array[String] = [S, A, B, C, D, OTHER]

## 标签 → 显示名（走 TranslationServer）
const DISPLAY_NAMES: Dictionary = {
	S: "S 档",
	A: "A 档",
	B: "B 档",
	C: "C 档",
	D: "D 档",
	OTHER: "其他",
}

## model_id（_model_display_key）→ 档位
## 只对已实际查看的模型重排；尚未进行本轮视觉审核的队列模型保留原档位。
const BY_ID: Dictionary = {
	# 本轮视觉审核：S
	"dragon": S,
	"rock_golem": S,
	# 本轮视觉审核：A
	"drow_blade": A,
	"spider": A,
	"orc_raider": A,
	"skeleton": A,
	"troll": A,
	"player": A,
	"minotaur": A,
	"slime": A,
	# 本轮视觉审核：B
	"goblin": B,
	"plague_doctor": B,
	"cultist_pyromancer": B,
	"bandit_crossbowman": B,
	"duergar_miner": B,
	# 本轮视觉审核：C/D
	"kobold": C,
	"zombie": D,
	# 尚未进行本轮视觉审核的历史队列档位
	"necrolord": A,
	"rat": A,
	"bartender": A,
	# 原 C
	"hobgoblin_legionary": C,
	"bugbear_brute": C,
	"gnoll_hyena": C,
	"lizardfolk_scout": C,
	"troglodyte": C,
	"dark_elf_hexer": C,
	"satyr_marauder": C,
	"harpy_matriarch": C,
	"werewolf_stalker": C,
	"vampire_thrall": C,
	"wight_guard": C,
	"ghoul_feaster": C,
	"mummy_cursebearer": C,
	"cultist_zealot": C,
	"bandit_cutthroat": C,
	"fungal_shambler": C,
	"myconid_sporekeeper": C,
	"elemental_ash": C,
	"elemental_frost": C,
	"elemental_storm": C,
	"gargoyle_sentinel": C,
	"animated_armor": C,
	"oni_revenant": C,
	"shadow_assassin": C,
	# 遗留角色占位
	"character": OTHER,
}


static func is_valid(tier: String) -> bool:
	return TIER_ORDER.has(tier)


static func tier_for(model_id: String) -> String:
	if model_id.is_empty():
		return OTHER
	return String(BY_ID.get(model_id, OTHER))


static func is_accepted(model_id: String) -> bool:
	return ACCEPTED_IDS.has(model_id)


static func accepted_model_ids() -> Array[String]:
	return ACCEPTED_IDS.duplicate()


static func display_name(tier: String) -> String:
	return TranslationServer.translate(String(DISPLAY_NAMES.get(tier, tier)))


static func all_tiers() -> Array[String]:
	return TIER_ORDER.duplicate()


static func all_model_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in BY_ID.keys():
		ids.append(String(id))
	ids.sort()
	return ids


static func model_ids_for_tier(tier: String) -> Array[String]:
	var ids: Array[String] = []
	for id in BY_ID.keys():
		if String(BY_ID[id]) == tier:
			ids.append(String(id))
	ids.sort()
	return ids
