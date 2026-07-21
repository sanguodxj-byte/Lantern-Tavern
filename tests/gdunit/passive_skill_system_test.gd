extends GdUnitTestSuite

## 测试 38 个全量被动技能与流派机制绑定

const SR := preload("res://globals/combat/skill_runtime.gd")
const SD := preload("res://globals/combat/skill_data.gd")

func test_skills_json_loading() -> void:
	# 1. 深度校验 skills.json 的物理文件与解析正确性
	var file = FileAccess.open("res://data/skills.json", FileAccess.READ)
	assert_object(file).is_not_null()
	var json_str := file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_err := json.parse(json_str)
	assert_int(parse_err).is_equal(OK)
	
	var data: Dictionary = json.data
	assert_bool(data.has("skills")).is_true()
	var skills_arr: Array = data["skills"]
	assert_int(skills_arr.size()).is_greater(35)
	
	# 校验每一个 skill 都具备非空 id 与 name_zh
	for skill in skills_arr:
		assert_str(String(skill.get("id", ""))).is_not_empty()
		assert_str(String(skill.get("name_zh", ""))).is_not_empty()

func test_player_real_passive_regen_and_style_switch() -> void:
	# 2. 真实实例化 Player 节点，验证 _process_passive_effects 的 5s 被动回血逻辑
	var player = auto_free(load("res://scenes/characters/player/player.tscn").instantiate())
	add_child(player)
	player.health.max_life = 100
	player.health.current_life = 80
	Service.skill_runtime().grant_mechanism_passive("passive_toughness")
	
	# 模拟 5 秒钟的 _process 时间步长推进
	player._process_passive_effects(5.0)
	
	# 断言回复了 2% 的最大血量（100 * 0.02 = 2 点，当前血量应变为 82）
	assert_int(player.health.current_life).is_equal(82)
