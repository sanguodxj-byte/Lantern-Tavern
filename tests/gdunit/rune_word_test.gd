extends GdUnitTestSuite
## 符文之语（RuneWord）测试套件。
## 覆盖：纯函数检测（flatten/detect/grants）+ SkillRuntime 集成（镶嵌→授予、卸下→移除、幂等）。

const RWD := preload("res://globals/combat/rune_word_data.gd")
const RD := preload("res://globals/combat/rune_data.gd")
const SR := preload("res://globals/combat/skill_runtime.gd")

var sr: Node
var ap: Node

func before() -> void:
	sr = Engine.get_main_loop().root.get_node_or_null("SkillRuntime")
	ap = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if sr: sr.reset()
	if ap: ap.reset()

func after() -> void:
	if sr: sr.reset()
	if ap: ap.reset()

# ---------- 数据完整性 ----------

func test_all_rune_word_recipes_use_valid_runes() -> void:
	for word_id in RWD.get_all_rune_word_ids():
		var word: Dictionary = RWD.get_rune_word(String(word_id))
		var recipe: Array = word.get("recipe", [])
		assert_bool(not recipe.is_empty()) \
			.override_failure_message("%s 配方不应为空" % word_id) \
			.is_true()
		for r in recipe:
			assert_bool(RD.has_rune(String(r))) \
				.override_failure_message("%s 配方含未知符文 %s" % [word_id, r]) \
				.is_true()

func test_every_rune_word_grants_at_least_one_passive() -> void:
	for word_id in RWD.get_all_rune_word_ids():
		var grants: Array = RWD.get_word_grants(String(word_id))
		assert_bool(not grants.is_empty()) \
			.override_failure_message("%s 应至少授予 1 个机制被动" % word_id) \
			.is_true()

## 语义关联验证：每个符文之语的梵语名(runic_name)必须包含至少一个配方符文的梵语名(runic_name)作为子串。
## 这确保符文之语名称与配方符文有直接的词根关联，而非无意义的独立命名。
func test_rune_word_name_embeds_recipe_rune_sanskrit() -> void:
	for word_id in RWD.get_all_rune_word_ids():
		var word: Dictionary = RWD.get_rune_word(String(word_id))
		var word_sanskrit := String(word.get("runic_name", ""))
		var recipe: Array = word.get("recipe", [])
		var found_match := false
		for r in recipe:
			var rid := String(r)
			var rune_sanskrit := String(RD.get_rune(rid).get("runic_name", ""))
			if not rune_sanskrit.is_empty() and word_sanskrit.contains(rune_sanskrit):
				found_match = true
				break
		assert_bool(found_match) \
			.override_failure_message("%s 的梵语名 '%s' 未包含任何配方符文(%s)的梵语词根" % [word_id, word_sanskrit, str(recipe)]) \
			.is_true()

func test_get_rune_word_returns_copy() -> void:
	var word: Dictionary = RWD.get_rune_word("thunder_run")
	word["name"] = "MUTATED"
	var again: Dictionary = RWD.get_rune_word("thunder_run")
	assert_str(String(again.get("name", ""))).is_equal("涌力之语")

func test_has_rune_word_and_name() -> void:
	assert_bool(RWD.has_rune_word("endless")).is_true()
	assert_bool(RWD.has_rune_word("nonexistent")).is_false()
	# get_rune_word_name 返回梵语 runic_name
	assert_str(RWD.get_rune_word_name("instant_charge")).is_equal("अग्निबलप्रवाह")
	assert_str(RWD.get_rune_word_name("nonexistent")).is_equal("nonexistent")

# ---------- flatten_slot_runes ----------

func test_flatten_empty_slot_runes() -> void:
	assert_array(RWD.flatten_slot_runes([[], [], [], [], [], [], []])).is_empty()

func test_flatten_skips_empty_and_non_array_slots() -> void:
	var flat: Array = RWD.flatten_slot_runes([["surge"], [], ["force", "quick"], "garbage", null, [], []])
	assert_array(flat).is_equal(["surge", "force", "quick"])

func test_flatten_preserves_order_across_slots() -> void:
	var flat: Array = RWD.flatten_slot_runes([["ember"], ["force"], ["surge"], [], [], [], []])
	assert_array(flat).is_equal(["ember", "force", "surge"])

