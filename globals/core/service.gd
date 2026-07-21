class_name Service
## 类型安全的单例访问器。
## 替代全项目泛滥的 Engine.get_main_loop().root.get_node_or_null("XxxManager") 模式。
## 用法： var sr := Service.skill_runtime()
extends RefCounted

static func _root() -> Node:
	var ml := Engine.get_main_loop()
	if ml == null:
		return null
	return ml.root

# ── core ──────────────────────────────────────────────
static func game_state() -> Node:
	var r := _root()
	return r.get_node_or_null("GameState") if r != null else null

static func game_events() -> Node:
	var r := _root()
	return r.get_node_or_null("GameEvents") if r != null else null

static func physics_setup() -> Node:
	var r := _root()
	return r.get_node_or_null("PhysicsSetup") if r != null else null

static func network_manager() -> Node:
	var r := _root()
	return r.get_node_or_null("NetworkManager") if r != null else null

static func fx_helper() -> Node:
	var r := _root()
	return r.get_node_or_null("FxHelper") if r != null else null

static func hit_stop_server() -> Node:
	var r := _root()
	return r.get_node_or_null("HitStopServer") if r != null else null

static func audio_manager() -> Node:
	var r := _root()
	return r.get_node_or_null("AudioManager") if r != null else null

static func localization_manager() -> Node:
	var r := _root()
	return r.get_node_or_null("LocalizationManager") if r != null else null

# ── combat ────────────────────────────────────────────
static func combat_engine() -> Node:
	var r := _root()
	return r.get_node_or_null("CombatEngine") if r != null else null

static func skill_runtime() -> Node:
	var r := _root()
	return r.get_node_or_null("SkillRuntime") if r != null else null

static func attr_panel() -> Node:
	var r := _root()
	return r.get_node_or_null("AttrPanel") if r != null else null

static func skill_icons() -> Node:
	var r := _root()
	return r.get_node_or_null("SkillIcons") if r != null else null

static func projectile_service() -> Node:
	var r := _root()
	return r.get_node_or_null("ProjectileService") if r != null else null

# ── tavern ────────────────────────────────────────────
static func tavern_manager() -> Node:
	var r := _root()
	return r.get_node_or_null("TavernManager") if r != null else null

static func tavern_settlement() -> Node:
	var r := _root()
	return r.get_node_or_null("TavernSettlement") if r != null else null

static func brewing_data() -> Node:
	var r := _root()
	return r.get_node_or_null("BrewingData") if r != null else null

static func fermentation_system() -> Node:
	var r := _root()
	return r.get_node_or_null("FermentationSystem") if r != null else null

static func loot_table() -> Node:
	var r := _root()
	return r.get_node_or_null("LootTable") if r != null else null

# ── dungeon ───────────────────────────────────────────
static func dungeon_spawner() -> Node:
	var r := _root()
	return r.get_node_or_null("DungeonSpawner") if r != null else null

static func zone_manager() -> Node:
	var r := _root()
	return r.get_node_or_null("ZoneManager") if r != null else null

# ── equipment ─────────────────────────────────────────
static func weapon_registry() -> Node:
	var r := _root()
	return r.get_node_or_null("WeaponRegistry") if r != null else null

static func affix_system() -> Node:
	var r := _root()
	return r.get_node_or_null("AffixSystem") if r != null else null

static func item_spawner() -> Node:
	var r := _root()
	return r.get_node_or_null("ItemSpawner") if r != null else null

# ── other ─────────────────────────────────────────────
static func lighting_controller() -> Node:
	var r := _root()
	return r.get_node_or_null("LightingController") if r != null else null

static func settings() -> Node:
	var r := _root()
	return r.get_node_or_null("Settings") if r != null else null
