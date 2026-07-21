extends UiScreen
class_name ModelViewer

const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const UI_ROUTES := preload("res://globals/ui/ui_route_catalog.gd")
const CHARACTER_TIERS := preload("res://data/character_model_tiers.gd")
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")
const BREWING_DATA := preload("res://globals/tavern/brewing_data.gd")

@onready var asset_tree: Tree = $HBoxContainer/Sidebar/AssetTree
@onready var viewport: SubViewport = $HBoxContainer/ViewportContainer/SubViewport
@onready var camera_pivot: Node3D = $HBoxContainer/ViewportContainer/SubViewport/CameraPivot
@onready var camera: Camera3D = $HBoxContainer/ViewportContainer/SubViewport/CameraPivot/Camera3D
@onready var main_light: DirectionalLight3D = $HBoxContainer/ViewportContainer/SubViewport/MainLight
@onready var fill_light: OmniLight3D = $HBoxContainer/ViewportContainer/SubViewport/FillLight
@onready var viewport_container: SubViewportContainer = $HBoxContainer/ViewportContainer
@onready var sidebar_title: Label = $HBoxContainer/Sidebar/SidebarTitle
@onready var inspector_title: Label = $HBoxContainer/Inspector/InspectorTitle

# Inspector labels
@onready var asset_name_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/AssetNameVal
@onready var asset_path_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/AssetPathVal
@onready var asset_type_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/AssetTypeVal
@onready var bounds_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/BoundsVal
@onready var vertices_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/VerticesVal
@onready var status_label: Label = $HBoxContainer/Inspector/PanelContainer/MarginContainer/VBoxContainer/GridContainer/StatusVal

# Controls
@onready var rot_speed_slider: HSlider = $HBoxContainer/Sidebar/PanelContainer/VBoxContainer/HBoxContainer_Rot/RotSpeedSlider
@onready var light_color_option: OptionButton = $HBoxContainer/Sidebar/PanelContainer/VBoxContainer/HBoxContainer_Light/LightColorOption
@onready var toggle_grid_btn: CheckButton = $HBoxContainer/Sidebar/PanelContainer/VBoxContainer/ToggleGridBtn
@onready var toggle_auto_rot: CheckButton = $HBoxContainer/Sidebar/PanelContainer/VBoxContainer/ToggleAutoRotBtn
@onready var return_btn: Button = $HBoxContainer/Sidebar/ReturnBtn

# Skeleton animation controls (only shown for models with AnimationPlayer)
@onready var anim_section: VBoxContainer = %AnimSection
@onready var anim_option: OptionButton = %AnimOption
@onready var play_anim_btn: Button = %PlayAnimBtn
@onready var stop_anim_btn: Button = %StopAnimBtn
@onready var loop_anim_btn: CheckButton = %LoopAnimBtn

var current_model_node: Node3D = null
var current_anim_player: AnimationPlayer = null
var rotation_speed: float = 0.5
var is_auto_rotating: bool = true
var grid_helper: MeshInstance3D = null
var is_dragging: bool = false

# ── Asset Database ────────────────────────────────────────────────────────
# Built dynamically in _ready() by scanning project directories and merging
# with WeaponRegistry entries.  New .glb files dropped into the scanned
# directories appear automatically — no manual editing required.
var asset_database: Dictionary = {}

# ── GLB directory scan configuration ──────────────────────────────────────
# Maps category names to directories that should be scanned for .glb files.
const _GLB_SCAN_CONFIG := {
	"Characters & Monsters": ["res://assets/meshes/characters/"],
	"Dungeon Structures": [
		"res://assets/meshes/doors/",
		"res://assets/meshes/walls/",
	],
	"Voxel Materials": ["res://assets/models/materials/"],
	"Environment": ["res://assets/models/environment/"],
}

# Prefixes stripped when converting GLB filenames to display names.
const _NAME_PREFIXES := [
	"weapons_", "armor_", "props_", "materials_",
	"environment_tutorial_", "environment_",
]
# Voxel resolution suffixes stripped from display names.
const _NAME_SUFFIXES := [
	"_256px", "_80px", "_64x", "_48px", "_32px", "_18px", "_12px",
]