# ---------- detect_active_rune_words ----------

func _slot_runes(flat: Array) -> Array:
	# 把一个扁平符文序列整体放进槽 0，方便构造测试
	return [flat.duplicate(), [], [], [], [], [], []]

func test_detect_thunder_run_in_single_slot() -> void:
	var active: Array = RWD.detect_active_rune_words(_slot_runes(["surge", "force", "quick"]))
	assert_array(active).contains(["thunder_run"])

func test_detect_word_across_slots() -> void:
	var active: Array = RWD.detect_active_rune_words([["surge"], ["force"], ["quick"], [], [], [], []])
	assert_array(active).contains(["thunder_run"])

func test_detect_word_across_empty_slot_gap() -> void:
	# 空槽不破坏连续性
	var active: Array = RWD.detect_active_rune_words([["surge"], [], ["force", "quick"], [], [], [], []])
	assert_array(active).contains(["thunder_run"])

func test_reversed_order_does_not_match() -> void:
	var active: Array = RWD.detect_active_rune_words(_slot_runes(["quick", "force", "surge"]))
	assert_bool(active.has("thunder_run")).is_false()

func test_partial_recipe_does_not_match() -> void:
	var active: Array = RWD.detect_active_rune_words(_slot_runes(["surge", "force"]))
	assert_bool(active.has("thunder_run")).is_false()

func test_intervening_rune_breaks_word() -> void:
	# surge 与 force 之间插入 ember，不再连续
	var active: Array = RWD.detect_active_rune_words(_slot_runes(["surge", "ember", "force", "quick"]))
	assert_bool(active.has("thunder_run")).is_false()

func test_multiple_words_active_simultaneously() -> void:
	# thunder_run=[surge,force,quick] + aegis=[guardian,guardian,force]
	var slot_runes := _slot_runes(["surge", "force", "quick", "guardian", "guardian", "force"])
	var active: Array = RWD.detect_active_rune_words(slot_runes)
	assert_array(active).contains("thunder_run")
	assert_array(active).contains("aegis")

func test_empty_slot_runes_detects_nothing() -> void:
	assert_array(RWD.detect_active_rune_words([[], [], [], [], [], [], []])).is_empty()

func test_all_words_detectable() -> void:
	# 逐个验证全部 33 个符文之语均可被检测激活
	var cases := {
		"thunder_run": ["surge", "force", "quick"],
		"instant_charge": ["ember", "force", "surge"],
		"endless": ["quick", "echo", "guardian"],
		"aegis": ["guardian", "guardian", "force"],
		"echoing": ["echo", "echo", "surge"],
		"agnivrishti": ["ember", "ember", "launch"],
		"nirmoksha": ["hima", "kala", "quick"],
		"mrityuhasta": ["mrityu", "force", "launch"],
		"chhayanritya": ["maya", "maya", "echo"],
		"dipasamrakshana": ["dipa", "guardian", "ayu"],
		"jalapavana": ["jala", "pavana"],
		"bhumiraksha": ["bhumi", "guardian"],
		"tejomarichi": ["tejas", "marichi"],
		"krishnatamas": ["krishna", "tamas"],
		"dhumakardama": ["dhuma", "kardama"],
		"vishajala": ["visha", "jala"],
		"parabhedana": ["para", "bhedana"],
		"dravaspandana": ["drava", "spandana"],
		"praghananighata": ["praghana", "nighata"],
		"aghatavikshepa": ["aghata", "vikshepa"],
		"nighatabhedana": ["nighata", "bhedana"],
		"praghanavikshepa": ["praghana", "vikshepa", "force"],
		"pranashakti": ["prana", "shakti"],
		"vidyatapas": ["vidya", "tapas"],
		"karmadharma": ["karma", "dharma"],
		"viryamantra": ["virya", "mantra"],
		"yantrachitta": ["yantra", "chitta"],
		"raudrabhaya": ["raudra", "bhaya"],
		"ghoranashana": ["ghora", "nashana"],
		"vibhatsamrityu": ["vibhatsa", "mrityu"],
		"siddhimoksha": ["siddhi", "moksha"],
		"amritayu": ["amrita", "ayu"],
		"vajraparajala": ["vajra", "para", "jala"],
	}
	for word_id in cases.keys():
		var active: Array = RWD.detect_active_rune_words(_slot_runes(cases[word_id]))
		assert_bool(active.has(String(word_id))) \
			.override_failure_message("%s 应被检测激活" % word_id) \
			.is_true()

