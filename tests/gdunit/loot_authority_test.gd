extends GdUnitTestSuite

# Phase 5/8（docs/25 §5.2/§8.3/§9.2）：LootAuthority 服务器权威掉落裁决。
# 用种子化 RNG 验证确定性与数量边界。客户端绝不决定掉落内容。

const LootAuthority := preload("res://globals/multiplayer/loot_authority.gd")

func _table() -> Dictionary:
	return {
		"goblin_tooth": {"kind": "material", "weight": 10, "min": 1, "max": 3},
		"rusty_coin": {"kind": "material", "weight": 5, "min": 1, "max": 1},
		"iron_rune": {"kind": "rune", "weight": 2, "min": 1, "max": 1},
	}

func test_roll_loot_deterministic_with_seed() -> void:
	var la = auto_free(LootAuthority.new())
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 12345
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 12345
	var a = la.roll_loot(_table(), rng1, 4)
	var b = la.roll_loot(_table(), rng2, 4)
	# 同种子 → 同结果（确定性，支持重连回放）
	assert_bool(a == b).is_true()

func test_roll_loot_within_table_bounds() -> void:
	var la = auto_free(LootAuthority.new())
	var rng := RandomNumberGenerator.new(); rng.seed = 999
	var out = la.roll_loot(_table(), rng, 4)
	assert_bool(out.size() >= 1).is_true()
	for id in out.keys():
		var spec = _table()[id]
		assert_int(int(out[id])).is_greater_equal(int(spec["min"]))
		# 单次抽取量不超过 max；多次同 id 累加后不超过 max * max_items
		assert_int(int(out[id])).is_less_equal(int(spec["max"]) * 4)

func test_roll_loot_empty_table_returns_empty() -> void:
	var la = auto_free(LootAuthority.new())
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var out = la.roll_loot({}, rng, 4)
	assert_bool(out == {}).is_true()

func test_roll_loot_null_rng_returns_empty() -> void:
	var la = auto_free(LootAuthority.new())
	var out = la.roll_loot(_table(), null, 4)
	assert_bool(out == {}).is_true()