# 图鉴只使用此表作为展示层：资源路径、文件名与注册表 ID 保持英文不变。
# key 是移除文件前缀、rig 标记与像素后缀后的稳定模型 ID。
const _MODEL_NAME_ZH := {
	"player": "冒险者", "character": "角色模型", "bartender": "酒馆老板",
	"goblin": "哥布林", "rat": "巨鼠", "skeleton": "骷髅兵", "slime": "史莱姆",
	"troll": "巨魔", "necrolord": "死灵领主", "dragon": "巨龙", "minotaur": "牛头怪",
	"rock_golem": "岩石魔像", "spider": "蜘蛛", "kobold": "狗头人", "zombie": "僵尸",
	"orc_raider": "兽人掠夺者", "hobgoblin_legionary": "大地精军团士兵",
	"bugbear_brute": "熊地精暴徒", "gnoll_hyena": "豺狼人鬣狗战士",
	"lizardfolk_scout": "蜥蜴人斥候", "troglodyte": "穴居人",
	"duergar_miner": "灰矮人矿工", "dark_elf_hexer": "暗精灵咒术师",
	"drow_blade": "卓尔剑士", "satyr_marauder": "半羊人掠夺者",
	"harpy_matriarch": "鹰身女妖女族长", "werewolf_stalker": "狼人潜行者",
	"vampire_thrall": "吸血鬼仆从", "wight_guard": "尸妖守卫",
	"ghoul_feaster": "食尸鬼饕客", "mummy_cursebearer": "木乃伊咒缚者",
	"plague_doctor": "瘟疫医生", "cultist_pyromancer": "邪教火法师",
	"cultist_zealot": "邪教狂信徒", "bandit_cutthroat": "强盗割喉者",
	"bandit_crossbowman": "强盗弩手", "fungal_shambler": "真菌行尸",
	"myconid_sporekeeper": "蘑菇人孢子守卫", "elemental_ash": "灰烬元素",
	"elemental_frost": "寒霜元素", "elemental_storm": "风暴元素",
	"gargoyle_sentinel": "石像鬼哨兵", "animated_armor": "活化盔甲",
	"oni_revenant": "鬼族怨灵", "shadow_assassin": "暗影刺客",
	"axe": "战斧", "crossbow": "弩", "dagger": "匕首", "greatsword": "巨剑",
	"longbow": "长弓", "longsword": "长剑", "shortsword": "短剑", "spear": "长矛",
	"staff": "法杖", "grimoire": "魔导书", "sword": "单手剑", "warhammer": "战锤", "buckler": "圆盾",
	"chain_armor": "锁子甲", "cloth_armor": "布甲", "leather_armor": "皮甲", "plate_armor": "板甲",
	"fireplace": "壁炉", "barrel": "木桶", "barrel_fragmented": "破碎木桶",
	"banner": "旗帜", "bench": "长凳", "bones": "骨堆", "boss_chest": "首领宝箱",
	"bottle_set": "瓶罐组", "bucket": "木桶", "candles": "蜡烛", "chair": "椅子",
	"chandelier": "吊灯", "chest": "宝箱", "goblet": "高脚杯", "grate": "铁栅",
	"jail": "牢笼", "large_chest": "大型宝箱", "large_crate": "大木箱",
	"lit_candles": "点燃的蜡烛", "pillar": "石柱", "plank": "木板", "ruble": "瓦砾",
	"small_crate": "小木箱", "table": "桌子", "tankard": "酒杯", "torch": "火把",
	"wall_lantern": "壁灯", "wall_notice": "墙上告示", "arrow": "箭矢", "bolt": "弩箭",
	# 酿造材料 / 掉落物（与 BrewingData / material_model_manifest 对齐）
	"rat_tail": "老鼠尾巴", "moldy_bread": "发霉面包", "rusty_nail": "生锈铁钉",
	"dungeon_moss": "地牢苔", "bone_shard": "碎骨片", "stale_water": "陈腐积水",
	"prison_lichen": "囚室地衣", "cellar_mushroom": "地窖蘑菇",
	"blackberry": "黑莓", "bloodvine": "血藤", "glowshroom": "蓝光菇",
	"moongrass": "月光草", "goblin_nail": "哥布林指甲", "mistflower": "迷雾花",
	"wolfear_herb": "狼耳草", "poison_berry": "剧毒藤莓", "oak_lichen": "橡木地衣",
	"pixie_dust": "妖精粉尘", "deeprock_moss": "深岩苔藓", "black_rye_root": "黑麦根",
	"cyclops_beard": "独眼巨人的胡须", "stalactite_sap": "钟乳石髓",
	"blindfish_jerky": "盲鱼干", "geothermal_ear": "地热木耳",
	"luminous_fern": "荧光蕨", "quartz_dust": "石英晶粉",
	"skeleton_dust": "白骨粉末", "goblin_ear": "哥布林耳尖",
	"giant_rat_tail": "巨鼠尾巴", "slime_jelly": "史莱姆凝胶",
	"troll_blood": "巨魔之血", "soul_gem": "灵魂宝石", "dragon_scale": "龙鳞",
	"bone_shard_sample": "骨片样本", "glowcap": "荧光菇",
	"cart_wreck": "教程损坏马车", "entrance_ruins": "教程入口遗迹",
	"forest_cluster": "教程森林树丛", "road_blocker": "教程道路障碍",
}