# ---------- get_granted_passives ----------

func test_granted_passives_union_and_dedup() -> void:
	# thunder_run 授予 rune_word_sprint_impact；aegis 授予 perfect_block_window + rune_word_shield_no_wear
	var grants: Array = RWD.get_granted_passives(["thunder_run", "aegis"])
	assert_array(grants).contains("rune_word_sprint_impact")
	assert_array(grants).contains("perfect_block_window")
	assert_array(grants).contains("rune_word_shield_no_wear")
	# 去重：无重复条目
	var seen: Dictionary = {}
	for g in grants:
		assert_bool(not seen.has(g)) \
			.override_failure_message("授予被动不应重复: %s" % g) \
			.is_true()
		seen[g] = true

func test_granted_passives_empty_for_empty_active() -> void:
	assert_array(RWD.get_granted_passives([])).is_empty()

func test_instant_charge_grants_charge_and_charge_free() -> void:
	var grants: Array = RWD.get_word_grants("instant_charge")
	assert_array(grants).contains("charge")
	assert_array(grants).contains("charge_free")

func test_endless_grants_ranged_no_wear() -> void:
	assert_array(RWD.get_word_grants("endless")).contains("rune_word_ranged_no_wear")

func test_echoing_grants_extra_projectile() -> void:
	assert_array(RWD.get_word_grants("echoing")).contains("rune_word_extra_projectile")

func test_get_active_word_infos_structure() -> void:
	var infos: Array = RWD.get_active_word_infos(["endless"])
	assert_int(infos.size()).is_equal(1)
	var info: Dictionary = infos[0]
	assert_str(String(info.get("id", ""))).is_equal("endless")
	assert_str(String(info.get("name", ""))).is_equal("回护之语")
	assert_array(info.get("recipe", [])).is_equal(["quick", "echo", "guardian"])

# ---------- get_rune_words_containing_rune ----------

func test_get_rune_words_containing_surge() -> void:
	# surge 出现在 thunder_run=[surge,force,quick]、instant_charge=[ember,force,surge]、echoing=[echo,echo,surge]
	var words: Array = RWD.get_rune_words_containing_rune("surge")
	assert_array(words).contains("thunder_run")
	assert_array(words).contains("instant_charge")
	assert_array(words).contains("echoing")

func test_get_rune_words_containing_guardian() -> void:
	# guardian 出现在 endless=[quick,echo,guardian]、aegis=[guardian,guardian,force]
	var words: Array = RWD.get_rune_words_containing_rune("guardian")
	assert_array(words).contains("endless")
	assert_array(words).contains("aegis")

func test_get_rune_words_containing_unknown_rune() -> void:
	assert_array(RWD.get_rune_words_containing_rune("nonexistent")).is_empty()

func test_get_rune_words_containing_launch() -> void:
	# launch 参与焰投之语(agnivrishti)和死投之语(mrityuhasta)
	var words: Array = RWD.get_rune_words_containing_rune("launch")
	assert_array(words).contains("agnivrishti")
	assert_array(words).contains("mrityuhasta")

func test_every_recipe_rune_has_matching_word() -> void:
	# 验证每个符文之语配方中的符文都能通过此函数反向找到该符文之语
	for word_id in RWD.get_all_rune_word_ids():
		var recipe: Array = RWD.get_rune_word(String(word_id)).get("recipe", [])
		for r in recipe:
			var containing: Array = RWD.get_rune_words_containing_rune(String(r))
			assert_bool(containing.has(String(word_id))) \
				.override_failure_message("符文 %s 应能通过 get_rune_words_containing_rune 找到符文之语 %s" % [r, word_id]) \
				.is_true()

# ---------- SkillRuntime 集成 ----------

func _reset_sr() -> void:
	# 与 skill_runtime_test._reset() 一致：每个集成测试开头显式重置，防止跨用例状态泄漏
	if sr: sr.reset()
	if ap: ap.reset()

