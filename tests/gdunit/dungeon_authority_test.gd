extends GdUnitTestSuite

## DungeonAuthority 测试（docs/25 §10.3 / Phase 7 地牢 seed/layout 同步）。
## 纯逻辑层：服务器权威 seed / layout_version / layout_revision + 客户端声明校验 + 重连序列化。

const DA := preload("res://globals/multiplayer/dungeon_authority.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func test_init_layout_version_and_inactive() -> void:
	var d: DA = auto_free(DA.new())
	assert_int(d.layout_version).is_equal(NP.DUNGEON_LAYOUT_VERSION)
	assert_bool(d.active).is_false()
	assert_int(d.seed).is_equal(0)
	assert_int(d.layout_revision).is_equal(0)

# ---------------------------------------------------------------------------
# 开启出征 / seed 决定
# ---------------------------------------------------------------------------

func test_start_with_explicit_seed() -> void:
	var d: DA = auto_free(DA.new())
	var evt: Dictionary = d.start_expedition(42)
	assert_bool(d.active).is_true()
	assert_int(d.seed).is_equal(42)
	assert_int(d.layout_revision).is_equal(1)
	assert_int(d.expedition_id).is_equal(1)
	assert_str(evt["type"]).is_equal(NP.EVT_DUNGEON_LAYOUT)
	assert_int(evt["seed"]).is_equal(42)
	assert_int(evt["layout_revision"]).is_equal(1)

func test_start_random_seed_deterministic_with_rng() -> void:
	var d: DA = auto_free(DA.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var evt: Dictionary = d.start_expedition(-1, rng)
	# 固定 rng 种子 => 确定性 seed
	assert_int(evt["seed"]).is_equal(d.seed)
	var d2: DA = auto_free(DA.new())
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 12345
	assert_int(d2.start_expedition(-1, rng2)["seed"]).is_equal(evt["seed"])

func test_start_bumps_revision_and_expedition_each_time() -> void:
	var d: DA = auto_free(DA.new())
	d.start_expedition(1)
	assert_int(d.layout_revision).is_equal(1)
	assert_int(d.expedition_id).is_equal(1)
	d.start_expedition(2)
	assert_int(d.layout_revision).is_equal(2)
	assert_int(d.expedition_id).is_equal(2)
	assert_int(d.seed).is_equal(2)

func test_end_expedition_marks_inactive() -> void:
	var d: DA = auto_free(DA.new())
	d.start_expedition(7)
	assert_bool(d.active).is_true()
	d.end_expedition()
	assert_bool(d.active).is_false()

# ---------------------------------------------------------------------------
# 客户端 layout 声明校验（防作弊 / 版本错配）
# ---------------------------------------------------------------------------

func test_validate_layout_request_ok() -> void:
	var d: DA = auto_free(DA.new())
	d.start_expedition(42)
	var res: Dictionary = d.validate_layout_request(1, 42, NP.DUNGEON_LAYOUT_VERSION)
	assert_bool(res["ok"]).is_true()
	assert_str(res["error_code"]).is_equal("")
	assert_str(res["event"]["type"]).is_equal(NP.EVT_DUNGEON_LAYOUT)
	assert_int(res["event"]["seed"]).is_equal(42)

func test_validate_rejects_wrong_layout_version() -> void:
	var d: DA = auto_free(DA.new())
	d.start_expedition(42)
	var res: Dictionary = d.validate_layout_request(1, 42, NP.DUNGEON_LAYOUT_VERSION + 1)
	assert_bool(res["ok"]).is_false()
	assert_str(res["error_code"]).is_equal(NP.ERR_DUNGEON_LAYOUT_VERSION)

func test_validate_rejects_inactive() -> void:
	var d: DA = auto_free(DA.new())
	# 未开启出征：active=false
	var res: Dictionary = d.validate_layout_request(1, 0, NP.DUNGEON_LAYOUT_VERSION)
	assert_bool(res["ok"]).is_false()
	assert_str(res["error_code"]).is_equal(NP.ERR_INVALID_STATE)

func test_validate_rejects_wrong_seed() -> void:
	var d: DA = auto_free(DA.new())
	d.start_expedition(42)
	var res: Dictionary = d.validate_layout_request(1, 99, NP.DUNGEON_LAYOUT_VERSION)
	assert_bool(res["ok"]).is_false()
	assert_str(res["error_code"]).is_equal(NP.ERR_DUNGEON_SEED_MISMATCH)

# ---------------------------------------------------------------------------
# 确定性 layout 指纹
# ---------------------------------------------------------------------------

func test_derive_layout_id_deterministic() -> void:
	assert_int(DA.derive_layout_id(42)).is_equal(DA.derive_layout_id(42))
	assert_int(DA.derive_layout_id(42)).is_not_equal(DA.derive_layout_id(43))

# ---------------------------------------------------------------------------
# 重连序列化
# ---------------------------------------------------------------------------

func test_serialize_deserialize_roundtrip() -> void:
	var d: DA = auto_free(DA.new())
	d.start_expedition(4242)
	var snap: Dictionary = d.serialize()
	var d2: DA = auto_free(DA.new())
	d2.deserialize(snap)
	assert_int(d2.seed).is_equal(4242)
	assert_int(d2.layout_version).is_equal(NP.DUNGEON_LAYOUT_VERSION)
	assert_int(d2.layout_revision).is_equal(1)
	assert_bool(d2.active).is_true()
	assert_int(d2.expedition_id).is_equal(1)