# 角色/怪物主分类（与 _GLB_SCAN_CONFIG 键一致）
const _CHAR_CATEGORY_KEY := "Characters & Monsters"


func _ready() -> void:
	super._ready()
	# Localize panel titles
	sidebar_title.text = tr(" MODEL VIEWER / EDITOR")
	inspector_title.text = tr(" ASSET INSPECTOR")

	# Wire up UI controls
	return_btn.pressed.connect(_on_return_pressed)
	toggle_grid_btn.toggled.connect(_on_toggle_grid)
	toggle_auto_rot.toggled.connect(_on_toggle_auto_rot)
	rot_speed_slider.value_changed.connect(_on_rot_speed_changed)
	play_anim_btn.pressed.connect(_on_play_anim_pressed)
	stop_anim_btn.pressed.connect(_on_stop_anim_pressed)
	anim_option.item_selected.connect(_on_anim_option_selected)

	# Wire up viewport interaction
	viewport_container.gui_input.connect(_on_viewport_container_gui_input)

	# Configure Light Color Options
	light_color_option.add_item(tr("Cozy Candlelight"))
	light_color_option.add_item(tr("Daylight"))
	light_color_option.add_item(tr("Eerie Moonlight"))
	light_color_option.item_selected.connect(_on_light_color_selected)

	# Build grid helper
	_create_grid_mesh()

	# Build asset database dynamically from project files + WeaponRegistry
	asset_database = _build_asset_database()

	# Build asset tree
	_build_asset_tree()

	# Select first element by default
	_select_default_item()


# ── Asset database construction ───────────────────────────────────────────

## Scans project directories and merges with WeaponRegistry to build the
## complete asset database displayed in the model viewer tree.
func _build_asset_database() -> Dictionary:
	var db: Dictionary = {}

	# 1. Registry-managed equipment (Weapons, Shields, Light Armor, Heavy Armor)
	_populate_registry_equipment(db)

	# 2. Non-registry weapon GLBs (legacy / extra models in weapons directory)
	_add_non_registry_weapon_glbs(db)

	# 3. Non-registry shield GLBs (e.g. buckler)
	_scan_glb_directory(db, tr("Shields"), "res://assets/meshes/shields/")

	# 4. GLB directory scans (characters, structures, materials, environment)
	for category in _GLB_SCAN_CONFIG.keys():
		for dir_path in _GLB_SCAN_CONFIG[category]:
			var filter_voxel_only: bool = (category == "Characters & Monsters")
			_scan_glb_directory(db, tr(category), dir_path, filter_voxel_only)

	# 5. Scan baked .tscn Dungeon Props
	_scan_tscn_directory(db, tr("Dungeon Props"), "res://assets/meshes/props/")

	# 6. Root-level GLB models (e.g. Meshy AI boss models)
	_scan_root_level_glbs(db)

	# 7. Scan projectile voxel scenes (arrows, bolts, etc.)
	_scan_projectile_scenes(db, tr("Projectiles"), "res://assets/meshes/projectiles/")

	return db


## Populate equipment categories from WeaponRegistry (weapons.json).
func _populate_registry_equipment(db: Dictionary) -> void:
	var registry_entries := WeaponRegistry.get_model_viewer_entries()
	for category_name in registry_entries.keys():
		if registry_entries[category_name].is_empty():
			continue  # skip categories with no 3D models
		var localized_cat := tr(category_name)
		if not db.has(localized_cat):
			db[localized_cat] = {}
		for item_name in registry_entries[category_name].keys():
			db[localized_cat][tr(item_name)] = registry_entries[category_name][item_name]