func _bind_slot_directly(slot_index: int, skill_id: String) -> void:
	# 绕过领悟校验直接绑定（与 skill_runtime_test 一致），同时清空该槽符文
	sr.slots[slot_index] = skill_id
	sr.slot_runes[slot_index] = []

func test_socketing_rune_word_grants_passive() -> void:
	if sr == null:
		return # SkillRuntime autoload 不可用
	_reset_sr()
	_bind_slot_directly(0, "踢击")
	assert_bool(sr.socket_rune(0, "surge")).is_true()
	assert_bool(sr.socket_rune(0, "force")).is_true()
	assert_bool(sr.socket_rune(0, "quick")).is_true()
	# thunder_run 激活 → 授予 rune_word_sprint_impact
	assert_bool(sr.has_mechanism_passive("rune_word_sprint_impact")).is_true()
	assert_array(sr.get_active_rune_words()).contains("thunder_run")

func test_unsocketing_breaks_rune_word() -> void:
	if sr == null:
		return # SkillRuntime autoload 不可用
	_reset_sr()
	_bind_slot_directly(0, "踢击")
	assert_bool(sr.socket_rune(0, "surge")).is_true()
	assert_bool(sr.socket_rune(0, "force")).is_true()
	assert_bool(sr.socket_rune(0, "quick")).is_true()
	assert_bool(sr.has_mechanism_passive("rune_word_sprint_impact")).is_true()
	# 移除第 3 个（quick）→ 配方断裂
	assert_bool(sr.unsocket_rune(0, 2)).is_true()
	assert_bool(sr.has_mechanism_passive("rune_word_sprint_impact")).is_false()
	assert_bool(sr.get_active_rune_words().has("thunder_run")).is_false()

func test_recompute_is_idempotent() -> void:
	if sr == null:
		return # SkillRuntime autoload 不可用
	_reset_sr()
	_bind_slot_directly(0, "踢击")
	assert_bool(sr.socket_rune(0, "ember")).is_true()
	assert_bool(sr.socket_rune(0, "force")).is_true()
	assert_bool(sr.socket_rune(0, "surge")).is_true()
	# 验证槽内符文序列正确
	assert_array(sr.get_slot_runes(0)).is_equal(["ember", "force", "surge"])
	# instant_charge 授予 charge_free
	assert_bool(sr.has_mechanism_passive("charge_free")).is_true()
	# 多次重算结果一致
	sr.recompute_mechanism_passives()
	sr.recompute_mechanism_passives()
	assert_bool(sr.has_mechanism_passive("charge_free")).is_true()
	assert_array(sr.get_active_rune_words()).contains("instant_charge")

func test_rune_word_across_slots_grants() -> void:
	if sr == null:
		return # SkillRuntime autoload 不可用
	_reset_sr()
	# 槽 0 放 surge，槽 1 放 force+quick（跨槽成词）
	_bind_slot_directly(0, "踢击")
	_bind_slot_directly(1, "冲撞")
	assert_bool(sr.socket_rune(0, "surge")).is_true()
	assert_bool(sr.socket_rune(1, "force")).is_true()
	assert_bool(sr.socket_rune(1, "quick")).is_true()
	assert_bool(sr.has_mechanism_passive("rune_word_sprint_impact")).is_true()

func test_reset_clears_rune_words() -> void:
	if sr == null:
		return # SkillRuntime autoload 不可用
	_reset_sr()
	_bind_slot_directly(0, "踢击")
	sr.socket_rune(0, "surge")
	sr.socket_rune(0, "force")
	sr.socket_rune(0, "quick")
	assert_bool(sr.has_mechanism_passive("rune_word_sprint_impact")).is_true()
	sr.reset()
	assert_bool(sr.has_mechanism_passive("rune_word_sprint_impact")).is_false()
	assert_array(sr.get_active_rune_words()).is_empty()

func test_serialize_preserves_slot_runes_for_rune_words() -> void:
	if sr == null:
		return # SkillRuntime autoload 不可用
	_reset_sr()
	_bind_slot_directly(0, "踢击")
	sr.socket_rune(0, "surge")
	sr.socket_rune(0, "force")
	sr.socket_rune(0, "quick")
	var data: Dictionary = sr.serialize()
	var saved_runes: Array = data.get("slot_runes", [])
	assert_array(saved_runes[0]).is_equal(["surge", "force", "quick"])