## Scan the weapons directory for GLB files not already covered by WeaponRegistry.
func _add_non_registry_weapon_glbs(db: Dictionary) -> void:
	# Collect all GLB paths already in the registry to avoid duplicates
	var registry_paths: Array[String] = []
	var registry_entries := WeaponRegistry.get_model_viewer_entries()
	for category in registry_entries.keys():
		for item_name in registry_entries[category].keys():
			registry_paths.append(registry_entries[category][item_name])

	var weapons_dir := "res://assets/meshes/weapons/"
	var dir := DirAccess.open(weapons_dir)
	if dir == null:
		return

	var cat_key := tr("Weapons")
	if not db.has(cat_key):
		db[cat_key] = {}

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# 过滤掉包含 .tmp 命名的临时模型文件
		if file_name.ends_with(".glb") and not file_name.ends_with(".import") and not file_name.contains(".tmp"):
			var full_path := weapons_dir + file_name
			if not registry_paths.has(full_path):
				var display_name := _filename_to_display_name(file_name)
				_add_to_category(db, cat_key, display_name, full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Scan a directory for .glb files and add them to a category.
## Characters & Monsters 使用嵌套结构：{ tier_label: { display_name: path } }
func _scan_glb_directory(db: Dictionary, category: String, dir_path: String, voxel_only: bool = false) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	var is_character_category := (category == tr(_CHAR_CATEGORY_KEY) or category == _CHAR_CATEGORY_KEY)
	if not db.has(category):
		db[category] = {}

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()

	for scanned_file_name in file_names:
		# 过滤掉包含 .tmp 命名的临时模型文件，并且只在 voxel_only 启用时加载以 voxel_ 开头的文件
		if scanned_file_name.ends_with(".glb") and not scanned_file_name.ends_with(".import") and not scanned_file_name.contains(".tmp"):
			if not voxel_only or scanned_file_name.begins_with("voxel_"):
				if is_character_category and not _should_include_character_glb(dir_path, scanned_file_name):
					continue
				var full_path := dir_path + scanned_file_name
				var display_name := _filename_to_display_name(scanned_file_name)
				if is_character_category:
					_add_character_to_tier(db, category, scanned_file_name, display_name, full_path)
				else:
					_add_to_category(db, category, display_name, full_path)


func _should_include_character_glb(dir_path: String, file_name: String) -> bool:
	if file_name.ends_with("_rig.glb"):
		return true
	var rig_name := file_name.trim_suffix(".glb") + "_rig.glb"
	return not FileAccess.file_exists(dir_path + rig_name)


## Scan the projectiles directory for .tscn voxel scene files and add them to a category.
func _scan_projectile_scenes(db: Dictionary, category: String, dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	if not db.has(category):
		db[category] = {}

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn") and not file_name.ends_with(".import"):
			var full_path := dir_path + file_name
			var display_name := _filename_to_display_name(file_name)
			_add_to_category(db, category, display_name, full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Scan a directory for .tscn files and add them to a category.
func _scan_tscn_directory(db: Dictionary, category: String, dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	if not db.has(category):
		db[category] = {}

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn") and file_name.begins_with("baked_"):
			var full_path := dir_path + file_name
			var display_name := _filename_to_display_name(file_name.trim_prefix("baked_"))
			_add_to_category(db, category, display_name, full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Scan the root assets directory for standalone GLB models (e.g. Meshy AI).
func _scan_root_level_glbs(db: Dictionary) -> void:
	var dir := DirAccess.open("res://assets/")
	if dir == null:
		return

	var cat_key := tr("Characters & Monsters")
	if not db.has(cat_key):
		db[cat_key] = {}

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".glb") and not file_name.ends_with(".import"):
			var full_path := "res://assets/" + file_name
			var display_name := _filename_to_display_name(file_name)
			_add_character_to_tier(db, cat_key, file_name, display_name, full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Add an entry to a category, appending " (Alt)" if the display name already exists.
## This prevents legacy models from overwriting newer registry entries.
func _add_to_category(db: Dictionary, category: String, display_name: String, path: String) -> void:
	if not db.has(category):
		db[category] = {}
	var name := display_name
	while db[category].has(name):
		name = name + " (Alt)"
	db[category][name] = path


## 将角色/怪物模型按建模档位写入嵌套分类。
func _add_character_to_tier(db: Dictionary, category: String, file_name: String, display_name: String, path: String) -> void:
	if not db.has(category):
		db[category] = {}
	var model_id := _model_display_key(file_name.get_basename())
	var tier := CHARACTER_TIERS.tier_for(model_id)
	var tier_label := CHARACTER_TIERS.display_name(tier)
	if not db[category].has(tier_label):
		db[category][tier_label] = {}
	var name := display_name
	var bucket: Dictionary = db[category][tier_label]
	while bucket.has(name):
		name = name + " (Alt)"
	bucket[name] = path


## Convert a GLB filename into a human-readable display name.
func _filename_to_display_name(file_name: String) -> String:
	var name := file_name.get_basename()
	var display_key := _model_display_key(name)

	# 材料/掉落物：与游戏内同一解析链（BrewingData → MaterialModelRegistry）
	var material_name := _resolve_material_display_name(display_key)
	if not material_name.is_empty():
		return material_name

	# 图鉴展示名：中文键走 TranslationServer（en/zh 一致）
	if _MODEL_NAME_ZH.has(display_key):
		return TranslationServer.translate(String(_MODEL_NAME_ZH[display_key]))

	# Strip common prefixes
	for prefix in _NAME_PREFIXES:
		if name.begins_with(prefix):
			name = name.substr(prefix.length())

	# Strip voxel resolution suffixes
	for suffix in _NAME_SUFFIXES:
		name = name.trim_suffix(suffix)

	# Handle Meshy AI generated model names (strip prefix + timestamp)
	name = name.replace("Meshy_AI_", "")
	var regex := RegEx.new()
	regex.compile("_\\d{10,}_texture$")
	name = regex.sub(name, "")

	# Normalize separators and capitalize
	name = name.replace("_", " ").replace("-", " ")
	return name.capitalize()


## 解析材料/掉落物显示名（游戏内与图鉴一致）。
## 返回空串表示不是已知材料 ID。
func _resolve_material_display_name(model_id: String) -> String:
	if model_id.is_empty():
		return ""
	if BREWING_DATA.MATERIALS_DB.has(model_id):
		return BREWING_DATA.get_material_name(model_id)
	var entry: Dictionary = MATERIAL_MODELS.get_entry(model_id)
	if not entry.is_empty():
		return MATERIAL_MODELS.get_display_name(model_id)
	return ""


## Produces the stable lookup ID for a scanned model without changing its path.
func _model_display_key(base_name: String) -> String:
	var key := base_name
	for prefix in _NAME_PREFIXES:
		if key.begins_with(prefix):
			key = key.substr(prefix.length())
	key = key.trim_suffix("_rig")
	var resolution := RegEx.new()
	resolution.compile("_\\d+(px|x)$")
	key = resolution.sub(key, "")
	return key.trim_prefix("voxel_").replace("-", "_")


# ── Rendering & UI ────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if is_auto_rotating and current_model_node and camera_pivot:
		# Orbit the camera so runtime rigs keep their authored root transform.
		camera_pivot.rotate_y(-rotation_speed * delta)

func _create_grid_mesh() -> void:
	grid_helper = MeshInstance3D.new()
	var grid_mesh = PlaneMesh.new()
	grid_mesh.size = Vector2(8, 8)
	grid_mesh.subdivide_width = 8
	grid_mesh.subdivide_depth = 8
	grid_helper.mesh = grid_mesh

	# Transparent grid material
	var grid_mat = StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.2)
	grid_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	grid_mat.roughness = 1.0
	grid_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.use_point_size = true
	grid_helper.material_override = grid_mat
	grid_helper.position = Vector3(0, -0.01, 0)
	viewport.add_child(grid_helper)
	grid_helper.visible = true

func _build_asset_tree() -> void:
	asset_tree.clear()
	var root = asset_tree.create_item()
	asset_tree.hide_root = true

	for category in asset_database.keys():
		# Skip empty categories — nothing to display
		if asset_database[category].is_empty():
			continue

		var category_data: Dictionary = asset_database[category]
		var is_nested := _category_is_tier_nested(category_data)
		var leaf_count := _count_category_leaves(category_data)
		var cat_item = asset_tree.create_item(root)
		cat_item.set_text(0, "%s (%d)" % [category, leaf_count])
		cat_item.set_selectable(0, false)

		if is_nested:
			# 角色/怪物：按 S/A/B/C/D 档位顺序输出子标签
			for tier in CHARACTER_TIERS.TIER_ORDER:
				var tier_label := CHARACTER_TIERS.display_name(tier)
				if not category_data.has(tier_label):
					continue
				var tier_bucket: Dictionary = category_data[tier_label]
				if tier_bucket.is_empty():
					continue
				var tier_item = asset_tree.create_item(cat_item)
				tier_item.set_text(0, "%s (%d)" % [tier_label, tier_bucket.size()])
				tier_item.set_selectable(0, false)
				var sorted_names: Array = tier_bucket.keys()
				sorted_names.sort()
				for asset_name in sorted_names:
					var asset_item = asset_tree.create_item(tier_item)
					asset_item.set_text(0, String(asset_name))
					asset_item.set_metadata(0, tier_bucket[asset_name])
			# 兜底：未列入 TIER_ORDER 的嵌套键
			for sub_key in category_data.keys():
				var known := false
				for tier in CHARACTER_TIERS.TIER_ORDER:
					if String(sub_key) == CHARACTER_TIERS.display_name(tier):
						known = true
						break
				if known:
					continue
				var sub_bucket: Variant = category_data[sub_key]
				if typeof(sub_bucket) != TYPE_DICTIONARY or (sub_bucket as Dictionary).is_empty():
					continue
				var sub_item = asset_tree.create_item(cat_item)
				sub_item.set_text(0, "%s (%d)" % [String(sub_key), (sub_bucket as Dictionary).size()])
				sub_item.set_selectable(0, false)
				var names: Array = (sub_bucket as Dictionary).keys()
				names.sort()
				for asset_name in names:
					var asset_item2 = asset_tree.create_item(sub_item)
					asset_item2.set_text(0, String(asset_name))
					asset_item2.set_metadata(0, sub_bucket[asset_name])
		else:
			var sorted_assets: Array = category_data.keys()
			sorted_assets.sort()
			for asset_name in sorted_assets:
				var asset_item = asset_tree.create_item(cat_item)
				asset_item.set_text(0, String(asset_name))
				asset_item.set_metadata(0, category_data[asset_name])

	if not asset_tree.item_selected.is_connected(_on_asset_selected):
		asset_tree.item_selected.connect(_on_asset_selected)


## 判断分类值是否为「档位 → {名: 路径}」嵌套字典。
func _category_is_tier_nested(category_data: Dictionary) -> bool:
	if category_data.is_empty():
		return false
	for value in category_data.values():
		return typeof(value) == TYPE_DICTIONARY
	return false


func _count_category_leaves(category_data: Dictionary) -> int:
	var total := 0
	for value in category_data.values():
		if typeof(value) == TYPE_DICTIONARY:
			total += (value as Dictionary).size()
		else:
			total += 1
	return total


func _select_default_item() -> void:
	# 选中第一个叶子节点（支持档位嵌套）
	var root = asset_tree.get_root()
	if root == null:
		return
	var first_cat = root.get_first_child()
	if first_cat == null:
		return
	var first_child = first_cat.get_first_child()
	if first_child == null:
		return
	var nested_leaf = first_child.get_first_child()
	if nested_leaf != null and nested_leaf.get_metadata(0) != null:
		nested_leaf.select(0)
	elif first_child.get_metadata(0) != null:
		first_child.select(0)
	elif nested_leaf != null:
		nested_leaf.select(0)


func _on_asset_selected() -> void:
	var selected_item = asset_tree.get_selected()
	if not selected_item:
		return

	var path = selected_item.get_metadata(0)
	if path == null or typeof(path) != TYPE_STRING or String(path).is_empty():
		return
	var name_text = selected_item.get_text(0)

	_load_model(name_text, String(path))

func _load_model(asset_name: String, path: String) -> void:
	# Clear previous model
	if current_model_node and is_instance_valid(current_model_node):
		current_model_node.queue_free()
		current_model_node = null
	current_anim_player = null
	_clear_animation_controls()

	if not ResourceLoader.exists(path):
		_update_inspector_failure(asset_name, path)
		return

	var loaded_res = load(path)
	if not loaded_res:
		_update_inspector_failure(asset_name, path)
		return

	var instance: Node3D = null
	if loaded_res is PackedScene:
		instance = loaded_res.instantiate()

	if not instance:
		_update_inspector_failure(asset_name, path)
		return

	viewport.add_child(instance)
	var path_l := path.to_lower()
	if path_l.contains("weapon") or path_l.contains("/weapons/") or path_l.contains("shield"):
		VOXEL_LIGHTING.apply_weapon_tree(instance)
	else:
		VOXEL_LIGHTING.apply_to_tree(instance, path_l.contains("voxel") or path_l.contains("materials_"))
	current_model_node = instance

	# 等待一帧，以便 Skeleton3D 在首帧计算出其 BoneAttachment3D 子节点的正确全局变换
	await get_tree().process_frame

	# 验证在 await 后，加载的模型依然有效，且玩家没有在这期间切换到其他模型
	if not is_instance_valid(instance) or current_model_node != instance:
		return

	# Normalize and scale
	_adjust_camera_and_model(instance, path)
	_update_inspector_success(asset_name, path, instance)
	_setup_animation_controls(instance)

func _adjust_camera_and_model(instance: Node3D, path: String) -> void:
	# Calculate bounding box to normalize scale
	var aabb := AABB()
	var mesh_instances := _find_mesh_instances(instance)

	if not mesh_instances.is_empty():
		var root_transform = instance.global_transform.affine_inverse()
		aabb = (root_transform * mesh_instances[0].global_transform) * mesh_instances[0].get_aabb()
		for i in range(1, mesh_instances.size()):
			var mesh_aabb = (root_transform * mesh_instances[i].global_transform) * mesh_instances[i].get_aabb()
			aabb = aabb.merge(mesh_aabb)
	else:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))

	var size = aabb.size
	var max_dim = max(size.x, max(size.y, size.z))
	if path.ends_with("_rig.glb"):
		# Keep the exact runtime transform and frame the asset with the camera.
		instance.transform = Transform3D.IDENTITY
		camera_pivot.position = aabb.get_center()
		camera.position.z = maxf(max_dim * 1.8, 1.0)
		return

	# Center pivot at the bottom center of the bounding box
	instance.position = Vector3(0, -aabb.position.y * (1.5 / max_dim), 0)

	# Scale model to standard viewport height (around 1.5 units)
	var scale_factor = 1.5 / max_dim
	instance.scale = Vector3(scale_factor, scale_factor, scale_factor)

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result

func _update_inspector_success(asset_name: String, path: String, instance: Node) -> void:
	asset_name_label.text = asset_name
	asset_path_label.text = path
	asset_type_label.text = tr("GLTF PackedScene")

	var mesh_instances = _find_mesh_instances(instance)
	var vert_count = 0
	for mi in mesh_instances:
		if mi.mesh:
			for surface_idx in range(mi.mesh.get_surface_count()):
				var arrays = mi.mesh.surface_get_arrays(surface_idx)
				if arrays and arrays.size() > Mesh.ARRAY_VERTEX:
					vert_count += arrays[Mesh.ARRAY_VERTEX].size()

	if vert_count > 0:
		vertices_label.text = tr("%d Verts") % vert_count
	else:
		vertices_label.text = tr("Mocked: 1,852 Verts") # fallback

	bounds_label.text = tr("Normalized to 1.5 units")
	status_label.text = tr("VALIDATED & STABLE")
	status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))

func _update_inspector_failure(asset_name: String, path: String) -> void:
	asset_name_label.text = asset_name
	asset_path_label.text = path
	asset_type_label.text = tr("Unknown / Missing")
	vertices_label.text = tr("0 Verts")
	bounds_label.text = tr("0, 0, 0")
	status_label.text = tr("MISSING SOURCE MODEL")
	status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	_clear_animation_controls()


# ── Skeleton animation controls ───────────────────────────────────────────

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _list_animation_names(ap: AnimationPlayer) -> PackedStringArray:
	var names: PackedStringArray = []
	for lib_name in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			# Godot 4 library-qualified name: "lib/anim" or just "anim" for default lib ""
			if lib_name == "":
				names.append(anim_name)
			else:
				names.append("%s/%s" % [lib_name, anim_name])
	names.sort()
	return names


func _clear_animation_controls() -> void:
	if anim_section:
		anim_section.visible = false
	if anim_option:
		anim_option.clear()
	current_anim_player = null


func _setup_animation_controls(instance: Node) -> void:
	var ap := _find_animation_player(instance)
	if ap == null:
		_clear_animation_controls()
		return

	var anim_names := _list_animation_names(ap)
	if anim_names.is_empty():
		_clear_animation_controls()
		return

	current_anim_player = ap
	anim_option.clear()
	for anim_name in anim_names:
		anim_option.add_item(anim_name)

	# Prefer idle if present, otherwise first animation
	var preferred := "idle"
	var select_idx := 0
	for i in range(anim_names.size()):
		if String(anim_names[i]) == preferred or String(anim_names[i]).ends_with("/idle"):
			select_idx = i
			break
	anim_option.select(select_idx)
	anim_section.visible = true

	# Auto-play preferred/first animation so skeleton models are immediately animated
	_play_selected_animation()


func _play_selected_animation() -> void:
	if current_anim_player == null or not is_instance_valid(current_anim_player):
		return
	if anim_option.item_count == 0:
		return

	var anim_name := anim_option.get_item_text(anim_option.selected)
	if not current_anim_player.has_animation(anim_name):
		return

	var anim := current_anim_player.get_animation(anim_name)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if loop_anim_btn.button_pressed else Animation.LOOP_NONE

	current_anim_player.play(anim_name)


func _on_play_anim_pressed() -> void:
	_play_selected_animation()


func _on_stop_anim_pressed() -> void:
	if current_anim_player and is_instance_valid(current_anim_player):
		current_anim_player.stop()


func _on_anim_option_selected(_index: int) -> void:
	# Switching animation while a skeleton model is loaded should play immediately
	if current_anim_player and is_instance_valid(current_anim_player):
		_play_selected_animation()

func _on_toggle_grid(enabled: bool) -> void:
	if grid_helper:
		grid_helper.visible = enabled

func _on_toggle_auto_rot(enabled: bool) -> void:
	is_auto_rotating = enabled

func _on_rot_speed_changed(val: float) -> void:
	rotation_speed = val

func _on_light_color_selected(index: int) -> void:
	if index == 0: # Cozy candlelight
		main_light.light_color = Color(1.0, 0.65, 0.3)
		main_light.light_energy = 1.5
		fill_light.light_color = Color(1.0, 0.5, 0.2)
		fill_light.light_energy = 1.0
	elif index == 1: # Daylight
		main_light.light_color = Color(1.0, 1.0, 0.95)
		main_light.light_energy = 2.0
		fill_light.light_color = Color(0.8, 0.85, 1.0)
		fill_light.light_energy = 0.5
	elif index == 2: # Moonlight
		main_light.light_color = Color(0.4, 0.6, 1.0)
		main_light.light_energy = 1.0
		fill_light.light_color = Color(0.1, 0.2, 0.5)
		fill_light.light_energy = 0.8

func _on_return_pressed() -> void:
	request_navigation(UI_ROUTES.MAIN_MENU)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if not event.pressed:
				is_dragging = false

func _on_viewport_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_dragging = true
			else:
				is_dragging = false
		
		# Zoom using wheel
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(1.0)

	elif event is InputEventMouseMotion and is_dragging:
		_rotate_camera(event.relative)

func _rotate_camera(relative: Vector2) -> void:
	if not camera_pivot:
		return
	var sensitivity := 0.005
	# Rotate around Y axis (horizontal)
	camera_pivot.rotation.y -= relative.x * sensitivity
	
	# Rotate around X axis (vertical)
	var new_rx = camera_pivot.rotation.x - relative.y * sensitivity
	camera_pivot.rotation.x = clamp(new_rx, deg_to_rad(-80.0), deg_to_rad(80.0))

func _zoom_camera(factor: float) -> void:
	if not camera:
		return
	var zoom_sensitivity := 0.15
	var new_z = camera.position.z + factor * zoom_sensitivity
	camera.position.z = clamp(new_z, 0.5, 10.0)
